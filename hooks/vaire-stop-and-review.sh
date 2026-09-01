#!/bin/bash
# Shared logic: stops the timer for $1 (a session_id), shows a summary
# dialog (with the estimate-vs-actual added-value line if Claude recorded
# one), and offers to adjust the time/note before it's saved. Used by both
# vaire-session-end.sh (real session termination) and
# vaire-session-start.sh (when the user picks "Dokončit" on /clear,
# since a task is more often finished at /clear time than at process exit).
#
# Meant to be sourced, not executed directly — call stop_and_review "$session_id".

stop_and_review() {
    local session_id="$1"

    source "$(dirname "${BASH_SOURCE[0]}")/vaire-i18n.sh"

    result=$(vaire stop-session "$session_id" 2>/dev/null)
    [ -z "$result" ] && return 0

    project=$(echo "$result" | grep '^project=' | cut -d= -f2-)
    duration_human=$(echo "$result" | grep '^duration_human=' | cut -d= -f2-)
    duration_seconds=$(echo "$result" | grep '^duration_seconds=' | cut -d= -f2-)
    note=$(echo "$result" | grep '^note=' | cut -d= -f2-)
    block_id=$(echo "$result" | grep '^block_id=' | cut -d= -f2-)
    estimated_hours=$(echo "$result" | grep '^estimated_hours_without_ai=' | cut -d= -f2-)
    estimated_human=$(echo "$result" | grep '^estimated_human=' | cut -d= -f2-)
    saved_human=$(echo "$result" | grep '^saved_human=' | cut -d= -f2-)

    added_value_line=""
    if [ -n "$estimated_hours" ]; then
        added_value_line="${L_ESTIMATE_WITHOUT_AI}${estimated_human}${L_SAVED_SUFFIX}${saved_human}${L_HOURS_SUFFIX}"
    fi

    # Pass all user-controlled/dynamic strings as `on run argv` arguments
    # instead of interpolating them into the AppleScript source — the note
    # can contain quotes, backslashes, or non-ASCII text that would
    # otherwise break the script or enable injection.
    choice=$(osascript - "$project" "$duration_human" "$note" "$added_value_line" "$L_WORKED_ON_PREFIX" "$L_NOTE_LABEL" "$L_DISCARD" "$L_EDIT" "$L_OK" "$L_SUMMARY_TITLE" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set proj to item 1 of argv
    set dur to item 2 of argv
    set noteText to item 3 of argv
    set addedValue to item 4 of argv
    set workedOnPrefix to item 5 of argv
    set noteLabel to item 6 of argv
    set discardBtn to item 7 of argv
    set editBtn to item 8 of argv
    set okBtn to item 9 of argv
    set titleText to item 10 of argv
    set msg to workedOnPrefix & proj & ": " & dur & return & noteLabel & noteText
    if addedValue is not "" then
        set msg to msg & return & addedValue
    end if
    try
        display dialog msg buttons {discardBtn, editBtn, okBtn} default button okBtn with title titleText
        return button returned of result
    on error
        return okBtn
    end try
end run
APPLESCRIPT
    )

    if [ "$choice" = "$L_DISCARD" ]; then
        if [ -n "$block_id" ]; then
            vaire delete-block "$block_id" >/dev/null 2>&1
        fi
        return 0
    fi

    if [ "$choice" = "$L_EDIT" ]; then
        default_minutes=$((duration_seconds / 60))

        new_minutes=$(prompt_for_number "$L_HOW_MANY_MINUTES" "$default_minutes")

        new_note=$(osascript - "$note" "$L_NOTE_COLON" "$L_TITLE" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set defaultVal to item 1 of argv
    set labelText to item 2 of argv
    set titleText to item 3 of argv
    try
        display dialog labelText default answer defaultVal with title titleText
        return text returned of result
    on error
        return ""
    end try
end run
APPLESCRIPT
        )

        if [ -n "$new_minutes" ] && [ -n "$block_id" ]; then
            vaire adjust-block "$block_id" "$new_minutes" "$new_note" >/dev/null 2>&1
        elif [ -n "$new_note" ] && [ -n "$block_id" ]; then
            vaire adjust-block "$block_id" "" "$new_note" >/dev/null 2>&1
        fi

        if [ -n "$block_id" ]; then
            default_estimate_minutes=$(awk "BEGIN { printf \"%.0f\", ${estimated_hours:-0} * 60 }")
            new_estimate_minutes=$(prompt_for_number "$L_ESTIMATE_HOURS_COLON" "$default_estimate_minutes")
            if [ -n "$new_estimate_minutes" ]; then
                new_estimate=$(awk "BEGIN { printf \"%.4f\", $new_estimate_minutes / 60 }")
                vaire adjust-estimate "$block_id" "$new_estimate" >/dev/null 2>&1
            fi
        fi
    fi
}

# Prompts for a single whole number, re-asking on non-numeric input.
# Returns empty string if the user cancels (osascript error), which callers
# treat as "skip this change" rather than guessing a value.
prompt_for_number() {
    local label="$1"
    local default_value="$2"
    local value="$default_value"

    while true; do
        value=$(osascript - "$label" "$value" "$L_TITLE" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set labelText to item 1 of argv
    set defaultVal to item 2 of argv
    set titleText to item 3 of argv
    try
        display dialog labelText default answer defaultVal with title titleText
        return text returned of result
    on error
        return ""
    end try
end run
APPLESCRIPT
        )

        [ -z "$value" ] && { echo ""; return; }

        if [[ "$value" =~ ^[0-9]+$ ]]; then
            echo "$value"
            return
        fi

        # Non-numeric input — re-prompt with an explicit error instead of
        # silently falling back to the default, so a typo doesn't silently
        # save the wrong time.
        osascript -e "display alert \"$L_NUMBER_ONLY_WARNING\" as warning" >/dev/null 2>&1
    done
}

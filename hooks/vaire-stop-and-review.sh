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

    result=$(vaire stop-session "$session_id" 2>/dev/null)
    [ -z "$result" ] && return 0

    project=$(echo "$result" | grep '^project=' | cut -d= -f2-)
    duration_human=$(echo "$result" | grep '^duration_human=' | cut -d= -f2-)
    duration_seconds=$(echo "$result" | grep '^duration_seconds=' | cut -d= -f2-)
    note=$(echo "$result" | grep '^note=' | cut -d= -f2-)
    block_id=$(echo "$result" | grep '^block_id=' | cut -d= -f2-)
    estimated_hours=$(echo "$result" | grep '^estimated_hours_without_ai=' | cut -d= -f2-)

    added_value_line=""
    if [ -n "$estimated_hours" ]; then
        actual_hours=$(awk "BEGIN { printf \"%.2f\", $duration_seconds / 3600 }")
        saved_hours=$(awk "BEGIN { printf \"%.1f\", $estimated_hours - $actual_hours }")
        added_value_line="Odhad bez AI: ${estimated_hours}h (ušetřeno ~${saved_hours}h)"
    fi

    # Pass all user-controlled/dynamic strings as `on run argv` arguments
    # instead of interpolating them into the AppleScript source — the note
    # can contain quotes, backslashes, or non-ASCII text that would
    # otherwise break the script or enable injection.
    choice=$(osascript - "$project" "$duration_human" "$note" "$added_value_line" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set proj to item 1 of argv
    set dur to item 2 of argv
    set noteText to item 3 of argv
    set addedValue to item 4 of argv
    set msg to "Odpracováno na " & proj & ": " & dur & return & "Poznámka: " & noteText
    if addedValue is not "" then
        set msg to msg & return & addedValue
    end if
    try
        display dialog msg buttons {"OK", "Upravit"} default button "OK" with title "Vaire — shrnutí"
        return button returned of result
    on error
        return "OK"
    end try
end run
APPLESCRIPT
    )

    if [ "$choice" = "Upravit" ]; then
        default_minutes=$((duration_seconds / 60))

        new_minutes=$(prompt_for_number "Kolik minut opravdu?" "$default_minutes")

        new_note=$(osascript - "$note" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set defaultVal to item 1 of argv
    try
        display dialog "Poznámka:" default answer defaultVal with title "Vaire"
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
            default_estimate="${estimated_hours:-0}"
            new_estimate=$(prompt_for_decimal "Odhad bez AI (hodiny):" "$default_estimate")
            [ -n "$new_estimate" ] && vaire adjust-estimate "$block_id" "$new_estimate" >/dev/null 2>&1
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
        value=$(osascript - "$label" "$value" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set labelText to item 1 of argv
    set defaultVal to item 2 of argv
    try
        display dialog labelText default answer defaultVal with title "Vaire"
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
        osascript -e 'display alert "Zadej prosím jen číslo." as warning' >/dev/null 2>&1
    done
}

# Like prompt_for_number but accepts decimals (e.g. "2.5") for hour
# estimates. Returns empty string on cancel — callers treat that as
# "leave the estimate unchanged" rather than clearing it.
prompt_for_decimal() {
    local label="$1"
    local default_value="$2"
    local value="$default_value"

    while true; do
        value=$(osascript - "$label" "$value" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set labelText to item 1 of argv
    set defaultVal to item 2 of argv
    try
        display dialog labelText default answer defaultVal with title "Vaire"
        return text returned of result
    on error
        return ""
    end try
end run
APPLESCRIPT
        )

        [ -z "$value" ] && { echo ""; return; }

        if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            echo "$value"
            return
        fi

        osascript -e 'display alert "Zadej prosím číslo (např. 2.5)." as warning' >/dev/null 2>&1
    done
}

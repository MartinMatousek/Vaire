#!/bin/bash
# Claude Code SessionStart hook. Asks whether to log time for this session
# and, if so, starts a Vaire timer via vaire. Never blocks
# session startup on failure — a missing CLI or App Group container should
# degrade to "not tracking", not stop work.
#
# /clear, /compact, and /resume all mint a NEW session_id, so a running
# timer from before the reset can't be found under the old id anymore. If
# one is still active for this cwd, offer to continue it instead of
# starting a second, overlapping timer for the same work.

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
cwd=$(echo "$input" | jq -r '.cwd // empty')
matcher_value=$(echo "$input" | jq -r '.matcher_value // empty')

if [ -z "$session_id" ] || [ -z "$cwd" ]; then
    exit 0
fi

if ! command -v vaire >/dev/null 2>&1; then
    exit 0
fi

enabled=$(vaire is-hooks-enabled "$cwd" 2>/dev/null)
if [ "$enabled" != "true" ]; then
    exit 0
fi

source "$(dirname "$0")/vaire-i18n.sh"

project_name=$(basename "$cwd")

active=""
active_session_id=""
active_note=""
active_elapsed_human=""
case "$matcher_value" in
resume | clear | compact)
    active=$(vaire find-active "$cwd" 2>/dev/null)
    if [ "$active" != "none" ] && [ -n "$active" ]; then
        active_session_id=$(echo "$active" | grep '^session_id=' | cut -d= -f2-)
        active_note=$(echo "$active" | grep '^note=' | cut -d= -f2-)
        elapsed_seconds=$(echo "$active" | grep '^elapsed_seconds=' | cut -d= -f2-)
        active_elapsed_human="$((elapsed_seconds / 3600))h $(((elapsed_seconds % 3600) / 60))m"
    fi
    ;;
esac

if [ -n "$active_session_id" ]; then
    note_line=""
    [ -n "$active_note" ] && note_line="$L_NOTE_PREFIX$active_note"

    # "Finish" only makes sense on /clear: that's usually when a task
    # actually wraps up, well before the Claude Code process itself ends
    # (which is when SessionEnd would otherwise show this same summary).
    # /compact and /resume are mid-task continuations, not endpoints.
    if [ "$matcher_value" = "clear" ]; then
        choice=$(osascript - "$project_name" "$active_elapsed_human" "$note_line" "$L_TASK_RUNNING_PREFIX" "$L_TASK_RUNNING_SUFFIX" "$L_CONTINUE_QUESTION" "$L_NO_NEW_TASK" "$L_FINISH" "$L_CONTINUE" "$L_TITLE" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set proj to item 1 of argv
    set elapsed to item 2 of argv
    set noteLine to item 3 of argv
    set prefixText to item 4 of argv
    set suffixText to item 5 of argv
    set continueQ to item 6 of argv
    set noNewTask to item 7 of argv
    set finishBtn to item 8 of argv
    set continueBtn to item 9 of argv
    set titleText to item 10 of argv
    set msg to prefixText & proj & suffixText & elapsed & "." & return & noteLine & return & continueQ
    try
        display dialog msg buttons {noNewTask, finishBtn, continueBtn} default button continueBtn with title titleText
        return button returned of result
    on error
        return continueBtn
    end try
end run
APPLESCRIPT
        )
    else
        choice=$(osascript - "$project_name" "$active_elapsed_human" "$note_line" "$L_TASK_RUNNING_PREFIX" "$L_TASK_RUNNING_SUFFIX" "$L_CONTINUE_QUESTION" "$L_NO_NEW_TASK" "$L_NO_NO_LOGGING" "$L_CONTINUE" "$L_TITLE" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set proj to item 1 of argv
    set elapsed to item 2 of argv
    set noteLine to item 3 of argv
    set prefixText to item 4 of argv
    set suffixText to item 5 of argv
    set continueQ to item 6 of argv
    set noNewTask to item 7 of argv
    set noNoLogging to item 8 of argv
    set continueBtn to item 9 of argv
    set titleText to item 10 of argv
    set msg to prefixText & proj & suffixText & elapsed & "." & return & noteLine & return & continueQ
    try
        display dialog msg buttons {noNewTask, noNoLogging, continueBtn} default button continueBtn with title titleText
        return button returned of result
    on error
        return continueBtn
    end try
end run
APPLESCRIPT
        )
    fi

    case "$choice" in
    "$L_CONTINUE")
        vaire continue-session "$active_session_id" "$session_id" >/dev/null 2>&1
        exit 0
        ;;
    "$L_FINISH")
        source "$(dirname "$0")/vaire-stop-and-review.sh"
        stop_and_review "$active_session_id"
        exit 0
        ;;
    "$L_NO_NEW_TASK")
        # Stop the old timer as-is, then fall through to the normal
        # start-new-task prompt below.
        vaire stop-session "$active_session_id" >/dev/null 2>&1
        ;;
    *)
        vaire stop-session "$active_session_id" >/dev/null 2>&1
        exit 0
        ;;
    esac
fi

choice=$(osascript - "$project_name" "$L_LOG_TIME_PREFIX" "$L_LOG_TIME_SUFFIX" "$L_NO" "$L_WITHOUT_NOTE" "$L_WITH_NOTE" "$L_TITLE" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set proj to item 1 of argv
    set prefixText to item 2 of argv
    set suffixText to item 3 of argv
    set noBtn to item 4 of argv
    set withoutNoteBtn to item 5 of argv
    set withNoteBtn to item 6 of argv
    set titleText to item 7 of argv
    try
        display dialog prefixText & proj & suffixText buttons {noBtn, withoutNoteBtn, withNoteBtn} default button withoutNoteBtn with title titleText
        return button returned of result
    on error
        return noBtn
    end try
end run
APPLESCRIPT
)

case "$choice" in
"$L_WITHOUT_NOTE")
    vaire start-session "$session_id" "$cwd" >/dev/null 2>&1
    ;;
"$L_WITH_NOTE")
    note=$(osascript - "$L_WHAT_WILL_YOU_DO" "$L_TITLE" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set promptText to item 1 of argv
    set titleText to item 2 of argv
    try
        display dialog promptText default answer "" with title titleText
        return text returned of result
    on error
        return ""
    end try
end run
APPLESCRIPT
    )
    vaire start-session "$session_id" "$cwd" "$note" >/dev/null 2>&1
    ;;
*)
    ;;
esac

exit 0

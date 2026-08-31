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
    [ -n "$active_note" ] && note_line="Poznámka: $active_note"

    # "Dokončit" only makes sense on /clear: that's usually when a task
    # actually wraps up, well before the Claude Code process itself ends
    # (which is when SessionEnd would otherwise show this same summary).
    # /compact and /resume are mid-task continuations, not endpoints.
    if [ "$matcher_value" = "clear" ]; then
        choice=$(osascript - "$project_name" "$active_elapsed_human" "$note_line" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set proj to item 1 of argv
    set elapsed to item 2 of argv
    set noteLine to item 3 of argv
    set msg to "Rozjetý task na " & proj & " už běží " & elapsed & "." & return & noteLine & return & "Pokračovat?"
    try
        display dialog msg buttons {"Ne (nový task)", "Dokončit", "Pokračovat"} default button "Pokračovat" with title "Vaire"
        return button returned of result
    on error
        return "Pokračovat"
    end try
end run
APPLESCRIPT
        )
    else
        choice=$(osascript - "$project_name" "$active_elapsed_human" "$note_line" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set proj to item 1 of argv
    set elapsed to item 2 of argv
    set noteLine to item 3 of argv
    set msg to "Rozjetý task na " & proj & " už běží " & elapsed & "." & return & noteLine & return & "Pokračovat?"
    try
        display dialog msg buttons {"Ne (nový task)", "Ne (bez logování)", "Pokračovat"} default button "Pokračovat" with title "Vaire"
        return button returned of result
    on error
        return "Pokračovat"
    end try
end run
APPLESCRIPT
        )
    fi

    case "$choice" in
    "Pokračovat")
        vaire continue-session "$active_session_id" "$session_id" >/dev/null 2>&1
        exit 0
        ;;
    "Dokončit")
        source "$(dirname "$0")/vaire-stop-and-review.sh"
        stop_and_review "$active_session_id"
        exit 0
        ;;
    "Ne (nový task)")
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

choice=$(osascript - "$project_name" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set proj to item 1 of argv
    try
        display dialog "Logovat čas pro session v " & proj & "?" buttons {"Ne", "Bez poznámky", "S poznámkou"} default button "Bez poznámky" with title "Vaire"
        return button returned of result
    on error
        return "Ne"
    end try
end run
APPLESCRIPT
)

case "$choice" in
"Bez poznámky")
    vaire start-session "$session_id" "$cwd" >/dev/null 2>&1
    ;;
"S poznámkou")
    note=$(osascript -e 'try
        display dialog "Co budeš dělat?" default answer "" with title "Vaire"
        return text returned of result
    on error
        return ""
    end try' 2>/dev/null)
    vaire start-session "$session_id" "$cwd" "$note" >/dev/null 2>&1
    ;;
*)
    ;;
esac

exit 0

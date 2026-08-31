#!/bin/bash
# Claude Code SessionStart hook. Asks whether to log time for this session
# and, if so, starts a TimeKeeper timer via timekeeper-cli. Never blocks
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

if ! command -v timekeeper-cli >/dev/null 2>&1; then
    exit 0
fi

project_name=$(basename "$cwd")

active=""
active_session_id=""
case "$matcher_value" in
resume | clear | compact)
    active=$(timekeeper-cli find-active "$cwd" 2>/dev/null)
    if [ "$active" != "none" ] && [ -n "$active" ]; then
        active_session_id=$(echo "$active" | grep '^session_id=' | cut -d= -f2-)
    fi
    ;;
esac

if [ -n "$active_session_id" ]; then
    choice=$(osascript - "$project_name" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set proj to item 1 of argv
    try
        display dialog "Pokračovat v rozjetém tasku na " & proj & "?" buttons {"Ne (nový task)", "Ne (bez logování)", "Pokračovat"} default button "Pokračovat" with title "TimeKeeper"
        return button returned of result
    on error
        return "Pokračovat"
    end try
end run
APPLESCRIPT
    )

    case "$choice" in
    "Pokračovat")
        timekeeper-cli continue-session "$active_session_id" "$session_id" >/dev/null 2>&1
        exit 0
        ;;
    "Ne (nový task)")
        # Stop the old timer as-is, then fall through to the normal
        # start-new-task prompt below.
        timekeeper-cli stop-session "$active_session_id" >/dev/null 2>&1
        ;;
    *)
        timekeeper-cli stop-session "$active_session_id" >/dev/null 2>&1
        exit 0
        ;;
    esac
fi

choice=$(osascript - "$project_name" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set proj to item 1 of argv
    try
        display dialog "Logovat čas pro session v " & proj & "?" buttons {"Ne", "Bez poznámky", "S poznámkou"} default button "Bez poznámky" with title "TimeKeeper"
        return button returned of result
    on error
        return "Ne"
    end try
end run
APPLESCRIPT
)

case "$choice" in
"Bez poznámky")
    timekeeper-cli start-session "$session_id" "$cwd" >/dev/null 2>&1
    ;;
"S poznámkou")
    note=$(osascript -e 'try
        display dialog "Co budeš dělat?" default answer "" with title "TimeKeeper"
        return text returned of result
    on error
        return ""
    end try' 2>/dev/null)
    timekeeper-cli start-session "$session_id" "$cwd" "$note" >/dev/null 2>&1
    ;;
*)
    ;;
esac

exit 0

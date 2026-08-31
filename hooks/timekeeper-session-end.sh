#!/bin/bash
# Claude Code SessionEnd hook. Stops the timer started by
# timekeeper-session-start.sh (if any), reports the logged duration and
# note, and offers to adjust either before saving. Silent no-op if this
# session was never tracked (user opted out, or the CLI/container was
# unavailable at start).
#
# NOTE: SessionEnd hooks share a small default timeout budget in Claude
# Code. This hook is interactive (waits on dialogs), so it must be
# registered with a generous per-hook timeout (e.g. 120s) in settings.json
# or the dialog will be killed mid-interaction.

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')

if [ -z "$session_id" ]; then
    exit 0
fi

if ! command -v timekeeper-cli >/dev/null 2>&1; then
    exit 0
fi

tracking=$(timekeeper-cli is-tracking "$session_id" 2>/dev/null)
if [ "$tracking" != "true" ]; then
    exit 0
fi

result=$(timekeeper-cli stop-session "$session_id" 2>/dev/null)
[ -z "$result" ] && exit 0

project=$(echo "$result" | grep '^project=' | cut -d= -f2-)
duration_human=$(echo "$result" | grep '^duration_human=' | cut -d= -f2-)
duration_seconds=$(echo "$result" | grep '^duration_seconds=' | cut -d= -f2-)
note=$(echo "$result" | grep '^note=' | cut -d= -f2-)
block_id=$(echo "$result" | grep '^block_id=' | cut -d= -f2-)

# Pass all user-controlled/dynamic strings as `on run argv` arguments
# instead of interpolating them into the AppleScript source — the note can
# contain quotes, backslashes, or non-ASCII text that would otherwise break
# the script or enable injection.
choice=$(osascript - "$project" "$duration_human" "$note" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set proj to item 1 of argv
    set dur to item 2 of argv
    set noteText to item 3 of argv
    try
        display dialog "Odpracováno na " & proj & ": " & dur & return & "Poznámka: " & noteText buttons {"OK", "Upravit"} default button "OK" with title "TimeKeeper — konec session"
        return button returned of result
    on error
        return "OK"
    end try
end run
APPLESCRIPT
)

if [ "$choice" = "Upravit" ]; then
    default_minutes=$((duration_seconds / 60))

    new_minutes=$(osascript - "$default_minutes" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set defaultVal to item 1 of argv
    try
        display dialog "Kolik minut opravdu?" default answer defaultVal with title "TimeKeeper"
        return text returned of result
    on error
        return ""
    end try
end run
APPLESCRIPT
    )

    new_note=$(osascript - "$note" <<'APPLESCRIPT' 2>/dev/null
on run argv
    set defaultVal to item 1 of argv
    try
        display dialog "Poznámka:" default answer defaultVal with title "TimeKeeper"
        return text returned of result
    on error
        return ""
    end try
end run
APPLESCRIPT
    )

    if [ -n "$new_minutes" ] && [ -n "$block_id" ]; then
        timekeeper-cli adjust-block "$block_id" "$new_minutes" "$new_note" >/dev/null 2>&1
    fi
fi

exit 0

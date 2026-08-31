#!/bin/bash
# Claude Code SessionStart hook. Asks whether to log time for this session
# and, if so, starts a TimeKeeper timer via timekeeper-cli. Never blocks
# session startup on failure — a missing CLI or App Group container should
# degrade to "not tracking", not stop work.

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
cwd=$(echo "$input" | jq -r '.cwd // empty')

if [ -z "$session_id" ] || [ -z "$cwd" ]; then
    exit 0
fi

if ! command -v timekeeper-cli >/dev/null 2>&1; then
    exit 0
fi

project_name=$(basename "$cwd")

choice=$(osascript <<EOF 2>/dev/null
try
    display dialog "Logovat čas pro session v $project_name?" buttons {"Ne", "Bez poznámky", "S poznámkou"} default button "Bez poznámky" with title "TimeKeeper"
    set btn to button returned of result
    return btn
on error
    return "Ne"
end try
EOF
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

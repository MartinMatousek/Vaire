#!/bin/bash
# Claude Code SessionStart hook. Opens VaireApp's real note+estimate form
# and, if the user fills it in, starts a Vaire timer via vaire. Never
# blocks session startup on failure — a missing CLI or App Group container
# should degrade to "not tracking", not stop work.

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
cwd=$(echo "$input" | jq -r '.cwd // empty')

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

result_dir="$HOME/Library/Application Support/Vaire/start-results"
result_file="$result_dir/${session_id}.json"
mkdir -p "$result_dir"
rm -f "$result_file"

encoded_cwd=$(printf '%s' "$cwd" | jq -Rr '@uri')
encoded_session_id=$(printf '%s' "$session_id" | jq -Rr '@uri')
[ -z "$encoded_cwd" ] && exit 0

# Wakes the already-running VaireApp (or launches it) to show its real
# note+estimate form instead of a sequence of AppleScript yes/no prompts —
# if the user doesn't want to log anything they just close the window.
open "vaire://start-session?session=$encoded_session_id&cwd=$encoded_cwd" >/dev/null 2>&1

timeout_seconds=180
elapsed=0
while [ ! -s "$result_file" ] && [ "$elapsed" -lt "$timeout_seconds" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
done

if [ -s "$result_file" ]; then
    outcome=$(jq -r '.outcome' "$result_file" 2>/dev/null)
    if [ "$outcome" = "started" ]; then
        note=$(jq -r '.note' "$result_file")
        vaire start-session "$session_id" "$cwd" "$note" >/dev/null 2>&1
        estimate_minutes=$(jq -r '.estimateMinutes' "$result_file")
        if [ "$estimate_minutes" != "null" ]; then
            new_estimate=$(awk "BEGIN { printf \"%.4f\", $estimate_minutes / 60 }")
            vaire set-estimate "$session_id" "$new_estimate" >/dev/null 2>&1
        fi
    else
        vaire decline-session "$session_id" >/dev/null 2>&1
    fi
else
    # App never responded within the timeout — don't leave this session
    # untracked-but-silent; record it as declined so has-estimate/is-tracking
    # checks elsewhere don't wait on it forever either.
    vaire decline-session "$session_id" >/dev/null 2>&1
fi

rm -f "$result_file"
exit 0

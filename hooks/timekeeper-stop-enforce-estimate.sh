#!/bin/bash
# Claude Code Stop hook. Runs after every assistant turn. If the current
# session is tracking time and no estimate has been recorded yet, blocks
# the turn (up to MAX_BLOCKS times) to prompt Claude to call
# `timekeeper-cli set-estimate` before the turn actually ends. Once an
# estimate is set, this becomes a no-op for the rest of the session.
#
# SessionEnd can't do this: its exit code is ignored entirely (verified —
# it has no blocking capability), so by the time a session is truly
# ending there's no way to hand control back to the model. Stop is the
# only point in the lifecycle where blocking can make Claude take one
# more action, which is why this fires on every turn instead of only at
# the end.
#
# Safety: never blocks more than MAX_BLOCKS times per session, tracked in
# our own counter file — independent of whatever stop_hook_active does,
# so a misunderstanding of that mechanism can't hang the whole session.
# Any failure (missing jq, missing CLI, malformed input) degrades to
# exit 0 (allow) rather than blocking — an annoying repeated block is a
# far worse failure mode here than an occasional missed estimate.

set -o pipefail

MAX_BLOCKS=2
COUNTER_DIR="/tmp/timekeeper-stop-hook-counters"

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)

[ -z "$session_id" ] && exit 0

# Respect Claude Code's own re-entrancy signal if present, on top of our
# own counter below — belt and suspenders, not a substitute for either.
if [ "$stop_hook_active" = "true" ]; then
    exit 0
fi

if ! command -v timekeeper-cli >/dev/null 2>&1; then
    exit 0
fi

tracking=$(timekeeper-cli is-tracking "$session_id" 2>/dev/null)
if [ "$tracking" != "true" ]; then
    exit 0
fi

has_estimate=$(timekeeper-cli has-estimate "$session_id" 2>/dev/null)
if [ "$has_estimate" = "true" ]; then
    exit 0
fi

mkdir -p "$COUNTER_DIR"
counter_file="$COUNTER_DIR/$session_id"
count=0
[ -f "$counter_file" ] && count=$(cat "$counter_file" 2>/dev/null || echo 0)
[[ "$count" =~ ^[0-9]+$ ]] || count=0

if [ "$count" -ge "$MAX_BLOCKS" ]; then
    exit 0
fi

echo $((count + 1)) > "$counter_file"

echo "TimeKeeper: před ukončením/clearem zavolej 'timekeeper-cli set-estimate \"$session_id\" <hodiny>' s odhadem, kolik by tenhle task trval bez AI asistence — i pro drobnost použij malé číslo (např. 0.1), nikdy 0. Pak pokračuj." >&2
exit 2

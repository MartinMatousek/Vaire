#!/bin/bash
# Claude Code SessionEnd hook. Fires on real process termination (closing
# the terminal, /exit, Ctrl-D) — NOT on /clear or /compact, which instead
# fire SessionStart with a new session_id (see timekeeper-session-start.sh,
# which offers to finish the task there since that's usually when work
# actually wraps up). Stops the timer for this session (if any) and shows
# the shared summary/edit dialog. Silent no-op if this session was never
# tracked.
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

source "$(dirname "$0")/timekeeper-stop-and-review.sh"
stop_and_review "$session_id"

exit 0

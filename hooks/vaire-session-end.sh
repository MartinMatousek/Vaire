#!/bin/bash
# Claude Code SessionEnd hook. Fires on real process termination (closing
# the terminal, /exit, Ctrl-D) — NOT on /clear or /compact, which instead
# fire SessionStart with a new session_id (see vaire-session-start.sh,
# which offers to finish the task there since that's usually when work
# actually wraps up). Stops the timer for this session (if any) and opens
# VaireApp's real edit window for the resulting block. Silent no-op if this
# session was never tracked.
#
# NOTE: SessionEnd hooks share a small default timeout budget in Claude
# Code. This hook is interactive (waits up to 180s for the edit window in
# vaire-stop-and-review.sh), so it must be registered with a generous
# per-hook timeout (200s+) in settings.json or the window will be killed
# mid-interaction.

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')

if [ -z "$session_id" ]; then
    exit 0
fi

# The Stop hook's per-session block counter (vaire-stop-enforce-estimate.sh)
# is never cleaned up on its own — remove it here so /tmp doesn't accumulate
# one file per session forever.
rm -f "/tmp/vaire-stop-hook-counters/$session_id"

if ! command -v vaire >/dev/null 2>&1; then
    exit 0
fi

tracking=$(vaire is-tracking "$session_id" 2>/dev/null)
if [ "$tracking" != "true" ]; then
    exit 0
fi

source "$(dirname "$0")/vaire-stop-and-review.sh"
stop_and_review "$session_id"

exit 0

#!/bin/bash
# Shared logic: stops the timer for $1 (a session_id) and opens VaireApp's
# real edit form (note + hours/minutes + estimate, identical to the manual
# stop-timer flow) so the user can adjust or discard it before it's saved.
# Used by both vaire-session-end.sh (real session termination) and
# vaire-session-start.sh (when the user picks "Finish" on /clear, since a
# task is more often finished at /clear time than at process exit).
#
# Meant to be sourced, not executed directly — call stop_and_review "$session_id".

stop_and_review() {
    local session_id="$1"

    result=$(vaire stop-session "$session_id" 2>/dev/null)
    [ -z "$result" ] && return 0

    block_id=$(echo "$result" | grep '^block_id=' | cut -d= -f2-)
    [ -z "$block_id" ] && return 0

    result_dir="$HOME/Library/Application Support/Vaire/edit-results"
    result_file="$result_dir/${block_id}.json"
    mkdir -p "$result_dir"
    rm -f "$result_file"

    # Wakes the already-running VaireApp (or launches it) to show its real
    # edit sheet directly — note + hours/minutes steppers + estimate,
    # identical to the manual stop-timer flow — instead of an intermediate
    # summary dialog first. If the user doesn't want to change anything
    # they just press Save (or close the window to leave it as recorded).
    open "vaire://edit-block?id=$block_id" >/dev/null 2>&1

    # Bounded wait so a SessionEnd hook can never hang Claude Code forever
    # if the user walks away or the app fails to respond; if it times out,
    # the block is simply left as stop-session recorded it.
    timeout_seconds=180
    elapsed=0
    while [ ! -s "$result_file" ] && [ "$elapsed" -lt "$timeout_seconds" ]; do
        sleep 1
        elapsed=$((elapsed + 1))
    done

    if [ -s "$result_file" ]; then
        outcome=$(jq -r '.outcome' "$result_file" 2>/dev/null)
        case "$outcome" in
        discarded)
            vaire delete-block "$block_id" >/dev/null 2>&1
            ;;
        saved)
            minutes=$(jq -r '.durationMinutes' "$result_file")
            new_note=$(jq -r '.note' "$result_file")
            vaire adjust-block "$block_id" "$minutes" "$new_note" >/dev/null 2>&1
            estimate_minutes=$(jq -r '.estimateMinutes' "$result_file")
            if [ "$estimate_minutes" != "null" ]; then
                new_estimate=$(awk "BEGIN { printf \"%.4f\", $estimate_minutes / 60 }")
                vaire adjust-estimate "$block_id" "$new_estimate" >/dev/null 2>&1
            fi
            ;;
        resumed | cancelled | notFound | *)
            : # leave the raw stopped block as-is
            ;;
        esac
        rm -f "$result_file"
    fi
}

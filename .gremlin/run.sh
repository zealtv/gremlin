#!/usr/bin/env bash
# run.sh — supervisor for the gremlin's loops.
#
# Backgrounds each loop and shuts them all down cleanly on SIGINT/SIGTERM.
# Tracks child PIDs and signals them explicitly — `trap 'kill 0' INT TERM`
# segfaults the supervisor itself on macOS bash 3.2.
#
# Loops:
#   - tend-loop.sh (~5s) — process items in .nest/in/
#   - tick-loop.sh (~60s) — joins in stage 7 (groundhog)
#
# Skills indexer call (stage 6) and .paused gate (s14) slot in here too.

set -uo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$GREMLIN_DIR/bin/index-skills.sh"

pids=()

shutdown() {
  trap - INT TERM
  for pid in "${pids[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null
  exit 0
}
trap shutdown INT TERM

( while sleep 5; do "$GREMLIN_DIR/bin/tend-loop.sh"; done ) &
pids+=($!)

# Align tick to wall-clock minute so groundhog's HH-MM schedules fire
# near :00 of their target minute.
( while :; do
    sleep $(( 60 - $(date +%s) % 60 ))
    "$GREMLIN_DIR/bin/tick-loop.sh"
  done
) &
pids+=($!)

wait

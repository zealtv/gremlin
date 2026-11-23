#!/usr/bin/env bash
# run.sh — supervisor for the gremlin's loops.
#
# Backgrounds each loop and shuts them all down cleanly on SIGINT/SIGTERM.
# Tracks child PIDs and signals them explicitly — `trap 'kill 0' INT TERM`
# segfaults the supervisor itself on macOS bash 3.2.
#
# Loops:
#   - tend-loop.sh (~5s) — process items in .nest/in/
#   - tick-loop.sh (~60s) — joins in stage 7 (groundhog); each minute it is
#     followed by moot-loop.sh, which does nothing unless the host has a .moot/
#
# Startup index refreshes and .paused gate (s14) slot in here too.

set -uo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_DIR="$(cd "$GREMLIN_DIR/.." && pwd)"

cd "$HOST_DIR"

if ! "$GREMLIN_DIR/bin/index-skills.sh"; then
  echo "warning: skills index refresh failed" >&2
fi

if [ -d "$HOST_DIR/.glean" ]; then
  if ! "$HOST_DIR/.glean/glean.sh" index; then
    echo "warning: glean index refresh failed" >&2
  fi
fi

pids=()

# nap <seconds>: sleep inside a loop subshell without ending the loop.
#   - A TERM to the sleep alone (something killed it) just ends the nap, so
#     the loop carries on; a bare `while sleep N` would end the loop for good.
#   - A TERM to the loop subshell kills its sleep first, so stopping the
#     gremlin leaves no orphaned sleep behind.
nap() {
  local nap_pid=""
  trap 'kill "$nap_pid" 2>/dev/null; exit 0' TERM
  sleep "$1" &
  nap_pid=$!
  wait "$nap_pid" 2>/dev/null
  trap - TERM
  return 0
}

shutdown() {
  trap - INT TERM
  for pid in "${pids[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  wait 2>/dev/null
  exit 0
}
trap shutdown INT TERM

( while :; do nap 5; "$GREMLIN_DIR/bin/tend-loop.sh"; done ) &
pids+=($!)

# Align tick to wall-clock minute so groundhog's HH-MM schedules fire
# near :00 of their target minute.
( while :; do
    nap $(( 60 - $(date +%s) % 60 ))
    "$GREMLIN_DIR/bin/tick-loop.sh"
    "$GREMLIN_DIR/bin/moot-loop.sh"
  done
) &
pids+=($!)

wait

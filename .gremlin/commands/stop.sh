#!/usr/bin/env bash
# stop — abort an in-flight model call: kill the pgid, drop the claim, log it
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIDFILE="$GREMLIN_DIR/.tending.pid"
NEST_IN="$GREMLIN_DIR/.nest/in"
NESTLING="$GREMLIN_DIR/.nest/nestling.sh"
TRANSCRIPT="$GREMLIN_DIR/transcript.md"

iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Drop any orphaned single .tending claim through canonical Nestlings. This is
# an explicit user action, so it bypasses retry while retaining canonical
# collision-safe dropped-history handling.
drop_active_claim() {
  local reason="$1"
  local claim base
  for claim in "$NEST_IN"/*.tending; do
    [ -e "$claim" ] || continue
    base="$(basename "$claim" .tending)"
    "$NESTLING" drop "$base" "$reason" >/dev/null
  done
}

if [ ! -e "$PIDFILE" ]; then
  echo "nothing to stop"
  exit 0
fi

pgid="$(tr -d '[:space:]' < "$PIDFILE")"
if ! [[ "$pgid" =~ ^[0-9]+$ ]]; then
  echo "stale pidfile (unparseable); cleaning"
  rm -f "$PIDFILE"
  drop_active_claim "stopped by user at $(iso) (stale pidfile)"
  exit 0
fi

# kill -0 with a negative pgid checks whether the group has any live members.
if ! kill -0 -- "-$pgid" 2>/dev/null; then
  echo "stale pidfile (pgid $pgid not alive); cleaning"
  rm -f "$PIDFILE"
  drop_active_claim "stopped by user at $(iso) (stale pidfile)"
  exit 0
fi

# Drop the claim before signalling so the tender's wait — which returns
# the moment the child dies — lands on the "claim is gone" abort branch
# and exits 0 cleanly. Reverse order leaves a benign 143 in the runner
# log; same end state, just noisier.
drop_active_claim "stopped by user at $(iso)"

kill -TERM -- "-$pgid" 2>/dev/null || true
sleep 0.5
if kill -0 -- "-$pgid" 2>/dev/null; then
  kill -KILL -- "-$pgid" 2>/dev/null || true
fi

# System turn announces the abort. Tender's abort branch sees the claim is
# gone and exits without writing an assistant turn.
printf '## system — %s\n✋ item aborted\n\n' "$(iso)" >> "$TRANSCRIPT"

# Race with the tender's EXIT trap is fine — both rm -f.
rm -f "$PIDFILE"

echo "stopped"

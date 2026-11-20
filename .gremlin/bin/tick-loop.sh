#!/usr/bin/env bash
# tick-loop.sh — one pass of the groundhog tick.
#
# Pure router: ticks groundhog, then moves each delivery-only item into
# .nest/in/. A delivery groundhog runs itself (its item carried a `run`)
# is left in out/ for groundhog. The tender owns shape recognition and
# transcript writes; this loop never writes transcript turns.

set -uo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_DIR="$(cd "$GREMLIN_DIR/.." && pwd)"

[ -e "$GREMLIN_DIR/.paused" ] && exit 0

GH="$HOST_DIR/.groundhog"
NEST_IN="$HOST_DIR/.nest/in"

"$GH/groundhog.sh" tick

for item in "$GH/out"/*; do
  [ -e "$item" ] || continue
  base="$(basename "$item")"
  case "$base" in
    .gitkeep) continue ;;
  esac
  [ -d "$item" ] || continue
  # A delivery whose record says groundhog runs it (an item that carried an
  # executable `run`) stays in out/: its run starts from there, on this tick
  # or a later one. Only delivery-only items come through the nest.
  if [ -f "$item/.groundhog-record" ]; then
    kind="" handler=""
    read -r kind _ _ handler _ < "$item/.groundhog-record" || true
    [ "$kind" = fired ] && [ "$handler" = run ] && continue
  fi

  target="$NEST_IN/$base"
  n=2
  while [ -e "$target" ]; do
    target="$NEST_IN/$base-$n"
    n=$((n+1))
  done
  mv "$item" "$target"
done

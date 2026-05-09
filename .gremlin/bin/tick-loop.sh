#!/usr/bin/env bash
# tick-loop.sh — one pass of the groundhog tick.
#
# Pure router: ticks groundhog, then moves each materialised item into
# .nest/in/. The tender owns shape recognition and transcript writes;
# this loop never writes transcript turns.

set -uo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[ -e "$GREMLIN_DIR/.paused" ] && exit 0

GH="$GREMLIN_DIR/.groundhog"
NEST_IN="$GREMLIN_DIR/.nest/in"

"$GH/groundhog.sh" tick

for item in "$GH/out"/*; do
  [ -e "$item" ] || continue
  base="$(basename "$item")"
  case "$base" in
    .gitkeep) continue ;;
  esac
  [ -d "$item" ] || continue

  target="$NEST_IN/$base"
  n=2
  while [ -e "$target" ]; do
    target="$NEST_IN/$base-$n"
    n=$((n+1))
  done
  mv "$item" "$target"
done

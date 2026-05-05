#!/usr/bin/env bash
# tick-loop.sh — one pass of the groundhog tick.
#
# 1. Tick groundhog so any due items materialize in .groundhog/out/.
# 2. Route each materialized item:
#    - has message.md → outbound: append the body to transcript.md as a
#      fresh `## assistant —` turn, then drop the materialised item.
#    - otherwise → tending: move the directory into .nest/in/ for the tender.

set -uo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[ -e "$GREMLIN_DIR/.paused" ] && exit 0

GH="$GREMLIN_DIR/.groundhog"
NEST_IN="$GREMLIN_DIR/.nest/in"
TRANSCRIPT="$GREMLIN_DIR/transcript.md"

"$GH/groundhog.sh" tick

for item in "$GH/out"/*; do
  [ -e "$item" ] || continue
  base="$(basename "$item")"
  case "$base" in
    .gitkeep) continue ;;
  esac
  [ -d "$item" ] || continue

  if [ -f "$item/message.md" ]; then
    iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    body="$(cat "$item/message.md")"
    printf '## assistant — %s\n%s\n\n' "$iso" "$body" >> "$TRANSCRIPT"
    rm -rf "$item"
  else
    target="$NEST_IN/$base"
    n=2
    while [ -e "$target" ]; do
      target="$NEST_IN/$base-$n"
      n=$((n+1))
    done
    mv "$item" "$target"
  fi
done

#!/usr/bin/env bash
# continue.sh — self-delegation: queue a note-to-self for the next tend.
#
# Usage:
#   ./.gremlin/tools/continue.sh "next step: ..."   # arg
#   echo "next step: ..." | ./.gremlin/tools/continue.sh   # stdin
#
# Writes the message into this gremlin's own .nest/in/ as an ordinary inbound
# item, then returns immediately (fire-and-forget — no wait for a reply). The
# tender picks it up on its next pass, so a long task can proceed as many short
# tends instead of one long opaque turn. This is delegation (docs/composition.md)
# pointed at self; the landed item is just another inbox message.
#
# It never touches transcript.md — the tender is the sole transcript writer.
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NESTLING="$GREMLIN_DIR/.nest/nestling.sh"

if [ "$#" -gt 0 ]; then
  msg="$*"
else
  msg="$(cat)"
fi

if [ -z "$msg" ]; then
  echo "usage: $0 <next-step message>   (or pipe via stdin)" >&2
  exit 2
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$msg" > "$tmp"
# The name carries a timestamp for ordering plus a random suffix for
# uniqueness: a long task doing quick back-to-back steps can re-queue twice
# within the same wall-clock second, and a bare second-resolution name would
# collide on ingest — silently dropping a step. The suffix keeps every
# self-continuation distinct while preserving lexical (time) ordering.
"$NESTLING" ingest "$tmp" "$(date -u +%Y-%m-%dT%H-%M-%SZ)-$RANDOM.md" >/dev/null

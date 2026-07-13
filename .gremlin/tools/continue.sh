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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '%s\n' "$msg" > "$tmp/instructions.md"
# A continuation is a note-to-self: re-running it is as safe as the human
# nudge it replaces (the model re-reads the transcript and re-assesses). Mark
# it recoverable so a watchdog timeout or tender crash re-queues the step
# under nestlings' bounded-attempts policy instead of dropping it — a dropped
# continuation strands the whole chain.
printf 'self-queued continuation — safe to re-run\n' > "$tmp/.recoverable"
# The name carries a timestamp for ordering plus a random suffix for
# uniqueness: a long task doing quick back-to-back steps can re-queue twice
# within the same wall-clock second, and a bare second-resolution name would
# collide on ingest — silently dropping a step. The suffix keeps every
# self-continuation distinct while preserving lexical (time) ordering. The
# `-continue-` marker is load-bearing: the tend loop's chain guard recognises
# a queued continuation by it, so an unrelated bridge message arriving
# mid-turn can't mask an unqueued chain.
"$NESTLING" ingest "$tmp" "$(date -u +%Y-%m-%dT%H-%M-%SZ)-continue-$RANDOM" >/dev/null

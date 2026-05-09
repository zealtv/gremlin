#!/usr/bin/env bash
# tend-loop.sh — one pass of the tend loop.
#
# Lists ready items in the nest, claims the oldest, dispatches by item
# shape, and archives the claimed item into .nest/out/.
#
# Shapes:
#   - directory with message.md (and no instructions.md) → no model;
#     emit `## system — 💌 message: <body>` and archive.
#   - directory with instructions.md, or a file item → model-backed:
#     emit `## user —`, run llm.sh, emit `## assistant —`, archive.
#
# The reply lives in transcript.md only; .nest/out/ records the inbound
# item, not the reply, per the nestlings protocol.
#
# Idempotent and single-shot: bin/run.sh invokes this on a cadence; each call
# processes at most one item.

set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_DIR="$(cd "$GREMLIN_DIR/.." && pwd)"

# .paused gate: while present, the loop is a no-op. Lets archive.sh (and
# any other coordinator) freeze the gremlin without killing the runner.
[ -e "$GREMLIN_DIR/.paused" ] && exit 0

# Run model/tool commands from the host workspace. Gremlin internals
# continue using absolute paths under GREMLIN_DIR.
cd "$HOST_DIR"

NEST="$GREMLIN_DIR/.nest"
NESTLING="$NEST/nestling.sh"
LLM="$GREMLIN_DIR/bin/llm.sh"
TRANSCRIPT="$GREMLIN_DIR/transcript.md"

items="$("$NESTLING" list)"
[ -n "$items" ] || exit 0

name="$(printf '%s\n' "$items" | head -n1)"
claimed_path="$("$NESTLING" claim "$name")"

# Shape dispatch. Directories with message.md (and no instructions.md)
# are non-model items routed in by tick-loop — emit a system turn and
# archive. Everything else is a model-backed tend.
if [ -d "$claimed_path" ] && [ -f "$claimed_path/message.md" ] && [ ! -f "$claimed_path/instructions.md" ]; then
  iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  body="$(cat "$claimed_path/message.md")"
  printf '## system — %s\n💌 message: %s\n\n' "$iso" "$body" >> "$TRANSCRIPT"
  "$NESTLING" complete "$name" "$claimed_path" >/dev/null
  exit 0
fi

# Model-backed path. Extract the body for the prompt.
if [ -d "$claimed_path" ]; then
  if [ -f "$claimed_path/instructions.md" ]; then
    body="$(cat "$claimed_path/instructions.md")"
  else
    body=""
  fi
else
  body="$(cat "$claimed_path")"
fi

# Tender owns transcript writes for both turns. Bridges only drop into
# .nest/in/; the user turn lands here at claim time.
iso_user="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '## user — %s\n%s\n\n' "$iso_user" "$body" >> "$TRANSCRIPT"

prompt_file="$(mktemp)"
trap 'rm -f "$prompt_file"' EXIT

{
  cat "$GREMLIN_DIR/gremlin.md"
  echo
  if [ -d "$GREMLIN_DIR/context" ]; then
    for f in "$GREMLIN_DIR/context"/*.md; do
      [ -e "$f" ] || continue
      cat "$f"
      echo
    done
  fi
  if [ -f "$GREMLIN_DIR/skills/INDEX.md" ]; then
    cat "$GREMLIN_DIR/skills/INDEX.md"
    echo
  fi
  if [ -f "$GREMLIN_DIR/tools/README.md" ]; then
    cat "$GREMLIN_DIR/tools/README.md"
    echo
  fi
  if [ -s "$TRANSCRIPT" ]; then
    cat "$TRANSCRIPT"
    echo
  fi
  printf '%s\n' "$body"
} > "$prompt_file"

reply="$("$LLM" < "$prompt_file")"

iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Transcript format: `## <role> — <iso>` header, body, single blank line.
# One `>>` per turn so concurrent appends with `say` don't interleave.
printf '## assistant — %s\n%s\n\n' "$iso" "$reply" >> "$TRANSCRIPT"

# Archive the inbound item into .nest/out/. The reply is already in the
# transcript; the protocol wants out/ to record what was actioned, not
# what was replied.
"$NESTLING" complete "$name" "$claimed_path" >/dev/null

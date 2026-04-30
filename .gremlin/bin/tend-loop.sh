#!/usr/bin/env bash
# tend-loop.sh — one pass of the tend loop.
#
# Lists ready items in the nest, claims the oldest, assembles a prompt from
# identity + context + transcript + item body, calls bin/llm.sh, writes the
# reply to .nest/out/<ts>.md, appends the assistant turn to transcript.md,
# and completes the claimed item.
#
# Idempotent and single-shot: run.sh invokes this on a cadence; each call
# processes at most one item.

set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEST="$GREMLIN_DIR/.nest"
NESTLING="$NEST/nestling.sh"
LLM="$GREMLIN_DIR/bin/llm.sh"
TRANSCRIPT="$GREMLIN_DIR/transcript.md"

items="$("$NESTLING" list)"
[ -n "$items" ] || exit 0

name="$(printf '%s\n' "$items" | head -n1)"
claimed_path="$("$NESTLING" claim "$name")"

# Extract the item body. Items may be files or directories (attachments
# extension). For directories, the convention is a message.md inside.
if [ -d "$claimed_path" ]; then
  if [ -f "$claimed_path/message.md" ]; then
    body="$(cat "$claimed_path/message.md")"
  else
    body=""
  fi
else
  body="$(cat "$claimed_path")"
fi

prompt_file="$(mktemp)"
reply_file="$(mktemp)"
trap 'rm -f "$prompt_file" "$reply_file"' EXIT

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
  # Skills INDEX.md and tools/README.md are added at stages 6 and 5.
  if [ -s "$TRANSCRIPT" ]; then
    cat "$TRANSCRIPT"
    echo
  fi
  printf '%s\n' "$body"
} > "$prompt_file"

reply="$("$LLM" < "$prompt_file")"
printf '%s\n' "$reply" > "$reply_file"

iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fname_ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"

# Transcript format: `## <role> — <iso>` header, body, single blank line.
# One `>>` per turn so concurrent appends with `say` don't interleave.
printf '## assistant — %s\n%s\n\n' "$iso" "$reply" >> "$TRANSCRIPT"

"$NESTLING" complete "$name" "$reply_file" "$fname_ts.md" >/dev/null

#!/usr/bin/env bash
# tend-loop.sh — one pass of the tend loop.
#
# Lists ready items in the nest, claims the oldest, dispatches by item
# shape, and archives the claimed item into .nest/out/.
#
# Shapes (checked in order; first match wins):
#   - directory with executable run.sh → no model; run the script in the
#     host folder, emit `## system — ⚙️ run: <stdout>` (or `⚠️ error:` on
#     non-zero exit), and archive. run.sh wins over message.md.
#   - directory with run.sh that is not executable → drop with reason; the
#     item named itself a script and is malformed, so don't fall through
#     to the model.
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

# Shape dispatch. run.sh is checked before message.md so a script wins
# when both exist (more specific). All non-model branches archive via
# nestling and exit; only the model-backed path falls through.

if [ -d "$claimed_path" ] && [ -e "$claimed_path/run.sh" ]; then
  if [ -x "$claimed_path/run.sh" ]; then
    iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    rc=0
    out="$("$claimed_path/run.sh")" || rc=$?
    if [ "$rc" -eq 0 ]; then
      if [ -n "$out" ]; then
        printf '## system — %s\n⚙️ run: %s\n\n' "$iso" "$out" >> "$TRANSCRIPT"
      fi
    else
      tail_out="$(printf '%s\n' "$out" | tail -n 20)"
      if [ -n "$tail_out" ]; then
        printf '## system — %s\n⚠️ error: run.sh exited %d\n%s\n\n' "$iso" "$rc" "$tail_out" >> "$TRANSCRIPT"
      else
        printf '## system — %s\n⚠️ error: run.sh exited %d\n\n' "$iso" "$rc" >> "$TRANSCRIPT"
      fi
    fi
    "$NESTLING" complete "$name" "$claimed_path" >/dev/null
    exit 0
  else
    echo "tend-loop: run.sh in '$name' is not executable; dropping" >&2
    "$NESTLING" drop "$name" "run.sh present but not executable" >/dev/null
    exit 0
  fi
fi

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
reply_file="$(mktemp)"
PIDFILE="$GREMLIN_DIR/.tending.pid"
trap 'rm -f "$prompt_file" "$reply_file" "$PIDFILE"' EXIT

{
  cat "$GREMLIN_DIR/gremlin.md"
  echo
  if [ -d "$GREMLIN_DIR/context" ]; then
    if [ -d "$GREMLIN_DIR/context/system" ]; then
      for f in "$GREMLIN_DIR/context/system"/*.md; do
        [ -L "$f" ] || continue
        cat "$f"
        echo
      done
    fi
    for f in "$GREMLIN_DIR/context"/*.md; do
      [ -e "$f" ] || continue
      cat "$f"
      echo
    done
  fi
  # Auto-recall: pull in findings whose Glean triggers fire on this message, so
  # memory is used deterministically instead of only when the agent chooses to
  # search. Promoted findings already arrive through context/ above; skip those
  # by basename to avoid loading them twice. Capped to keep context lean.
  if [ -x "$GREMLIN_DIR/.glean/glean.sh" ]; then
    recalled=0
    while IFS= read -r finding; do
      [ -n "$finding" ] || continue
      base="$(basename "$finding")"
      if [ -e "$GREMLIN_DIR/context/$base" ] || [ -e "$GREMLIN_DIR/context/system/$base" ]; then
        continue
      fi
      if [ "$recalled" -eq 0 ]; then
        printf '## recalled memory\n\n'
        printf 'Findings whose triggers matched this message — treat as background context.\n\n'
      fi
      cat "$finding"
      echo
      recalled=$((recalled + 1))
      if [ "$recalled" -ge 5 ]; then break; fi
    done < <(printf '%s' "$body" | "$GREMLIN_DIR/.glean/glean.sh" recall 2>/dev/null)
  fi
  if [ -s "$TRANSCRIPT" ]; then
    cat "$TRANSCRIPT"
    echo
  fi
  printf '%s\n' "$body"
} > "$prompt_file"

# Per-item model override: if the claimed directory contains a .model
# file, its single-line alias takes precedence over the gremlin-wide
# .model setting for this tend. Lets a scheduled item pick a cheaper or
# heavier preset than the default.
if [ -d "$claimed_path" ] && [ -f "$claimed_path/.model" ]; then
  item_model="$(tr -d '[:space:]' < "$claimed_path/.model")"
  [ -n "$item_model" ] && export GREMLIN_MODEL="$item_model"
fi

# Run the model in its own process group so /stop can signal the whole
# tree (the preset's curl/jq/SDK children too) with a single kill.
# `set -m` makes the backgrounded command its own pgid (== pid in bash),
# portably across macOS and Linux without depending on `setsid`.
set -m
"$LLM" < "$prompt_file" > "$reply_file" &
llm_pid=$!
set +m
printf '%s\n' "$llm_pid" > "$PIDFILE.tmp"
mv "$PIDFILE.tmp" "$PIDFILE"

rc=0
wait "$llm_pid" || rc=$?
rm -f "$PIDFILE"

# Abort path: /stop kills the pgid and moves the claim out of .nest/in/
# into .nest/dropped/. If the claim is gone, treat this as a clean abort
# — /stop already wrote the system turn — and exit without an assistant
# turn or a complete-into-out/.
if [ "$rc" -ne 0 ] && [ ! -e "$claimed_path" ]; then
  exit 0
fi

if [ "$rc" -ne 0 ]; then
  echo "tend-loop: llm.sh exited $rc" >&2
  exit "$rc"
fi

reply="$(cat "$reply_file")"

iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Transcript format: `## <role> — <iso>` header, body, single blank line.
# One `>>` per turn so concurrent appends with `say` don't interleave.
#
# Empty reply on a clean exit: the preset returned no stdout (a harness
# refusal, an auth/rate condition that leaked to stderr, etc). Surface it
# as a loud system error rather than a silent empty `## assistant —`,
# which bridges correctly decline to push.
if [ -z "${reply//[[:space:]]/}" ]; then
  printf '## system — %s\n⚠️ error: empty model reply\n\n' "$iso" >> "$TRANSCRIPT"
else
  printf '## assistant — %s\n%s\n\n' "$iso" "$reply" >> "$TRANSCRIPT"
fi

# Archive the inbound item into .nest/out/. The reply is already in the
# transcript; the protocol wants out/ to record what was actioned, not
# what was replied.
"$NESTLING" complete "$name" "$claimed_path" >/dev/null

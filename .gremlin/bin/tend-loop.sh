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

PIDFILE="$GREMLIN_DIR/.tending.pid"

# Nestlings reports old claims but deliberately does not infer abandonment.
# Gremlin owns that policy because it owns the tender process group. Resolve
# stale claims only when the recorded group is absent or dead.
tender_alive() {
  local pgid
  [ -f "$PIDFILE" ] || return 1
  pgid="$(tr -d '[:space:]' < "$PIDFILE")"
  [[ "$pgid" =~ ^[0-9]+$ ]] || return 1
  kill -0 -- "-$pgid" 2>/dev/null
}

recover_stale_claims() {
  tender_alive && return 0
  rm -f "$PIDFILE"

  local name outcome
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    outcome="$("$NESTLING" resolve "$name" \
      "orphaned stale claim (tender exited without completing it)" 2>&1)" \
      || echo "tend-loop: resolve failed for $name: $outcome" >&2
  done < <("$NESTLING" stale)
}

recover_stale_claims

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
  # Surface attachment files (anything besides the control files) as absolute
  # paths so the model can open them — e.g. an image the bridge downloaded.
  # The item dir was renamed on claim, so these post-claim paths are the
  # authoritative ones; instructions.md refers to the files by bare name.
  attachments=""
  for af in "$claimed_path"/*; do
    [ -e "$af" ] || continue
    case "$(basename "$af")" in
      instructions.md | message.md | run.sh) continue ;;
    esac
    attachments="${attachments}- ${af}
"
  done
  if [ -n "$attachments" ]; then
    body="${body}

## attachments

Files attached to this message (absolute paths you can open):
${attachments}"
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
err_file="$(mktemp)"
timeout_flag="$(mktemp)"
trap 'rm -f "$prompt_file" "$reply_file" "$err_file" "$timeout_flag" "$PIDFILE"' EXIT

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
  # The current turn is already the tail of the transcript (appended at claim
  # time above), so dumping the transcript presents it exactly once — headed and
  # last, which is the active message to answer. No separate trailing echo: a
  # bare restatement here would duplicate the turn and risk double-counting.
  if [ -s "$TRANSCRIPT" ]; then
    cat "$TRANSCRIPT"
    echo
  fi
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
"$LLM" < "$prompt_file" > "$reply_file" 2> "$err_file" &
llm_pid=$!
set +m
printf '%s\n' "$llm_pid" > "$PIDFILE.tmp"
mv "$PIDFILE.tmp" "$PIDFILE"

# Watchdog: bound the model call so a hung preset can't wedge the claim
# forever. On overrun, signal the whole process group — the same pgid /stop
# targets (set -m made llm_pid its own pgid) — so the preset's children die
# too, and flag it as a timeout. GREMLIN_MODEL_TIMEOUT=0 disables the bound.
timeout_secs="${GREMLIN_MODEL_TIMEOUT:-900}"
case "$timeout_secs" in ''|*[!0-9]*) timeout_secs=0 ;; esac
watchdog_pid=""
if [ "$timeout_secs" -gt 0 ]; then
  (
    sleep "$timeout_secs"
    kill -0 "$llm_pid" 2>/dev/null || exit 0
    printf 'timeout\n' > "$timeout_flag"
    kill -TERM -- "-$llm_pid" 2>/dev/null || true
    sleep 5
    kill -KILL -- "-$llm_pid" 2>/dev/null || true
  ) &
  watchdog_pid=$!
fi

rc=0
wait "$llm_pid" || rc=$?

# Model settled (finished or was killed) — retire the watchdog so its sleep
# doesn't outlive the turn.
if [ -n "$watchdog_pid" ]; then
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
fi
rm -f "$PIDFILE"

timed_out=0
[ -s "$timeout_flag" ] && timed_out=1

# Abort path: /stop kills the pgid and moves the claim out of .nest/in/
# into .nest/dropped/. If the claim is gone, treat this as a clean abort
# — /stop already wrote the system turn — and exit without an assistant
# turn or a complete-into-out/.
if [ "$rc" -ne 0 ] && [ ! -e "$claimed_path" ]; then
  exit 0
fi

# Failure path: the model exited non-zero (a real failure, or killed by the
# timeout watchdog) but the claim is still here — not the /stop abort above.
# Surface it loudly in the transcript with any stderr tail, then resolve the
# claim through the recovery policy — re-queue if recoverable and under its
# attempt limit, otherwise drop — so it never sits as silent *.tending residue.
if [ "$rc" -ne 0 ]; then
  if [ "$timed_out" -eq 1 ]; then
    detail="model timed out after ${timeout_secs}s"
  else
    detail="model exited $rc"
  fi
  echo "tend-loop: $detail" >&2
  iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  err_tail="$(tail -n 20 "$err_file" 2>/dev/null)"
  if [ -n "${err_tail//[[:space:]]/}" ]; then
    printf '## system — %s\n⚠️ error: %s\n%s\n\n' "$iso" "$detail" "$err_tail" >> "$TRANSCRIPT"
  else
    printf '## system — %s\n⚠️ error: %s\n\n' "$iso" "$detail" >> "$TRANSCRIPT"
  fi
  outcome="$("$NESTLING" resolve "$name" "$detail" 2>&1)" \
    || echo "tend-loop: resolve failed for $name: $outcome" >&2
  exit "$rc"
fi

reply="$(cat "$reply_file")"

iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Transcript format: `## <role> — <iso>` header, body, single blank line.
# One `>>` per turn so concurrent appends with `say` don't interleave.
#
# A reply of exactly `<silent>` is a stated sentinel: the gremlin chose not
# to speak. Complete the item but write no turn. Checked before the empty
# branch so a genuine empty reply stays a loud error, not silence.
#
# Empty reply on a clean exit: the preset returned no stdout (a harness
# refusal, an auth/rate condition that leaked to stderr, etc). Surface it
# as a loud system error rather than a silent empty `## assistant —`,
# which bridges correctly decline to push.
if [ "${reply//[[:space:]]/}" = "<silent>" ]; then
  : # silence: stated sentinel, no transcript turn
elif [ -z "${reply//[[:space:]]/}" ]; then
  printf '## system — %s\n⚠️ error: empty model reply\n\n' "$iso" >> "$TRANSCRIPT"
else
  printf '## assistant — %s\n%s\n\n' "$iso" "$reply" >> "$TRANSCRIPT"
fi

# Archive the inbound item into .nest/out/. The reply is already in the
# transcript; the protocol wants out/ to record what was actioned, not
# what was replied.
"$NESTLING" complete "$name" "$claimed_path" >/dev/null

#!/usr/bin/env bash
# long-task.sh — regression for the long-task start/progress compliance stitch.
#
# Origin: on 2026-06-30 a ~3-minute vendored-primitives sync (inspect, edit,
# test, commit, loom tie-off) produced only a final turn — no start
# announcement, no intermediate progress. The long-task skill exists; the gap
# was behavioural: a multi-step task that *fits* in one silent tend was run as
# one opaque span.
#
# This test pins the machinery the fixed skill relies on: when the model plays
# the long-task protocol (announce first, then one bounded step per tend,
# re-queuing itself with tools/continue.sh), observers see — in transcript
# order — a start turn, at least one earned progress turn, and a final turn,
# each as its own `## assistant` turn. A short task stays a single quiet turn.
#
# The model itself is non-deterministic, so we can't assert it *chooses* the
# protocol here; we stub the model to follow it and prove the tender + nest +
# continue.sh chain surfaces every step as a distinct, ordered turn. Skill-level
# trigger wording is the other half of the fix and lives in skills/long-task.md.
#
# Usage: ./test/long-task.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

HOST="$TMP/host"
mkdir -p "$HOST"
cp -R "$ROOT/.gremlin" "$HOST/.gremlin"
GREMLIN="$HOST/.gremlin"
NEST="$GREMLIN/.nest"
TRANSCRIPT="$GREMLIN/transcript.md"

reset_nest() {
  rm -rf "$NEST/in" "$NEST/out" "$NEST/dropped"
  mkdir -p "$NEST/in" "$NEST/out" "$NEST/dropped"
  : > "$TRANSCRIPT"
  rm -f "$GREMLIN/.tending.pid" "$GREMLIN/.test-step"
}

# Stub the single LLM seam with a scripted long-task tender. When the
# `.test-longtask` flag is present it plays the protocol driven by a per-tend
# step counter, calling the real tools/continue.sh to re-queue itself — exactly
# what a compliant model would do. Otherwise it answers a short task in one turn.
cat > "$GREMLIN/bin/llm.sh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
cat >/dev/null   # drain the assembled prompt
GDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ ! -e "$GDIR/.test-longtask" ]]; then
  echo "SHORTTURN 4"
  exit 0
fi

step=0
[[ -f "$GDIR/.test-step" ]] && step="$(cat "$GDIR/.test-step")"
case "$step" in
  0) echo "STARTTURN on it — syncing the vendored primitives across three repos; I'll report as I go"
     "$GDIR/tools/continue.sh" "step 1/3: inspect the vendored copies, patch drift" >/dev/null ;;
  1) echo "PROGRESSTURN inspected and patched the three vendored copies; running tests next"
     "$GDIR/tools/continue.sh" "step 2/3: run the tests, then commit" >/dev/null ;;
  2) echo "PROGRESSTURN tests green; committing and tying off the loom stitch"
     "$GDIR/tools/continue.sh" "step 3/3: commit and tie off" >/dev/null ;;
  *) echo "FINALTURN ✅ synced, committed, loom tied off" ;;
esac
echo "$((step + 1))" > "$GDIR/.test-step"
STUB
chmod +x "$GREMLIN/bin/llm.sh"

queue() {  # queue <name> <body>
  mkdir -p "$NEST/in/$1"
  printf '%s\n' "$2" > "$NEST/in/$1/instructions.md"
}

drain() {  # run tends until the nest is quiet (bounded against a runaway chain)
  local guard=0
  while [ -n "$("$NEST/nestling.sh" list)" ] && [ "$guard" -lt 12 ]; do
    "$GREMLIN/bin/tend-loop.sh" >/dev/null 2>&1
    guard=$((guard + 1))
  done
}

line_of() { grep -n -- "$2" "$1" | head -n1 | cut -d: -f1; }
count_of() { grep -c -- "$2" "$1"; }

# ============================================================================
echo "== a multi-step task surfaces start -> progress -> final, each its own turn =="

reset_nest
touch "$GREMLIN/.test-longtask"
queue sync-primitives "sync the vendored primitives across every repo"
drain

turns="$(count_of "$TRANSCRIPT" '^## assistant —')"
[ "$turns" -ge 3 ] && ok "at least three assistant turns (got $turns)" \
  || bad "expected >=3 assistant turns, got $turns"

starts="$(count_of "$TRANSCRIPT" 'STARTTURN')"
progs="$(count_of "$TRANSCRIPT" 'PROGRESSTURN')"
finals="$(count_of "$TRANSCRIPT" 'FINALTURN')"
[ "$starts" -eq 1 ] && ok "exactly one start announcement" || bad "start turns: $starts (want 1)"
[ "$progs" -ge 1 ] && ok "at least one earned progress turn (got $progs)" || bad "progress turns: $progs (want >=1)"
[ "$finals" -eq 1 ] && ok "exactly one final turn" || bad "final turns: $finals (want 1)"

# Each scripted line landed under its own `## assistant —` header — no lumping
# of steps into a single opaque turn.
sentinels=$((starts + progs + finals))
[ "$turns" -eq "$sentinels" ] && ok "every step is a distinct assistant turn ($turns == $sentinels)" \
  || bad "assistant turns ($turns) != scripted step lines ($sentinels)"

# Order in the transcript: start before any progress, progress before final.
s="$(line_of "$TRANSCRIPT" 'STARTTURN')"
p="$(line_of "$TRANSCRIPT" 'PROGRESSTURN')"
f="$(line_of "$TRANSCRIPT" 'FINALTURN')"
if [ -n "$s" ] && [ -n "$p" ] && [ -n "$f" ] && [ "$s" -lt "$p" ] && [ "$p" -lt "$f" ]; then
  ok "start ($s) < progress ($p) < final ($f)"
else
  bad "out-of-order turns: start=$s progress=$p final=$f"
fi

# The start announcement is the first thing spoken — before the work, not after.
first_assistant="$(line_of "$TRANSCRIPT" '^## assistant —')"
[ -n "$first_assistant" ] && [ -n "$s" ] && [ "$s" -gt "$first_assistant" ] \
  && [ "$((s - first_assistant))" -le 2 ] \
  && ok "first assistant turn is the start announcement" \
  || bad "first assistant turn is not the start announcement (assistant@$first_assistant start@$s)"

# The chain stopped on its own — no dangling re-queue after the final turn.
[ -z "$("$NEST/nestling.sh" list)" ] && ok "chain terminated (inbox empty)" \
  || bad "inbox not empty after final turn"

# ============================================================================
echo "== a short task stays a single quiet turn =="

reset_nest
rm -f "$GREMLIN/.test-longtask"
queue quick "what's 2 plus 2?"
"$GREMLIN/bin/tend-loop.sh" >/dev/null 2>&1

turns="$(count_of "$TRANSCRIPT" '^## assistant —')"
[ "$turns" -eq 1 ] && ok "short task is exactly one assistant turn" || bad "short task turns: $turns (want 1)"
[ "$(count_of "$TRANSCRIPT" 'STARTTURN')" -eq 0 ] && ok "no start-announcement ceremony for trivia" \
  || bad "short task emitted a long-task start turn"
[ -z "$("$NEST/nestling.sh" list)" ] && ok "short task did not re-queue itself" \
  || bad "short task left work in the inbox"

# ============================================================================
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
echo "ok - long-task start/progress compliance"

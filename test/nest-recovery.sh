#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "not ok - $*" >&2; exit 1; }
assert_exists() { [[ -e "$1" ]] || fail "missing $1"; }
assert_absent() { [[ ! -e "$1" ]] || fail "unexpected $1"; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "$1 does not contain [$2]"; }

HOST="$TMP/host"
mkdir -p "$HOST"
cp -R "$ROOT/.gremlin" "$HOST/.gremlin"
GREMLIN="$HOST/.gremlin"
NEST="$GREMLIN/.nest"
rm -rf "$NEST/in" "$NEST/out" "$NEST/dropped"
mkdir -p "$NEST/in" "$NEST/out" "$NEST/dropped"
: > "$GREMLIN/transcript.md"
rm -f "$GREMLIN/.tending.pid"

# A deterministic model stub: success by default, requested failure otherwise.
cat > "$GREMLIN/bin/llm.sh" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
if [[ "${TEST_LLM_RC:-0}" -ne 0 ]]; then
  echo "stub model failure" >&2
  exit "$TEST_LLM_RC"
fi
echo "stub reply"
EOF
chmod +x "$GREMLIN/bin/llm.sh"

queue_recoverable() {
  local name="$1"
  mkdir -p "$NEST/in/$name"
  touch "$NEST/in/$name/.recoverable"
  printf 'test %s\n' "$name" > "$NEST/in/$name/instructions.md"
}

# A live tender process group prevents stale resolution.
queue_recoverable live-guard
"$NEST/nestling.sh" claim live-guard >/dev/null
touch -t 200001010000 "$NEST/in/live-guard.tending"
pgid="$(ps -o pgid= -p $$ | tr -d '[:space:]')"
printf '%s\n' "$pgid" > "$GREMLIN/.tending.pid"
"$GREMLIN/bin/tend-loop.sh"
assert_exists "$NEST/in/live-guard.tending"

# A dead/missing pid permits resolution; the same pass processes the retry.
rm -f "$GREMLIN/.tending.pid"
"$GREMLIN/bin/tend-loop.sh"
assert_exists "$NEST/out/live-guard/.recovery.md"
assert_contains "$NEST/out/live-guard/.recovery.md" "attempt: 1/3"

# Model failures hand the claim to canonical resolve and stop at the cap.
queue_recoverable model-failure
for attempt in 1 2; do
  if TEST_LLM_RC=42 NEST_MAX_ATTEMPTS=2 "$GREMLIN/bin/tend-loop.sh"; then
    fail "model failure returned success on attempt $attempt"
  fi
  assert_exists "$NEST/in/model-failure"
done
if TEST_LLM_RC=42 NEST_MAX_ATTEMPTS=2 "$GREMLIN/bin/tend-loop.sh"; then
  fail "exhausted model failure returned success"
fi
assert_exists "$NEST/dropped/model-failure"
assert_contains "$NEST/dropped/model-failure.reason.md" "recovery attempts exhausted (2/2)"

# /stop is an explicit user action and drops directly, even when recoverable,
# while canonical drop keeps an existing same-named history collision-safe.
mkdir -p "$NEST/dropped/stopped"
printf 'prior\n' > "$NEST/dropped/stopped.reason.md"
queue_recoverable stopped
"$NEST/nestling.sh" claim stopped >/dev/null
printf '99999999\n' > "$GREMLIN/.tending.pid"
"$GREMLIN/commands/stop.sh" >/dev/null
assert_exists "$NEST/dropped/stopped"
assert_absent "$NEST/in/stopped"
stopped_histories="$(find "$NEST/dropped" -mindepth 1 -maxdepth 1 -name 'stopped*' ! -name '*.reason.md' | wc -l | tr -d ' ')"
[[ "$stopped_histories" == 2 ]] || fail "expected two stopped histories, got $stopped_histories"

echo "ok - gremlin canonical nest recovery integration"

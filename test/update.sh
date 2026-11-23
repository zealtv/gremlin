#!/usr/bin/env bash
# update.sh — /update from a local tarball: it rebuilds the skills index, and
# says when bin/run.sh changed under a running gremlin, and only then.
#
# Usage: ./test/update.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
RUNNER_PID=""
cleanup() {
  [ -n "$RUNNER_PID" ] && pkill -P "$RUNNER_PID" 2>/dev/null; [ -n "$RUNNER_PID" ] && kill "$RUNNER_PID" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

NOTE='bin/run.sh changed'

# A canonical tarball built from this checkout, the way GitHub ships one: a
# single top-level directory holding .gremlin/.
make_tarball() {  # make_tarball <name> — from $TMP/canon
  tar -czf "$TMP/$1.tar.gz" -C "$TMP" canon
}

HOST="$TMP/host"
mkdir -p "$HOST" "$TMP/canon"
cp -R "$ROOT/.gremlin" "$HOST/.gremlin"
cp -R "$ROOT/.gremlin" "$TMP/canon/.gremlin"
G="$HOST/.gremlin"
# A skill of the host's own, which the canonical index does not list.
cat > "$G/skills/host-own.md" <<'SKILL'
---
name: host-own
triggers:
  - a host's own skill
---
# host-own
SKILL
"$G/bin/index-skills.sh" >/dev/null

run_update() {  # run_update <tarball name>
  printf 'file://%s\n' "$TMP/$1.tar.gz" > "$G/.upstream"
  "$G/commands/update.sh" 2>&1
}

# 1. Asleep, run.sh unchanged: no note; the host's skill stays in the index.
make_tarball same
out="$(run_update same)"
printf '%s\n' "$out" | grep -q '✨ updated' && ok "the update ran" || bad "the update did not run: $out"
printf '%s\n' "$out" | grep -qF "$NOTE" && bad "a note with run.sh unchanged" || ok "no note when run.sh is unchanged"
grep -q '`host-own`' "$G/skills/INDEX.md" && ok "the host's own skill is still indexed" \
  || bad "the overlay dropped the host's own skill from the index"

# 2. Awake (a process running this host's bin/run.sh), only a doc changed: no note.
# A stand-in runner: a shell whose command line names this host's
# bin/run.sh, so pgrep -f finds it the way gremlin's own status does, with no
# loops to tend anything.
start_runner() {
  bash -c 'sleep 30; :' "$G/bin/run.sh" &
  RUNNER_PID=$!
  sleep 0.3
}
start_runner
echo "a docs change" >> "$TMP/canon/.gremlin/docs/protocol.md"
make_tarball doc
out="$(run_update doc)"
printf '%s\n' "$out" | grep -qF "$NOTE" && bad "a note when only a doc changed" || ok "no note when only a doc changed"

# 3. Awake, run.sh changed: the note.
echo "# a change" >> "$TMP/canon/.gremlin/bin/run.sh"
make_tarball runner
out="$(run_update runner)"
printf '%s\n' "$out" | grep -qF "$NOTE" && ok "awake with run.sh changed: says to restart" \
  || bad "no note with run.sh changed while awake: $out"
pkill -P "$RUNNER_PID" 2>/dev/null; kill "$RUNNER_PID" 2>/dev/null; wait "$RUNNER_PID" 2>/dev/null; RUNNER_PID=""

# 4. Asleep, run.sh changed again: no note (the next wake loads it).
echo "# another change" >> "$TMP/canon/.gremlin/bin/run.sh"
make_tarball runner2
out="$(run_update runner2)"
printf '%s\n' "$out" | grep -qF "$NOTE" && bad "a note while asleep" || ok "no note while asleep"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

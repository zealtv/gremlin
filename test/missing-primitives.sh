#!/usr/bin/env bash
# missing-primitives.sh — a copy of .gremlin/ with no primitives says what it
# lacks, instead of waking a loop that errors every few seconds.
#
# Covers: wake refuses without a nest (and starts nothing, writes nothing to
# the log); prompt and tend fail with one clear line, not exit 127; status and
# sleep keep working; doctor no longer calls the host files ok; and a host
# that has a nest is not stopped by the check.
#
# Usage: ./test/missing-primitives.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
HOST="$TMP/host"
trap '"$HOST/.gremlin/gremlin" sleep >/dev/null 2>&1; rm -rf "${TMP:?}"' EXIT

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

mkdir -p "$HOST"
cp -R "$ROOT/.gremlin" "$HOST/.gremlin"
printf 'echo\n' > "$HOST/.gremlin/.model"
G="$HOST/.gremlin/gremlin"
LOG="$HOST/.gremlin/run.log"
HINT='install-primitives.sh'

# 1. wake refuses, names the fix, and starts no loop.
out="$("$G" wake 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "wake exits non-zero without a nest" || bad "wake exited 0 without a nest"
printf '%s' "$out" | grep -q "$HINT" && ok "wake names install-primitives.sh" || bad "wake did not name the fix: $out"
printf '%s' "$out" | grep -q 'is awake' && bad "wake claimed to be awake" || ok "wake does not claim to be awake"
sleep 6
[ ! -s "$LOG" ] && ok "run.log stays empty (no loop started)" || bad "run.log has content: $(head -c 200 "$LOG")"

# 2. status and sleep still work.
out="$("$G" status 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'asleep' && ok "status says asleep" || bad "status failed: $out"
out="$("$G" sleep 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'asleep' && ok "sleep works" || bad "sleep failed: $out"

# 3. prompt and tend fail with the one line, not a bash 127.
for verb in "prompt hello" "tend"; do
  # shellcheck disable=SC2086
  out="$("$G" $verb 2>&1)"; rc=$?
  [ "$rc" -eq 1 ] && ok "$verb exits 1" || bad "$verb exited $rc (want 1): $out"
  printf '%s' "$out" | grep -q "$HINT" && ok "$verb names install-primitives.sh" || bad "$verb did not name the fix: $out"
  printf '%s' "$out" | grep -q 'No such file' && bad "$verb leaked a bash error" || ok "$verb leaks no bash error"
done

# 4. doctor does not call the host files ok when the primitives are missing.
out="$("$G" doctor 2>&1)"
printf '%s' "$out" | grep -q 'ok host files' && bad "doctor still says ok host files" || ok "doctor does not say ok host files"
printf '%s' "$out" | grep -q 'not installed at the host' && ok "doctor reports the scheduled jobs as not placed" \
  || bad "doctor did not report the jobs as not placed"

# 5. install-host-files.sh --check exits 1 and lists the unplaced files.
out="$("$HOST/.gremlin/bin/install-host-files.sh" --check "$HOST" 2>/dev/null)"; rc=$?
[ "$rc" -eq 1 ] && ok "--check exits 1 when a primitive is missing" || bad "--check exited $rc"
printf '%s' "$out" | grep -q '^missing .groundhog/' && ok "--check lists the unplaced files" || bad "--check listed nothing: $out"

# 6. With a nest in place, the check passes.
mkdir -p "$HOST/.nest"
printf '#!/bin/sh\nexit 0\n' > "$HOST/.nest/nestling.sh"; chmod +x "$HOST/.nest/nestling.sh"
"$HOST/.gremlin/bin/require-nest.sh" >/dev/null 2>&1 \
  && ok "require-nest.sh passes when .nest/nestling.sh exists" || bad "require-nest.sh failed with a nest present"

printf '\npassed: %d, failed: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || { echo "not ok - missing primitives" >&2; exit 1; }
echo "ok - missing primitives"

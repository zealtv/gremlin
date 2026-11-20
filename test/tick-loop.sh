#!/usr/bin/env bash
# tick-loop.sh — the tick loop routes delivery-only items into the nest and
# leaves a delivery groundhog runs itself (its item carried a `run`) in out/.
#
# Uses a sibling groundhog checkout when there is one (offline), else the
# network installer. The `run` cases need a groundhog with `handlers-v1`
# and are skipped on an older one.
#
# Usage: ./test/tick-loop.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }
skip() { printf '  skip %s\n' "$1"; }

PRIMITIVE_REPOS="${PRIMITIVE_REPOS:-$(cd "$ROOT/.." && pwd)}"

# new_host <name>: a host with .gremlin, .groundhog and a .nest/in directory.
new_host() {
  local h="$TMP/$1"
  mkdir -p "$h/.nest/in"
  cp -R "$ROOT/.gremlin" "$h/.gremlin"
  if [ -x "$PRIMITIVE_REPOS/groundhog/install.sh" ]; then
    "$PRIMITIVE_REPOS/groundhog/install.sh" "$h" >/dev/null 2>&1
  else
    "$h/.gremlin/bin/install-primitives.sh" "$h" groundhog >/dev/null 2>&1
  fi
  printf '%s' "$h"
}

# item <host> <id> [run]: a once item dated in the past, so the next tick fires it.
# With `run`, it also carries an executable `run` that leaves a marker.
item() {
  local d="$1/.groundhog/schedule/once/2000-01-01/$2"
  mkdir -p "$d"
  printf 'do the thing\n' > "$d/instructions.md"
  if [ "${3:-}" = run ]; then
    printf '#!/bin/sh\ntouch "$1/ran"\n' > "$d/run"
    chmod +x "$d/run"
  fi
}

# at <dir> <id>: the delivery of item <id> in <dir> (groundhog names a delivery
# <id>-<date>), or nothing.
at() { for d in "$1/$2" "$1/$2"-*; do [ -d "$d" ] && { printf '%s' "$d"; return 0; }; done; return 1; }

tick() { "$1/.gremlin/bin/tick-loop.sh" >/dev/null 2>&1; }

# wait_for <path>: up to ~5 s for a run started in the background.
wait_for() {
  local i=0
  while [ ! -e "$1" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
  [ -e "$1" ]
}

echo "tick-loop"

H="$(new_host plain)"
[ -x "$H/.groundhog/groundhog.sh" ] || { echo "not ok - no groundhog installed"; exit 1; }
handlers=0
"$H/.groundhog/groundhog.sh" capabilities --json 2>/dev/null | grep -q '"handlers-v1"' && handlers=1

# 1. A delivery-only item comes through the nest, as before.
item "$H" note
tick "$H"
[ -f "$(at "$H/.nest/in" note)/instructions.md" ] && ok "a delivery-only item lands in .nest/in/" \
  || bad "a delivery-only item did not reach the nest: $(ls -A "$H/.nest/in" "$H/.groundhog/out" | tr '\n' ' ')"
! at "$H/.groundhog/out" note >/dev/null && ok "and leaves out/" || bad "the delivered item is still in out/"

# 2. A delivery with its own `run` stays in out/ and runs there.
if [ "$handlers" = 1 ]; then
  H="$(new_host handler)"
  item "$H" job run
  tick "$H"
  job="$(at "$H/.groundhog/out" job)" && ok "a delivery with a run stays in out/" \
    || bad "a delivery with a run left out/"
  ! at "$H/.nest/in" job >/dev/null && ok "and never reaches the nest" || bad "a delivery with a run reached the nest"
  wait_for "${job:-$H/none}/ran" && ok "its run ran in out/" || bad "its run never ran"
  tick "$H"
  ! at "$H/.nest/in" job >/dev/null && ok "a later tick leaves it alone too" || bad "a later tick moved the finished delivery"
else
  skip "runs (this groundhog has no handlers-v1)"
fi

# 3. The gremlin's own pause: nothing fires.
H="$(new_host gremlin-paused)"
item "$H" note
touch "$H/.gremlin/.paused"
tick "$H"
[ -z "$(ls -A "$H/.groundhog/out" | grep -v '^\.gitkeep$')" ] && ! at "$H/.nest/in" note >/dev/null \
  && ok ".gremlin/.paused fires nothing" || bad ".gremlin/.paused still fired"

# 4. Groundhog's own pause (protocol 2, no token): nothing fires and no run starts.
if "$H/.groundhog/groundhog.sh" capabilities --json 2>/dev/null | grep -q '"pause-v2"'; then
  H="$(new_host groundhog-paused)"
  item "$H" note
  item "$H" job run
  "$H/.groundhog/groundhog.sh" pause >/dev/null 2>&1
  tick "$H"
  ! at "$H/.nest/in" note >/dev/null && ! at "$H/.groundhog/out" job >/dev/null \
    && ok "a paused groundhog fires nothing" || bad "a paused groundhog still fired"
  "$H/.groundhog/groundhog.sh" resume >/dev/null 2>&1
  tick "$H"
  [ -f "$(at "$H/.nest/in" note)/instructions.md" ] && at "$H/.groundhog/out" job >/dev/null \
    && ok "after resume, the item comes through and the run stays in out/" \
    || bad "after resume: nest $(ls -A "$H/.nest/in" | tr '\n' ' '), out $(ls -A "$H/.groundhog/out" | tr '\n' ' ')"
else
  skip "groundhog pause (this groundhog has no pause-v2)"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

#!/usr/bin/env bash
# run-loops.sh — run.sh keeps its tend loop alive when its sleep is killed,
# and stopping the gremlin leaves no loop or sleep behind.
#
# Starts run.sh on a temp host (no model: items are scripts the tender runs),
# kills the tend loop's own `sleep`, and checks a later item still gets tended.
# Then stops the gremlin two ways (a TERM to run.sh, and `gremlin sleep`) and
# checks that nothing it started is still running.
#
# Uses a sibling nestlings checkout when there is one (offline), else the
# network installer.
#
# Usage: ./test/run-loops.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

RUN_PID=""
SEEN=""   # every pid started under a run, so cleanup can reach what a stop missed

# descendants <pid>: its children, grandchildren and so on (one pid per line).
descendants() {
  ps -axo pid=,ppid= | awk -v root="$1" '
    { child[NR] = $1; parent[NR] = $2 }
    END {
      seen[root] = 1
      do {
        grew = 0
        for (i = 1; i <= NR; i++)
          if ((parent[i] in seen) && !(child[i] in seen)) { seen[child[i]] = 1; grew = 1; print child[i] }
      } while (grew)
    }'
}

cleanup() {
  local p
  for p in $RUN_PID $SEEN; do kill -9 "$p" 2>/dev/null; done
  rm -rf "${TMP:?}"
}
trap cleanup EXIT

alive() { kill -0 "$1" 2>/dev/null; }

# wait_until <seconds> <command...>: poll every 0.1 s until the command succeeds.
wait_until() {
  local max=$(( $1 * 10 )) i=0
  shift
  while ! "$@"; do
    i=$((i + 1))
    [ "$i" -ge "$max" ] && return 1
    sleep 0.1
  done
}

# new_host: a host with .gremlin and a nest, set to the echo model so that
# nothing here can reach a real one.
new_host() {
  local h="$TMP/host-$1" repos="${PRIMITIVE_REPOS:-$(cd "$ROOT/.." && pwd)}"
  mkdir -p "$h"
  cp -R "$ROOT/.gremlin" "$h/.gremlin"
  if [ -x "$repos/nestlings/install.sh" ]; then
    "$repos/nestlings/install.sh" "$h" >/dev/null 2>&1
  else
    "$h/.gremlin/bin/install-primitives.sh" "$h" nest >/dev/null 2>&1
  fi
  printf 'echo\n' > "$h/.gremlin/.model"
  : > "$h/.gremlin/transcript.md"
  printf '%s' "$h"
}

# start <host>: run.sh in the background, up to its two loop subshells.
start() {
  "$1/.gremlin/bin/run.sh" >> "$1/run.log" 2>&1 &
  RUN_PID=$!
  wait_until 10 two_loops
}
two_loops() { [ "$(ps -axo pid=,ppid= | awk -v p="$RUN_PID" '$2 == p' | wc -l)" -ge 2 ]; }

# tend_loop: the pid of the tend loop's subshell. run.sh starts it first, so it
# is the lower pid of run.sh's two children.
tend_loop() {
  ps -axo pid=,ppid= | awk -v p="$RUN_PID" '$2 == p { print $1 }' | sort -n | head -n 1
}

# tend_sleep: the pid of the sleep the tend loop is in, or nothing.
tend_sleep() {
  ps -axo pid=,ppid=,command= | awk -v p="$(tend_loop)" '$2 == p && $3 == "sleep" { print $1; exit }'
}
has_tend_sleep() { [ -n "$(tend_sleep)" ]; }

# item <host> <name>: an item the tender runs without a model; it leaves a marker.
item() {
  local d="$TMP/stage-$2"
  mkdir -p "$d"
  printf '#!/bin/sh\ntouch "%s/ran-%s"\n' "$1" "$2" > "$d/run.sh"
  chmod +x "$d/run.sh"
  mv "$d" "$1/.nest/in/$2"
}

tended() { [ -e "$1/ran-$2" ] && [ ! -e "$1/.nest/in/$2" ]; }

# kill_tend_sleep: kill the tend loop's own sleep; fail if it can't be found.
kill_tend_sleep() {
  local s
  wait_until 10 has_tend_sleep || return 1
  s="$(tend_sleep)"
  kill "$s" 2>/dev/null || return 1
  wait_until 5 sh -c "! kill -0 $s 2>/dev/null"
}

# gone <pids...>: none of them is running.
gone() { local p; for p in "$@"; do alive "$p" && return 1; done; return 0; }

echo "run-loops"

H="$(new_host kill)"
[ -x "$H/.nest/nestling.sh" ] || { echo "not ok - no nest installed"; exit 1; }
start "$H"
loop="$(tend_loop)"
two_loops && ok "run.sh starts its two loops" || bad "run.sh did not start two loops"

# 1. A killed sleep does not end the tend loop: a later item is still tended.
kill_tend_sleep && ok "the tend loop's sleep was killed" || bad "could not kill the tend loop's sleep"
sleep 0.3
alive "$loop" && ok "its loop is still running" || bad "the tend loop ended with its sleep"
item "$H" one
wait_until 15 tended "$H" one && ok "an item dropped after the kill is tended" \
  || bad "an item dropped after the kill was never tended"

# 2. And again, several times over: a pending item is tended right after the last kill.
wait_until 10 has_tend_sleep || bad "the tend loop has no sleep after a pass"
kill_tend_sleep; kill_tend_sleep
item "$H" two
kill_tend_sleep
wait_until 6 tended "$H" two && ok "the loop survives repeated kills" \
  || bad "an item was never tended after repeated kills"
alive "$loop" && ok "still the same loop" || bad "the tend loop ended"

# 3. A TERM to run.sh stops everything it started, sleeps included.
wait_until 10 has_tend_sleep
SEEN="$(descendants "$RUN_PID" | tr '\n' ' ')"
sleeps=0
for p in $SEEN; do
  [ "$(ps -o command= -p "$p" 2>/dev/null | awk '{ print $1 }')" = sleep ] && sleeps=$((sleeps + 1))
done
[ "$sleeps" -ge 2 ] && ok "two sleeps were running (tend, tick)" || bad "expected a tend and a tick sleep, saw $sleeps"
kill "$RUN_PID" 2>/dev/null
wait_until 5 gone "$RUN_PID" $SEEN \
  && ok "TERM to run.sh leaves no loop or sleep behind" \
  || bad "left running after TERM: $(for p in $RUN_PID $SEEN; do alive "$p" && printf '%s ' "$p"; done)"
RUN_PID=""

# 4. `gremlin sleep` (a TERM to run.sh and to both loops at once) does too.
H="$(new_host sleep)"
start "$H"
wait_until 10 has_tend_sleep
SEEN="$RUN_PID $(descendants "$RUN_PID" | tr '\n' ' ')"
"$H/.gremlin/gremlin" sleep >/dev/null 2>&1
wait_until 5 gone $SEEN \
  && ok "gremlin sleep leaves no loop or sleep behind" \
  || bad "left running after gremlin sleep: $(for p in $SEEN; do alive "$p" && printf '%s ' "$p"; done)"
RUN_PID=""

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

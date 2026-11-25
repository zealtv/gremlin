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

# cleanup: stop what a failing case may have left. Besides the pids a case
# noted, every process whose command line names one of this suite's hosts (a
# runner a missed `gremlin sleep` left, or one a second `wake` started) gets a
# TERM, so a runner's trap can take its sleeps with it, then a KILL.
cleanup() {
  local p left
  left="$(ps -A -o pid= -o args= 2>/dev/null | HOSTS="$TMP/host-" awk '{ pid = $1; sub(/^[ \t]*[0-9]+[ \t]+/, ""); if (index($0, ENVIRON["HOSTS"])) print pid }')"
  for p in $left; do kill "$p" 2>/dev/null; done
  sleep 0.3
  for p in $RUN_PID $SEEN $left; do kill -9 "$p" 2>/dev/null; done
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

# sleep_arg <pid>: the argument of the sleep that loop subshell <pid> is in, or nothing.
sleep_arg() {
  ps -axo pid=,ppid=,command= | awk -v p="$1" '$2 == p && $3 == "sleep" { print $4; exit }'
}

# find_tend_loop: tell the tend loop from the tick loop by what each sleeps:
# the tend loop naps 5 s, the tick loop until the next minute. At :55 both
# show `sleep 5`, and a loop between naps shows none, so it succeeds only once
# both loops nap and exactly one of them is in `sleep 5`; callers retry.
TEND_LOOP=""
find_tend_loop() {
  local c a fives=0 asleep=0 pick=""
  for c in $(ps -axo pid=,ppid= | awk -v p="$RUN_PID" '$2 == p { print $1 }'); do
    a="$(sleep_arg "$c")"
    [ -n "$a" ] && asleep=$((asleep + 1))
    if [ "$a" = 5 ]; then fives=$((fives + 1)); pick="$c"; fi
  done
  [ "$asleep" -eq 2 ] && [ "$fives" -eq 1 ] || return 1
  TEND_LOOP="$pick"
}
tend_loop() { printf '%s' "$TEND_LOOP"; }

# both_asleep: each of run.sh's two loop subshells is in its nap.
both_asleep() {
  local c n=0
  for c in $(ps -axo pid=,ppid= | awk -v p="$RUN_PID" '$2 == p { print $1 }'); do
    [ -n "$(sleep_arg "$c")" ] && n=$((n + 1))
  done
  [ "$n" -eq 2 ]
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
# kills counts the sleeps killed, for the run.log check below.
kills=0
kill_tend_sleep() {
  local s
  wait_until 10 has_tend_sleep || return 1
  s="$(tend_sleep)"
  kill "$s" 2>/dev/null || return 1
  kills=$((kills + 1))
  wait_until 5 sh -c "! kill -0 $s 2>/dev/null"
}

# early_lines <host>: how many times run.log says a nap's sleep ended early.
early_lines() { grep -c "a nap's sleep ended early" "$1/run.log" 2>/dev/null || true; }

# gone <pids...>: none of them is running.
gone() { local p; for p in "$@"; do alive "$p" && return 1; done; return 0; }

echo "run-loops"

H="$(new_host kill)"
[ -x "$H/.nest/nestling.sh" ] || { echo "not ok - no nest installed"; exit 1; }
start "$H"
two_loops && ok "run.sh starts its two loops" || bad "run.sh did not start two loops"
wait_until 10 find_tend_loop && ok "the tend loop is the one napping 5 s" || bad "could not tell the tend loop apart"
loop="$(tend_loop)"

# 1. A killed sleep does not end the tend loop: a later item is still tended.
kill_tend_sleep && ok "the tend loop's sleep was killed" || bad "could not kill the tend loop's sleep"
sleep 0.3
alive "$loop" && ok "its loop is still running" || bad "the tend loop ended with its sleep"
item "$H" one
wait_until 15 tended "$H" one && ok "an item dropped after the kill is tended" \
  || bad "an item dropped after the kill was never tended"

# 2. And again, several times over: a pending item is tended right after the last kill.
wait_until 10 has_tend_sleep || bad "the tend loop has no sleep after a pass"
# Every kill must land: one that found no sleep would let the item be tended on
# the loop's own schedule and pass for nothing. The wait after the last kill is
# shorter than a nap, so only the kill can have woken the loop in time.
k=0
kill_tend_sleep && k=$((k + 1)); kill_tend_sleep && k=$((k + 1))
item "$H" two
kill_tend_sleep && k=$((k + 1))
[ "$k" -eq 3 ] && ok "three more kills each found the tend loop's sleep" || bad "only $k of 3 kills found a sleep"
wait_until 3 tended "$H" two && ok "the loop survives repeated kills" \
  || bad "an item was never tended after repeated kills"
alive "$loop" && ok "still the same loop" || bad "the tend loop ended"

# 2b. Each killed sleep leaves one line in run.log (stderr of run.sh), and the
# naps that ran their full time (the tend loop's every few seconds) leave none.
sleep 0.3
[ "$(early_lines "$H")" -eq "$kills" ] \
  && ok "run.log has one early-end line for each of the $kills killed sleeps" \
  || bad "run.log has $(early_lines "$H") early-end line(s) for $kills killed sleeps: $(tail -n 3 "$H/run.log" | tr '\n' '|')"
grep -q "a nap's sleep ended early (status 143)" "$H/run.log" \
  && ok "and the line names the sleep's status" || bad "no early-end line names status 143"

# 3. A TERM to run.sh stops everything it started, sleeps included.
# Count the sleeps from ONE ps snapshot of run.sh's descendants, and retry that
# snapshot until it shows both naps: the tick loop is briefly between naps each
# minute, and reading the loops and then each pid a moment later could straddle
# the boundary and see one sleep.
SNAP=""   # "<sleeps> <descendant pids...>", from one snapshot
snapshot_sleeps() {
  SNAP="$(ps -axo pid=,ppid=,command= | awk -v root="$RUN_PID" '
    { pid[NR] = $1; par[NR] = $2; isleep[NR] = ($3 == "sleep") }
    END {
      seen[root] = 1
      do {
        grew = 0
        for (i = 1; i <= NR; i++)
          if ((par[i] in seen) && !(pid[i] in seen)) {
            seen[pid[i]] = 1; grew = 1; list = list " " pid[i]; if (isleep[i]) n++
          }
      } while (grew)
      print n + 0 list
    }')"
}
two_sleeps() { snapshot_sleeps; [ "${SNAP%% *}" -ge 2 ]; }
wait_until 10 two_sleeps && ok "one snapshot shows both naps (tend, tick)" \
  || bad "no snapshot showed two sleeps within 10 s: last was '$SNAP'"
early_before="$(early_lines "$H")"
SEEN="${SNAP#* }"
kill "$RUN_PID" 2>/dev/null
wait_until 5 gone "$RUN_PID" $SEEN \
  && ok "TERM to run.sh leaves no loop or sleep behind" \
  || bad "left running after TERM: $(for p in $RUN_PID $SEEN; do alive "$p" && printf '%s ' "$p"; done)"
RUN_PID=""
[ "$(early_lines "$H")" -eq "$early_before" ] \
  && ok "and the stop leaves no early-end line in run.log" || bad "the stop added early-end line(s) to run.log"

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

# 5. A host path with regex characters is still found: status says awake, a second
# wake starts no second runner, and sleep stops it (the launcher looks the runner
# up by its path, which pgrep -f reads as a regex).
# runner_procs <host>: the pids of that host's run.sh (the runner and its two loops).
runner_procs() {
  ps -axo pid=,command= | awk -v s="$1/.gremlin/bin/run.sh" \
    'index($0, s) && $2 ~ /(^|\/)bash$/ { print $1 }'
}
H="$(new_host 'my (host) v2+c.d')"
three_procs() { [ "$(runner_procs "$H" | wc -l | tr -d ' ')" -ge 3 ]; }
"$H/.gremlin/gremlin" wake >/dev/null 2>&1
wait_until 10 three_procs
SEEN="$(runner_procs "$H" | tr '\n' ' ')"
three_procs \
  && ok "gremlin wake started a runner under a path with ( ) + ." || bad "wake did not start a runner: ${SEEN:-none}"
"$H/.gremlin/gremlin" status 2>&1 | grep -q 'is awake' \
  && ok "status says awake for that path" || bad "status did not say awake"
before="$(runner_procs "$H" | wc -l | tr -d ' ')"
"$H/.gremlin/gremlin" wake >/dev/null 2>&1 && bad "a second wake succeeded" || ok "a second wake is refused"
[ "$(runner_procs "$H" | wc -l | tr -d ' ')" = "$before" ] \
  && ok "and starts no second runner" || bad "a second wake started more processes"
"$H/.gremlin/gremlin" sleep >/dev/null 2>&1
wait_until 5 gone $SEEN \
  && ok "gremlin sleep stops the runner found by that path" \
  || bad "left running after gremlin sleep: $(for p in $SEEN; do alive "$p" && printf '%s ' "$p"; done)"

# 6. `gremlin status` names the supervisor and each loop, says awake only while all
# three live, says what is missing otherwise (and that restart brings it back),
# and says asleep when nothing runs. It reads the process table, nothing more.
# status_pid <label> <status output>: the pid on that label's line, or nothing.
status_pid() { printf '%s\n' "$2" | sed -n "s/^  $1  *//p"; }
H="$(new_host status)"
G="$H/.gremlin/gremlin"
out="$("$G" status 2>&1)"
printf '%s\n' "$out" | grep -q 'is asleep' && ok "status says asleep when nothing runs" || bad "status, nothing running: $out"
RUN_PID="$("$G" wake 2>&1 | sed -n 's/.*is awake: //p')"
wait_until 10 two_loops
wait_until 10 find_tend_loop
SEEN="$RUN_PID $(descendants "$RUN_PID" | tr '\n' ' ')"
out="$("$G" status 2>&1)"
tick="$(ps -axo pid=,ppid= | awk -v p="$RUN_PID" -v t="$(tend_loop)" '$2 == p && $1 != t { print $1 }')"
{ printf '%s\n' "$out" | grep -q 'is awake' \
  && [ "$(status_pid supervisor "$out")" = "$RUN_PID" ] \
  && [ "$(status_pid 'tend loop' "$out")" = "$(tend_loop)" ] \
  && [ "$(status_pid 'tick loop' "$out")" = "$tick" ]; } \
  && ok "awake: status names the supervisor, the tend loop and the tick loop by pid" \
  || bad "awake status did not name the three (run $RUN_PID, tend $(tend_loop), tick $tick): $out"

# Asked from inside the gremlin (here a nest item the tend loop runs, so a
# descendant of a loop), status still says awake: it must not leave out the loop
# that runs the caller, which macOS pgrep does.
d="$TMP/stage-inside"
mkdir -p "$d"
printf '#!/bin/sh\n"%s/.gremlin/gremlin" status > "%s/inside.txt"\n' "$H" "$H" > "$d/run.sh"
chmod +x "$d/run.sh"
mv "$d" "$H/.nest/in/inside"
inside_done() { [ -s "$H/inside.txt" ]; }
wait_until 20 inside_done
grep -q 'is awake' "$H/inside.txt" 2>/dev/null \
  && ok "status asked from a nest item inside the gremlin says awake" \
  || bad "status from inside the gremlin said: $(cat "$H/inside.txt" 2>/dev/null || echo nothing)"

# The tend loop dies, the supervisor and the tick loop live on.
loop="$(tend_loop)"
kill "$loop" 2>/dev/null
wait_until 5 gone "$loop"
out="$("$G" status 2>&1)"
printf '%s\n' "$out" | grep -q 'awake' && bad "status still says awake with no tend loop: $out" || ok "no tend loop: status no longer says awake"
{ printf '%s\n' "$out" | grep -q 'no tend loop' && ! printf '%s\n' "$out" | grep -q 'no tick loop' \
  && printf '%s\n' "$out" | grep -q "tick loop $tick" && printf '%s\n' "$out" | grep -q "supervisor $RUN_PID"; } \
  && ok "and names the tend loop as the one missing, with the others' pids" || bad "missing-loop line: $out"
printf '%s\n' "$out" | grep -q 'gremlin restart' && ok "and says restart brings it back" || bad "no restart hint: $out"

# restart brings both loops back; then the tick loop dies.
RUN_PID="$("$G" restart 2>&1 | sed -n 's/.*is awake: //p')"
wait_until 10 two_loops
wait_until 10 find_tend_loop
SEEN="$SEEN $RUN_PID $(descendants "$RUN_PID" | tr '\n' ' ')"
out="$("$G" status 2>&1)"
printf '%s\n' "$out" | grep -q 'is awake' && ok "after restart status says awake again" || bad "not awake after restart: $out"
tick="$(ps -axo pid=,ppid= | awk -v p="$RUN_PID" -v t="$(tend_loop)" '$2 == p && $1 != t { print $1 }')"
kill "$tick" 2>/dev/null
wait_until 5 gone "$tick"
out="$("$G" status 2>&1)"
{ printf '%s\n' "$out" | grep -q 'no tick loop' && ! printf '%s\n' "$out" | grep -q 'no tend loop' \
  && ! printf '%s\n' "$out" | grep -q 'awake'; } \
  && ok "no tick loop: status says so and not awake" || bad "tick loop missing line: $out"

"$G" sleep >/dev/null 2>&1
wait_until 5 gone $SEEN
"$G" status 2>&1 | grep -q 'is asleep' && ok "after sleep status says asleep" || bad "not asleep after sleep: $("$G" status 2>&1)"
RUN_PID=""

# 7. A runner started under a wrapper that stays its parent (sh -c in a cron line
# or a unit, sudo, timeout) still reads awake: the wrapper's command line holds
# the runner's path too, but it is not a fork of the runner.
H="$(new_host wrapped)"
G="$H/.gremlin/gremlin"
sh -c "cd '$H' && '$H/.gremlin/bin/run.sh' >> '$H/run.log' 2>&1; true" &
WRAP_PID=$!
SEEN="$WRAP_PID"
wrapped_awake() { out="$("$G" status 2>&1)"; case "$out" in *'is awake'*) return 0 ;; esac; return 1; }
wait_until 10 wrapped_awake
{ printf '%s\n' "$out" | grep -q 'is awake' && ! printf '%s\n' "$out" | grep -q "supervisor  $WRAP_PID"; } \
  && ok "a runner under an sh -c wrapper reads awake, and the wrapper is not the supervisor" \
  || bad "status for a wrapped runner: $out"
"$G" sleep >/dev/null 2>&1
SEEN="$SEEN $(runner_procs "$H" | tr '\n' ' ')"
wait_until 5 gone $SEEN || bad "left running after sleep with a wrapped runner: $SEEN"

# 8. If ps fails (a busybox that refuses the options), status says so in one line
# and fails, rather than printing only ps's own error.
mkdir -p "$TMP/psfail"
printf '#!/bin/sh\necho "ps: invalid option" >&2\nexit 1\n' > "$TMP/psfail/ps"
chmod +x "$TMP/psfail/ps"
out="$(PATH="$TMP/psfail:$PATH" "$G" status 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -q "ps failed, so I can't say"; } \
  && ok "with ps failing, status says so in one line and exits non-zero" \
  || bad "status with a failing ps (rc $rc): $out"

# 9. A missing or non-executable bin/runner-pids.sh is an error, not "asleep":
# status, wake and sleep say so and fail, and wake starts nothing.
H="$(new_host nohelper)"
G="$H/.gremlin/gremlin"
chmod -x "$H/.gremlin/bin/runner-pids.sh"
for verb in status wake sleep; do
  out="$("$G" $verb 2>&1)"; rc=$?
  { [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -q 'runner-pids.sh'; } \
    && ok "without the helper, $verb says so and fails" \
    || bad "without the helper, $verb (rc $rc): $out"
done
[ -z "$(runner_procs "$H")" ] && ok "and wake started no runner" \
  || { bad "wake started a runner without the helper"; SEEN="$(runner_procs "$H" | tr '\n' ' ')"; }

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

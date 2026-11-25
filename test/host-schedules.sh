#!/usr/bin/env bash
# host-schedules.sh — the gremlin's scheduled jobs land on a host with dates
# that make sense from the day of installing, and no tracked file names a date.
#
# `host/.../once/+26w/reflect-expire/` is a template: install-host-files.sh
# resolves `+26w` to a date 26 weeks after the install. A literal date shipped
# in the product would fire on the next tick for any gremlin installed after it.
#
# Uses a sibling groundhog checkout when there is one (offline), else the
# network installer. "Installed on day X" is faked with a `date` shim that
# answers only `date +%F`.
#
# Usage: ./test/host-schedules.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

PRIMITIVE_REPOS="${PRIMITIVE_REPOS:-$(cd "$ROOT/.." && pwd)}"

# new_host <name>: a host with .gremlin, .groundhog and a .nest directory.
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

# A `date` that says it is $1 when asked for `+%F`, and is the real one otherwise.
REAL_DATE="$(command -v date)"
SHIM="$TMP/shim"
mkdir -p "$SHIM"
cat > "$SHIM/date" <<SH
#!/usr/bin/env bash
if [ "\$*" = "+%F" ] && [ -n "\${FAKE_TODAY:-}" ]; then echo "\$FAKE_TODAY"; exit 0; fi
exec "$REAL_DATE" "\$@"
SH
chmod +x "$SHIM/date"

# expiries <host>: the dates of once/<date>[.paused]/reflect-expire dirs, one per line.
expiries() {
  find "$1/.groundhog/schedule/once" -mindepth 2 -maxdepth 2 -type d -name 'reflect-expire*' 2>/dev/null \
    | sed 's|.*/once/\([^/]*\)/.*|\1|' | sort
}

SCHED=".groundhog/schedule"
JOB="$SCHED/weekly/sun/22-00/reflect"

# 5. Regression guard: nothing in the product names a date.
dated="$(cd "$ROOT/.gremlin/host" && find . | grep -E '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' || true)"
[ -z "$dated" ] && ok "no path under host/ names a date" \
  || bad "a dated path ships under host/: $dated"
[ -d "$ROOT/.gremlin/host/$SCHED/once/+26w/reflect-expire" ] \
  && ok "the expiry ships as once/+26w/" || bad "once/+26w/reflect-expire is missing from host/"

# 1. A fresh install gets exactly one expiry, 26 weeks out.
H="$(new_host fresh)"
"$H/.gremlin/bin/install-host-files.sh" "$H" >/dev/null 2>&1
want="$(python3 -c 'import datetime as d; print(d.date.today()+d.timedelta(weeks=26))')"
got="$(expiries "$H")"
[ "$got" = "$want" ] && ok "fresh install: one expiry, dated $want (today + 26 weeks)" \
  || bad "fresh install: expected one expiry on $want, got: ${got:-none}"
[ -x "$H/$SCHED/once/$want/reflect-expire/run.sh" ] \
  && ok "the installed expiry is executable" || bad "the installed expiry is not executable"
[ -e "$H/$SCHED/once/+26w" ] && bad "the +26w template leaked into the host" \
  || ok "no +26w folder in the host"

# 3. A second run adds nothing, and --check is content.
before="$(find "$H/.groundhog/schedule" | sort)"
"$H/.gremlin/bin/install-host-files.sh" "$H" >/dev/null 2>&1
after="$(find "$H/.groundhog/schedule" | sort)"
[ "$before" = "$after" ] && ok "a second run changes nothing" || bad "a second run changed the schedule"
"$H/.gremlin/bin/install-host-files.sh" --check "$H" >/dev/null 2>&1 \
  && ok "--check exits 0 on a complete host" || bad "--check reported a gap on a complete host"

# 2. Installed on any date: faked days, including a leap day and a year end.
for case in "2030-03-01 2030-08-30" "2028-02-29 2028-08-29" "2031-01-01 2031-07-02"; do
  set -- $case
  H="$(new_host "d$1")"
  FAKE_TODAY="$1" PATH="$SHIM:$PATH" "$H/.gremlin/bin/install-host-files.sh" "$H" >/dev/null 2>&1
  got="$(expiries "$H")"
  [ "$got" = "$2" ] && ok "installed on $1: expiry $2" \
    || bad "installed on $1: expected $2, got: ${got:-none}"
done

# 4. A human-re-dated expiry, and a paused one, both survive a second run.
H="$(new_host redated)"
"$H/.gremlin/bin/install-host-files.sh" "$H" >/dev/null 2>&1
mv "$H/$SCHED/once/$(expiries "$H")" "$H/$SCHED/once/2099-01-01"
"$H/.gremlin/bin/install-host-files.sh" "$H" >/dev/null 2>&1
[ "$(expiries "$H")" = "2099-01-01" ] && ok "a re-dated expiry stays as the human set it" \
  || bad "a re-dated expiry was added to or replaced: $(expiries "$H" | tr '\n' ' ')"
mv "$H/$SCHED/once/2099-01-01" "$H/$SCHED/once/2099-01-01.paused"
"$H/.gremlin/bin/install-host-files.sh" "$H" >/dev/null 2>&1
[ "$(expiries "$H")" = "2099-01-01.paused" ] && ok "a paused expiry date folder is not reinstalled beside itself" \
  || bad "a paused expiry was reinstalled: $(expiries "$H" | tr '\n' ' ')"
mv "$H/$SCHED/once/2099-01-01.paused/reflect-expire" "$H/$SCHED/once/2099-01-01.paused/reflect-expire.paused"
"$H/.gremlin/bin/install-host-files.sh" "$H" >/dev/null 2>&1
[ "$(expiries "$H")" = "2099-01-01.paused" ] && ok "a paused expiry job is not reinstalled beside itself" \
  || bad "a paused expiry job was reinstalled: $(expiries "$H" | tr '\n' ' ')"

# 4b. A host path holding glob characters: a re-run a week later still finds the
# expiry in place (the host path is matched literally, only the date is a glob).
H="$(new_host "my [proj]")"
FAKE_TODAY=2030-03-01 PATH="$SHIM:$PATH" "$H/.gremlin/bin/install-host-files.sh" "$H" >/dev/null 2>&1
FAKE_TODAY=2030-03-08 PATH="$SHIM:$PATH" "$H/.gremlin/bin/install-host-files.sh" "$H" >/dev/null 2>&1
[ "$(expiries "$H")" = "2030-08-30" ] && ok "a host path with [ ] keeps one expiry across a re-run" \
  || bad "a host path with [ ] got: $(expiries "$H" | tr '\n' ' ')"

# 6. The expiry still drops the reflect job; running the installer re-arms both.
H="$(new_host expire)"
"$H/.gremlin/bin/install-host-files.sh" "$H" >/dev/null 2>&1
exp="$(expiries "$H")"
out="$(bash "$H/$SCHED/once/$exp/reflect-expire/run.sh" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ ! -e "$H/$JOB" ] && ok "the expiry drops the weekly reflect job" \
  || bad "the expiry left the reflect job (exit $rc)"
printf '%s' "$out" | grep -q 'install-host-files.sh' && ok "the expiry says how to re-arm" \
  || bad "the expiry message does not mention the installer"
rm -rf "${H:?}/$SCHED/once/$exp"
FAKE_TODAY=2031-01-01 PATH="$SHIM:$PATH" "$H/.gremlin/bin/install-host-files.sh" "$H" >/dev/null 2>&1
[ -x "$H/$JOB/run.sh" ] && [ "$(expiries "$H")" = "2031-07-02" ] \
  && ok "re-running the installer restores the job with a fresh expiry" \
  || bad "re-arm failed: job $([ -x "$H/$JOB/run.sh" ] && echo present || echo missing), expiry $(expiries "$H")"

# 6b. A literal-dated once/ source left over from an older gremlin (/update never
# deletes) is never placed; only the +26w template is.
H="$(new_host leftover)"
mkdir -p "$H/.gremlin/host/$SCHED/once/2020-01-01/reflect-expire"
cp "$H/.gremlin/host/$SCHED/once/+26w/reflect-expire/run.sh" "$H/.gremlin/host/$SCHED/once/2020-01-01/reflect-expire/"
"$H/.gremlin/bin/install-host-files.sh" "$H" >/dev/null 2>&1
[ ! -e "$H/$SCHED/once/2020-01-01" ] && [ "$(expiries "$H" | wc -l | tr -d ' ')" = 1 ] \
  && ok "a dated once/ source left in host/ is not placed" \
  || bad "dated once/ source was placed: $(expiries "$H" | tr '\n' ' ')"
"$H/.gremlin/bin/install-host-files.sh" --check "$H" >/dev/null 2>&1 \
  && ok "--check ignores the dated source" || bad "--check counts the dated source as missing"

# 7. A moved reflect job keeps its cursor in its own directory, and leaves no stray copy.
H="$(new_host moved)"
"$H/.gremlin/bin/install-host-files.sh" "$H" >/dev/null 2>&1
mkdir -p "$H/$SCHED/weekly/sat/09-00"
mv "$H/$JOB" "$H/$SCHED/weekly/sat/09-00/reflect"
echo 99999999 > "$H/$SCHED/weekly/sat/09-00/reflect/cursor"      # more than the transcript holds: a resync
mkdir -p "$H/.nest/in/reflect"
cp "$H/$SCHED/weekly/sat/09-00/reflect/run.sh" "$H/.nest/in/reflect/run.sh"   # as groundhog materialises it
: > "$H/.gremlin/transcript.md"
bash "$H/.nest/in/reflect/run.sh" >/dev/null 2>&1
[ "$(cat "$H/$SCHED/weekly/sat/09-00/reflect/cursor" 2>/dev/null)" != 99999999 ] \
  && ok "the moved job's cursor is written in its new directory" \
  || bad "the moved job's cursor was not updated where the job lives"
[ ! -e "$H/$JOB" ] && ok "no stray reflect directory at the shipped slot" \
  || bad "a stray reflect directory reappeared at the shipped slot"
lint="$("$H/.groundhog/groundhog.sh" lint 2>&1)"
printf '%s' "$lint" | grep -q "exists at 2 schedule paths" \
  && bad "groundhog sees reflect at two paths" || ok "groundhog sees one reflect job"
"$H/.groundhog/groundhog.sh" drop reflect >/dev/null 2>&1 \
  && ok "the moved job can still be dropped by name (the expiry's route)" \
  || bad "drop reflect failed on the moved job"

# 8. The reflect gate counts transcript-archive/ (BSD find has no -printf, and
# a failing size count under pipefail once ended the job on every tick).
# A stub tools/continue.sh records whether the gate escalated.
reflect_gate() {  # reflect_gate <bytes per archive file|none> — prints fired, quiet or exit-nonzero
  local h="$TMP/gate" n="$1"
  rm -rf "${h:?}"
  mkdir -p "$h/.nest/in/reflect" "$h/.gremlin/tools"
  : > "$h/.gremlin/transcript.md"
  printf '#!/bin/sh\necho fired > "%s/fired"\n' "$h" > "$h/.gremlin/tools/continue.sh"
  chmod +x "$h/.gremlin/tools/continue.sh"
  cp "$ROOT/.gremlin/host/$JOB/run.sh" "$h/.nest/in/reflect/run.sh"
  if [ "$n" != none ]; then
    mkdir -p "$h/.gremlin/transcript-archive/2030/01"
    head -c "$n" /dev/zero | tr '\0' x > "$h/.gremlin/transcript-archive/2030/01/a.md"
    head -c "$n" /dev/zero | tr '\0' x > "$h/.gremlin/transcript-archive/b.md"
  fi
  bash "$h/.nest/in/reflect/run.sh" >/dev/null 2>&1 || { echo exit-nonzero; return; }
  [ -e "$h/fired" ] && echo fired || echo quiet
}
[ "$(reflect_gate 3000)" = fired ] \
  && ok "reflect: a 6000-byte archive alone passes the threshold" \
  || bad "reflect: a 6000-byte archive was not counted"
[ "$(reflect_gate 100)" = quiet ] \
  && ok "reflect: a small archive stays quiet" || bad "reflect: a small archive did not stay quiet"
[ "$(reflect_gate none)" = quiet ] \
  && ok "reflect: a missing transcript-archive/ is a quiet tick, not a failure" \
  || bad "reflect: a missing transcript-archive/ ended the job"

# 9. More than one reflect folder: the first is used, and one line on stderr names
# them all; with one folder there is nothing extra. stdout stays empty either way.
dup_gate() {  # dup_gate <number of reflect folders> — prints the job's stderr
  local h="$TMP/dup" n="$1" i
  rm -rf "${h:?}"
  mkdir -p "$h/.nest/in/reflect" "$h/.gremlin/tools"
  : > "$h/.gremlin/transcript.md"
  for i in $(seq 1 "$n"); do mkdir -p "$h/.groundhog/schedule/weekly/d$i/reflect"; done
  cp "$ROOT/.gremlin/host/$JOB/run.sh" "$h/.nest/in/reflect/run.sh"
  bash "$h/.nest/in/reflect/run.sh" 2>&1 >"$h/stdout"
  [ ! -s "$h/stdout" ] || echo "STDOUT NOT EMPTY"
}
err="$(dup_gate 2)"
[ "$(printf '%s\n' "$err" | wc -l | tr -d ' ')" = 1 ] \
  && printf '%s' "$err" | grep -qF "weekly/d1/reflect" && printf '%s' "$err" | grep -qF "weekly/d2/reflect" \
  && ok "reflect: two reflect folders get one stderr line naming both" \
  || bad "reflect: two folders, stderr was: ${err:-nothing}"
err="$(dup_gate 1)"
[ -z "$err" ] && ok "reflect: one reflect folder says nothing extra" \
  || bad "reflect: one folder, stderr was: $err"

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]

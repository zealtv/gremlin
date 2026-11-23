#!/usr/bin/env bash
# moot.sh — the moot catch-up pass (bin/moot-loop.sh): a mention on the board
# reaches the nest and costs one model turn; a quiet board costs none; a host
# with no moot, or no nest, or a paused gremlin is left alone. Also: the tracked
# skills/INDEX.md lists the moot skill, and a delivered mention reaches the model
# as the last turn of a prompt that names it.
#
# Uses sibling nestlings, glean and moot checkouts when there are some
# (offline), else the network installers. With no moot to be had, the moot
# cases are skipped and the test still passes.
#
# Usage: ./test/moot.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

pass=0
fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }
skip() { printf '  skip %s\n' "$1"; }

PRIMITIVE_REPOS="${PRIMITIVE_REPOS:-$(cd "$ROOT/.." && pwd)}"

# moot_src: a directory holding a .moot/, from a sibling checkout or the
# network. Prints its path, or nothing when there is none to be had.
moot_src() {
  local d="$TMP/moot-src" url
  if [ -f "$PRIMITIVE_REPOS/moot/.moot/moot.sh" ]; then
    mkdir -p "$d"
    cp -R "$PRIMITIVE_REPOS/moot/.moot" "$d/.moot"
  else
    url="${GREMLIN_PRIMITIVE_URL_BASE:-https://github.com/zealtv}/moot/archive/refs/heads/main.tar.gz"
    mkdir -p "$d/fetch"
    curl -fsSL "$url" -o "$d/moot.tar.gz" 2>/dev/null || return 0
    tar -xzf "$d/moot.tar.gz" -C "$d/fetch" 2>/dev/null || return 0
    local top
    top="$(find "$d/fetch" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    [ -f "$top/.moot/moot.sh" ] || return 0
    cp -R "$top/.moot" "$d/.moot"
  fi
  chmod +x "$d/.moot/moot.sh" 2>/dev/null
  printf '%s' "$d"
}

# install_primitive <host> <dotdir-name> <repo>: from a sibling checkout, else the network.
install_primitive() {
  if [ -x "$PRIMITIVE_REPOS/$3/install.sh" ]; then
    "$PRIMITIVE_REPOS/$3/install.sh" "$1" >/dev/null 2>&1
  else
    "$1/.gremlin/bin/install-primitives.sh" "$1" "$2" >/dev/null 2>&1
  fi
}

# new_host <name> [nest]: a host with .gremlin and, unless told "no-nest", a nest
# and glean. Its model appends a line to .gremlin/model.calls on every call, and
# keeps the prompt it was given in .gremlin/prompt.seen.
new_host() {
  local h="$TMP/$1"
  mkdir -p "$h"
  cp -R "$ROOT/.gremlin" "$h/.gremlin"
  if [ "${2:-}" != no-nest ]; then
    install_primitive "$h" nest nestlings
    install_primitive "$h" glean glean
    "$h/.glean/glean.sh" index >/dev/null 2>&1
    "$h/.gremlin/bin/doctor.sh" >/dev/null 2>&1
  fi
  cat > "$h/.gremlin/models/echo.sh" <<'EOF'
#!/usr/bin/env bash
GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cat > "$GREMLIN_DIR/prompt.seen"
echo called >> "$GREMLIN_DIR/model.calls"
printf 'model response\n'
EOF
  chmod +x "$h/.gremlin/models/echo.sh"
  printf 'echo\n' > "$h/.gremlin/.model"
  : > "$h/.gremlin/transcript.md"
  printf '%s' "$h"
}

# add_moot <host>: a .moot/ in the host.
add_moot() { cp -R "$MOOT_SRC/.moot" "$1/.moot"; }

# calls <host>: how many times the model was called.
calls() { if [ -f "$1/.gremlin/model.calls" ]; then wc -l < "$1/.gremlin/model.calls" | tr -d ' '; else echo 0; fi; }

# pass_of <host>: one moot pass, as the runner makes it (from the host folder);
# stdout is kept in $TMP/out, stderr in $TMP/err, and the status is returned.
pass_of() {
  ( cd "$1" && "$1/.gremlin/bin/moot-loop.sh" >"$TMP/out" 2>"$TMP/err" )
}

# tend <host>: one tender pass, as the runner makes it.
tend() { ( cd "$1" && "$1/.gremlin/bin/tend-loop.sh" >/dev/null 2>&1 ); }

# delivered <host>: the moot items waiting in the nest, one name per line.
delivered() { ls -A "$1/.nest/in" 2>/dev/null | grep '^moot-' || true; }
count_delivered() { delivered "$1" | grep -c . || true; }

# tree <host>: everything in the host, with its type, so two listings can be compared.
tree() { ( cd "$1" && find . -print | sort ); }

echo "moot"

# 0. run.sh runs the pass. A live wait for the minute would slow the suite.
grep -q 'bin/moot-loop.sh' "$ROOT/.gremlin/bin/run.sh" \
  && ok "run.sh calls bin/moot-loop.sh" || bad "run.sh does not call bin/moot-loop.sh"
awk '/tick-loop\.sh"/ { t = NR } /moot-loop\.sh"/ { m = NR } END { exit !(t && m > t) }' "$ROOT/.gremlin/bin/run.sh" \
  && ok "and after the tick loop's pass" || bad "the moot pass does not follow the tick loop's pass"
[ -x "$ROOT/.gremlin/bin/moot-loop.sh" ] && ok "bin/moot-loop.sh is executable" \
  || bad "bin/moot-loop.sh is missing or not executable"

# 1. A gremlin with no .moot/ is left exactly as it was.
H="$(new_host no-moot)"
[ -x "$H/.nest/nestling.sh" ] || { echo "not ok - no nest installed"; exit 1; }
before="$(tree "$H")"
pass_of "$H"; rc=$?
[ "$rc" -eq 0 ] && ok "no .moot/: the pass exits 0" || bad "no .moot/: the pass exited $rc"
[ ! -s "$TMP/out" ] && [ ! -s "$TMP/err" ] && ok "and says nothing" || bad "no .moot/: the pass printed something"
[ "$(tree "$H")" = "$before" ] && ok "and creates nothing" || bad "no .moot/: the pass changed the host"

# 1b. The tracked skills/INDEX.md lists the moot skill: regenerating it in a
# host gives the same file, so a skill added without regenerating fails here.
"$H/.gremlin/bin/index-skills.sh" >/dev/null 2>&1
grep -q '^- `moot` — ' "$ROOT/.gremlin/skills/INDEX.md" \
  && ok "skills/INDEX.md lists the moot skill" || bad "skills/INDEX.md does not list the moot skill"
cmp -s "$H/.gremlin/skills/INDEX.md" "$ROOT/.gremlin/skills/INDEX.md" \
  && ok "and matches what index-skills.sh makes" || bad "skills/INDEX.md is stale: run .gremlin/bin/index-skills.sh"

MOOT_SRC="$(moot_src)"
if [ -z "$MOOT_SRC" ]; then
  skip "moot cases (no moot checkout next to this one, and none could be fetched)"
  echo "$pass passed, $fail failed"
  [ "$fail" -eq 0 ]
  exit
fi

# 2. A .moot/ with no .nest/: nothing is delivered, and no nest is made.
H="$(new_host no-nest no-nest)"
add_moot "$H"
before="$(tree "$H")"
pass_of "$H"; rc=$?
[ "$rc" -eq 0 ] && ok ".moot/ but no .nest/: the pass exits 0" || bad ".moot/ but no .nest/: the pass exited $rc"
[ ! -e "$H/.nest" ] && ok "and no .nest/ appears" || bad "the pass made a .nest/ on a host with no nest"
[ "$(tree "$H")" = "$before" ] && ok "and nothing else changes" || bad ".moot/ but no .nest/: the pass changed the host"

# A keeper elsewhere holds the room "board"; the gremlin's host hears it.
KEEPER="$TMP/keeper"
mkdir -p "$KEEPER"
cp -R "$MOOT_SRC/.moot" "$KEEPER/.moot"
"$KEEPER/.moot/moot.sh" create board >/dev/null 2>&1
say() { "$KEEPER/.moot/moot.sh" post --as alice --room board -m "$1" >/dev/null 2>&1; }

H="$(new_host heard)"
add_moot "$H"
name="$("$H/.gremlin/bin/name.sh")"
"$H/.moot/moot.sh" join "$KEEPER/.moot/rooms/board" >/dev/null 2>&1
[ -e "$H/.moot/rooms/board" ] && ok "the gremlin's host hears the board" || bad "could not join the board"

# 3. A silent board: a post that mentions nobody costs nothing.
say "lunch is at noon"
sleep 1
pass_of "$H"; rc=$?
[ "$rc" -eq 0 ] && ok "silent board: the pass exits 0" || bad "silent board: the pass exited $rc"
[ ! -s "$TMP/out" ] && ok "and prints nothing on stdout" || bad "silent board: stdout was [$(cat "$TMP/out")]"
[ "$(count_delivered "$H")" -eq 0 ] && ok "and delivers nothing" || bad "silent board: delivered $(delivered "$H" | tr '\n' ' ')"
tend "$H"
[ "$(calls "$H")" -eq 0 ] && ok "and the tender makes no model call" || bad "silent board: $(calls "$H") model call(s)"

# 4. A post that @s the gremlin by name is one item, one turn, delivered once.
say "@$name could you look at this?"
sleep 1
pass_of "$H"; rc=$?
[ "$rc" -eq 0 ] && ok "a mention: the pass exits 0" || bad "a mention: the pass exited $rc"
[ ! -s "$TMP/out" ] && ok "and prints nothing on stdout" || bad "a mention: stdout was [$(cat "$TMP/out")]"
n="$(count_delivered "$H")"
[ "$n" -eq 1 ] && delivered "$H" | grep -q '^moot-board-.*\.md$' \
  && ok "exactly one moot-board-*.md reaches .nest/in/" || bad "a mention: $n item(s): $(delivered "$H" | tr '\n' ' ')"
tend "$H"
[ "$(calls "$H")" -eq 1 ] && ok "the tender makes exactly one model call" || bad "a mention: $(calls "$H") model call(s)"
grep -q '^## user — ' "$H/.gremlin/transcript.md" && grep -q '# moot mention' "$H/.gremlin/transcript.md" \
  && ok "transcript.md holds a user turn with the mention" || bad "the mention is not a user turn in transcript.md"
# The model sees the moot skill in its index, and the mention is the last turn.
awk '/^## user — / { u = NR } /^- `moot` — / { m = NR } END { exit !(m && u && m < u) }' "$H/.gremlin/prompt.seen" \
  && ok "the prompt names the moot skill before the mention" || bad "the prompt does not name the moot skill"
awk '/^## / { last = $0; body = "" ; next } { body = body $0 "\n" }
     END { exit !(last ~ /^## user — / && body ~ /# moot mention · board · alice/) }' "$H/.gremlin/prompt.seen" \
  && ok "and ends with the mention turn" || bad "the prompt does not end with the mention turn"

pass_of "$H"
[ "$(count_delivered "$H")" -eq 0 ] && ok "a second pass delivers nothing" || bad "a second pass delivered again"
tend "$H"
[ "$(calls "$H")" -eq 1 ] && ok "and costs no further model call" || bad "a second pass cost a model call ($(calls "$H") in all)"

# 5. A paused gremlin hears nothing; the mention waits and arrives after.
say "@$name are you there?"
touch "$H/.gremlin/.paused"
sleep 1
pass_of "$H"; rc=$?
[ "$rc" -eq 0 ] && [ "$(count_delivered "$H")" -eq 0 ] \
  && ok ".paused: a new mention is not delivered" || bad ".paused: rc=$rc, delivered $(delivered "$H" | tr '\n' ' ')"
rm -f "$H/.gremlin/.paused"
pass_of "$H"
[ "$(count_delivered "$H")" -eq 1 ] && ok "without .paused, the next pass delivers it" \
  || bad "after .paused, delivered $(count_delivered "$H") item(s)"

# 6. moot's own complaints reach the runner's log, and its status is the pass's.
H="$(new_host failing)"
add_moot "$H"
printf '#!/usr/bin/env bash\necho "moot: broken" >&2\necho "some chatter"\nexit 3\n' > "$H/.moot/moot.sh"
chmod +x "$H/.moot/moot.sh"
pass_of "$H"; rc=$?
[ "$rc" -eq 3 ] && ok "the pass exits with moot's status" || bad "moot failed with 3, the pass exited $rc"
grep -q 'moot: broken' "$TMP/err" && [ ! -s "$TMP/out" ] \
  && ok "stderr is kept and stdout dropped" || bad "stdout [$(cat "$TMP/out")], stderr [$(cat "$TMP/err")]"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]

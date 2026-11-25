#!/usr/bin/env bash
# host-map.sh — doctor says when it first writes into a host's root, and a
# host with no primitives gets no map.
#
# Covers: a fresh host (AGENTS.md created, CLAUDE.md linked, both announced); a
# host with a hand-written AGENTS.md (block added, preamble kept, announced);
# an existing real CLAUDE.md (left alone, told about once); a re-run (quiet, one ok
# line); and no primitives (no AGENTS.md, no link, one line saying why).
#
# Usage: ./test/host-map.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }
has() { printf '%s' "$1" | grep -qF -- "$2"; }

# A host with the gremlin copied in and, when asked, one primitive (a dotdir
# with its own script and README).
new_host() {
  local h="$TMP/$1"
  mkdir -p "$h"
  cp -R "$ROOT/.gremlin" "$h/.gremlin"
  if [ "${2:-}" = primitive ]; then
    mkdir -p "$h/.glean"
    printf '# 🔮 glean\n\nMemory: small, current guidance.\n' > "$h/.glean/README.md"
    printf '#!/bin/sh\nexit 0\n' > "$h/.glean/glean.sh"
  fi
  echo "$h"
}
doctor() { "$1/.gremlin/bin/doctor.sh" 2>&1; }

# 1. Fresh host: AGENTS.md created, CLAUDE.md linked, both announced.
H="$(new_host fresh primitive)"
out="$(doctor "$H")"
[ -f "$H/AGENTS.md" ] && ok "fresh: AGENTS.md written" || bad "fresh: no AGENTS.md"
[ -L "$H/CLAUDE.md" ] && [ "$(readlink "$H/CLAUDE.md")" = "AGENTS.md" ] \
  && ok "fresh: CLAUDE.md links to AGENTS.md" || bad "fresh: CLAUDE.md link missing"
has "$out" "created AGENTS.md" && ok "fresh: doctor announces the new AGENTS.md" || bad "fresh: AGENTS.md not announced: $out"
has "$out" "linked CLAUDE.md" && ok "fresh: doctor announces the CLAUDE.md link" || bad "fresh: link not announced: $out"

# 2. Re-run: quiet, one ok line, nothing announced.
out="$(doctor "$H")"
has "$out" "ok PRIMITIVES.md + AGENTS.md (regenerated)" && ok "re-run: one ok line" || bad "re-run: no ok line: $out"
for w in "created AGENTS" "added the primitives" "linked CLAUDE" "no AGENTS.md map"; do
  has "$out" "$w" && bad "re-run: announced '$w'" || ok "re-run: says nothing about '$w'"
done

# 3. Hand-written AGENTS.md: block added once, preamble kept, announced once.
H="$(new_host handwritten primitive)"
printf '# My notes\n\nKeep tests green.\n' > "$H/AGENTS.md"
out="$(doctor "$H")"
has "$out" "added the primitives map to your AGENTS.md" && ok "hand-written: block addition announced" || bad "hand-written: not announced: $out"
head -n 3 "$H/AGENTS.md" | grep -q 'Keep tests green' && ok "hand-written: preamble kept" || bad "hand-written: preamble lost"
grep -qF 'BEGIN GENERATED PRIMITIVES' "$H/AGENTS.md" && ok "hand-written: block appended" || bad "hand-written: no block"
out="$(doctor "$H")"
has "$out" "added the primitives" && bad "hand-written re-run: announced again" || ok "hand-written re-run: quiet"

# 4. Existing real CLAUDE.md: left alone, told about.
H="$(new_host realclaude primitive)"
printf 'my own notes\n' > "$H/CLAUDE.md"
out="$(doctor "$H")"
[ ! -L "$H/CLAUDE.md" ] && [ "$(cat "$H/CLAUDE.md")" = "my own notes" ] \
  && ok "real CLAUDE.md: left untouched" || bad "real CLAUDE.md: changed"
has "$out" "CLAUDE.md is a real file" && ok "real CLAUDE.md: doctor mentions it" || bad "real CLAUDE.md: not mentioned: $out"
has "$out" "linked CLAUDE" && bad "real CLAUDE.md: claimed a link" || ok "real CLAUDE.md: no link claimed"
out="$(doctor "$H")"
has "$out" "CLAUDE.md is a real file" && bad "real CLAUDE.md re-run: said it again: $out" || ok "real CLAUDE.md re-run: the note is not repeated"
has "$out" "ok PRIMITIVES.md + AGENTS.md (regenerated)" && ok "real CLAUDE.md re-run: one ok line" || bad "real CLAUDE.md re-run: no ok line: $out"

# 5. No primitives: no AGENTS.md, no link, one line saying why.
H="$(new_host bare)"
out="$(doctor "$H")"
[ ! -e "$H/AGENTS.md" ] && ok "bare: no AGENTS.md" || bad "bare: AGENTS.md written"
[ ! -e "$H/CLAUDE.md" ] && [ ! -L "$H/CLAUDE.md" ] && ok "bare: no CLAUDE.md link" || bad "bare: CLAUDE.md created"
has "$out" "no AGENTS.md map: no primitives" && has "$out" "install-primitives.sh" \
  && ok "bare: doctor says why and names the fix" || bad "bare: no explanation: $out"
has "$out" "ok PRIMITIVES.md + AGENTS.md" && bad "bare: still printed the ok line" || ok "bare: no ok line"

# 6. A host whose only dotdir lacks a script is not a primitive.
H="$(new_host readme-only)"
mkdir -p "$H/.notes"; printf '# notes\n\nNothing runnable.\n' > "$H/.notes/README.md"
doctor "$H" >/dev/null
[ ! -e "$H/AGENTS.md" ] && ok "readme-only dotdir: no AGENTS.md" || bad "readme-only dotdir counted as a primitive"

# 7. moot is an optional dotdir: with a .moot/ the map carries its "Start here"
# and ownership lines; without one the map never mentions moot.
H="$(new_host nomoot primitive)"
doctor "$H" >/dev/null
grep -qi 'moot' "$H/AGENTS.md" "$H/.gremlin/PRIMITIVES.md" 2>/dev/null \
  && bad "no .moot: the map mentions moot" || ok "no .moot: the map says nothing about moot"
H="$(new_host withmoot primitive)"
mkdir -p "$H/.moot"
printf '# 📣 moot\n\nA moot is a directory of messages.\n' > "$H/.moot/README.md"
printf '#!/bin/sh\nexit 0\n' > "$H/.moot/moot.sh"
doctor "$H" >/dev/null
grep -qF 'Read `.moot/SKILL.md` before posting to or catching up on a shared room' "$H/AGENTS.md" \
  && ok ".moot: AGENTS.md carries the moot Start here line" || bad ".moot: no Start here line in AGENTS.md"
grep -qF '`.moot/` — rooms shared with other folders and people' "$H/AGENTS.md" \
  && ok ".moot: AGENTS.md carries the moot ownership line" || bad ".moot: no ownership line in AGENTS.md"
grep -qF '`.moot/moot.sh rooms`' "$H/AGENTS.md" \
  && ok ".moot: the Start here line names the rooms command" || bad ".moot: no rooms command named"
[ -f "$H/.gremlin/PRIMITIVES.md" ] && grep -qF '.moot/' "$H/.gremlin/PRIMITIVES.md" \
  && ok ".moot: PRIMITIVES.md lists it" || bad ".moot: PRIMITIVES.md does not list it"
# With a gremlin here, the line tells other agents the gremlin reads the rooms
# each minute and not to move its cursor; a repo mapped with no gremlin gets no such line.
grep -F 'Read `.moot/SKILL.md`' "$H/AGENTS.md" | grep -qF 'catches up each minute' \
  && grep -F 'Read `.moot/SKILL.md`' "$H/AGENTS.md" | grep -qF "don't run \`read --new\` in this folder" \
  && grep -F 'Read `.moot/SKILL.md`' "$H/AGENTS.md" | grep -qF '.moot/moot.sh read --room <room> --tail 20' \
  && ok ".moot with a gremlin: the Start here line says the gremlin catches up and not to run read --new" \
  || bad ".moot with a gremlin: the Start here line lacks the gremlin's catch-up note"
[ "$(grep -cF 'Read `.moot/SKILL.md`' "$H/AGENTS.md")" -eq 1 ] \
  && ok ".moot with a gremlin: the Start here line stays one line" || bad ".moot with a gremlin: the moot Start here line is not one line"
N="$TMP/nogremlin"
mkdir -p "$N/.moot"
cp "$H/.moot/README.md" "$H/.moot/moot.sh" "$N/.moot/"
"$ROOT/.gremlin/bin/index-primitives.sh" "$N" >/dev/null 2>&1
grep -qF 'Read `.moot/SKILL.md`' "$N/AGENTS.md" 2>/dev/null && ! grep -qF 'catches up each minute' "$N/AGENTS.md" \
  && ok ".moot, no gremlin: the line carries no gremlin note" || bad ".moot, no gremlin: the map is missing or names a gremlin"

# 6. A gremlin name moot can't take or can't @ gets a note naming a board name
# file; a plain name, or a .moot/name already there, gets none.
moot_host() {  # moot_host <label> <gremlin name>: a host with a moot stub that hears a room
  local h
  h="$(new_host "$1" primitive)"
  mkdir -p "$h/.moot/rooms/lobby"
  printf '#!/bin/sh\nexit 0\n' > "$h/.moot/moot.sh"; chmod +x "$h/.moot/moot.sh"
  "$h/.gremlin/bin/name.sh" set "$2" >/dev/null
  printf '%s' "$h"
}
for n in "O'Malley" "Fox Jr."; do
  H="$(moot_host "board-$(printf '%s' "$n" | tr -c 'A-Za-z' x)" "$n")"
  out="$(doctor "$H")"
  has "$out" "board name" && ok "board name: a note for '$n'" || bad "board name: no note for '$n': $out"
  mkdir -p "$H/.moot"; printf 'Fox\n' > "$H/.moot/name"
  out="$(doctor "$H")"
  has "$out" "board name" && bad "board name: a note for '$n' despite .moot/name" || ok "board name: none for '$n' once .moot/name exists"
done
H="$(moot_host board-plain "Mr Fox")"
out="$(doctor "$H")"
has "$out" "board name" && bad "board name: a note for 'Mr Fox': $out" || ok "board name: none for 'Mr Fox'"

printf '\npassed: %d, failed: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || { echo "not ok - host map" >&2; exit 1; }
echo "ok - host map"

#!/usr/bin/env bash
# host-map.sh — doctor says when it first writes into a host's root, and a
# host with no primitives gets no map.
#
# Covers: a fresh host (AGENTS.md created, CLAUDE.md linked, both announced); a
# host with a hand-written AGENTS.md (block added, preamble kept, announced);
# an existing real CLAUDE.md (left alone, told about); a re-run (quiet, one ok
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

printf '\npassed: %d, failed: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || { echo "not ok - host map" >&2; exit 1; }
echo "ok - host map"

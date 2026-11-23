#!/usr/bin/env bash
# install-primitives.sh — a fresh host ends up with the five primitives at its
# root, .gremlin/ beside them, and the gremlin's own host files in place.
#
# This replaces the old lore-primitive.sh, which asserted that gremlin ships a
# working vendored .lore/. It no longer does: the primitives are installed by
# their own installers, and each project tests its own protocol. What is worth
# testing here is the seam — that gremlin can stand a host up from nothing.
#
# Uses sibling checkouts of the primitive repos when they exist (offline), and
# falls back to bin/install-primitives.sh, which needs the network.
#
# Usage: ./test/install-primitives.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

HOST="$TMP/host"
mkdir -p "$HOST"
cp -R "$ROOT/.gremlin" "$HOST/.gremlin"
GREMLIN="$HOST/.gremlin"

PRIMITIVE_REPOS="${PRIMITIVE_REPOS:-$(cd "$ROOT/.." && pwd)}"
for pair in "nest nestlings" "loom loom" "lore lore" "glean glean" "groundhog groundhog"; do
  set -- $pair
  name="$1"; repo="$2"
  if [ -x "$PRIMITIVE_REPOS/$repo/install.sh" ]; then
    "$PRIMITIVE_REPOS/$repo/install.sh" "$HOST" >/dev/null 2>&1
  else
    "$GREMLIN/bin/install-primitives.sh" "$HOST" "$name" >/dev/null 2>&1
  fi
done

for name in nest loom lore glean groundhog; do
  [ -d "$HOST/.$name" ] && ok ".$name installed at the host root" \
    || bad ".$name missing from the host root"
  [ -d "$GREMLIN/.$name" ] && bad ".$name was vendored inside .gremlin/" \
    || ok ".$name is not inside .gremlin/"
done

# The gremlin's own contributions: scheduled work, and nothing else.
"$GREMLIN/bin/install-host-files.sh" "$HOST" >/dev/null 2>&1
[ -x "$HOST/.groundhog/schedule/weekly/sun/22-00/reflect/run.sh" ] \
  && ok "the weekly reflect job is on the host's shared schedule" \
  || bad "reflect job missing from the host schedule"
[ -e "$HOST/.groundhog/schedule/weekly/sun/23-00/curate-findings.paused" ] \
  && ok "the curate job ships paused" || bad "paused curate job missing"

# Facts, not policy: the host's own policy files are the primitives' and stay
# that way. gremlin must not ship, install or overwrite either.
[ -e "$GREMLIN/host/.nest/tend.md" ] && bad "gremlin ships a tend.md" \
  || ok "gremlin ships no tend.md"
[ -e "$GREMLIN/host/.glean/distil.md" ] && bad "gremlin ships a distil.md" \
  || ok "gremlin ships no distil.md"
grep -qF "Replace the prompts below" "$HOST/.nest/tend.md" \
  && ok "the nest keeps nestlings' own tend.md" \
  || bad "something overwrote the host's tend.md"
grep -qF "the local brief for distillation in this glean" "$HOST/.glean/distil.md" \
  && ok "the glean keeps its own distil.md" \
  || bad "something overwrote the host's distil.md"
out="$("$GREMLIN/bin/doctor.sh" 2>&1)"
printf '%s' "$out" | grep -q 'tend.md is still its primitive' \
  && ok "doctor notices an untouched tend.md" || bad "doctor said nothing about tend.md"
printf '%s' "$out" | grep -q 'distil.md is still its primitive' \
  && ok "doctor notices an untouched distil.md" || bad "doctor said nothing about distil.md"
echo "# this repo's actual policy" > "$HOST/.nest/tend.md"
printf '%s' "$("$GREMLIN/bin/doctor.sh" 2>&1)" | grep -q 'tend.md is still its primitive' \
  && bad "doctor still nags about a written tend.md" \
  || ok "doctor goes quiet once the host writes its own policy"

# Never overwrites: a paused job survives a second run.
mv "$HOST/.groundhog/schedule/weekly/sun/22-00/reflect" \
   "$HOST/.groundhog/schedule/weekly/sun/22-00/reflect.paused"
"$GREMLIN/bin/install-host-files.sh" "$HOST" >/dev/null 2>&1
[ ! -e "$HOST/.groundhog/schedule/weekly/sun/22-00/reflect" ] \
  && ok "a paused job is not reinstalled beside itself" \
  || bad "reinstalled a job the human had paused"

# doctor is quiet about correct placement and loud about a missing primitive.
out="$("$GREMLIN/bin/doctor.sh" 2>&1)"
printf '%s' "$out" | grep -q 'ok .nest' && ok "doctor reports the siblings ok" \
  || bad "doctor did not report .nest ok"
printf '%s' "$out" | grep -q 'LEGACY' && bad "doctor cried legacy on a correct host" \
  || ok "doctor is quiet about correct placement"
rm -rf "$HOST/.glean"
out="$("$GREMLIN/bin/doctor.sh" 2>&1)"
printf '%s' "$out" | grep -q '.glean MISSING' && ok "doctor fails loud on a missing primitive" \
  || bad "doctor was quiet about a missing .glean"
printf '%s' "$out" | grep -q 'install.sh | bash' && ok "doctor names the install command" \
  || bad "doctor did not name an install command"

# A legacy host — primitives still inside .gremlin/ — is named as such.
LEGACY="$TMP/legacy"
mkdir -p "$LEGACY/.gremlin/.nest"
cp -R "$ROOT/.gremlin/bin" "$LEGACY/.gremlin/bin"
out="$("$LEGACY/.gremlin/bin/doctor.sh" 2>&1)"
printf '%s' "$out" | grep -q 'LEGACY placement' && ok "doctor names legacy placement" \
  || bad "doctor missed a vendored primitive"
rm -rf "$LEGACY/.gremlin/.nest"
ln -s ../.nest "$LEGACY/.gremlin/.nest"
out="$("$LEGACY/.gremlin/bin/doctor.sh" 2>&1)"
printf '%s' "$out" | grep -q 'LEGACY placement' && ok "doctor rejects a legacy symlink" \
  || bad "doctor missed a legacy symlink"

# moot is an optional sixth dotdir. install-primitives.sh with no names still
# installs exactly the five; naming moot adds .moot/. Offline when every
# primitive has a sibling checkout (each is packed into a local tarball and
# fetched through GREMLIN_PRIMITIVE_URL_BASE), else through the network.
BASE_ARGS=()
offline=1
for repo in nestlings loom lore glean groundhog moot; do
  [ -x "$PRIMITIVE_REPOS/$repo/install.sh" ] || offline=0
done
if [ "$offline" = 1 ]; then
  for repo in nestlings loom lore glean groundhog moot; do
    mkdir -p "$TMP/tarballs/$repo/archive/refs/heads" "$TMP/pack/$repo-main"
    cp -R "$PRIMITIVE_REPOS/$repo/." "$TMP/pack/$repo-main/"
    rm -rf "${TMP:?}/pack/$repo-main/.git"
    tar -czf "$TMP/tarballs/$repo/archive/refs/heads/main.tar.gz" -C "$TMP/pack" "$repo-main"
  done
  export GREMLIN_PRIMITIVE_URL_BASE="file://$TMP/tarballs"
fi
MH="$TMP/optional-host"
mkdir -p "$MH"
cp -R "$ROOT/.gremlin" "$MH/.gremlin"
"$MH/.gremlin/bin/install-primitives.sh" "$MH" >/dev/null 2>&1
n=0
for name in nest loom lore glean groundhog; do [ -d "$MH/.$name" ] && n=$((n + 1)); done
[ "$n" = 5 ] && ok "a default run installs the five" || bad "a default run installed $n of the five"
[ -e "$MH/.moot" ] && bad "a default run installed .moot" || ok "a default run installs no .moot"
printf '%s' "$("$MH/.gremlin/bin/doctor.sh" 2>&1)" | grep -q 'moot' \
  && bad "doctor mentions moot on a host with no .moot" \
  || ok "doctor says nothing about moot on a host with no .moot"
out="$("$MH/.gremlin/bin/install-primitives.sh" "$MH" moot 2>&1)"
[ -x "$MH/.moot/moot.sh" ] && ok "naming moot installs .moot/moot.sh" || bad "naming moot installed no .moot/moot.sh: $out"
out="$("$MH/.gremlin/bin/install-primitives.sh" "$MH" moot 2>&1)"
printf '%s' "$out" | grep -q 'already installed' && ok "a second run says moot is already installed" \
  || bad "a second run did not say already installed: $out"
unset GREMLIN_PRIMITIVE_URL_BASE

# doctor and moot: nothing without a .moot/; ok with one; a note while no room
# is heard; and doctor never runs moot.sh (every moot command repairs links).
DH="$TMP/doctor-host"
mkdir -p "$DH"
cp -R "$ROOT/.gremlin" "$DH/.gremlin"
printf '%s' "$("$DH/.gremlin/bin/doctor.sh" 2>&1)" | grep -qi 'moot' \
  && bad "doctor mentions moot with no .moot/" || ok "doctor: no moot line without .moot/"
mkdir -p "$DH/.moot/rooms"
printf '#!/bin/sh\ntouch "%s/moot-ran"\n' "$DH" > "$DH/.moot/moot.sh"
chmod +x "$DH/.moot/moot.sh"
out="$("$DH/.gremlin/bin/doctor.sh" 2>&1)"
printf '%s' "$out" | grep -qF 'ok .moot' && ok "doctor: ok .moot with a .moot/" || bad "doctor: no ok .moot: $out"
printf '%s' "$out" | grep -qF '.moot hears no room yet' && ok "doctor: notes that no room is heard" \
  || bad "doctor: no 'hears no room yet' note: $out"
printf '%s' "$out" | grep -qF 'join <path-to-room>' && printf '%s' "$out" | grep -qF 'create <room>' \
  && ok "doctor: the note names create and join" || bad "doctor: the note lacks create or join: $out"
[ -e "$DH/moot-ran" ] && bad "doctor ran moot.sh" || ok "doctor does not run moot.sh"
mkdir -p "$DH/.moot/rooms/example"
out="$("$DH/.gremlin/bin/doctor.sh" 2>&1)"
printf '%s' "$out" | grep -qF 'ok .moot' && ok "doctor: still ok .moot with a room" || bad "doctor: lost ok .moot with a room"
printf '%s' "$out" | grep -qF 'hears no room yet' && bad "doctor: notes no room although one is there" \
  || ok "doctor: no note once a room is there"
rm -rf "$DH/.moot/rooms/example"
ln -s "$TMP/nowhere" "$DH/.moot/rooms/example"
printf '%s' "$("$DH/.gremlin/bin/doctor.sh" 2>&1)" | grep -qF 'hears no room yet' \
  && bad "doctor: a linked room does not count" || ok "doctor: a linked room counts as heard"
chmod -x "$DH/.moot/moot.sh"
out="$("$DH/.gremlin/bin/doctor.sh" 2>&1)"
printf '%s' "$out" | grep -qF '.moot/moot.sh is not executable' \
  && ok "doctor: names a moot.sh that is not executable" || bad "doctor: silent about a moot.sh that is not executable: $out"
printf '%s' "$out" | grep -qF 'ok .moot' \
  && bad "doctor: says ok .moot for a moot.sh that is not executable" || ok "and does not say ok .moot for it"
rm -f "$DH/.moot/moot.sh"
printf '%s' "$("$DH/.gremlin/bin/doctor.sh" 2>&1)" | grep -qF '.moot exists at the host root but has no moot.sh' \
  && ok "doctor: names a .moot/ with no moot.sh" || bad "doctor: silent about a .moot/ with no moot.sh"

printf '\npassed: %d, failed: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || { echo "not ok - fresh install produces the sibling shape" >&2; exit 1; }
echo "ok - fresh install produces the sibling shape"

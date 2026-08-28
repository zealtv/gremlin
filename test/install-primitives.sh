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
declare -A REPO=( [nest]=nestlings [loom]=loom [lore]=lore [glean]=glean [groundhog]=groundhog )
for name in nest loom lore glean groundhog; do
  repo="${REPO[$name]}"
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
printf '%s' "$out" | grep -q 'hoist-primitives.sh' && ok "doctor names the migration" \
  || bad "doctor did not name hoist-primitives.sh"

printf '\npassed: %d, failed: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || { echo "not ok - fresh install produces the sibling shape" >&2; exit 1; }
echo "ok - fresh install produces the sibling shape"

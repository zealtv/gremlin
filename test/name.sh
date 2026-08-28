#!/usr/bin/env bash
# name.sh — a gremlin has a name of its own: rolled once, persisted, changeable,
# and never touched by an update.
#
# Usage: ./test/name.sh
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
NAME="$GREMLIN/bin/name.sh"

[ ! -e "$GREMLIN/name" ] && ok "canonical ships no name — a name is per-install" \
  || bad "canonical ships a name file"

first="$("$NAME")"
[ -n "$first" ] && ok "first call rolls a name ($first)" || bad "no name rolled"
grep -qxF "$first" <(grep -v '^#' "$GREMLIN/names/v1.txt" | grep -v '^[[:space:]]*$') \
  && ok "the name came from the vocabulary" || bad "$first is not in names/v1.txt"
[ "$("$NAME")" = "$first" ] && [ "$("$NAME" get)" = "$first" ] \
  && ok "the name is stable once rolled" || bad "the name changed between calls"
[ "$("$NAME" source)" = "generated" ] && ok "a rolled name is generated" \
  || bad "source is not generated"
grep -q '^vocabulary=1$' "$GREMLIN/name" && ok "the vocabulary version is recorded" \
  || bad "no vocabulary version in the name file"

rolled="$("$NAME" roll)"
[ "$rolled" != "$first" ] && ok "roll never returns the current name" \
  || bad "roll returned the same name"
[ "$("$NAME")" = "$rolled" ] && ok "a rolled name persists" || bad "roll did not persist"

"$NAME" set "Roo The Second" >/dev/null
[ "$("$NAME")" = "Roo The Second" ] && ok "a human can name it" || bad "set did not take"
[ "$("$NAME" source)" = "custom" ] && ok "a chosen name is recorded as custom" \
  || bad "a chosen name is not marked custom"
[ "$("$NAME" slug)" = "roo-the-second" ] && ok "the slug is safe for machines" \
  || bad "unexpected slug: $("$NAME" slug)"
"$NAME" set "" >/dev/null 2>&1 && bad "accepted a blank name" || ok "refuses a blank name"

# A copy is a twin: it keeps the name until someone rolls it. This is the
# deliberate consequence of persisting rather than deriving — a gremlin is a
# folder you can mv, and deriving from the path would rename it on every move.
cp -R "$HOST" "$TMP/twin"
[ "$("$TMP/twin/.gremlin/bin/name.sh")" = "Roo The Second" ] \
  && ok "cp -r produces a twin with the same name" || bad "the copy renamed itself"
"$TMP/twin/.gremlin/bin/name.sh" roll >/dev/null
[ "$("$NAME")" = "Roo The Second" ] && ok "rolling the twin leaves the original alone" \
  || bad "the twin renamed the original"

# doctor writes identity.md from the name and links it into the broadcast
# surface, so the gremlin can say what it is called.
"$GREMLIN/bin/doctor.sh" >/dev/null 2>&1
grep -q 'Roo The Second' "$GREMLIN/identity.md" && ok "identity.md carries the name" \
  || bad "identity.md missing or stale"
[ -L "$GREMLIN/context/system/identity.md" ] && ok "identity.md is broadcast through context" \
  || bad "identity.md is not linked into context/system"
grep -q 'A human chose it' "$GREMLIN/identity.md" \
  && ok "identity.md knows the name was chosen, not rolled" \
  || bad "identity.md does not distinguish custom from generated"

# The whole point of the exclude: an update must never rename anyone. Drive
# rsync with update.sh's own exclude list rather than asserting about it.
canonical="$TMP/canonical/.gremlin"
mkdir -p "$canonical"
cp -R "$ROOT/.gremlin/." "$canonical/"
printf 'name=canonical\nsource=generated\nvocabulary=1\n' > "$canonical/name"
echo "# canonical identity" > "$canonical/identity.md"
excludes=$(sed -n "/^excludes=(/,/^)/p" "$GREMLIN/commands/update.sh" \
  | grep -oE "\-\-exclude='[^']*'" | tr '\n' ' ')
eval rsync -a $excludes "$canonical/" "$GREMLIN/"
[ "$("$NAME")" = "Roo The Second" ] && ok "an update does not rename the gremlin" \
  || bad "update overwrote the name with $("$NAME")"
grep -q 'Roo The Second' "$GREMLIN/identity.md" && ok "an update does not overwrite identity.md" \
  || bad "update clobbered identity.md"

printf '\npassed: %d, failed: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || { echo "not ok - the gremlin's name" >&2; exit 1; }
echo "ok - the gremlin's name"

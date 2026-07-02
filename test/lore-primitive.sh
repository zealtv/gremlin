#!/usr/bin/env bash
# lore-primitive.sh — the vendored .lore/ primitive works out of the box.
#
# Mirrors a fresh install: copies the template .lore/ into a scratch host, runs
# `init` (as install.sh does), then proves the full loop — keep an item, it
# appears in INDEX.md, fetch finds it case-insensitively, status is clean — and
# that the shipped items/.gitkeep is ignored rather than mistaken for an item.
#
# Usage: ./test/lore-primitive.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

LORE="$TMP/host/.lore"
mkdir -p "$TMP/host"
cp -R "$ROOT/.gremlin/.lore" "$LORE"

# The template ships lore.sh, README.md, and an empty items/ tray tracked by
# .gitkeep — and no generated INDEX.md (install/init generates it).
[ -x "$LORE/lore.sh" ] && ok "lore.sh ships and is executable" || bad "lore.sh missing/not executable"
[ -f "$LORE/README.md" ] && ok "the lore README ships" || bad "lore README missing"
[ -f "$LORE/items/.gitkeep" ] && ok "items/ tray is tracked (.gitkeep)" || bad "items/.gitkeep missing"
[ ! -e "$LORE/INDEX.md" ] && ok "no INDEX.md is shipped (generated at install)" \
  || bad "template should not ship a generated INDEX.md"

# install.sh runs this.
"$LORE/lore.sh" init >/dev/null 2>&1 \
  && ok "lore.sh init succeeds on the shipped tray" || bad "lore.sh init failed"

# Keep a record, then it must show up in the freshly generated INDEX.md.
mkdir -p "$TMP/prep/content"
printf '# First decision\n\nWhy we chose the folder-based design.\n' > "$TMP/prep/item.md"
printf 'the whole rationale\n' > "$TMP/prep/content/rationale.md"
"$LORE/lore.sh" keep "$TMP/prep" first-decision >/dev/null 2>&1 \
  && ok "an item can be kept" || bad "keep failed"
"$LORE/lore.sh" index >/dev/null 2>&1
if [ -f "$LORE/INDEX.md" ] && grep -q 'First decision' "$LORE/INDEX.md"; then
  ok "the kept item appears in INDEX.md"
else
  bad "kept item not in INDEX.md"
fi

# .gitkeep must not be enumerated as an item (would show as invalid).
"$LORE/lore.sh" status > "$TMP/status.out" 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok "status is clean (exit 0)" || bad "status not clean (exit $rc)"
grep -q 'invalid: 0' "$TMP/status.out" && ok "no invalid items — .gitkeep is ignored" \
  || bad ".gitkeep was mistaken for an item ($(grep invalid "$TMP/status.out"))"

# fetch matches case-insensitively (metadata and the all-content path agree).
"$LORE/lore.sh" fetch "FIRST DECISION" 2>/dev/null | grep -q 'first-decision' \
  && ok "fetch is case-insensitive" || bad "fetch missed a case-varied query"

# ============================================================================
echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ] || exit 1
echo "ok - vendored lore primitive"

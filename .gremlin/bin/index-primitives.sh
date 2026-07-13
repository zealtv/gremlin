#!/usr/bin/env bash
# index-primitives.sh — build PRIMITIVES.md, the gremlin's map of its own
# installed primitives, generated from what is actually on disk (the
# index-skills.sh pattern: generated, so it cannot rot).
#
# A primitive is a self-named dotdir directly inside .gremlin/ that bundles
# its own script (*.sh) and a README.md. Name and emoji come from the
# README's title line; the one-line purpose is the first prose line after it.
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$GREMLIN_DIR/PRIMITIVES.md"
TMP="$OUT.tmp"

{
  echo "# primitives"
  echo
  echo "Installed primitives — self-contained dotdir protocols living inside \`.gremlin/\`. Each bundles its script and its data; read its README before working with one."
  echo
  for d in "$GREMLIN_DIR"/.*/; do
    d="${d%/}"
    base="$(basename "$d")"
    case "$base" in .|..) continue ;; esac
    [ -f "$d/README.md" ] || continue
    set -- "$d"/*.sh
    [ -e "$1" ] || continue
    title="$(head -n 1 "$d/README.md")"
    title="${title#\# }"
    purpose="$(awk 'NR>1 && NF { sub(/^[[:space:]]+/, ""); print; exit }' "$d/README.md")"
    echo "- $title — \`.gremlin/$base/\` — $purpose"
  done
} > "$TMP"
mv "$TMP" "$OUT"

echo "wrote $OUT"

#!/usr/bin/env bash
# index-primitives.sh — build PRIMITIVES.md, the map of the primitives
# installed at the host root, generated from what is actually on disk (the
# index-skills.sh pattern: generated, so it cannot rot).
#
# A primitive is a self-named dotdir at the HOST ROOT — a sibling of .gremlin,
# not something inside it — that bundles its own script (*.sh) and a README.md.
# .gremlin lists itself: under the placement law it is a primitive among peers,
# the repository's optional tender, and a map that omitted the mapmaker would
# be lying by omission. Its entry is written by hand here because its
# executable is `gremlin`, not `*.sh`.
#
# Name and emoji come from the README's title line; the one-line purpose is
# the first prose line after it.
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_DIR="$(cd "$GREMLIN_DIR/.." && pwd)"
OUT="$GREMLIN_DIR/PRIMITIVES.md"
TMP="$OUT.tmp"

{
  echo "# primitives"
  echo
  echo "Installed primitives — self-contained dotdir protocols at the root of this repository, siblings of \`.gremlin/\`. Each bundles its script and its data; read its README before working with one."
  echo
  for d in "$HOST_DIR"/.*/; do
    d="${d%/}"
    base="$(basename "$d")"
    case "$base" in .|..) continue ;; esac
    [ -f "$d/README.md" ] || continue
    if [ "$base" = ".gremlin" ]; then
      echo "- 👀 gremlin — \`.gremlin/\` — The optional tender of this folder: reads the nest, works the loom, keeps the record."
      continue
    fi
    set -- "$d"/*.sh
    [ -e "$1" ] || continue
    title="$(head -n 1 "$d/README.md")"
    title="${title#\# }"
    purpose="$(awk 'NR>1 && NF { sub(/^[[:space:]]+/, ""); print; exit }' "$d/README.md")"
    echo "- $title — \`$base/\` — $purpose"
  done
} > "$TMP"
mv "$TMP" "$OUT"

echo "wrote $OUT"

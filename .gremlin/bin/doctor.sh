#!/usr/bin/env bash
# doctor.sh — repair gremlin-managed context links.
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYSTEM_DIR="$GREMLIN_DIR/context/system"

mkdir -p "$SYSTEM_DIR"

readme="$SYSTEM_DIR/README.md"
if [ ! -e "$readme" ]; then
  cat > "$readme" <<'EOF_README'
# context/system

This directory is managed by `gremlin doctor`.
It holds symlinks for gremlin-managed material that should be broadcast through `context/`.
Remove a specific entry to opt out of that broadcast; running `gremlin doctor` restores missing managed entries.
Real files placed here are left alone.
EOF_README
  echo "created context/system/README.md"
else
  echo "ok context/system/README.md"
fi

repair_link() {
  local rel="$1"
  local target="$2"
  local path="$SYSTEM_DIR/$rel"
  local current

  if [ -L "$path" ]; then
    current="$(readlink "$path")"
    if [ "$current" = "$target" ]; then
      echo "ok context/system/$rel"
    else
      ln -sfn "$target" "$path"
      echo "relinked context/system/$rel"
    fi
  elif [ -e "$path" ]; then
    echo "skipped (real file) context/system/$rel"
  else
    ln -s "$target" "$path"
    echo "created context/system/$rel"
  fi
}

for f in "$SYSTEM_DIR"/*.md; do
  [ -e "$f" ] || continue
  [ -L "$f" ] && continue
  [ "$(basename "$f")" = "README.md" ] && continue
  echo "skipped (real file) context/system/$(basename "$f")"
done

repair_link "skills.md" "../../skills/INDEX.md"
repair_link "tools.md" "../../tools/README.md"
repair_link "memory.md" "../../.glean/findings/INDEX.md"

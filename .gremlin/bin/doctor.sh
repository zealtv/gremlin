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

Remove a specific entry to opt out of that broadcast. Running `gremlin doctor` restores missing managed entries. The `/update` command also runs `gremlin doctor`, so updates currently restore deleted managed entries too; there is no durable opt-out in this stage.

Entries are symlinks by convention. The tender reads only symlinked `.md` files from this directory, which is why this `README.md` is not loaded into the prompt. Real `.md` files dropped here are ignored by the tender, left alone by doctor, and reported as `skipped (real file)`.
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
repair_link "turntaking.md" "../../docs/turntaking.md"
repair_link "media-embeds.md" "../../docs/media-embeds.md"

check_preset() {
  local alias="$1"
  local path="$GREMLIN_DIR/models/$alias.sh"
  if [ ! -e "$path" ]; then
    echo "‼️  models/$alias.sh MISSING — items with .model=$alias will silently fall back to default.sh"
    return
  fi
  if [ ! -x "$path" ]; then
    echo "‼️  models/$alias.sh NOT EXECUTABLE — items with .model=$alias will silently fall back to default.sh"
    return
  fi
  if [ "$(head -c 2 "$path")" != "#!" ]; then
    echo "‼️  models/$alias.sh has no shebang — likely broken"
    return
  fi
  echo "ok models/$alias.sh"
}

check_preset "default"
check_preset "memory"

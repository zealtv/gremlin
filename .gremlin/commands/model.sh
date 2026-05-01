#!/usr/bin/env bash
# model — list or set the active model preset
set -euo pipefail
GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODELS_DIR="$GREMLIN_DIR/models"
ACTIVE_FILE="$GREMLIN_DIR/.model"

active="default"
if [ -f "$ACTIVE_FILE" ]; then
  candidate="$(tr -d '[:space:]' < "$ACTIVE_FILE")"
  [ -n "$candidate" ] && active="$candidate"
fi

list_presets() {
  for f in "$MODELS_DIR"/*.env; do
    [ -e "$f" ] || continue
    name="$(basename "$f" .env)"
    model="$( ( grep -E '^[[:space:]]*MODEL=' "$f" | head -1 | sed 's/^[[:space:]]*MODEL=//; s/"//g' ) || true )"
    if [ "$name" = "$active" ]; then
      printf '* %s — %s\n' "$name" "$model"
    else
      printf '  %s — %s\n' "$name" "$model"
    fi
  done
}

if [ "$#" -eq 0 ]; then
  list_presets
  exit 0
fi

target="$1"
preset="$MODELS_DIR/$target.env"
if [ ! -f "$preset" ]; then
  {
    echo "no preset '$target'. available:"
    list_presets
  } >&2
  exit 1
fi

printf '%s\n' "$target" > "$ACTIVE_FILE"
echo "model: $target"

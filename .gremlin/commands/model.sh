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

# Label = first `# ...` comment line after the shebang. If absent, blank.
preset_label() {
  awk '
    NR == 1 && /^#!/ { next }
    /^#[[:space:]]/ { sub(/^#[[:space:]]*/, ""); print; exit }
    /^[^#[:space:]]/ { exit }
  ' "$1"
}

list_presets() {
  for f in "$MODELS_DIR"/*.sh; do
    [ -e "$f" ] || continue
    name="$(basename "$f" .sh)"
    label="$(preset_label "$f")"
    marker="  "
    [ "$name" = "$active" ] && marker="* "
    if [ -n "$label" ]; then
      printf '%s%s — %s\n' "$marker" "$name" "$label"
    else
      printf '%s%s\n' "$marker" "$name"
    fi
  done
}

if [ "$#" -eq 0 ]; then
  list_presets
  exit 0
fi

target="$1"
preset="$MODELS_DIR/$target.sh"
if [ ! -f "$preset" ]; then
  {
    echo "no preset '$target'. available:"
    list_presets
  } >&2
  exit 1
fi

printf '%s\n' "$target" > "$ACTIVE_FILE"
echo "model: $target"

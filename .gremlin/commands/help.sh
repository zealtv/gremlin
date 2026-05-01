#!/usr/bin/env bash
# help — show available commands
set -euo pipefail
COMMANDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Each command is a script under commands/. Its first line beginning with
# `# <name> —` is treated as the summary; we print one row per script.
for f in "$COMMANDS_DIR"/*.sh; do
  [ -e "$f" ] || continue
  name="$(basename "$f" .sh)"
  summary="$(awk '/^# / { sub(/^# /, ""); print; exit }' "$f")"
  # Strip leading "<name> — " if present so the menu doesn't repeat it.
  summary="${summary#$name — }"
  summary="${summary#$name -- }"
  printf '/%-8s %s\n' "$name" "$summary"
done

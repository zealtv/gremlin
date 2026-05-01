#!/usr/bin/env bash
# index-skills.sh — build skills/INDEX.md from skill frontmatter.
#
# - skills with `triggers: [always]` get their bodies inlined.
# - other skills get a one-line entry: `- `name` — first trigger`.
#
# Format expected per skill file:
#
#   ---
#   name: <slug>
#   triggers: [always]              # OR
#   triggers:
#     - first trigger
#     - second trigger
#   ---
#
#   # body...

set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS="$GREMLIN_DIR/skills"
INDEX="$SKILLS/INDEX.md"

[ -d "$SKILLS" ] || { echo "no skills/ dir" >&2; exit 1; }

extract_body() {
  awk 'BEGIN{c=0} /^---$/ { c++; next } c>=2 { print }' "$1"
}

extract_name() {
  awk '/^---$/{c++;next} c==1 && /^name:/ { sub(/^name:[[:space:]]*/, ""); print; exit }' "$1"
}

is_always() {
  awk '/^---$/{c++;next} c==1 && /^triggers:[[:space:]]*\[[[:space:]]*always[[:space:]]*\]/ { f=1; exit } END { exit !f }' "$1"
}

first_trigger() {
  awk '
    /^---$/ { c++; next }
    c==1 && /^triggers:/ { intl=1; next }
    c==1 && intl && /^[[:space:]]*-[[:space:]]/ {
      sub(/^[[:space:]]*-[[:space:]]*/, "")
      print
      exit
    }
  ' "$1"
}

always_block=""
triggered_lines=""

for f in "$SKILLS"/*.md; do
  [ -e "$f" ] || continue
  base="$(basename "$f")"
  [ "$base" = "INDEX.md" ] && continue

  name="$(extract_name "$f")"
  [ -n "$name" ] || continue

  if is_always "$f"; then
    body="$(extract_body "$f")"
    always_block+="$body"$'\n\n'
  else
    trig="$(first_trigger "$f")"
    triggered_lines+="- \`$name\` — $trig"$'\n'
  fi
done

{
  echo "# skills index"
  echo
  echo "Always-applicable skills are inlined below. For triggered skills, the trigger is listed; \`cat skills/<name>.md\` when a trigger matches the user's request."
  echo

  if [ -n "$always_block" ]; then
    echo "## always"
    echo
    printf '%s' "$always_block"
  fi

  if [ -n "$triggered_lines" ]; then
    echo "## triggered"
    echo
    printf '%s' "$triggered_lines"
  fi
} > "$INDEX"

echo "wrote $INDEX"

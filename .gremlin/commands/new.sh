#!/usr/bin/env bash
# new — start fresh and queue memory review for the ended session
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

archive_output="$("$GREMLIN_DIR/bin/archive.sh")"
printf '%s\n' "$archive_output"

archive_path="$(printf '%s\n' "$archive_output" | awk '/^archived to / { sub(/^archived to /, ""); print; exit }')"
if [ -z "$archive_path" ]; then
  echo "fresh transcript"
  echo "memory review skipped: no transcript archive was produced"
  exit 0
fi

archive_id="$(basename "$archive_path" .md)"
item_id="memory-review-$archive_id"
nest_in="$GREMLIN_DIR/.nest/in"
item="$nest_in/$item_id"
landing="$item.landing"

mkdir -p "$nest_in"
if [ -e "$item" ] || [ -e "$item.tending" ] || [ -e "$landing" ]; then
  echo "fresh transcript"
  echo "memory review already queued: $item_id"
  exit 0
fi

mkdir "$landing"
printf 'memory\n' > "$landing/.model"
# Scheduled, idempotent work: canonical Nestlings may safely re-queue it after
# Gremlin establishes that the owning tender is no longer alive.
printf 'scheduled memory review — safe to re-run\n' > "$landing/.recoverable"
cat > "$landing/instructions.md" <<EOF_REVIEW
# Memory review: $archive_id

Review the archived transcript at:

\`\`\`text
$archive_path
\`\`\`

Use the distil skill and the local brief at \`.gremlin/.glean/distil.md\`.

Decide whether this ended session earned durable memory. You may create or
revise findings under \`.gremlin/.glean/findings/\`, retire stale findings with
\`.gremlin/.glean/glean.sh drop\`, or do nothing when nothing durable was
earned.

Do not copy the whole transcript into \`.gremlin/.glean/in/\`. If findings
change, run \`.gremlin/.glean/glean.sh index\`. In your reply, report the brief
memory-review outcome and any finding ids affected.
EOF_REVIEW

mv "$landing" "$item"

echo "fresh transcript"
echo "memory review queued: $item_id"

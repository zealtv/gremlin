#!/usr/bin/env bash
# archive.sh — rotate transcript.md into transcript-archive/.
#
# Coordinates with the tend/tick loops via .paused so a pass mid-flight
# can't append into the freshly-rotated transcript:
#
#   1. touch .paused           # loops idle on their next iteration
#   2. sleep past tend cadence # any in-flight pass finishes its `>>`
#   3. mv transcript.md → transcript-archive/<YYYY-MM-DD>.md
#   4. touch a new empty transcript.md
#   5. rm .paused              # loops resume
#
# Pending nest and groundhog items live in their own subtrees; archive
# does not touch them.

set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRANSCRIPT="$GREMLIN_DIR/transcript.md"
ARCHIVE_DIR="$GREMLIN_DIR/transcript-archive"
PAUSE_FLAG="$GREMLIN_DIR/.paused"

# Long enough that any started tend pass (5s cadence) has finished.
QUIESCE_SECS=6

mkdir -p "$ARCHIVE_DIR"

touch "$PAUSE_FLAG"
trap 'rm -f "$PAUSE_FLAG"' EXIT

sleep "$QUIESCE_SECS"

if [ -f "$TRANSCRIPT" ]; then
  date_stamp="$(date +%Y-%m-%d)"
  target="$ARCHIVE_DIR/$date_stamp.md"
  n=2
  while [ -e "$target" ]; do
    target="$ARCHIVE_DIR/$date_stamp-$n.md"
    n=$((n+1))
  done
  mv "$TRANSCRIPT" "$target"
  echo "archived to $target"
fi

touch "$TRANSCRIPT"

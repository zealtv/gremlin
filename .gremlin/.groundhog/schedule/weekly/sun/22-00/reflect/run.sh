#!/usr/bin/env bash
# reflect/run.sh — the quiet weekly gate for the reflect skill.
#
# Clock-paced goal (docs/protocol.md "Work That Outlives A Turn"): groundhog
# fires this weekly, but it stays SILENT unless enough new conversation has
# accrued since the last reflection. A no-material tick prints nothing — so the
# tender writes no turn and runs no model (the empty-stdout guard in
# tend-loop.sh). On a material tick it escalates to a model-backed reflect tend
# via tools/continue.sh and advances its cursor; that reflection then decides
# whether anything is worth recording, replying <silent> if not. Two gates: the
# clock bounds frequency, the cursor bounds noise — cadence is milestones, not
# the clock.
set -euo pipefail

# Depth-independent: groundhog materialises this to .nest/in/<name>/ regardless
# of its schedule depth, so walk up to the directory that holds .nest.
GREMLIN_DIR="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; \
  while [ "$d" != / ] && [ ! -d "$d/.nest" ]; do d="$(dirname "$d")"; done; \
  printf %s "$d")"
[ -d "$GREMLIN_DIR/.nest" ] || { echo "reflect: could not locate gremlin dir" >&2; exit 1; }

# The cursor lives in the schedule SOURCE (excluded from /update, persists across
# firings) — never this materialised copy, which is discarded after the tend.
STATE="$GREMLIN_DIR/.groundhog/schedule/weekly/sun/22-00/reflect/cursor"
THRESHOLD="${REFLECT_THRESHOLD:-4000}"   # bytes of new transcript before reflecting is worth it

# Material accrued = current transcript + everything archived. /new resets
# transcript.md but grows transcript-archive/, so the sum is monotonic across
# sessions and a reflection is never missed just because a session was closed.
live=$(wc -c < "$GREMLIN_DIR/transcript.md" 2>/dev/null || echo 0)
archived=$(find "$GREMLIN_DIR/transcript-archive" -type f -printf '%s\n' 2>/dev/null \
  | awk '{s+=$1} END{print s+0}')
cur=$(( live + archived ))
last=0
[ -f "$STATE" ] && last=$(cat "$STATE" 2>/dev/null || echo 0)

mkdir -p "$(dirname "$STATE")"

# A shrinking total (manual archive cleanup) just resyncs the cursor, no reflect.
if [ "$cur" -lt "$last" ]; then
  printf '%s\n' "$cur" > "$STATE"
  exit 0
fi

# Not enough new material: quiet tick — no stdout, so no turn and no model call.
if [ $(( cur - last )) -lt "$THRESHOLD" ]; then
  exit 0
fi

# Material: advance the cursor (we are reflecting on everything up to here) and
# escalate to a model-backed reflect tend. Stay silent ourselves so the only turn
# is the reflection itself.
printf '%s\n' "$cur" > "$STATE"
"$GREMLIN_DIR/tools/continue.sh" \
  "Scheduled weekly self-reflection. Run your reflect skill (skills/reflect.md): review your recent work since the last reflection, distil any durable lessons into Glean findings (Tier A), and stage any warranted behavior-change proposals for human review (Tier B) — honor the self-edit denylist. If nothing is worth recording or proposing, reply with exactly <silent>." \
  >/dev/null
exit 0

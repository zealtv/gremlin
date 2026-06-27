#!/usr/bin/env bash
# reflect-expire/run.sh — dead-man's switch for the weekly reflect goal.
#
# Per docs/protocol.md, every standing schedule carries a once/<date> backstop so
# it cannot run forever unattended. On its date this drops the reflect goal; the
# once/ item then removes itself (groundhog rule 4). /stop and .paused remain the
# human backstops — this is the automatic one. To keep reflecting past this date,
# re-arm the goal and set a fresh expiry.
set -euo pipefail

GREMLIN_DIR="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; \
  while [ "$d" != / ] && [ ! -d "$d/.nest" ]; do d="$(dirname "$d")"; done; \
  printf %s "$d")"
[ -d "$GREMLIN_DIR/.nest" ] || { echo "reflect-expire: could not locate gremlin dir" >&2; exit 1; }

# Drop the goal even if it never reached a done-condition. Tolerate it already
# being gone (renamed .paused, dropped by hand) so the switch still self-removes.
"$GREMLIN_DIR/.groundhog/groundhog.sh" drop reflect >/dev/null 2>&1 || true
echo "expired the weekly reflect goal (dead-man's switch). Re-arm by recreating .groundhog/schedule/weekly/sun/22-00/reflect/ with a fresh once/<date>/reflect-expire/ if still wanted."

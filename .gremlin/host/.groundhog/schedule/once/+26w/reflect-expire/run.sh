#!/usr/bin/env bash
# reflect-expire/run.sh — dead-man's switch for the weekly reflect goal.
#
# Per docs/protocol.md, every standing schedule carries a once/<date> backstop so
# it cannot run forever unattended. On its date this drops the reflect goal; the
# once/ item then removes itself (groundhog rule 4). /stop and .paused remain the
# human backstops — this is the automatic one.
#
# This file ships under once/+26w/, and bin/install-host-files.sh turns that
# into the date 26 weeks after the install. To keep reflecting past it, run
# .gremlin/bin/install-host-files.sh again: it restores the reflect job and a
# fresh expiry.
set -euo pipefail

HOST_DIR="$(d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; \
  while [ "$d" != / ] && [ ! -d "$d/.nest" ]; do d="$(dirname "$d")"; done; \
  printf %s "$d")"
GREMLIN_DIR="$HOST_DIR/.gremlin"
[ -d "$HOST_DIR/.nest" ] || { echo "reflect-expire: could not locate the host root" >&2; exit 1; }

# Drop the goal even if it never reached a done-condition. Tolerate it already
# being gone (renamed .paused, dropped by hand) so the switch still self-removes.
"$HOST_DIR/.groundhog/groundhog.sh" drop reflect >/dev/null 2>&1 || true
echo "expired the weekly reflect goal (dead-man's switch). To keep reflecting, run .gremlin/bin/install-host-files.sh again: it restores the job with a fresh expiry."

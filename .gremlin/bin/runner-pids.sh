#!/usr/bin/env bash
# runner-pids.sh — the pids of this gremlin's running bin/run.sh (the runner and
# the loop subshells it forked), one per line; nothing if it is asleep.
#
# `gremlin` (status, wake, sleep) and `/update` (the restart note) both ask this,
# so the answer comes from one place. pgrep -f reads its pattern as an extended
# regex, and the host's path goes into it: escape the path first, or a host in
# `my host (v2)+c/` is never found.
#
# usage: runner-pids.sh      (exit 0 either way; the output is the answer)
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pattern="$(printf '%s' "$GREMLIN_DIR/bin/run.sh" | sed 's/[][(){}.^$*+?|\\]/\\&/g')"
pgrep -f "$pattern" 2>/dev/null || true

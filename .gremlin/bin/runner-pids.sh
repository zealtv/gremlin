#!/usr/bin/env bash
# runner-pids.sh — the pids of this gremlin's running bin/run.sh (the runner and
# the loop subshells it forked), one per line; nothing if it is asleep.
#
# `gremlin` (status, wake, sleep) and `/update` (the restart note) both ask this,
# so the answer comes from one place. It reads `ps` and matches the path as a
# plain string (no regex, so a host in `my host (v2)+c/` needs no escaping), not
# `pgrep`: macOS pgrep leaves out its own ancestors, so asked from inside the
# gremlin (its agent, a nest item, a groundhog job) it would miss the loop that
# runs the caller. `COLUMNS=` stops procps cutting a long command line; the path
# goes through the environment so the awk doesn't match its own command line.
#
# usage: runner-pids.sh      (exit 0 either way; the output is the answer)
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COLUMNS= ps -A -o pid= -o args= 2>/dev/null \
  | RUNNER="$GREMLIN_DIR/bin/run.sh" awk '{ pid = $1; sub(/^[ \t]*[0-9]+[ \t]+/, ""); if (index($0, ENVIRON["RUNNER"])) print pid }' || true

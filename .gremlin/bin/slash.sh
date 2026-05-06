#!/usr/bin/env bash
# slash — shared slash-command dispatcher for bridges.
#
# Usage:
#   bin/slash.sh "/cmd args..."     # leading slash optional
#   bin/slash.sh cmd args...        # equivalent
#
# Resolves commands/<cmd>.sh and runs it from $GREMLIN_DIR with stdin closed.
# Stdout/stderr pass through. Exit code is the command's exit code.
#
# Bridge-lifecycle commands like /exit and /quit are NOT handled here; that
# is a bridge-process concern.

set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMANDS="$GREMLIN_DIR/commands"

usage() {
  echo "usage: $0 /<command> [args...]   (try /help)" >&2
}

if [ "$#" -eq 0 ]; then
  usage
  exit 2
fi

# Accept either `slash.sh "/cmd a b"` or `slash.sh /cmd a b` or `slash.sh cmd a b`.
if [ "$#" -eq 1 ]; then
  rest="$1"
else
  rest="$*"
fi
rest="${rest#/}"
rest="${rest#"${rest%%[![:space:]]*}"}"  # ltrim

if [ -z "$rest" ]; then
  usage
  exit 2
fi

cmd="${rest%% *}"
if [ "$cmd" = "$rest" ]; then
  args=()
else
  # shellcheck disable=SC2206
  args=(${rest#"$cmd "})
fi

script="$COMMANDS/$cmd.sh"
if [ ! -x "$script" ]; then
  echo "unknown command: /$cmd" >&2
  echo "try /help" >&2
  exit 127
fi

cd "$GREMLIN_DIR"
exec "$script" "${args[@]}" </dev/null

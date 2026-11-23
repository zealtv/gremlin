#!/usr/bin/env bash
# moot-loop.sh — one pass of the moot catch-up.
#
# Does nothing unless the host has a moot (.moot/moot.sh) and a nest. Otherwise
# asks moot for the posts that mention this gremlin (`@<name>`, `@all`, or any
# post in a direct-message room) and delivers each into .nest/in/ as
# moot-<room>-<id>.md, where the tender takes it as an ordinary model turn.
# A board with nothing for the gremlin delivers nothing and costs no model turn.
#
# The pass moves moot's cursor, so it is the only reader this host should run.
# moot's stdout is discarded (it would add a line a minute to the runner's
# log); its stderr and exit status pass through.

set -uo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_DIR="$(cd "$GREMLIN_DIR/.." && pwd)"

[ -e "$GREMLIN_DIR/.paused" ] && exit 0

# No moot here, or no nest to deliver into: nothing to do. (`--deliver` makes
# its directory, so without the nest check this pass would create .nest/in/.)
[ -x "$HOST_DIR/.moot/moot.sh" ] || exit 0
[ -e "$HOST_DIR/.nest/nestling.sh" ] || exit 0

"$HOST_DIR/.moot/moot.sh" read --new --deliver "$HOST_DIR/.nest/in" >/dev/null

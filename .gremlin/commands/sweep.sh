#!/bin/sh
if [ "${GREMLIN_BASH_TRAMPOLINE:-}" != "1" ]; then
  [ "${LC_ALL:-}" = "C.UTF-8" ] && unset LC_ALL
  export GREMLIN_BASH_TRAMPOLINE=1
  exec bash "$0" "$@"
fi
unset GREMLIN_BASH_TRAMPOLINE
# sweep — remove old nestling and groundhog archive entries
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
days="${1:-14}"

if [ "$#" -gt 1 ]; then
  echo "usage: /sweep [days]" >&2
  exit 2
fi

"$GREMLIN_DIR/.nest/nestling.sh" sweep "$days"
"$GREMLIN_DIR/.groundhog/groundhog.sh" sweep "$days"

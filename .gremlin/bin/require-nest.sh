#!/usr/bin/env bash
# require-nest.sh — fail with one plain line when the host has no nest.
#
# A gremlin tends a nest it does not carry: .nest/ comes from the nestlings
# primitive at the host root. `wake`, `prompt` and `tend` call this first, so a
# copy that lacks it says so instead of erroring on every loop pass.
#
# usage: require-nest.sh [host-dir]   (default: the host of this gremlin)
# exit 0 if <host>/.nest/nestling.sh exists, else print the fix and exit 1.
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_DIR="$(cd "${1:-$GREMLIN_DIR/..}" 2>/dev/null && pwd)" || {
  echo "no such host dir: ${1:-}" >&2; exit 1; }

[ -e "$HOST_DIR/.nest/nestling.sh" ] && exit 0

echo "gremlin: this folder has no nest (.nest/nestling.sh); run ./.gremlin/bin/install-primitives.sh to add the missing primitives" >&2
exit 1

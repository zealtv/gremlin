#!/usr/bin/env bash
# usage: ./init.sh <host-dir>
# Places a fresh .gremlin/ inside the given host directory.
set -euo pipefail
[[ -n "${1:-}" ]] || { echo "usage: $0 <host-dir>" >&2; exit 2; }
target="$1/.gremlin"
[[ ! -e "$target" ]] || { echo "refusing: $target already exists" >&2; exit 1; }
cp -r "$(dirname "$0")/.gremlin" "$target"
echo "initialised gremlin at $target"

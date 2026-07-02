#!/usr/bin/env bash
# usage: curl -fsSL https://raw.githubusercontent.com/zealtv/gremlin/main/install.sh | bash
#        curl -fsSL https://raw.githubusercontent.com/zealtv/gremlin/main/install.sh | bash -s -- <host-dir>
# Places a fresh .gremlin/ inside the given host directory, downloading it from
# the canonical GitHub tarball.
set -euo pipefail

target="${1:-$PWD}"
dest="$target/.gremlin"
url="${GREMLIN_INSTALL_URL:-https://github.com/zealtv/gremlin/archive/refs/heads/main.tar.gz}"

[[ ! -e "$dest" ]] || { echo "refusing: $dest already exists" >&2; exit 1; }
mkdir -p "$target"

tmp="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp"
}
trap cleanup EXIT

curl -fsSL "$url" -o "$tmp/gremlin.tar.gz"
tar -xzf "$tmp/gremlin.tar.gz" -C "$tmp"

extracted="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
src="$extracted/.gremlin"
[[ -d "$src" ]] || { echo "tarball does not contain a .gremlin/ at its root" >&2; exit 1; }

cp -R "$src" "$dest"
"$dest/.glean/glean.sh" init
"$dest/.glean/glean.sh" index >/dev/null
"$dest/.lore/lore.sh" init
"$dest/.lore/lore.sh" index >/dev/null
"$dest/bin/doctor.sh" >/dev/null
echo "initialised gremlin at $dest"

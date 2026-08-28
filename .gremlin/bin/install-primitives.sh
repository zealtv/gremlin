#!/usr/bin/env bash
# install-primitives.sh — install any of the five primitives that are missing
# from a host root, using each primitive's OWN install.sh from its own repo.
#
# This is install-time convenience, never update-time. gremlin does not deliver
# the primitives and does not own their contents: this fetches each project's
# canonical tarball and runs the installer that ships with it. An installed
# primitive is never touched again — the script only ever fills a gap, so it is
# safe to re-run.
#
# usage: install-primitives.sh [host-dir] [name...]
#   host-dir  defaults to the host of the gremlin this script is installed in
#   name...   defaults to all five (nest loom lore glean groundhog)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# dotdir name -> github repo name. `.nest` comes from `nestlings`; the rest
# share their names.
repo_for() {
  case "$1" in
    nest) echo nestlings ;;
    loom|lore|glean|groundhog) echo "$1" ;;
    *) return 1 ;;
  esac
}

host="${1:-}"
if [ -n "$host" ]; then shift; else host="$(cd "$SCRIPT_DIR/../.." && pwd)"; fi
host="$(cd "$host" 2>/dev/null && pwd)" || { echo "no such host dir: $host" >&2; exit 1; }

names=("$@")
[ "${#names[@]}" -gt 0 ] || names=(nest loom lore glean groundhog)

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

installed=0
for name in "${names[@]}"; do
  repo="$(repo_for "$name")" || { echo "not a primitive: $name" >&2; exit 2; }
  if [ -d "$host/.$name" ]; then
    echo "ok .$name already installed"
    continue
  fi
  url="${GREMLIN_PRIMITIVE_URL_BASE:-https://github.com/zealtv}/$repo/archive/refs/heads/main.tar.gz"
  echo "📦 installing .$name from $repo"
  if ! curl -fsSL "$url" -o "$tmp/$repo.tar.gz"; then
    echo "‼️  could not download $url — install .$name by hand" >&2
    continue
  fi
  rm -rf "${tmp:?}/$repo"
  mkdir -p "$tmp/$repo"
  tar -xzf "$tmp/$repo.tar.gz" -C "$tmp/$repo"
  src="$(find "$tmp/$repo" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [ ! -x "$src/install.sh" ]; then
    echo "‼️  $repo has no install.sh — install .$name by hand" >&2
    continue
  fi
  "$src/install.sh" "$host"
  installed=$((installed + 1))
done

echo "installed $installed primitive(s) at $host"

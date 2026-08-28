#!/usr/bin/env bash
# usage: curl -fsSL https://raw.githubusercontent.com/zealtv/gremlin/main/install.sh | bash
#        curl -fsSL https://raw.githubusercontent.com/zealtv/gremlin/main/install.sh | bash -s -- <host-dir>
#
# Places a fresh .gremlin/ at the host directory, and — because a gremlin with
# no nest cannot be tended — offers to install any of the five primitives that
# are missing, using each primitive's own install.sh from its own repo.
#
# That offer is install-time only. gremlin does not deliver the primitives:
# /update never touches them, and doctor reports a missing one rather than
# quietly reaching for a private copy. Set GREMLIN_SKIP_PRIMITIVES=1 to install
# the tender alone.
set -euo pipefail

target="${1:-$PWD}"
dest="$target/.gremlin"
url="${GREMLIN_INSTALL_URL:-https://github.com/zealtv/gremlin/archive/refs/heads/main.tar.gz}"

[[ ! -e "$dest" ]] || { echo "refusing: $dest already exists" >&2; exit 1; }
mkdir -p "$target"
target="$(cd "$target" && pwd)"
dest="$target/.gremlin"

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

if [[ "${GREMLIN_SKIP_PRIMITIVES:-0}" != "1" ]]; then
  # Which primitives are arriving with this install? Their policy files are
  # the project's own placeholders, so gremlin's versions replace them; a
  # primitive that was already here keeps everything it has.
  fresh=""
  for name in nest loom lore glean groundhog; do
    [[ -d "$target/.$name" ]] || fresh="$fresh $name"
  done
  "$dest/bin/install-primitives.sh" "$target"
  "$dest/bin/install-host-files.sh" --fresh "$fresh" "$target"
  # Generated indexes: each primitive writes its own, but only once it has been
  # asked to. memory.md is broadcast from .glean/findings/INDEX.md, so a
  # never-indexed glean leaves a dangling context link on the very first tend.
  [[ -x "$target/.glean/glean.sh" ]] && "$target/.glean/glean.sh" index >/dev/null
  [[ -x "$target/.lore/lore.sh" ]] && "$target/.lore/lore.sh" index >/dev/null
fi

"$dest/bin/doctor.sh"
echo "initialised gremlin at $dest"

#!/usr/bin/env bash
# update — pull canonical gremlin from .upstream and lay it over this copy
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_FILE="$GREMLIN_DIR/.upstream"
PAUSED_FILE="$GREMLIN_DIR/.paused"

dry_run=0
if [ "${1:-}" = "--dry-run" ]; then
  dry_run=1
elif [ "$#" -gt 0 ]; then
  echo "usage: /update [--dry-run]" >&2
  exit 2
fi

if [ ! -f "$UPSTREAM_FILE" ]; then
  echo "no .upstream file at $UPSTREAM_FILE" >&2
  echo "write the canonical tarball URL to it (see commands/README.md)" >&2
  exit 1
fi

url="$(tr -d '[:space:]' < "$UPSTREAM_FILE")"
if [ -z "$url" ]; then
  echo ".upstream is empty" >&2
  exit 1
fi

# Excludes: runtime queues, personal context, identity, per-install state.
# context/ is skipped as local state; bin/doctor.sh restores managed
# context/system symlinks after the overlay.
# No --delete: user-created files (custom skills, tools, commands, presets)
# survive untouched.
excludes=(
  --exclude='transcript*'
  --exclude='.nest/in/'
  --exclude='.nest/out/'
  --exclude='.nest/dropped/'
  --exclude='.groundhog/out/'
  --exclude='.groundhog/fired/'
  --exclude='.groundhog/schedule/'
  --exclude='.glean/in/'
  --exclude='.glean/findings/'
  --exclude='.glean/out/'
  --exclude='.glean/dropped/'
  --exclude='.glean/distil.md'
  --exclude='context/'
  --exclude='gremlin.md'
  --exclude='.upstream'
  --exclude='.model'
  --exclude='.paused'
)

tmp="$(mktemp -d)"
created_pause=0
cleanup() {
  rm -rf "$tmp"
  [ "$created_pause" = "1" ] && rm -f "$PAUSED_FILE"
  true
}
trap cleanup EXIT

echo "fetching $url"
if ! curl -fsSL "$url" -o "$tmp/gremlin.tar.gz"; then
  echo "download failed" >&2
  exit 1
fi
tar -xzf "$tmp/gremlin.tar.gz" -C "$tmp"

# GitHub archive tarballs extract to a single top-level dir (e.g.
# gremlin-main/). Discover it rather than hardcode.
extracted="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
src="$extracted/.gremlin/"
if [ ! -d "$src" ]; then
  echo "tarball does not contain a .gremlin/ at its root" >&2
  exit 1
fi

if [ "$dry_run" = "1" ]; then
  echo "dry run — no changes will be written"
  rsync -a --dry-run --itemize-changes "${excludes[@]}" "$src" "$GREMLIN_DIR/"
  exit 0
fi

# Pause the loops while we swap files in. Existing .paused (set by
# archive.sh or the user) is honoured — don't remove what we didn't set.
if [ ! -e "$PAUSED_FILE" ]; then
  : > "$PAUSED_FILE"
  created_pause=1
fi

count="$(rsync -a --itemize-changes "${excludes[@]}" "$src" "$GREMLIN_DIR/" \
  | grep -cE '^[<>ch.][fdLDS]' || true)"

echo "updated: $count file(s)"
echo "doctor:"
"$GREMLIN_DIR/bin/doctor.sh" | sed 's/^/  /'

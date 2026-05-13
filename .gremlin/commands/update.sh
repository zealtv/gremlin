#!/usr/bin/env bash
# update — pull canonical gremlin from .upstream and lay it over this copy
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_FILE="$GREMLIN_DIR/.upstream"
PAUSED_FILE="$GREMLIN_DIR/.paused"

dry_run=0
revert_path=""
case "${1:-}" in
  "")
    ;;
  --dry-run)
    dry_run=1
    [ "$#" -eq 1 ] || { echo "usage: /update [--dry-run | --revert <path>]" >&2; exit 2; }
    ;;
  --revert)
    [ "$#" -eq 2 ] || { echo "usage: /update --revert <path>" >&2; exit 2; }
    revert_path="$2"
    case "$revert_path" in
      /*|*..*) echo "--revert path must be relative and must not contain ..; got: $revert_path" >&2; exit 2 ;;
      "") echo "--revert path is empty" >&2; exit 2 ;;
    esac
    ;;
  *)
    echo "usage: /update [--dry-run | --revert <path>]" >&2
    exit 2
    ;;
esac

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
  # User-specialisable model presets. The README invites editing these;
  # leave them alone on update. Custom presets (models/local.sh, etc.) are
  # already safe because rsync has no --delete. Use /update --revert
  # models/default.sh (or memory.sh) to pull the canonical copy back.
  --exclude='models/default.sh'
  --exclude='models/memory.sh'
)

tmp="$(mktemp -d)"
created_pause=0
cleanup() {
  rm -rf "$tmp"
  [ "$created_pause" = "1" ] && rm -f "$PAUSED_FILE"
  true
}
trap cleanup EXIT

echo "📦 fetching: $url"
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

if [ -n "$revert_path" ]; then
  src_file="$src$revert_path"
  if [ ! -e "$src_file" ]; then
    echo "no such path in canonical: $revert_path" >&2
    exit 1
  fi
  if [ ! -f "$src_file" ]; then
    echo "--revert supports single files only; $revert_path is not a regular file in canonical" >&2
    exit 2
  fi
  dst_file="$GREMLIN_DIR/$revert_path"
  mkdir -p "$(dirname "$dst_file")"
  cp -p "$src_file" "$dst_file"
  echo "↩️  reverted $revert_path to canonical"
  exit 0
fi

if [ "$dry_run" = "1" ]; then
  echo "🔎 dry run — no changes will be written"
  rsync -a --dry-run --itemize-changes "${excludes[@]}" "$src" "$GREMLIN_DIR/" \
    | grep -vE '^\.[d]\.\.t\.\.\.\. \./$' || true
  exit 0
fi

# Pause the loops while we swap files in. Existing .paused (set by
# archive.sh or the user) is honoured — don't remove what we didn't set.
if [ ! -e "$PAUSED_FILE" ]; then
  : > "$PAUSED_FILE"
  created_pause=1
fi

changes="$(rsync -a --itemize-changes "${excludes[@]}" "$src" "$GREMLIN_DIR/" \
  | grep -vE '^\.[d]\.\.t\.\.\.\. \./$' || true)"
if [ -n "$changes" ]; then
  count="$(printf '%s\n' "$changes" | grep -cE '^[<>ch.][fdLDS]' || true)"
else
  count=0
fi

echo "✨ updated: $count file(s)"
echo "🩺 doctor:"
"$GREMLIN_DIR/bin/doctor.sh" | sed 's/^/  /'

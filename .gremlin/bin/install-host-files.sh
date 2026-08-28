#!/usr/bin/env bash
# install-host-files.sh — place this gremlin's contributions to its host's
# primitives: its own scheduled work, and nothing else. Everything under
# `host/` mirrors the host root, so
# `host/.groundhog/schedule/weekly/sun/22-00/reflect/` lands at
# `<host>/.groundhog/schedule/weekly/sun/22-00/reflect/`.
#
# It ships no policy files. A gremlin may generate facts about its host; it
# does not author policy for it — `.nest/tend.md` and `.glean/distil.md` belong
# to whoever owns the repository, and doctor reports when one is still the
# primitive's untouched default.
#
# The gremlin's self-care runs on the repository's SHARED schedule, not a
# private one. Visibility is the point of the placement law: a human reading
# `.groundhog/schedule/` sees that this repository reflects on Sunday nights,
# and pausing it is a legitimate human action (`mv reflect reflect.paused`).
#
# Install-time convenience, never delivery and never update-time. Nothing here
# is ever overwritten: a job you paused, a tend.md you rewrote, a finding brief
# you tuned — all stay yours. The installer only fills gaps, so re-running it
# is safe.
#
# usage: install-host-files.sh [--check] [host-dir]
#   --check reports what is missing and writes nothing (exit 1 if anything is).
set -euo pipefail

check_only=0
if [ "${1:-}" = "--check" ]; then check_only=1; shift; fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREMLIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HOST_DIR="$(cd "${1:-$GREMLIN_DIR/..}" 2>/dev/null && pwd)" || {
  echo "no such host dir: ${1:-}" >&2; exit 1; }

SRC="$GREMLIN_DIR/host"
[ -d "$SRC" ] || { echo "no host/ in $GREMLIN_DIR" >&2; exit 1; }

installed=0
skipped=0
missing=""

# Walk the files, not the directories: a file's own primitive must already be
# installed (we never create .nest or .groundhog ourselves — that is the
# primitive's own install.sh's job, via bin/install-primitives.sh), but the
# directories below it are ours to make.
while IFS= read -r src; do
  rel="${src#"$SRC"/}"
  prim="${rel%%/*}"
  dst="$HOST_DIR/$rel"
  if [ ! -d "$HOST_DIR/$prim" ]; then
    case " $missing " in *" $prim "*) ;; *) missing="$missing $prim" ;; esac
    continue
  fi
  # Present already? Either the file itself, or its containing job directory
  # renamed to pause or un-pause it (`reflect` <-> `reflect.paused`) — a human
  # renaming a job must not cause the original to be reinstalled beside it.
  parent="$(dirname "$dst")"
  if [ -e "$dst" ] || [ -e "${parent%.paused}" ] || [ -e "$parent.paused" ]; then
    [ "$check_only" = 1 ] || echo "ok $rel already present"
    skipped=$((skipped + 1))
    continue
  fi
  if [ "$check_only" = 1 ]; then
    echo "missing $rel"
    installed=$((installed + 1))
    continue
  fi
  mkdir -p "$(dirname "$dst")"
  cp -p "$src" "$dst"
  echo "installed $rel"
  installed=$((installed + 1))
done < <(find "$SRC" -type f ! -name README.md | sort)

if [ -n "$missing" ]; then
  for prim in $missing; do
    echo "‼️  ${prim} is not installed at $HOST_DIR — skipped its files" >&2
  done
  echo "     install missing primitives with:" >&2
  echo "     $GREMLIN_DIR/bin/install-primitives.sh $HOST_DIR" >&2
fi

if [ "$check_only" = 1 ]; then
  [ "$installed" = 0 ] || exit 1
  exit 0
fi
echo "host files: $installed installed, $skipped already present"

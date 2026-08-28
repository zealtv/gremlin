#!/usr/bin/env bash
# install-host-files.sh — place this gremlin's contributions to its host's
# primitives: its own scheduled jobs, and the host-local policy files the
# primitives leave to whoever tends the folder (`.nest/tend.md`,
# `.glean/distil.md`).
#
# Everything under `host/` mirrors the host root, so `host/.nest/tend.md` lands
# at `<host>/.nest/tend.md`.
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
# usage: install-host-files.sh [--check] [--fresh "<names>"] [host-dir]
#   --check reports what is missing and writes nothing (exit 1 if anything is).
#   --fresh names primitives that were just installed from scratch, so their
#     placeholder policy files are the primitive's own defaults rather than
#     anyone's work. nestlings ships a tend.md that says "replace the prompts
#     below with the host folder's policy", and glean ships a generic
#     distil.md; on a primitive installed seconds ago, gremlin's versions are
#     that policy and should land. On a primitive that was already there, they
#     never touch it.
set -euo pipefail

check_only=0
fresh=""
while [ "$#" -gt 0 ]; do
  case "${1:-}" in
    --check) check_only=1; shift ;;
    --fresh) fresh="${2:-}"; shift 2 ;;
    *) break ;;
  esac
done

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
  is_fresh=0
  case " $fresh " in *" ${prim#.} "*) is_fresh=1 ;; esac
  if [ "$is_fresh" = 1 ] && [ -f "$dst" ] && [ "$check_only" = 0 ]; then
    cp -p "$src" "$dst"
    echo "installed $rel (over a just-installed primitive's default)"
    installed=$((installed + 1))
    continue
  fi
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

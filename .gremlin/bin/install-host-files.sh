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
# No tracked file names a date. A `once/` folder spelled `+<N>w` (or `+<N>d`)
# in `host/` means "N weeks (days) after the day of installing", and lands in the
# host as that date: `once/+26w/reflect-expire/` installed on 2030-03-01 becomes
# `once/2030-08-30/reflect-expire/`. A date baked into the product would fire on
# the next tick for any gremlin installed after it (groundhog: a past-dated
# one-shot "fires on the next tick regardless").
#
# Install-time convenience, never delivery and never update-time. Nothing here
# is ever overwritten: a job you paused, a tend.md you rewrote, a finding brief
# you tuned — all stay yours. The installer only fills gaps, so re-running it
# is safe.
#
# usage: install-host-files.sh [--check] [host-dir]
#   --check reports what is missing and writes nothing (exit 1 if anything is),
#   including files whose primitive is not installed.
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

# date_after <N> <w|d> — the date N weeks/days after today, as YYYY-MM-DD.
# BSD date and GNU date spell this differently, so try both; "today" comes from
# one plain `date +%F` call, which is also the only call a test needs to fake.
date_after() {
  local n="$1" unit="$2" today word
  today="$(date +%F)"
  case "$unit" in w) word=weeks ;; *) word=days ;; esac
  date -j -v"+${n}${unit}" -f %F "$today" +%F 2>/dev/null \
    || date -d "$today + $n $word" +%F 2>/dev/null \
    || { echo "cannot work out a date $n $word from $today" >&2; return 1; }
}

# Walk the files, not the directories: a file's own primitive must already be
# installed (we never create .nest or .groundhog ourselves — that is the
# primitive's own install.sh's job, via bin/install-primitives.sh), but the
# directories below it are ours to make.
while IFS= read -r src; do
  rel="${src#"$SRC"/}"
  prim="${rel%%/*}"
  # A relative once/ date (`once/+26w/`) is resolved now; `anydate` is the same
  # path with the date as a glob, to recognise an expiry already in place under
  # whatever date it carries (a human may have re-dated or paused it).
  anydate=""
  if [[ "$rel" =~ ^(.*/once/)\+([0-9]+)([wd])(/.*)$ ]]; then
    anydate="$HOST_DIR/${BASH_REMATCH[1]}*${BASH_REMATCH[4]}"
    when="$(date_after "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}")" || exit 1
    rel="${BASH_REMATCH[1]}$when${BASH_REMATCH[4]}"
  fi
  dst="$HOST_DIR/$rel"
  if [ ! -d "$HOST_DIR/$prim" ]; then
    case " $missing " in *" $prim "*) ;; *) missing="$missing $prim" ;; esac
    # A check counts a file that cannot be placed as not placed.
    if [ "$check_only" = 1 ]; then
      echo "missing $rel"
      installed=$((installed + 1))
    fi
    continue
  fi
  # Present already? Either the file itself, or its containing job directory
  # renamed to pause or un-pause it (`reflect` <-> `reflect.paused`) — a human
  # renaming a job must not cause the original to be reinstalled beside it.
  parent="$(dirname "$dst")"
  present=0
  if [ -e "$dst" ] || [ -e "${parent%.paused}" ] || [ -e "$parent.paused" ]; then
    present=1
  elif [ -n "$anydate" ]; then
    adir="$(dirname "$anydate")"
    compgen -G "$adir" >/dev/null && present=1
    compgen -G "$adir.paused" >/dev/null && present=1
  fi
  if [ "$present" = 1 ]; then
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

#!/usr/bin/env bash
# name.sh — the gremlin's own name.
#
# A gremlin has a name of its own, so that "the gremlin" and "the repository it
# tends" stop being the same word. Before this, a gremlin borrowed its host
# directory's name: the web header's `name@host` was really `folder@machine`,
# and after the sibling-primitive inversion the folder is a repository with its
# own identity — the gremlin tending ~/repos would have been called "repos".
#
# The name is **rolled once, at first use, and persisted** — never derived from
# the host path. Deriving would rename a gremlin the moment it was moved, and a
# gremlin is a folder you can `mv`. The consequence, ruled deliberately: `cp -r`
# produces a twin with the same name. The copy is the same gremlin until you say
# otherwise; `name.sh roll` gives it a fresh one.
#
# Storage is .gremlin/name, key=value, and rides /update's exclude list as
# identity alongside gremlin.md and .model:
#
#   name=snallygaster
#   source=generated        # or: custom, once a human has named it
#   vocabulary=1            # which names/vN.txt it was drawn from
#
# usage:
#   name.sh                 print the name, rolling one if there is none
#   name.sh get             same
#   name.sh slug            the name, safe for places a display name cannot go
#   name.sh source          generated | custom
#   name.sh roll            roll a new generated name (never the current one)
#   name.sh set <name>      name it yourself; recorded as custom
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME_FILE="$GREMLIN_DIR/name"
VOCAB_VERSION="${GREMLIN_VOCABULARY:-1}"
VOCAB="$GREMLIN_DIR/names/v$VOCAB_VERSION.txt"

field() {  # field <key> — read one key from the name file
  [ -f "$NAME_FILE" ] || return 1
  local v
  v="$(grep -m1 "^$1=" "$NAME_FILE" 2>/dev/null | cut -d= -f2-)" || true
  [ -n "$v" ] || return 1
  printf '%s' "$v"
}

write_name() {  # write_name <name> <source>
  local tmp="$NAME_FILE.tmp"
  {
    printf 'name=%s\n' "$1"
    printf 'source=%s\n' "$2"
    printf 'vocabulary=%s\n' "$VOCAB_VERSION"
  } > "$tmp"
  mv "$tmp" "$NAME_FILE"
}

vocabulary() {
  [ -f "$VOCAB" ] || {
    echo "no vocabulary at $VOCAB" >&2
    echo "names/v$VOCAB_VERSION.txt ships with the gremlin; run /update to restore it" >&2
    exit 1
  }
  grep -v '^#' "$VOCAB" | grep -v '^[[:space:]]*$'
}

roll() {  # roll [avoid] — pick a word, never the one to avoid
  local avoid="${1:-}" pool
  pool="$(vocabulary | { [ -n "$avoid" ] && grep -vxF "$avoid" || cat; })"
  # shuf is coreutils; $RANDOM is the fallback for a shell without it.
  if command -v shuf >/dev/null 2>&1; then
    printf '%s\n' "$pool" | shuf -n 1
  else
    printf '%s\n' "$pool" | awk -v seed="$RANDOM$$" '
      { lines[NR] = $0 }
      END { srand(seed); print lines[int(rand() * NR) + 1] }'
  fi
}

ensure() {  # the name, rolling and persisting one the first time it is asked for
  local current
  if current="$(field name)"; then
    printf '%s\n' "$current"
    return 0
  fi
  local rolled
  rolled="$(roll)"
  write_name "$rolled" generated
  printf '%s\n' "$rolled"
}

case "${1:-get}" in
  get|"")
    ensure
    ;;
  slug)
    # Vocabulary words are already lowercase ASCII, but a custom name is
    # whatever a human typed. Fold it to something a URL, a filename or a
    # process listing can carry.
    ensure | tr '[:upper:]' '[:lower:]' \
      | sed -e 's/[^a-z0-9]\+/-/g' -e 's/^-\+//' -e 's/-\+$//'
    ;;
  source)
    field source || echo generated
    ;;
  roll)
    current="$(field name || true)"
    rolled="$(roll "$current")"
    write_name "$rolled" generated
    printf '%s\n' "$rolled"
    ;;
  set)
    [ "$#" -ge 2 ] || { echo "usage: name.sh set <name>" >&2; exit 2; }
    shift
    given="$*"
    case "$given" in
      *[!\ -~]*) echo "a name must be printable ASCII: $given" >&2; exit 2 ;;
    esac
    [ -n "${given// /}" ] || { echo "a name cannot be blank" >&2; exit 2; }
    write_name "$given" custom
    printf '%s\n' "$given"
    ;;
  *)
    echo "usage: name.sh [get|slug|source|roll|set <name>]" >&2
    exit 2
    ;;
esac

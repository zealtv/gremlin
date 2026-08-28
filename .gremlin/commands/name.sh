#!/usr/bin/env bash
# name — show or change this gremlin's name.
#
# A gremlin's name is its own, not its folder's. It is rolled once at first
# start and persisted; a human can change it, and the change is recorded as
# custom so a later roll never quietly undoes it.
#
# usage:
#   /name                 what are you called?
#   /name <new name>      call it something else (recorded as custom)
#   /name --roll          roll a fresh generated name
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME_SH="$GREMLIN_DIR/bin/name.sh"

[ -x "$NAME_SH" ] || { echo "bin/name.sh missing — run /update" >&2; exit 1; }

case "${1:-}" in
  "")
    printf '%s (%s)\n' "$("$NAME_SH" get)" "$("$NAME_SH" source)"
    ;;
  --roll)
    old="$("$NAME_SH" get)"
    new="$("$NAME_SH" roll)"
    printf 'rolled: %s -> %s\n' "$old" "$new"
    ;;
  --help|-h)
    sed -n '2,12p' "$0" | sed 's/^# \?//'
    exit 0
    ;;
  *)
    old="$("$NAME_SH" get)"
    new="$("$NAME_SH" set "$@")"
    printf 'renamed: %s -> %s\n' "$old" "$new"
    ;;
esac

# identity.md is generated from the name; refresh it so the next prompt says
# the right thing.
"$GREMLIN_DIR/bin/doctor.sh" >/dev/null 2>&1 || true

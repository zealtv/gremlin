#!/usr/bin/env bash
# hoist-primitives.sh — move a gremlin's vendored primitives out to the host root.
#
# One-time migration for the sibling-primitive refactor. NOT part of the
# delivered .gremlin/ bundle: it does not ride /update, and a migrated host has
# no further use for it.
#
#   .../<host>/.gremlin/.nest      ->  .../<host>/.nest
#              .gremlin/.loom      ->             .loom
#              .gremlin/.lore      ->             .lore
#              .gremlin/.glean     ->             .glean
#              .gremlin/.groundhog ->             .groundhog
#
# and leaves a relative symlink behind for each, so un-retargeted code keeps
# working until stitch 50 lands. Spike 20 proved the shim survives /update, but
# only once update.sh excludes the five primitive dirs wholesale — so this
# script refuses to migrate a host whose update.sh has not taken that change.
#
# usage:
#   ./hoist-primitives.sh [--dry-run] <host-dir>
#   ./hoist-primitives.sh --revert    <host-dir>
set -euo pipefail

PRIMITIVES=(nest loom lore glean groundhog)

# Relative paths inside a primitive that belong to the HOST's own install of
# that primitive: its program files and its generated indexes. In the merge
# case the vendored copy of one of these is never folded in and never wins —
# it is parked for review. Everything else is data: it merges, and a genuine
# same-path conflict refuses the whole run.
host_owned() {
  case "$1" in
    nest)      echo "nestling.sh README.md tend.md" ;;
    loom)      echo "loom.sh README.md format-version queue install.sh docs" ;;
    lore)      echo "lore.sh README.md INDEX.md" ;;
    glean)     echo "glean.sh README.md findings/INDEX.md" ;;
    groundhog) echo "groundhog.sh README.md" ;;
  esac
}

die() { echo "❌ $*" >&2; exit 1; }

dry_run=0
revert=0
host=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --revert)  revert=1 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    -*)        die "unknown option: $1" ;;
    *)         [ -z "$host" ] || die "one host dir at a time; got extra: $1"; host="$1" ;;
  esac
  shift
done
[ -n "$host" ] || die "usage: $(basename "$0") [--dry-run | --revert] <host-dir>"
[ "$dry_run" = 1 ] && [ "$revert" = 1 ] && die "--dry-run and --revert are mutually exclusive"

host="$(cd "$host" 2>/dev/null && pwd)" || die "no such directory: $host"
gd="$host/.gremlin"
[ -d "$gd" ] || die "no .gremlin/ in $host — nothing to migrate"

manifest="$gd/.hoist-manifest"
parked="$gd/.hoist-parked"

# ---------------------------------------------------------------- git awareness
repo_root=""
if repo_root="$(git -C "$host" rev-parse --show-toplevel 2>/dev/null)"; then :; else repo_root=""; fi

tracked() {  # tracked <path> — true if git knows about this path (file or subtree)
  [ -n "$repo_root" ] || return 1
  [ -n "$(git -C "$repo_root" ls-files -- "$1" 2>/dev/null | head -n 1)" ]
}

move_path() {  # move_path <src> <dst> — history-preserving where git can
  local src="$1" dst="$2"
  if tracked "$src" && git -C "$repo_root" mv "$src" "$dst" 2>/dev/null; then
    return 0
  fi
  mv "$src" "$dst"
}

# ------------------------------------------------------------------- revert
if [ "$revert" = 1 ]; then
  [ -f "$manifest" ] || die "no migration manifest at $manifest — nothing to revert"
  # Reverse order: links first, then every move, then the directories we made.
  tac "$manifest" | while IFS=$'\t' read -r verb a b; do
    case "$verb" in
      link)  [ -L "$a" ] && rm "$a" && echo "🔗 removed shim $a" ;;
      move|park)
        if [ -e "$b" ] || [ -L "$b" ]; then
          mkdir -p "$(dirname "$a")"
          move_path "$b" "$a"
          echo "↩️  $b -> $a"
        else
          echo "⚠️  missing, cannot restore: $b" >&2
        fi ;;
      mkdir) rmdir "$a" 2>/dev/null && echo "🗑️  removed empty $a" || true ;;
    esac
  done
  find "$parked" -depth -type d -empty -delete 2>/dev/null || true
  rm -f "$manifest"
  echo "✅ reverted; $host is un-migrated"
  exit 0
fi

# ------------------------------------------------------------ pre-flight gates
update_sh="$gd/commands/update.sh"
[ -f "$update_sh" ] || die "no commands/update.sh in $gd — is this a gremlin?"
if [ "$(grep -c "exclude='\.loom/'" "$update_sh")" != "1" ]; then
  cat >&2 <<GATE
❌ this gremlin's update.sh does not exclude the primitive dirs wholesale.

   /update overwrites update.sh itself, so a host migrated now would be
   silently un-migrated by its next update (spike 20, §5). Ship the five
   wholesale excludes canonically, run /update on this host first, confirm

     grep -c "exclude='.loom/'" $update_sh

   reads 1, and then migrate.
GATE
  exit 1
fi

if [ "$dry_run" = 0 ] && pgrep -f "$gd/bin/run.sh" >/dev/null 2>&1; then
  die "the gremlin is running — stop it first: $gd/gremlin stop && pkill -f $gd/bin/run.sh"
fi

if [ -f "$manifest" ]; then
  die "$manifest exists — this host looks already migrated; --revert first"
fi

# ------------------------------------------------------------------- planning
plan=()          # verb \t src \t dst
collisions=()
notes=()

is_host_owned() {  # is_host_owned <primitive> <relpath>
  local p="$1" rel="$2" own
  for own in $(host_owned "$p"); do
    [ "$rel" = "$own" ] && return 0
    case "$rel" in "$own"/*) return 0 ;; esac
  done
  return 1
}

plan_merge() {  # plan_merge <primitive> <srcdir> <dstdir> <relprefix>
  local p="$1" srcdir="$2" dstdir="$3" prefix="$4" entry name rel s d
  local -a kids=()
  shopt -s nullglob dotglob
  kids=("$srcdir"/*)
  shopt -u nullglob dotglob
  for entry in "${kids[@]}"; do
    name="$(basename "$entry")"
    rel="${prefix:+$prefix/}$name"
    s="$srcdir/$name"
    d="$dstdir/$name"
    if is_host_owned "$p" "$rel"; then
      plan+=("park	$s	$parked/$p/$rel")
      notes+=("$p: host install owns $rel — vendored copy parked")
    elif [ ! -e "$d" ] && [ ! -L "$d" ]; then
      plan+=("move	$s	$d")
    elif [ -d "$s" ] && [ -d "$d" ]; then
      plan_merge "$p" "$s" "$d" "$rel"
    elif [ -f "$s" ] && [ -f "$d" ] && cmp -s "$s" "$d"; then
      plan+=("park	$s	$parked/$p/$rel")
    else
      collisions+=(".$p/$rel — vendored and host copies differ")
    fi
  done
}

for p in "${PRIMITIVES[@]}"; do
  src="$gd/.$p"
  dst="$host/.$p"
  if [ -L "$src" ]; then
    notes+=(".$p: already a symlink ($(readlink "$src")) — skipped")
    continue
  fi
  if [ ! -d "$src" ]; then
    notes+=(".$p: not vendored here — skipped")
    continue
  fi
  if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
    plan+=("move	$src	$dst")
    plan+=("link	$src	../.$p")
  elif [ -d "$dst" ]; then
    notes+=(".$p: merging into existing host primitive")
    plan_merge "$p" "$src" "$dst" ""
    plan+=("rmtree	$src	")
    plan+=("link	$src	../.$p")
  else
    collisions+=(".$p — host root has a non-directory at $dst")
  fi
done

# --------------------------------------------------------------------- report
echo "🪺 hoist: $host"
[ -n "$repo_root" ] && echo "   git repo: $repo_root (moves use git mv where tracked)"
for n in "${notes[@]:-}"; do [ -n "$n" ] && echo "   · $n"; done

if [ "${#collisions[@]}" -gt 0 ] && [ -n "${collisions[0]:-}" ]; then
  echo
  echo "❌ refusing: real collisions between vendored and host data." >&2
  for c in "${collisions[@]}"; do echo "   ✗ $c" >&2; done
  echo >&2
  echo "   Resolve each by hand — rename, merge or drop one side — then rerun." >&2
  echo "   Nothing was moved." >&2
  exit 1
fi

if [ "${#plan[@]}" -eq 0 ] || [ -z "${plan[0]:-}" ]; then
  echo "   nothing to do."
  exit 0
fi

echo
for line in "${plan[@]}"; do
  IFS=$'\t' read -r verb a b <<<"$line"
  case "$verb" in
    move)   echo "   mv    ${a#$host/}  ->  ${b#$host/}" ;;
    park)   echo "   park  ${a#$host/}  ->  ${b#$host/}" ;;
    rmtree) echo "   rmdir ${a#$host/}  (emptied by the merge)" ;;
    link)   echo "   ln -s $b  ${a#$host/}" ;;
  esac
done

if [ "$dry_run" = 1 ]; then
  echo
  echo "🔎 dry run — nothing written."
  exit 0
fi

# ---------------------------------------------------------------------- apply
: > "$manifest"
record() { printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >> "$manifest"; }

for line in "${plan[@]}"; do
  IFS=$'\t' read -r verb a b <<<"$line"
  case "$verb" in
    move|park)
      parent="$(dirname "$b")"
      if [ ! -d "$parent" ]; then
        mkdir -p "$parent"
        record mkdir "$parent"
      fi
      move_path "$a" "$b"
      record "$verb" "$a" "$b"
      ;;
    rmtree)
      # Every child was moved or parked; anything left is an empty dir tree.
      find "$a" -depth -type d -empty -delete 2>/dev/null || true
      [ -e "$a" ] && die "merge left files behind in $a — inspect, then --revert"
      ;;
    link)
      ln -s "$b" "$a"
      record link "$a"
      ;;
  esac
done

echo
echo "✅ migrated. Shim symlinks in place; manifest at ${manifest#$host/}"
[ -d "$parked" ] && echo "⚠️  parked copies to review: ${parked#$host/}"
echo "   Next: start the gremlin and confirm it still tends."

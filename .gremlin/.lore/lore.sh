#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage:
  lore.sh init
  lore.sh keep <prepared-item-dir> <slug>
  lore.sh index
  lore.sh fetch [--all] <query...>
  lore.sh status

notes:
  - a prepared item contains a valid item.md and a content/ directory
  - keep prefixes <slug> with today's local date and never overwrites
  - INDEX.md is generated; items/ is the source of truth
  - lore has no delete, retire, expire, or sweep command
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

resolve_paths() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [[ "$(basename "$script_dir")" == ".lore" ]] || die "lore.sh must live inside a .lore/ directory"
  LORE_DIR="$script_dir"
  ITEMS_DIR="$LORE_DIR/items"
  INDEX_FILE="$LORE_DIR/INDEX.md"
}

require_lore() {
  resolve_paths
  [[ -d "$ITEMS_DIR" ]] || die "lore is not initialized; run lore.sh init"
}

slug_is_valid() {
  local slug="$1"
  [[ -n "$slug" &&
     "$slug" =~ ^[A-Za-z0-9._-]+$ &&
     "$slug" != .* &&
     "$slug" != *..* ]]
}

validate_slug() {
  local slug="$1"
  slug_is_valid "$slug" || die "invalid slug '$slug' (use letters, numbers, ., _, -; no leading . or ..)"
}

extract_title() {
  local line
  line="$(grep -m1 '^# ' "$1" 2>/dev/null || true)"
  printf '%s' "${line#\# }"
}

extract_description() {
  awk '
    /^# / && !found_title { found_title=1; next }
    found_title && /^[[:space:]]*$/ { next }
    found_title && /^#/ { exit }
    found_title { print; exit }
  ' "$1"
}

validate_item() {
  local item="$1"
  local label="$(basename "$item")"
  local title desc symlink

  [[ -d "$item" ]] || { echo "invalid $label: item must be a directory" >&2; return 1; }
  [[ -f "$item/item.md" && ! -L "$item/item.md" ]] || { echo "invalid $label: missing or symlinked item.md" >&2; return 1; }
  [[ -d "$item/content" && ! -L "$item/content" ]] || { echo "invalid $label: missing or symlinked content/ directory" >&2; return 1; }

  if ! symlink="$(find "$item" -type l -print -quit)"; then
    echo "invalid $label: could not inspect item" >&2
    return 1
  fi
  [[ -z "$symlink" ]] || { echo "invalid $label: symlinks are not complete copied content" >&2; return 1; }

  title="$(extract_title "$item/item.md")"
  desc="$(extract_description "$item/item.md")"
  [[ -n "$title" ]] || { echo "invalid $label: item.md needs a '# Title'" >&2; return 1; }
  [[ -n "$desc" ]] || { echo "invalid $label: item.md needs a description after its title" >&2; return 1; }
}

validate_stored_item() {
  local item="$1"
  local id="$(basename "$item")"
  local slug month day
  validate_item "$item" || return 1
  [[ "$id" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[A-Za-z0-9._-]+$ ]] || {
    echo "invalid $id: expected YYYY-MM-DD-<slug>" >&2
    return 1
  }
  month=$((10#${id:5:2}))
  day=$((10#${id:8:2}))
  (( month >= 1 && month <= 12 && day >= 1 && day <= 31 )) || {
    echo "invalid $id: capture date is out of range" >&2
    return 1
  }
  slug="${id:11}"
  slug_is_valid "$slug" || {
    echo "invalid $id: slug has an invalid shape" >&2
    return 1
  }
}

list_item_entries() {
  # Items are directories (items/<id>/); `-type d` ignores stray files such as a
  # `.gitkeep` used to track an empty store in git, or an incidental `.DS_Store`,
  # so they are never mistaken for invalid items.
  find "$ITEMS_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '*.landing' -print | sort -r
}

list_partials() {
  find "$ITEMS_DIR" -mindepth 1 -maxdepth 1 -name '*.landing' -print | sort
}

collect_item_entries() {
  local -n result="$1"
  local output
  result=()
  output="$(list_item_entries)" || return 1
  if [[ -n "$output" ]]; then
    mapfile -t result <<< "$output"
  fi
}

collect_partials() {
  local -n result="$1"
  local output
  result=()
  output="$(list_partials)" || return 1
  if [[ -n "$output" ]]; then
    mapfile -t result <<< "$output"
  fi
}

warn_if_index_stale() {
  if [[ ! -f "$INDEX_FILE" ]]; then
    echo "warning: INDEX.md is missing; run lore.sh index" >&2
    return
  fi

  local entries=()
  local indexed_count
  collect_item_entries entries || die "could not enumerate items/"
  indexed_count="$(grep -c '^- \[' "$INDEX_FILE" 2>/dev/null || true)"
  if (( indexed_count != ${#entries[@]} )); then
    echo "warning: INDEX.md is stale; run lore.sh index" >&2
    return
  fi

  local entry newer
  for entry in "${entries[@]}"; do
    if [[ "$entry" -nt "$INDEX_FILE" ]]; then
      echo "warning: INDEX.md is stale; run lore.sh index" >&2
      return
    fi
    newer="$(find "$entry" -mindepth 1 -newer "$INDEX_FILE" -print -quit 2>/dev/null || true)"
    if [[ -n "$newer" ]]; then
      echo "warning: INDEX.md is stale; run lore.sh index" >&2
      return
    fi
  done
}

cmd_init() {
  (( $# == 0 )) || die "init takes no arguments"
  resolve_paths
  mkdir -p "$ITEMS_DIR"
  if [[ ! -f "$INDEX_FILE" ]]; then
    cmd_index >/dev/null
  fi
  echo "initialized $LORE_DIR"
}

cmd_keep() {
  (( $# == 2 )) || die "keep requires <prepared-item-dir> <slug>"
  require_lore
  local src="$1"
  local slug="$2"
  validate_slug "$slug"
  [[ -d "$src" ]] || die "prepared item not found or not a directory: $src"
  validate_item "$src"

  local id dest landing
  id="$(date +%Y-%m-%d)-$slug"
  dest="$ITEMS_DIR/$id"
  landing="$dest.landing"
  [[ ! -e "$dest" && ! -L "$dest" ]] || die "item already exists: $id"
  [[ ! -e "$landing" && ! -L "$landing" ]] || die "partial landing already exists: $(basename "$landing")"

  mkdir "$landing"
  cp -R "$src"/. "$landing"/
  validate_item "$landing"
  mv "$landing" "$dest"
  echo "$dest"
}

cmd_index() {
  (( $# == 0 )) || die "index takes no arguments"
  require_lore
  local entries=()
  local entry
  collect_item_entries entries || die "could not enumerate items/"

  for entry in "${entries[@]}"; do
    validate_stored_item "$entry"
  done

  local landing="$INDEX_FILE.$$.landing"
  if ! {
    echo '<!-- auto-generated; run lore.sh index to refresh -->'
    echo
    local id title desc
    for entry in "${entries[@]}"; do
      id="$(basename "$entry")"
      title="$(extract_title "$entry/item.md")"
      desc="$(extract_description "$entry/item.md")"
      printf -- '- [%s](items/%s/) — %s — %s\n' "$id" "$id" "$title" "$desc"
    done
  } > "$landing"; then
    rm -f "$landing"
    return 1
  fi

  if ! mv "$landing" "$INDEX_FILE"; then
    rm -f "$landing"
    return 1
  fi
  echo "$INDEX_FILE"
}

matches_metadata() {
  local item="$1"
  shift
  local id haystack term
  id="$(basename "$item")"
  haystack="$id"$'\n'"$(cat "$item/item.md")"
  for term in "$@"; do
    if printf '%s' "$haystack" | grep -iqF -- "$term"; then
      return 0
    fi
  done
  return 1
}

matches_content() {
  local item="$1"
  shift
  local term
  for term in "$@"; do
    if grep -rIiqF -- "$term" "$item/content" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

cmd_fetch() {
  require_lore
  local mode="strict"
  if [[ "${1:-}" == "--all" ]]; then
    mode="all"
    shift
  fi
  (( $# > 0 )) || die "fetch requires <query...>"
  local terms=("$@")
  warn_if_index_stale

  local entries=()
  local entry
  collect_item_entries entries || die "could not enumerate items/"
  for entry in "${entries[@]}"; do
    if ! validate_stored_item "$entry" >/dev/null 2>&1; then
      echo "warning: ignoring invalid item $(basename "$entry")" >&2
      continue
    fi
    if matches_metadata "$entry" "${terms[@]}"; then
      printf '%s\n' "$entry"
    elif [[ "$mode" == all ]] && matches_content "$entry" "${terms[@]}"; then
      printf '%s\n' "$entry"
    fi
  done
}

cmd_status() {
  (( $# == 0 )) || die "status takes no arguments"
  require_lore
  local entries=() partials=() invalid=()
  local entry
  collect_item_entries entries || die "could not enumerate items/"
  collect_partials partials || die "could not enumerate partial items"

  for entry in "${entries[@]}"; do
    if ! validate_stored_item "$entry" >/dev/null 2>&1; then
      invalid+=("$entry")
    fi
  done

  local valid_count=$(( ${#entries[@]} - ${#invalid[@]} ))
  printf 'items: %s\n' "$valid_count"
  if (( ${#invalid[@]} == 0 )); then
    cmd_index >/dev/null
    echo 'index: refreshed'
  else
    echo 'index: not refreshed (invalid items)'
  fi

  printf 'invalid: %s\n' "${#invalid[@]}"
  for entry in "${invalid[@]}"; do
    printf '  - %s\n' "$(basename "$entry")"
  done

  printf 'partial: %s\n' "${#partials[@]}"
  for entry in "${partials[@]}"; do
    printf '  - %s\n' "$(basename "$entry")"
  done

  (( ${#invalid[@]} == 0 && ${#partials[@]} == 0 ))
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    init)
      shift
      cmd_init "$@"
      ;;
    keep)
      shift
      cmd_keep "$@"
      ;;
    index)
      shift
      cmd_index "$@"
      ;;
    fetch)
      shift
      cmd_fetch "$@"
      ;;
    status)
      shift
      cmd_status "$@"
      ;;
    -h|--help|help|'')
      usage
      ;;
    *)
      usage >&2
      die "unknown command '$cmd'"
      ;;
  esac
}

main "$@"

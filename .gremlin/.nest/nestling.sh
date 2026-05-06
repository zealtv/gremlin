#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage:
  nestling.sh ensure
  nestling.sh list
  nestling.sh ingest <src> [name]
  nestling.sh claim <name>
  nestling.sh complete <name> <result-src> [out-name]
  nestling.sh drop <name> [reason...]
  nestling.sh sweep [days]

notes:
  - this script operates on the .nest/ directory beside it
  - root entries in .nest/in/ are ready now
  - items can be files or directories
  - *.landing means being written
  - *.tending means claimed
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_nest() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [[ "$(basename "$script_dir")" == ".nest" ]] || die "nestling.sh must live inside a .nest/ directory"
  NEST_DIR="$script_dir"
  IN_DIR="$NEST_DIR/in"
  OUT_DIR="$NEST_DIR/out"
  DROPPED_DIR="$NEST_DIR/dropped"
}

ensure_dirs() {
  mkdir -p "$IN_DIR" "$OUT_DIR" "$DROPPED_DIR"
}

validate_name() {
  local name="$1"
  [[ -n "$name" ]] || die "name cannot be empty"
  [[ "$name" != */* ]] || die "name cannot contain /"
  [[ "$name" != "." && "$name" != ".." ]] || die "invalid name '$name'"
}

is_reserved_name() {
  local name="$1"
  [[ "$name" == *.landing || "$name" == *.tending ]]
}

ensure_stable_name() {
  local name="$1"
  validate_name "$name"
  if is_reserved_name "$name"; then
    die "name '$name' must not end with .landing or .tending"
  fi
}

stage_and_finalize() {
  local src="$1"
  local dest_dir="$2"
  local name="$3"
  local tmp="$dest_dir/$name.landing"
  local final="$dest_dir/$name"

  [[ -e "$src" ]] || die "source not found: $src"
  [[ ! -e "$tmp" ]] || die "temporary path already exists: $tmp"
  [[ ! -e "$final" ]] || die "destination already exists: $final"

  if [[ -d "$src" ]]; then
    cp -R -- "$src" "$tmp"
  else
    cp -- "$src" "$tmp"
  fi

  mv -- "$tmp" "$final"
  printf '%s\n' "$final"
}

claimed_path() {
  local name="$1"
  printf '%s/%s.tending\n' "$IN_DIR" "$name"
}

cmd_ensure() {
  require_nest
  ensure_dirs
}

cmd_list() {
  require_nest
  ensure_dirs

  local path base
  for path in "$IN_DIR"/*; do
    [[ -e "$path" ]] || continue
    base="$(basename "$path")"
    is_reserved_name "$base" && continue
    printf '%s\n' "$base"
  done
}

cmd_ingest() {
  require_nest
  ensure_dirs

  local src="${1:-}"
  local name="${2:-}"

  [[ -n "$src" ]] || die "ingest requires <src>"
  [[ -e "$src" ]] || die "source not found: $src"

  if [[ -z "$name" ]]; then
    name="$(basename "$src")"
  fi

  ensure_stable_name "$name"
  stage_and_finalize "$src" "$IN_DIR" "$name"
}

cmd_claim() {
  require_nest
  ensure_dirs

  local name="${1:-}"
  [[ -n "$name" ]] || die "claim requires <name>"
  ensure_stable_name "$name"

  local src="$IN_DIR/$name"
  local dst
  dst="$(claimed_path "$name")"

  [[ -e "$src" ]] || die "item not found: $src"
  [[ ! -e "$dst" ]] || die "claimed path already exists: $dst"

  mv -- "$src" "$dst"
  printf '%s\n' "$dst"
}

cmd_complete() {
  require_nest
  ensure_dirs

  local name="${1:-}"
  local result_src="${2:-}"
  local out_name="${3:-$name}"
  local claimed

  [[ -n "$name" ]] || die "complete requires <name>"
  [[ -n "$result_src" ]] || die "complete requires <result-src>"
  ensure_stable_name "$name"
  ensure_stable_name "$out_name"
  [[ -e "$result_src" ]] || die "result source not found: $result_src"

  claimed="$(claimed_path "$name")"
  [[ -e "$claimed" ]] || die "claimed item not found: $claimed"

  stage_and_finalize "$result_src" "$OUT_DIR" "$out_name" >/dev/null
  rm -rf -- "$claimed"
  printf '%s\n' "$OUT_DIR/$out_name"
}

cmd_drop() {
  require_nest
  ensure_dirs

  local name="${1:-}"
  shift || true
  ensure_stable_name "$name"

  local claimed dropped reason_file reason
  claimed="$(claimed_path "$name")"
  dropped="$DROPPED_DIR/$name"
  reason_file="$DROPPED_DIR/$name.reason.md"

  [[ -e "$claimed" ]] || die "claimed item not found: $claimed"
  [[ ! -e "$dropped" ]] || die "destination already exists: $dropped"
  [[ ! -e "$reason_file" ]] || die "reason file already exists: $reason_file"

  mv -- "$claimed" "$dropped"

  if (( $# > 0 )); then
    reason="$*"
  else
    reason="Add the reason here."
  fi

  {
    echo "# why $name was dropped"
    echo
    printf '%s\n' "$reason"
  } > "$reason_file"

  printf '%s\n' "$dropped"
}

sweep_dir() {
  local dir="$1" kind="$2" days="$3"
  [[ -d "$dir" ]] || return 0
  local entry name
  local find_args=(-mindepth 1 -maxdepth 1)
  if [[ "$days" != "0" ]]; then
    find_args+=(-mtime +"$days")
  fi
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    name="$(basename "$entry")"
    rm -rf -- "$entry"
    if [[ "$kind" == "dropped" && -e "$dir/$name.reason.md" ]]; then
      rm -f -- "$dir/$name.reason.md"
    fi
    printf 'swept %s %s\n' "$kind" "$name"
  done < <(find "$dir" "${find_args[@]}" ! -name '.gitkeep' ! -name '*.reason.md' | sort)
}

cmd_sweep() {
  require_nest
  ensure_dirs
  local days="${1:-14}"
  [[ "$days" =~ ^[0-9]+$ ]] || die "sweep <days> must be a non-negative integer"
  sweep_dir "$OUT_DIR" out "$days"
  sweep_dir "$DROPPED_DIR" dropped "$days"
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    ensure) shift; cmd_ensure "$@" ;;
    list) shift; cmd_list "$@" ;;
    ingest) shift; cmd_ingest "$@" ;;
    claim) shift; cmd_claim "$@" ;;
    complete) shift; cmd_complete "$@" ;;
    drop) shift; cmd_drop "$@" ;;
    sweep) shift; cmd_sweep "$@" ;;
    -h|--help|help|"") usage ;;
    *) die "unknown command '$cmd'" ;;
  esac
}

main "$@"

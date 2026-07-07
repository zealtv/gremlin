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
  nestling.sh stale [max-age-mins]
  nestling.sh resolve <name> [reason...]
  nestling.sh sweep [days]

notes:
  - this script operates on the .nest/ directory beside it
  - root entries in .nest/in/ are ready now
  - items can be files or directories
  - *.landing means being written
  - *.tending means claimed
  - stale only reports old claims; it never resolves them
  - resolve retries marked directories up to NEST_MAX_ATTEMPTS (default 3)
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

mtime_epoch() {
  stat -c %Y -- "$1" 2>/dev/null || stat -f %m -- "$1" 2>/dev/null
}

max_attempts() {
  local value="${NEST_MAX_ATTEMPTS:-3}"
  [[ "$value" =~ ^[0-9]+$ ]] || die "NEST_MAX_ATTEMPTS must be a non-negative integer"
  printf '%d\n' "$((10#$value))"
}

item_attempts() {
  local claimed="$1" value
  if [[ ! -f "$claimed/.attempts" ]]; then
    printf '0\n'
    return
  fi

  value="$(<"$claimed/.attempts")"
  [[ "$value" =~ ^[[:space:]]*([0-9]+)[[:space:]]*$ ]] || die ".attempts must contain a non-negative integer: $claimed/.attempts"
  printf '%d\n' "$((10#${BASH_REMATCH[1]}))"
}

move_no_replace() {
  local src="$1" dst="$2"

  # `-T` prevents a directory source from being nested inside a destination
  # created after the caller's collision check; `-n` prevents replacement.
  mv -nT -- "$src" "$dst"
}

drop_destination() {
  local name="$1" candidate timestamp suffix=2
  candidate="$name"
  if [[ ! -e "$DROPPED_DIR/$candidate" && ! -e "$DROPPED_DIR/$candidate.reason.md" ]]; then
    printf '%s\n' "$candidate"
    return
  fi

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  candidate="$name.$timestamp"
  while [[ -e "$DROPPED_DIR/$candidate" || -e "$DROPPED_DIR/$candidate.reason.md" ]]; do
    candidate="$name.$timestamp.$suffix"
    suffix=$((suffix + 1))
  done
  printf '%s\n' "$candidate"
}

drop_claimed() {
  local name="$1"
  shift
  local claimed dropped_name dropped reason_file reason
  claimed="$(claimed_path "$name")"
  [[ -e "$claimed" ]] || die "claimed item not found: $claimed"

  if (( $# > 0 )); then
    reason="$*"
  else
    reason="Add the reason here."
  fi

  while :; do
    dropped_name="$(drop_destination "$name")"
    dropped="$DROPPED_DIR/$dropped_name"
    reason_file="$DROPPED_DIR/$dropped_name.reason.md"
    move_no_replace "$claimed" "$dropped" 2>/dev/null && break
  done
  {
    echo "# why $name was dropped"
    echo
    printf '%s\n' "$reason"
  } > "$reason_file"
  printf '%s\n' "$dropped"
  if (( $# == 0 )); then
    printf 'next: read, then edit %s (agent harnesses refuse to overwrite unread files)\n' "$reason_file"
  fi
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

  drop_claimed "$name" "$@"
}

cmd_stale() {
  require_nest
  ensure_dirs

  local max_age_mins="${1:-10}"
  [[ "$max_age_mins" =~ ^[0-9]+$ ]] || die "stale <max-age-mins> must be a non-negative integer"
  (( $# <= 1 )) || die "stale accepts at most one argument"

  local now cutoff path base mtime age
  now="$(date +%s)"
  cutoff=$((max_age_mins * 60))
  for path in "$IN_DIR"/*.tending; do
    [[ -e "$path" ]] || continue
    mtime="$(mtime_epoch "$path")" || die "cannot read mtime: $path"
    age=$((now - mtime))
    (( age >= cutoff )) || continue
    base="$(basename "$path")"
    printf '%s\n' "${base%.tending}"
  done
}

cmd_resolve() {
  require_nest
  ensure_dirs

  local name="${1:-}"
  shift || true
  ensure_stable_name "$name"

  local claimed attempts limit reason next ready now why backup
  claimed="$(claimed_path "$name")"
  [[ -e "$claimed" ]] || die "claimed item not found: $claimed"
  limit="$(max_attempts)"
  reason="${*:-unspecified}"

  if [[ -d "$claimed" ]]; then
    attempts="$(item_attempts "$claimed")"
  else
    attempts=0
  fi

  if [[ -d "$claimed" && -f "$claimed/.recoverable" && "$attempts" -lt "$limit" ]]; then
    ready="$IN_DIR/$name"
    [[ ! -e "$ready" ]] || die "cannot retry, ready path exists: $ready"
    backup="$(mktemp -d "${TMPDIR:-/tmp}/nestlings-resolve.XXXXXX")"
    [[ ! -e "$claimed/.attempts" ]] || cp -p -- "$claimed/.attempts" "$backup/.attempts"
    [[ ! -e "$claimed/.recovery.md" ]] || cp -p -- "$claimed/.recovery.md" "$backup/.recovery.md"
    next=$((attempts + 1))
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s\n' "$next" > "$claimed/.attempts"
    {
      echo "# recovery"
      echo
      printf -- '- time: %s\n' "$now"
      printf -- '- attempt: %d/%d\n' "$next" "$limit"
      printf -- '- reason: %s\n' "$reason"
    } > "$claimed/.recovery.md"
    if ! move_no_replace "$claimed" "$ready"; then
      if [[ -e "$backup/.attempts" ]]; then
        cp -p -- "$backup/.attempts" "$claimed/.attempts"
      else
        rm -f -- "$claimed/.attempts"
      fi
      if [[ -e "$backup/.recovery.md" ]]; then
        cp -p -- "$backup/.recovery.md" "$claimed/.recovery.md"
      else
        rm -f -- "$claimed/.recovery.md"
      fi
      rm -rf -- "$backup"
      die "cannot retry, ready path appeared concurrently: $ready"
    fi
    rm -rf -- "$backup"
    printf 're-queued %s (attempt %d/%d)\n' "$name" "$next" "$limit"
    return
  fi

  if [[ -d "$claimed" && -f "$claimed/.recoverable" ]]; then
    why="$reason; recovery attempts exhausted ($attempts/$limit)"
  else
    why="$reason; item is not recoverable"
  fi
  drop_claimed "$name" "$why" >/dev/null
  printf 'dropped %s\n' "$name"
}

sweep_dir() {
  local dir="$1" kind="$2" days="$3"
  [[ -d "$dir" ]] || return 0
  local entry name
  local find_args=(-mindepth 1 -maxdepth 1)
  # `sweep 0` matches everything regardless of mtime. find treats `-mtime +0`
  # as "modified more than 0 days ago" → always false on freshly touched
  # items, so the flag has to be elided to mean "right now".
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
    stale) shift; cmd_stale "$@" ;;
    resolve) shift; cmd_resolve "$@" ;;
    sweep) shift; cmd_sweep "$@" ;;
    -h|--help|help|"") usage ;;
    *) die "unknown command '$cmd'" ;;
  esac
}

main "$@"

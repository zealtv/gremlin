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
  nestling.sh resolve <name> [reason...]
  nestling.sh recover [max-age-mins]
  nestling.sh sweep [days]

notes:
  - this script operates on the .nest/ directory beside it
  - root entries in .nest/in/ are ready now
  - items can be files or directories
  - *.landing means being written
  - *.tending means claimed
  - resolve applies the recovery policy to one claimed item: a recoverable
    item under its attempt limit is re-queued with a note, otherwise it is
    dropped with a reason. recover sweeps stale *.tending claims the same way.
  - recoverability: a claimed directory is recoverable if it holds a
    .recoverable file or its name matches a glob in NEST_RECOVERABLE_GLOBS
    (default: memory-review-*). attempt limit is NEST_MAX_ATTEMPTS (default 3).
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

# --- recovery policy -------------------------------------------------------
# A claimed item that never completes (tender died/hung) or whose model exited
# non-zero must not sit as silent *.tending residue. resolve_claim either
# re-queues a recoverable item (with a note, bounded by an attempt count) or
# drops it with a reason. recover sweeps stale claims through the same gate.

# Globs whose matching item names are treated as safe to re-run. Until item
# producers stamp a .recoverable marker (commands/new.sh does for memory
# reviews), this name heuristic is the fallback.
NEST_RECOVERABLE_GLOBS="${NEST_RECOVERABLE_GLOBS:-memory-review-*}"
# How many times an item may be re-queued before it is dropped instead, so a
# persistently failing item cannot retry forever.
NEST_MAX_ATTEMPTS="${NEST_MAX_ATTEMPTS:-3}"

gremlin_dir() { printf '%s\n' "$(cd "$NEST_DIR/.." && pwd)"; }

# Portable file mtime in epoch seconds (GNU stat, then BSD stat).
mtime_epoch() {
  stat -c %Y -- "$1" 2>/dev/null || stat -f %m -- "$1" 2>/dev/null
}

# True while a tender process is live, so recovery never races an in-flight
# model turn. The tender writes its pid to .tending.pid for the duration of
# the call and removes it on exit; a stale file (hard kill) fails kill -0.
tender_alive() {
  local pidfile pid
  pidfile="$(gremlin_dir)/.tending.pid"
  [[ -f "$pidfile" ]] || return 1
  pid="$(tr -d '[:space:]' < "$pidfile")"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

# A claimed directory is recoverable if it carries a .recoverable marker or its
# stable name matches a recoverable glob. File items are never recoverable —
# they have nowhere to carry the attempt count or note.
is_recoverable() {
  local claimed="$1" name="$2" glob
  [[ -d "$claimed" ]] || return 1
  [[ -f "$claimed/.recoverable" ]] && return 0
  for glob in $NEST_RECOVERABLE_GLOBS; do
    # shellcheck disable=SC2254 -- $glob is intentionally a pattern
    case "$name" in $glob) return 0 ;; esac
  done
  return 1
}

item_attempts() {
  local claimed="$1"
  if [[ -d "$claimed" && -f "$claimed/.attempts" ]]; then
    tr -cd '0-9' < "$claimed/.attempts"
  else
    printf '0'
  fi
}

# Move a claimed item to dropped/ with a reason. Tolerant of name collisions
# (a same-named item dropped earlier) so recovery never wedges on a clash.
drop_claimed() {
  local name="$1"; shift
  local claimed dropped reason_file reason ts
  claimed="$(claimed_path "$name")"
  [[ -e "$claimed" ]] || die "claimed item not found: $claimed"

  dropped="$DROPPED_DIR/$name"
  reason_file="$DROPPED_DIR/$name.reason.md"
  if [[ -e "$dropped" || -e "$reason_file" ]]; then
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    dropped="$DROPPED_DIR/$name.$ts"
    reason_file="$DROPPED_DIR/$name.$ts.reason.md"
  fi

  mv -- "$claimed" "$dropped"
  if (( $# > 0 )); then reason="$*"; else reason="Add the reason here."; fi
  {
    echo "# why $name was dropped"
    echo
    printf '%s\n' "$reason"
  } > "$reason_file"
  printf '%s\n' "$dropped"
}

# Re-queue a recoverable claim: rename it back to a ready name, bump the
# attempt count, and (for a directory with instructions.md) prepend a note so
# the model knows it is processing a recovered, late, possibly out-of-order
# item. Returns the ready path.
requeue_claim() {
  local name="$1" reason="$2" attempts="$3"
  local claimed dst next iso note tmp
  claimed="$(claimed_path "$name")"
  dst="$IN_DIR/$name"
  [[ ! -e "$dst" ]] || die "cannot re-queue, ready path exists: $dst"
  next=$((attempts + 1))
  iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  if [[ -d "$claimed" && -f "$claimed/instructions.md" ]]; then
    note="$(cat <<EOF
> **⚠️ Recovered item — re-queued $iso (attempt $next/$NEST_MAX_ATTEMPTS).** Reason: $reason.
> This item was left as a stale \`.tending\` claim and is being processed late and
> possibly out of order. Treat its context as older than it appears, and note in
> your outcome that this was a recovered/retried item.

EOF
)"
    tmp="$(mktemp)"
    { printf '%s\n' "$note"; cat "$claimed/instructions.md"; } > "$tmp"
    mv -- "$tmp" "$claimed/instructions.md"
  fi

  [[ -d "$claimed" ]] && printf '%s\n' "$next" > "$claimed/.attempts"
  mv -- "$claimed" "$dst"
  printf '%s\n' "$dst"
}

# The policy gate. Re-queue a recoverable item still under its attempt limit;
# otherwise drop it with a reason. Used by both `resolve` (the tender's
# failure path) and `recover` (the stale-claim sweep).
resolve_claim() {
  local name="$1" reason="$2"
  local claimed attempts
  claimed="$(claimed_path "$name")"
  [[ -e "$claimed" ]] || die "claimed item not found: $claimed"
  attempts="$(item_attempts "$claimed")"

  if is_recoverable "$claimed" "$name" && (( attempts < NEST_MAX_ATTEMPTS )); then
    requeue_claim "$name" "$reason" "$attempts" >/dev/null
    printf 're-queued %s (attempt %d/%d)\n' "$name" "$((attempts + 1))" "$NEST_MAX_ATTEMPTS"
  else
    local why
    if is_recoverable "$claimed" "$name"; then
      why="$reason; recovery attempts exhausted ($attempts/$NEST_MAX_ATTEMPTS)"
    else
      why="$reason; item is not recoverable"
    fi
    drop_claimed "$name" "$why" >/dev/null
    printf 'dropped %s\n' "$name"
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

cmd_resolve() {
  require_nest
  ensure_dirs

  local name="${1:-}"
  shift || true
  ensure_stable_name "$name"
  local reason="${*:-unspecified}"

  resolve_claim "$name" "$reason"
}

cmd_recover() {
  require_nest
  ensure_dirs

  local max_age_mins="${1:-10}"
  [[ "$max_age_mins" =~ ^[0-9]+$ ]] || die "recover <max-age-mins> must be a non-negative integer"

  # Never recover while a tender is live — it owns the current claim and the
  # next pass will sweep once it has exited.
  if tender_alive; then
    return 0
  fi

  local now cutoff path base name mtime age
  now="$(date +%s)"
  cutoff=$((max_age_mins * 60))

  for path in "$IN_DIR"/*.tending; do
    [[ -e "$path" ]] || continue
    base="$(basename "$path")"
    name="${base%.tending}"
    mtime="$(mtime_epoch "$path")"; mtime="${mtime:-$now}"
    age=$(( now - mtime ))
    (( age >= cutoff )) || continue
    resolve_claim "$name" "orphaned stale claim (tender exited without completing it)"
  done
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
    resolve) shift; cmd_resolve "$@" ;;
    recover) shift; cmd_recover "$@" ;;
    sweep) shift; cmd_sweep "$@" ;;
    -h|--help|help|"") usage ;;
    *) die "unknown command '$cmd'" ;;
  esac
}

main "$@"

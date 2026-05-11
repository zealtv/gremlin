#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
usage:
  glean.sh init
  glean.sh ingest <src> [name]
  glean.sh ingest - <name>
  glean.sh complete <id>
  glean.sh drop <id> [reason...]
  glean.sh index
  glean.sh fetch [--all] <q...>
  glean.sh status
  glean.sh sweep [days]
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

resolve_paths() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [[ "$(basename "$script_dir")" == ".glean" ]] || die "glean.sh must live inside a .glean/ directory"
  GLEAN_DIR="$script_dir"
}

require_glean() {
  resolve_paths
}

validate_id() {
  local id="$1"
  [[ "$id" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid id '$id' (use letters, numbers, ., _, -)"
  [[ "$id" != *"/"* ]] || die "id cannot contain /"
}

# Find a single in/ item matching <id>. Skips .landing partials.
find_in_item() {
  local id="$1"
  local matches=() path
  for path in "$GLEAN_DIR/in/$id" "$GLEAN_DIR/in/$id.md"; do
    [[ -e "$path" ]] && matches+=("$path")
  done
  if (( ${#matches[@]} == 0 )); then return 1; fi
  if (( ${#matches[@]} > 1 )); then
    printf '%s\n' "${matches[@]}" >&2
    die "multiple in/ items match id '$id'"
  fi
  printf '%s\n' "${matches[0]}"
}

cmd_init() {
  resolve_paths
  mkdir -p "$GLEAN_DIR/in" "$GLEAN_DIR/findings" "$GLEAN_DIR/out" "$GLEAN_DIR/dropped"
  if [[ ! -f "$GLEAN_DIR/distil.md" ]]; then
    cat > "$GLEAN_DIR/distil.md" <<'DISTIL'
# Distil

This is the local brief for distillation in this glean.

Distil is the act of shaping the carry-forward corpus — both digesting new
material from `in/` and curating `findings/` over time. The two rhythms
share one posture; they differ in what triggers them and which verbs they
use. Edit this file freely; the protocol doesn't care what you write here.

## Posture

Glean stays small, legible, and revisable. Keep it that way.

- Do not force synthesis.
- Do not mistake compression for understanding.
- Do not create a new finding when revising an existing one is enough.
- Do not let `findings/` grow into a heap.
- Do not carry forward material that does not improve judgment.

A heap of findings is just another inbox. The value of memory comes from the
discipline of distillation, not the volume of capture.

## Per-item distillation

When an item arrives in `in/`, read it and choose one of three outcomes:

1. **Revise** an existing finding — edit `findings/<id>.md`.
2. **Create** a new finding — write `findings/<new-id>.md` directly.
3. **Nothing earned** — the material doesn't merit carry-forward.

In all three cases, close the inbox item:

```
glean.sh complete <in-id>      # in/<id> → out/<id>
```

`out/` is the audit residue: every inbox item that was considered passes
through it, regardless of whether a finding was produced. No reason needed.
`out/` is swept on retention.

The inbox item leaves `in/` only via `complete`. Items remaining in `in/`
are still awaiting distillation.

## Curation, in the same pass

Curation is not a separate rhythm — it rides on per-item distillation. The
moments below all happen *while* working an inbox item, so act on what you
notice in the same pass:

- **Before creating** a new finding, search `findings/` for similar ones.
  If one already covers the ground, revise it instead.
- **While revising**, if the finding has drifted to cover two ideas, split
  it. If it now overlaps with another, merge them and `drop` the loser.
- **When writing or revising**, link related findings under
  `## Associations`.

These moves are file edits plus `glean.sh drop`. Don't defer them — the
in/ item is the trigger, and you only have this brief in context now.

## Corpus review

A deliberate "look across `findings/` as a whole" pass only happens when a
human asks for it — the agent has no rhythm of its own to schedule one. On
review, read across `findings/` and apply the same merge / split / link /
retire moves at scale.

`drop` retires a *finding* into `dropped/` with a reason file. `dropped/` is
the reflection drawer for retired ideas — durable and not swept. Read it by
hand when you want to remember what was let go and why.

## What a finding looks like

A finding is one markdown file at `findings/<id>.md`:

- **Title** — first line, an H1 (`# Some claim`). Required.
- **Description** — first non-empty line after the title. One sentence.
  Surfaces in `INDEX.md`; an agent reads it to decide relevance.
- **Body** — free markdown. Common sections (all optional):
  - `## Why` — motivation, source, the experience that earned this finding.
  - `## Triggers` — phrases, topics, or symptoms that should bring this
    finding to mind. `fetch` searches this by default.
  - `## Associations` — wikilinks to related findings: `- [[other-id]]`.
  - `## Context` — examples, references, longer notes.

Run `glean.sh index` after writing or revising a finding to refresh
`findings/INDEX.md`.

## Local notes

(Anything host-specific goes here.)
DISTIL
  fi
  echo "initialized $GLEAN_DIR"
}

cmd_ingest() {
  require_glean
  local src="${1:-}"
  [[ -n "$src" ]] || die "ingest requires <src> [name]"
  shift
  local name="${1:-}"

  if [[ "$src" == "-" ]]; then
    [[ -n "$name" ]] || die "ingest from stdin requires a name"
    validate_id "$name"
    local dest="$GLEAN_DIR/in/$name.md"
    local landing="$dest.landing"
    [[ ! -e "$dest" ]] || die "in/$name.md already exists"
    [[ ! -e "$landing" ]] || die "in/$name.md.landing already exists (clean up?)"
    cat > "$landing"
    mv "$landing" "$dest"
    echo "$dest"
    return 0
  fi

  [[ -e "$src" ]] || die "source not found: $src"
  if [[ -z "$name" ]]; then
    name="$(basename "$src")"
  fi
  validate_id "$name"
  local dest="$GLEAN_DIR/in/$name"
  local landing="$dest.landing"
  [[ ! -e "$dest" ]] || die "in/$name already exists"
  [[ ! -e "$landing" ]] || die "in/$name.landing already exists (clean up?)"

  if [[ -d "$src" ]]; then
    cp -R "$src" "$landing"
  else
    cp "$src" "$landing"
  fi
  mv "$landing" "$dest"
  echo "$dest"
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

extract_triggers() {
  awk '
    /^## Triggers[[:space:]]*$/ { in_section=1; next }
    in_section && /^## / { exit }
    in_section { print }
  ' "$1"
}

cmd_index() {
  require_glean
  local dir="$GLEAN_DIR/findings"
  local idx="$dir/INDEX.md"
  mkdir -p "$dir"

  local files=()
  mapfile -t files < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -name '*.md' ! -name 'INDEX.md' 2>/dev/null | sort)

  {
    echo "<!-- auto-generated; run glean.sh index to refresh -->"
    echo
    local f id title desc
    for f in "${files[@]}"; do
      id="$(basename "$f" .md)"
      title="$(extract_title "$f")"
      desc="$(extract_description "$f")"
      [[ -n "$title" ]] || title="$id"
      [[ -n "$desc" ]] || desc="(no description)"
      echo "- [[$id]] — $title — $desc"
    done
  } > "$idx"

  echo "$idx"
}

cmd_fetch() {
  require_glean
  local mode="strict"
  if [[ "${1:-}" == "--all" || "${1:-}" == "-a" ]]; then
    mode="all"
    shift
  fi
  (( $# > 0 )) || die "fetch requires <q...>"
  local terms=("$@")

  local dir="$GLEAN_DIR/findings"
  local files=()
  mapfile -t files < <(find "$dir" -mindepth 1 -maxdepth 1 -type f -name '*.md' ! -name 'INDEX.md' 2>/dev/null | sort)

  local f haystack term
  for f in "${files[@]}"; do
    if [[ "$mode" == "all" ]]; then
      haystack="$(cat "$f")"
    else
      local id title desc triggers
      id="$(basename "$f" .md)"
      title="$(extract_title "$f")"
      desc="$(extract_description "$f")"
      triggers="$(extract_triggers "$f")"
      haystack="$id"$'\n'"$title"$'\n'"$desc"$'\n'"$triggers"
    fi

    for term in "${terms[@]}"; do
      if printf '%s' "$haystack" | grep -iqF -- "$term"; then
        printf '%s\n' "$f"
        break
      fi
    done
  done
}

cmd_complete() {
  require_glean
  local id="${1:-}"
  [[ -n "$id" ]] || die "complete requires <id>"
  validate_id "$id"

  local src
  src="$(find_in_item "$id" || true)"
  [[ -n "$src" ]] || die "no in/ item matches '$id'"

  mkdir -p "$GLEAN_DIR/out"
  local dest="$GLEAN_DIR/out/$(basename "$src")"
  [[ ! -e "$dest" ]] || die "out/$(basename "$src") already exists"
  mv "$src" "$dest"
  echo "$dest"
}

cmd_drop() {
  require_glean
  local id="${1:-}"
  shift || true
  [[ -n "$id" ]] || die "drop requires <id>"
  validate_id "$id"

  if [[ -e "$GLEAN_DIR/dropped/$id.md" ]]; then
    echo "already dropped: $id"
    return 0
  fi

  local src="$GLEAN_DIR/findings/$id.md"
  [[ -e "$src" ]] || die "no finding 'findings/$id.md'"

  mkdir -p "$GLEAN_DIR/dropped"
  local dest="$GLEAN_DIR/dropped/$id.md"
  [[ ! -e "$dest" ]] || die "drop destination already exists: $dest"
  mv "$src" "$dest"

  local reason="$GLEAN_DIR/dropped/$id.reason.md"
  {
    echo "# why $id was dropped"
    echo
    if (( $# > 0 )); then
      printf '%s\n' "$*"
    else
      echo "Add the reason here."
    fi
  } > "$reason"

  echo "$dest"
}

print_dir_entries() {
  local dir="$1"
  if [[ -d "$dir" ]] && [[ -n "$(ls -A "$dir" 2>/dev/null | grep -v '^\.gitkeep$' || true)" ]]; then
    find "$dir" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) ! -name '.gitkeep' 2>/dev/null \
      | awk -F/ '{print $NF}' | sort | sed 's/^/- /'
  else
    echo "(empty)"
  fi
}

print_findings() {
  local dir="$1"
  local entries=""
  if [[ -d "$dir" ]]; then
    entries="$(find "$dir" -mindepth 1 -maxdepth 1 -type f -name '*.md' ! -name 'INDEX.md' 2>/dev/null \
      | awk -F/ '{print $NF}' | sed 's/\.md$//' | sort)"
  fi
  if [[ -n "$entries" ]]; then
    echo "$entries" | sed 's/^/- /'
  else
    echo "(empty)"
  fi
}

print_dropped() {
  local dir="$1"
  local entries=""
  if [[ -d "$dir" ]]; then
    entries="$(find "$dir" -mindepth 1 -maxdepth 1 \( -type f -o -type d \) ! -name '*.reason.md' ! -name '.gitkeep' 2>/dev/null \
      | awk -F/ '{print $NF}' | sort)"
  fi
  if [[ -n "$entries" ]]; then
    echo "$entries" | sed 's/^/- /'
  else
    echo "(empty)"
  fi
}

cmd_status() {
  require_glean
  echo "in"
  print_dir_entries "$GLEAN_DIR/in"
  echo
  echo "findings"
  print_findings "$GLEAN_DIR/findings"
  echo
  echo "out"
  print_dir_entries "$GLEAN_DIR/out"
  echo
  echo "dropped"
  print_dropped "$GLEAN_DIR/dropped"
}

cmd_sweep() {
  require_glean
  local days="${1:-14}"
  local dir="$GLEAN_DIR/out"
  [[ -d "$dir" ]] || return 0

  local items=()
  if (( days == 0 )); then
    mapfile -t items < <(find "$dir" -mindepth 1 -maxdepth 1 ! -name '.gitkeep' 2>/dev/null | sort)
  else
    mapfile -t items < <(find "$dir" -mindepth 1 -maxdepth 1 ! -name '.gitkeep' -mtime "+$days" 2>/dev/null | sort)
  fi

  local item
  for item in "${items[@]}"; do
    rm -rf "$item"
    echo "swept $(basename "$item")"
  done
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    init) shift; cmd_init "$@" ;;
    ingest) shift; cmd_ingest "$@" ;;
    complete) shift; cmd_complete "$@" ;;
    drop) shift; cmd_drop "$@" ;;
    index) shift; cmd_index "$@" ;;
    fetch) shift; cmd_fetch "$@" ;;
    status) shift; cmd_status "$@" ;;
    sweep) shift; cmd_sweep "$@" ;;
    -h|--help|help|"") usage ;;
    *) die "unknown command '$cmd'" ;;
  esac
}

main "$@"

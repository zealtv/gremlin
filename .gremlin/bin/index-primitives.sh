#!/usr/bin/env bash
# index-primitives.sh — generate the map of the primitives installed at a host
# root, from what is actually on disk (the index-skills.sh pattern: generated,
# so it cannot rot).
#
# It writes two things:
#   <host>/AGENTS.md         a generated block between markers, leaving any
#                            hand-written preamble alone — the map a cold agent
#                            of any runtime reads to orient
#   <host>/.gremlin/PRIMITIVES.md   the same list as gremlin context (skipped
#                            when the host has no gremlin)
#
# A primitive is a self-named dotdir at the HOST ROOT — a sibling of .gremlin,
# not something inside it — that bundles its own script (*.sh) and a README.md.
# .gremlin lists itself: under the placement law it is a primitive among peers,
# and a map that omitted the mapmaker would be lying by omission. Its entry is
# written by hand here because its executable is `gremlin`, not `*.sh`.
#
# Name and emoji come from the README's title line; the one-line purpose is
# the first prose line after it. The reading order and ownership sentences are
# keyed by primitive name — an unknown dotdir is still listed, just without
# them.
#
# usage: index-primitives.sh [host-dir]
#   Defaults to the host of the gremlin this script is installed in. Given a
#   directory, it maps that repository instead — a repo with no gremlin at all
#   can be mapped from a gremlin checkout.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$#" -gt 0 ]; then
  HOST_DIR="$(cd "$1" 2>/dev/null && pwd)" || { echo "no such directory: $1" >&2; exit 1; }
else
  HOST_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi
GREMLIN_DIR="$HOST_DIR/.gremlin"

BEGIN_MARK="<!-- BEGIN GENERATED PRIMITIVES — .gremlin/bin/index-primitives.sh -->"
END_MARK="<!-- END GENERATED PRIMITIVES -->"

# Reading order for the "Start here" list, and what each dotdir owns. Only
# installed primitives appear. Order is deliberate: current guidance first,
# then open work, then arrivals, then the record.
read_order=(glean loom nest groundhog lore gremlin)

start_here() {
  case "$1" in
    glean)     echo 'Read `.glean/findings/INDEX.md` for compact current guidance; fetch a body only when it is relevant (`./.glean/glean.sh fetch <terms>`).' ;;
    loom)      echo 'Run `./.loom/loom.sh status`. The loom is the sole owner of finite open work, blockers and queue order.' ;;
    nest)      echo 'Read `.nest/tend.md` and inspect `.nest/in/` for arrivals waiting to be actioned.' ;;
    groundhog) echo 'Check `.groundhog/schedule/` for the recurring work this repository expects to happen on its own.' ;;
    lore)      echo 'Consult `.lore/INDEX.md` only when complete evidence or history is needed. Lore is dark by default.' ;;
    gremlin)   echo 'A gremlin tends this folder. `.gremlin/gremlin.md` is who it is; `.gremlin/transcript.md` is what it has been told and has said.' ;;
  esac
}

owns() {
  case "$1" in
    glean)     echo 'small, current, revisable guidance' ;;
    loom)      echo 'finite work: threads, stitches, dependencies, queue order' ;;
    nest)      echo 'arrivals — inbox, claimed, completed' ;;
    groundhog) echo 'recurring work and its firing history' ;;
    lore)      echo 'complete dated records, kept whole' ;;
    gremlin)   echo 'the tender itself: identity, context, skills, tools, transcript' ;;
  esac
}

# ---- discover -------------------------------------------------------------
installed=()
lines=()
for d in "$HOST_DIR"/.*/; do
  d="${d%/}"
  base="$(basename "$d")"
  case "$base" in .|..) continue ;; esac
  [ -f "$d/README.md" ] || continue
  name="${base#.}"
  if [ "$base" = ".gremlin" ]; then
    installed+=("gremlin")
    lines+=("- 👀 gremlin — \`.gremlin/\` — The optional tender of this folder: reads the nest, works the loom, keeps the record.")
    continue
  fi
  set -- "$d"/*.sh
  [ -e "$1" ] || continue
  title="$(head -n 1 "$d/README.md")"
  title="${title#\# }"
  purpose="$(awk 'NR>1 && NF { sub(/^[[:space:]]+/, ""); print; exit }' "$d/README.md")"
  installed+=("$name")
  lines+=("- $title — \`$base/\` — $purpose")
done

has() { local n="$1" i; for i in "${installed[@]:-}"; do [ "$i" = "$n" ] && return 0; done; return 1; }

# ---- the generated block --------------------------------------------------
block() {
  echo "$BEGIN_MARK"
  echo
  echo "## The primitives"
  echo
  echo "This repository's shape is held by the dotdirs at its root. Each is a"
  echo "self-contained file-based protocol bundling its own script and its own"
  echo "data; read its README before working with one. This section is"
  echo "**generated** from what is on disk — edit the primitives, not these lines."
  echo
  printf '%s\n' "${lines[@]:-  (none installed)}"
  echo
  echo "### Start here"
  echo
  local n=0 p line
  for p in "${read_order[@]}"; do
    has "$p" || continue
    line="$(start_here "$p")"
    [ -n "$line" ] || continue
    n=$((n + 1))
    echo "$n. $line"
  done
  [ "$n" = 0 ] && echo "_No primitives are installed at this root yet._"
  echo
  echo "### Ownership boundaries"
  echo
  for p in "${read_order[@]}"; do
    has "$p" || continue
    line="$(owns "$p")"
    [ -n "$line" ] || continue
    echo "- \`.$p/\` — $line"
  done
  echo
  echo "One arrival may earn several routes — evidence in lore, a current"
  echo "constraint in glean, an action on the loom. Those are different"
  echo "consequences of one thing, not competing copies of it."
  if has nest || has glean; then
    echo
    echo "**This section is the only part of this repository a gremlin maintains.**"
    echo "It is generated *facts*: what is installed, and where to start reading."
    echo "The policy is yours to write —"
    has nest  && echo "\`.nest/tend.md\` says how arrivals here should be routed;"
    has glean && echo "\`.glean/distil.md\` says what this repository considers worth remembering."
    echo "A gremlin reads those; it does not write them."
  fi

  echo "$END_MARK"
}

# ---- write AGENTS.md, preserving the hand-written preamble -----------------
AGENTS="$HOST_DIR/AGENTS.md"
tmp="$AGENTS.tmp"
if [ -f "$AGENTS" ] && grep -qF "$BEGIN_MARK" "$AGENTS"; then
  # Replace the existing block in place; everything outside it is untouched.
  awk -v begin="$BEGIN_MARK" -v end="$END_MARK" -v blockfile="/dev/stdin" '
    $0 == begin { skipping = 1; while ((getline line < blockfile) > 0) print line; next }
    $0 == end   { skipping = 0; next }
    !skipping   { print }
  ' "$AGENTS" < <(block) > "$tmp"
else
  {
    if [ -f "$AGENTS" ]; then
      cat "$AGENTS"
      echo
    else
      echo "# Working notes for agents"
      echo
      echo "Hand-written notes belong above and below the generated block:"
      echo "working agreements, project shape, anything a person wants said."
      echo "The block itself is rewritten from disk and edits to it are lost."
      echo
    fi
    block
  } > "$tmp"
fi
mv "$tmp" "$AGENTS"
echo "wrote $AGENTS"

# CLAUDE.md is the same map under the name Claude Code looks for. A symlink,
# never a copy — two files would drift. An existing real CLAUDE.md is left
# alone: it is someone's hand-written notes, and clobbering it would be the
# opposite of "leave the preamble intact".
CLAUDE="$HOST_DIR/CLAUDE.md"
if [ -L "$CLAUDE" ]; then
  :
elif [ -e "$CLAUDE" ]; then
  echo "note CLAUDE.md is a real file — the generated map is in AGENTS.md only"
else
  ln -s "AGENTS.md" "$CLAUDE"
  echo "linked $CLAUDE -> AGENTS.md"
fi

# ---- PRIMITIVES.md, the gremlin's own context copy ------------------------
if [ -d "$GREMLIN_DIR" ]; then
  OUT="$GREMLIN_DIR/PRIMITIVES.md"
  TMP="$OUT.tmp"
  {
    echo "# primitives"
    echo
    echo "Installed primitives — self-contained dotdir protocols at the root of this repository, siblings of \`.gremlin/\`. Each bundles its script and its data; read its README before working with one."
    echo
    printf '%s\n' "${lines[@]:-}"
  } > "$TMP"
  mv "$TMP" "$OUT"
  echo "wrote $OUT"
fi

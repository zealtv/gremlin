#!/usr/bin/env bash
# doctor.sh — repair gremlin-managed context links.
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_DIR="$(cd "$GREMLIN_DIR/.." && pwd)"
SYSTEM_DIR="$GREMLIN_DIR/context/system"

mkdir -p "$SYSTEM_DIR"

readme="$SYSTEM_DIR/README.md"
if [ ! -e "$readme" ]; then
  cat > "$readme" <<'EOF_README'
# context/system

This directory is managed by `gremlin doctor`.
It holds symlinks for gremlin-managed material that should be broadcast through `context/`.

Remove a specific entry to opt out of that broadcast. Running `gremlin doctor` restores missing managed entries. The `/update` command also runs `gremlin doctor`, so updates currently restore deleted managed entries too; there is no durable opt-out in this stage.

Entries are symlinks by convention. The tender reads only symlinked `.md` files from this directory, which is why this `README.md` is not loaded into the prompt. Real `.md` files dropped here are ignored by the tender, left alone by doctor, and reported as `skipped (real file)`.
EOF_README
  echo "created context/system/README.md"
else
  echo "ok context/system/README.md"
fi

repair_link() {
  local rel="$1"
  local target="$2"
  local path="$SYSTEM_DIR/$rel"
  local current

  if [ -L "$path" ]; then
    current="$(readlink "$path")"
    if [ "$current" = "$target" ]; then
      echo "ok context/system/$rel"
    else
      ln -sfn "$target" "$path"
      echo "relinked context/system/$rel"
    fi
  elif [ -e "$path" ]; then
    echo "skipped (real file) context/system/$rel"
  else
    ln -s "$target" "$path"
    echo "created context/system/$rel"
  fi
}

for f in "$SYSTEM_DIR"/*.md; do
  [ -e "$f" ] || continue
  [ -L "$f" ] && continue
  [ "$(basename "$f")" = "README.md" ] && continue
  echo "skipped (real file) context/system/$(basename "$f")"
done

# Regenerate the primitives map from disk before linking it: generated, so
# it cannot rot the way hand-written prose does. This also refreshes the
# generated block in the host's AGENTS.md — the map a cold agent of any
# runtime reads to orient. Hand-written prose around the block is untouched.
if [ -x "$GREMLIN_DIR/bin/index-primitives.sh" ]; then
  "$GREMLIN_DIR/bin/index-primitives.sh" >/dev/null
  echo "ok PRIMITIVES.md + AGENTS.md (regenerated)"
else
  echo "‼️  bin/index-primitives.sh MISSING — run /update to restore it"
fi

repair_link "skills.md" "../../skills/INDEX.md"
repair_link "tools.md" "../../tools/README.md"
repair_link "memory.md" "../../../.glean/findings/INDEX.md"
repair_link "turntaking.md" "../../docs/turntaking.md"
repair_link "media-embeds.md" "../../docs/media-embeds.md"
repair_link "primitives.md" "../../PRIMITIVES.md"

# The host's loom: ensure its trays exist. The loom belongs to the repository,
# not to the gremlin, but a missing tray breaks a tie weeks later and nothing
# notices — so doctor seeds them. loom.sh init is idempotent and never touches
# existing threads.
LOOM_DIR="$HOST_DIR/.loom"
if [ -x "$LOOM_DIR/loom.sh" ]; then
  if [ -d "$LOOM_DIR/threads" ] && [ -d "$LOOM_DIR/tied" ] && [ -d "$LOOM_DIR/dropped" ]; then
    echo "ok .loom trays"
  else
    "$LOOM_DIR/loom.sh" init >/dev/null
    echo "initialized .loom trays"
  fi
fi

# Placement (docs/protocol.md "Placement"): the five primitives are SIBLINGS of
# .gremlin at the host root. The gremlin acts on them; it is not composed of
# them. Two things are worth saying out loud:
#   - a missing sibling fails loud, naming its install one-liner. There is no
#     fallback to a vendored copy: a gremlin with no nest cannot be tended, and
#     quietly inventing one hides the real problem.
#   - a primitive dotdir still INSIDE .gremlin/ is legacy placement from before
#     the primitives moved out. Name the migration rather than guessing.
INSTALL_BASE="https://raw.githubusercontent.com/zealtv"
check_primitive() {
  local prim="$1" script="$2" repo="$3"
  local sib="$HOST_DIR/.$prim"
  if [ -d "$sib" ] && [ -e "$sib/$script" ]; then
    echo "ok .$prim"
  elif [ -d "$sib" ]; then
    echo "‼️  .$prim exists at the host root but has no $script — incomplete install"
  else
    echo "‼️  .$prim MISSING at the host root — install it beside .gremlin/:"
    echo "     curl -fsSL $INSTALL_BASE/$repo/main/install.sh | bash -s"
  fi
  # Legacy placement: the same primitive still vendored inside .gremlin/.
  # A symlink there is the transition shim, not drift.
  if [ -d "$GREMLIN_DIR/.$prim" ] && [ ! -L "$GREMLIN_DIR/.$prim" ]; then
    echo "‼️  .gremlin/.$prim is LEGACY placement — primitives live at the host root."
    echo "     migrate with: <gremlin-repo>/hoist-primitives.sh $HOST_DIR"
  fi
}
check_primitive "nest" "nestling.sh" "nestlings"
check_primitive "loom" "loom.sh" "loom"
check_primitive "lore" "lore.sh" "lore"
check_primitive "glean" "glean.sh" "glean"
check_primitive "groundhog" "groundhog.sh" "groundhog"
if [ -d "$HOST_DIR/.dash" ]; then
  echo "note .dash present at the host root — gremlin-produced content (correct placement)"
fi

# Host policy files. gremlin ships neither: a gremlin may generate facts about
# its host (AGENTS.md), it does not author policy for it. What it can do is
# notice that a primitive's own starting point is still sitting there untouched
# and say what a gremlin would like to find in it. Detection is a marker phrase
# from each primitive's shipped default — if upstream rewords its template this
# check simply stops firing, which is the quiet failure worth accepting for a
# note that is never load-bearing.
check_policy() {
  local file="$1" marker="$2" advice="$3"
  local path="$HOST_DIR/$file"
  [ -f "$path" ] || return 0
  if grep -qF -- "$marker" "$path"; then
    echo "note $file is still its primitive's starting point — $advice"
  fi
}
check_policy ".nest/tend.md" \
  "Replace the prompts below with the host folder's policy." \
  "this nest is tended by the gremlin beside it (.gremlin/bin/tend-loop.sh, described in .gremlin/docs/protocol.md); write the routing policy you want here"
check_policy ".glean/distil.md" \
  "This is the local brief for distillation in this glean." \
  "say what THIS repository considers worth remembering; the mechanics are already in .gremlin/skills/distil.md"

# The gremlin's own contributions to the host's primitives — its scheduled
# jobs, the tend brief, the distillation brief. Reported, never installed here:
# a job you deleted stays deleted, and doctor is not an installer.
if [ -x "$GREMLIN_DIR/bin/install-host-files.sh" ]; then
  if missing="$("$GREMLIN_DIR/bin/install-host-files.sh" --check "$HOST_DIR" 2>/dev/null)"; then
    echo "ok host files (jobs, tend.md, distil.md)"
  else
    printf '%s\n' "$missing" | sed 's/^missing /note not installed at the host: /'
    echo "     install with: $GREMLIN_DIR/bin/install-host-files.sh"
  fi
fi

check_preset() {
  local alias="$1"
  local path="$GREMLIN_DIR/models/$alias.sh"
  if [ ! -e "$path" ]; then
    echo "‼️  models/$alias.sh MISSING — items with .model=$alias will silently fall back to default.sh"
    return
  fi
  if [ ! -x "$path" ]; then
    echo "‼️  models/$alias.sh NOT EXECUTABLE — items with .model=$alias will silently fall back to default.sh"
    return
  fi
  if [ "$(head -c 2 "$path")" != "#!" ]; then
    echo "‼️  models/$alias.sh has no shebang — likely broken"
    return
  fi
  echo "ok models/$alias.sh"
}

check_preset "default"
check_preset "memory"

#!/usr/bin/env bash
# gitignore.sh — a copied gremlin hides nothing of the host's, and its own
# per-install state stays out of the host's `git status`.
#
# Copies every tracked file of the repo into a fresh host, installs the five
# primitives beside it, commits that as the host's baseline, then runs the
# gremlin (doctor, wake, prompt, sleep) with the echo model and checks what
# git makes of the result.
#
# Uses sibling primitive checkouts when there are some (offline), else the
# network installer.
#
# Usage: ./test/gitignore.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

HOST="$TMP/host"
mkdir -p "$HOST"

# The repo as a checkout hands it over: tracked files only, root files included.
(cd "$ROOT" && git ls-files --cached | while IFS= read -r f; do { [ -e "$f" ] || [ -L "$f" ]; } && printf '%s\n' "$f"; done) \
  | tar -C "$ROOT" -cf - -T - | tar -C "$HOST" -xf -

GREMLIN="$HOST/.gremlin"
PRIMITIVE_REPOS="${PRIMITIVE_REPOS:-$(cd "$ROOT/.." && pwd)}"
for pair in "nest nestlings" "loom loom" "lore lore" "glean glean" "groundhog groundhog"; do
  set -- $pair
  if [ -x "$PRIMITIVE_REPOS/$2/install.sh" ]; then
    "$PRIMITIVE_REPOS/$2/install.sh" "$HOST" >/dev/null 2>&1
  else
    "$GREMLIN/bin/install-primitives.sh" "$HOST" "$1" >/dev/null 2>&1
  fi
done

cd "$HOST" || exit 1
git init -q .
# A host's own files, in the places a gremlin's .gitignore must not reach.
mkdir -p .claude council
echo '{}' > .claude/settings.json
echo 'notes' > council/notes.md

# 1. Nothing at the host root is ignored: the host's own loom, Claude settings
#    and anything else are all committable.
hidden=""
for p in .loom/loom.sh .claude/settings.json council/notes.md .nest/nestling.sh \
         .glean/glean.sh .lore/lore.sh .groundhog/groundhog.sh AGENTS.md README.md \
         src/main.c; do
  git check-ignore -q "$p" && hidden="$hidden $p"
done
[ -z "$hidden" ] && ok "no host-root path is ignored" || bad "host paths ignored:$hidden"

# 2. Nothing in the copy names a host-root path in a root .gitignore.
if [ -e .gitignore ]; then
  grep -Eq '^[^#]*(\.loom|\.claude|council|\.nest|\.glean|\.lore|\.groundhog)' .gitignore \
    && bad "root .gitignore names a host-root path" || ok "root .gitignore names no host-root path"
else
  ok "no root .gitignore ships"
fi

# 3. The per-install files are ignored.
unignored=""
for p in .gremlin/name .gremlin/identity.md .gremlin/.model .gremlin/.tending.pid \
         .gremlin/.paused .gremlin/run.log .gremlin/transcript.md \
         .gremlin/transcript-archive/2026-01-01.md .gremlin/PRIMITIVES.md \
         .gremlin/context/system/identity.md .gremlin/context/system/primitives.md \
         .gremlin/bridges/web/config .gremlin/bridges/telegram/config \
         .gremlin/bridges/web/web.pid .gremlin/bridges/tui/tui.log \
         .gremlin/bridges/web/.cursor .gremlin/bridges/web/.cache/x \
         .gremlin/bridges/telegram/.update-offset .gremlin/bridges/web/__pycache__/x.pyc; do
  git check-ignore -q "$p" || unignored="$unignored $p"
done
[ -z "$unignored" ] && ok "per-install files are ignored" || bad "not ignored:$unignored"

# 4. Files the gremlin ships are not ignored.
shipped_hidden=""
for p in .gremlin/.gitignore .gremlin/.upstream .gremlin/gremlin.md .gremlin/models/echo.sh \
         .gremlin/bridges/web/config.example .gremlin/transcript-archive/.gitkeep; do
  git check-ignore -q "$p" && shipped_hidden="$shipped_hidden $p"
done
[ -z "$shipped_hidden" ] && ok "shipped files are not ignored" || bad "shipped files ignored:$shipped_hidden"

# 5. transcript.md is not tracked in the repo.
(cd "$ROOT" && git ls-files --error-unmatch .gremlin/transcript.md >/dev/null 2>&1) \
  && bad "transcript.md is tracked" || ok "transcript.md is not tracked"

# 6. Run the gremlin, then look at git. The baseline holds the host as it was
#    handed over; a used gremlin must add nothing under .gremlin/ to its status.
git add -A >/dev/null 2>&1
git -c user.name=test -c user.email=test@example.com commit -qm baseline
echo models/echo.sh > "$GREMLIN/.model"

"$GREMLIN/gremlin" doctor >/dev/null 2>&1
"$GREMLIN/gremlin" wake >/dev/null 2>&1
sleep 1
reply="$(timeout 90 "$GREMLIN/bin/prompt.sh" hello 2>&1)"
"$GREMLIN/gremlin" sleep >/dev/null 2>&1

[ -n "$reply" ] && ok "prompt got a reply from the echo model" || bad "prompt got no reply"
[ -s "$GREMLIN/transcript.md" ] && ok "transcript.md is recreated when missing" \
  || bad "transcript.md was not recreated"
status="$(git status --porcelain -uall -- .gremlin)"
[ -z "$status" ] && ok "a used gremlin leaves .gremlin/ clean in git status" \
  || bad "git status shows: $(printf '%s' "$status" | tr '\n' ';')"

printf '\npassed: %d, failed: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || { echo "not ok - a copied gremlin hides nothing and leaves its state out of git" >&2; exit 1; }
echo "ok - a copied gremlin hides nothing and leaves its state out of git"

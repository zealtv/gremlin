#!/usr/bin/env bash
# verbs.sh — wake, sleep, tend, ask, tell: the verb surface, and the deliberate
# absence of the ones they replaced.
#
# Usage: ./test/verbs.sh
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
cp -R "$ROOT/.gremlin" "$HOST/.gremlin"
GREMLIN="$HOST/.gremlin"
G="$GREMLIN/gremlin"

PRIMITIVE_REPOS="${PRIMITIVE_REPOS:-$(cd "$ROOT/.." && pwd)}"
for pair in "nest nestlings" "glean glean" "groundhog groundhog"; do
  set -- $pair
  if [ -x "$PRIMITIVE_REPOS/$2/install.sh" ]; then
    "$PRIMITIVE_REPOS/$2/install.sh" "$HOST" >/dev/null 2>&1
  else
    "$GREMLIN/bin/install-primitives.sh" "$HOST" "$1" >/dev/null 2>&1
  fi
done
"$HOST/.glean/glean.sh" index >/dev/null 2>&1
"$GREMLIN/bin/doctor.sh" >/dev/null 2>&1

# A deterministic model: the reply is the prompt's last line, prefixed.
cat > "$GREMLIN/models/echo.sh" <<'EOF'
#!/usr/bin/env bash
tail -n 1
EOF
chmod +x "$GREMLIN/models/echo.sh"
echo echo > "$GREMLIN/.model"

# --- the renamed verbs are gone, and say so ---------------------------------
for pair in "start wake" "stop sleep" "say ask"; do
  set -- $pair
  out="$("$G" "$1" 2>&1)"; rc=$?
  [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "is now .$2" \
    && ok "\`$1\` fails loud and names \`$2\`" \
    || bad "\`$1\` did not fail with a pointer to \`$2\` (rc=$rc)"
done

# The specific trap this protects: /stop aborts an in-flight model call, so a
# `stop` that fell through to the command dispatcher would do something
# different from what it used to, silently.
[ -x "$GREMLIN/commands/stop.sh" ] \
  && ok "commands/stop.sh still exists — the reason refusal beats fall-through" \
  || bad "commands/stop.sh is gone; the refusal's rationale needs revisiting"
"$G" stop 2>&1 | grep -qi 'nothing to stop' \
  && bad "\`stop\` fell through to the /stop command" \
  || ok "\`stop\` does not fall through to /stop"

# --- wake / status / sleep ---------------------------------------------------
"$G" status 2>&1 | grep -q 'asleep' && ok "status says asleep before waking" \
  || bad "status did not report asleep"
"$G" wake >/dev/null 2>&1
sleep 1
"$G" status 2>&1 | grep -q 'awake' && ok "wake starts the loops" || bad "wake did not start the loops"
second="$("$G" wake 2>&1)"
printf '%s' "$second" | grep -q 'already awake' && ok "waking twice is refused, not doubled" \
  || bad "wake did not notice it was already awake: [$second]"
"$G" sleep >/dev/null 2>&1
"$G" status 2>&1 | grep -q 'asleep' && ok "sleep stops the loops" || bad "sleep did not stop the loops"
"$G" sleep 2>&1 | grep -q 'already asleep' && ok "sleeping twice is harmless" \
  || bad "sleep on a sleeping gremlin was not graceful"

# The gremlin answers by name, not by folder.
name="$("$GREMLIN/bin/name.sh")"
"$G" status 2>&1 | grep -qF "$name" && ok "status speaks in the gremlin's name ($name)" \
  || bad "status did not use the gremlin's name"

# --- tend: one pass, now, while asleep ---------------------------------------
printf 'the item body\n' > "$TMP/item.md"
"$HOST/.nest/nestling.sh" ingest "$TMP/item.md" "manual.md" >/dev/null
"$G" tend >/dev/null 2>&1
grep -q 'the item body' "$GREMLIN/transcript.md" \
  && ok "tend works the nest once while asleep" || bad "tend did not process the item"
[ -z "$(ls -A "$HOST/.nest/in" 2>/dev/null)" ] && ok "tend emptied the inbox" \
  || bad "the item is still queued after tend"

# --- ask: inbound, and waits --------------------------------------------------
# ask waits for the answer, so someone has to be awake to give it.
"$G" wake >/dev/null 2>&1
sleep 1
reply="$("$G" ask "a question" 2>/dev/null | tail -n 1)"
[ -n "$reply" ] && ok "ask returns the answer it waited for" || bad "ask returned nothing"
"$G" ask "/name" >/dev/null 2>&1 && ok "ask still dispatches slash commands" \
  || bad "ask broke slash dispatch"
"$G" sleep >/dev/null 2>&1

# --- tell: outbound, unprompted ----------------------------------------------
"$G" tell "the backup finished" >/dev/null
tail -n 5 "$GREMLIN/transcript.md" | grep -q 'the backup finished' \
  && ok "tell lands in the transcript" || bad "tell did not reach the transcript"
tail -n 5 "$GREMLIN/transcript.md" | grep -q '^## assistant — ' \
  && ok "tell speaks as the assistant, so bridges fan it out" \
  || bad "tell did not write an assistant turn"
"$G" tell "" >/dev/null 2>&1 && bad "tell accepted an empty message" \
  || ok "tell refuses to say nothing"
echo "from stdin" | "$G" tell >/dev/null
tail -n 3 "$GREMLIN/transcript.md" | grep -q 'from stdin' && ok "tell reads stdin" \
  || bad "tell ignored stdin"

# --- help teaches the new surface --------------------------------------------
help="$("$G" help 2>&1)"
printf '%s' "$help" | grep -q 'wake' && printf '%s' "$help" | grep -q 'tell' \
  && ok "help lists the new verbs" || bad "help does not list the new verbs"
printf '%s' "$help" | grep -qE '^  (start|say)$' \
  && bad "help still advertises a removed verb" || ok "help does not advertise removed verbs"

printf '\npassed: %d, failed: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || { echo "not ok - the verb surface" >&2; exit 1; }
echo "ok - the verb surface"

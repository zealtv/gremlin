#!/usr/bin/env bash
# verbs.sh — wake, sleep, tend, prompt: the verb surface, and the deliberate
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

# A deterministic model: retain the complete assembled prompt for contract
# assertions, then return a stable response.
cat > "$GREMLIN/models/echo.sh" <<'EOF'
#!/usr/bin/env bash
GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cat > "$GREMLIN_DIR/prompt.seen"
printf 'model response\n'
EOF
chmod +x "$GREMLIN/models/echo.sh"
echo echo > "$GREMLIN/.model"

# --- the renamed verbs are gone, and say so ---------------------------------
for pair in "start wake" "stop sleep" "say prompt" "ask prompt" "tell prompt"; do
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

# --- prompt: one conversational turn, and wait -------------------------------
# prompt waits for the response, so someone has to be awake to give it.
"$G" wake >/dev/null 2>&1
sleep 1
reply="$("$G" prompt "a question" 2>/dev/null | tail -n 1)"
[ "$reply" = "model response" ] && ok "prompt returns the response it waited for" \
  || bad "prompt returned the wrong response: [$reply]"
grep -q 'a question' "$GREMLIN/prompt.seen" \
  && ok "prompt reaches the model" || bad "prompt did not reach the model"
grep -q '^## current-turn contract$' "$GREMLIN/prompt.seen" \
  && bad "ordinary prompt unexpectedly carried a contract" \
  || ok "ordinary prompt remains unrestricted"

"$G" prompt --read-only "review this" >/dev/null 2>&1
grep -q '^## current-turn contract$' "$GREMLIN/prompt.seen" \
  && grep -q 'This turn is read-only' "$GREMLIN/prompt.seen" \
  && ok "--read-only reaches the model as a scoped contract" \
  || bad "--read-only contract did not reach the model"
grep -q 'gremlin-prompt-contract' "$GREMLIN/transcript.md" \
  && bad "private prompt metadata leaked into the transcript" \
  || ok "private prompt metadata stays out of the transcript"
grep -q 'review this' "$GREMLIN/transcript.md" \
  && ok "read-only prompt records the human's actual words" \
  || bad "read-only prompt body is missing from the transcript"

echo "from stdin" | "$G" prompt >/dev/null 2>&1
grep -q 'from stdin' "$GREMLIN/transcript.md" \
  && ok "prompt reads stdin" || bad "prompt ignored stdin"
"$G" prompt "" >/dev/null 2>&1 \
  && bad "prompt accepted an empty message" || ok "prompt refuses an empty message"

# Slash syntax belongs to interactive bridges; shell commands use the direct
# wrapper surface and never masquerade as conversational prompts.
"$G" model echo >/dev/null 2>&1 \
  && ok "commands dispatch directly from the wrapper" \
  || bad "direct command dispatch failed"
"$G" prompt "/name" >/dev/null 2>&1
grep -q '^/name$' "$GREMLIN/prompt.seen" \
  && ok "prompt treats slash text as conversation" \
  || bad "prompt still dispatched slash text as a command"
"$G" sleep >/dev/null 2>&1

[ ! -e "$GREMLIN/bin/say.sh" ] && [ ! -e "$GREMLIN/bin/tell.sh" ] \
  && ok "obsolete say/tell implementations are gone" \
  || bad "an obsolete say/tell implementation remains"

# --- help teaches the new surface --------------------------------------------
help="$("$G" help 2>&1)"
printf '%s' "$help" | grep -q 'wake' && printf '%s' "$help" | grep -q 'prompt' \
  && ok "help lists the new verbs" || bad "help does not list the new verbs"
printf '%s' "$help" | grep -qE '^  (start|say|ask|tell)$' \
  && bad "help still advertises a removed verb" || ok "help does not advertise removed verbs"

printf '\npassed: %d, failed: %d\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || { echo "not ok - the verb surface" >&2; exit 1; }
echo "ok - the verb surface"

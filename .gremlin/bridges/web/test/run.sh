#!/usr/bin/env bash
# run.sh - the web bridge invariant + M0 acceptance suite.
#
# Two halves, both designed so an *elegant betrayal* fails here rather than
# slipping through review:
#   1. Static invariants  — grep the source for forbidden write/model paths, and
#      prove the greps have teeth by catching a deliberately doctored copy.
#   2. M0 acceptance      — boot the daemon against a throwaway fixture on a free
#      port and exercise the real HTTP surface (no real gremlin is touched).
#
# Usage: ./.gremlin/bridges/web/test/run.sh

set -uo pipefail

BRIDGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_SH="$BRIDGE_DIR/web.sh"
SERVER_PY="$BRIDGE_DIR/server.py"

pass=0
fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }
check() { if "$@"; then return 0; else return 1; fi; }

# --- the two invariant predicates (also reused to prove they have teeth) ------

# A transcript-write betrayal: opening transcript.md for write/append, in Python
# or via a shell redirect/tee. Reading (rb / tail -c) is fine and must not match.
writes_transcript() {
  grep -Eq 'open\([^)]*([Tt]ranscript|TRANSCRIPT)[^)]*,[[:space:]]*["'\''][aw]' "$1" \
    || grep -Eq '(>>?|tee[^|]*)[[:space:]]*"?\$?\{?(TRANSCRIPT|transcript)' "$1"
}

# A model-call betrayal: invoking a model preset / llm for conversation.
calls_model() {
  grep -Eq '(bin/llm\.sh|models/[A-Za-z0-9_-]+\.sh|run_preset|parse_mode=model)' "$1"
}

# ============================================================================
echo "== static invariants =="

# Invariants 1 & 3: the bridge never writes a user/assistant turn.
if writes_transcript "$SERVER_PY" || writes_transcript "$WEB_SH"; then
  bad "no transcript turn writes (invariants 1, 3)"
else
  ok "no transcript turn writes (invariants 1, 3)"
fi

# Invariant 4: the bridge never calls a model for conversation.
if calls_model "$SERVER_PY" || calls_model "$WEB_SH"; then
  bad "no model calls in the conversation path (invariant 4)"
else
  ok "no model calls in the conversation path (invariant 4)"
fi

# Teeth: a doctored copy that appends an assistant turn MUST be caught — else the
# grep above is decorative.
betrayal="$(mktemp)"
cp "$SERVER_PY" "$betrayal"
printf '\nwith open(TRANSCRIPT, "a") as fh: fh.write("## assistant — now\\nhi\\n")\n' >> "$betrayal"
if writes_transcript "$betrayal"; then
  ok "betrayal detector catches an injected assistant-turn write"
else
  bad "betrayal detector MISSED an injected assistant-turn write"
fi
rm -f "$betrayal"

betrayal="$(mktemp)"
cp "$SERVER_PY" "$betrayal"
printf '\nsubprocess.run([GREMLIN_DIR + "/bin/llm.sh"], input=body)\n' >> "$betrayal"
if calls_model "$betrayal"; then
  ok "betrayal detector catches an injected model call"
else
  bad "betrayal detector MISSED an injected model call"
fi
rm -f "$betrayal"

# ============================================================================
echo "== M0 acceptance (live daemon, fixture) =="

FIXTURE="$(mktemp -d)"
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
URL="http://127.0.0.1:$PORT"

# A seeded transcript exercising all three roles + verbatim system bodies.
cat > "$FIXTURE/transcript.md" <<'EOF'
## user — 2026-06-29T10:00:00Z
what repos exist?

## assistant — 2026-06-29T10:00:03Z
Host pwd: /home/bob/repos

## system — 2026-06-29T10:00:05Z
💌 message: nightly backup ok

## system — 2026-06-29T10:00:09Z
⚠️ error: empty model reply

## assistant — 2026-06-29T10:00:12Z
Here is the chart: 🖼️ [the chart](https://example.test/chart.png)
EOF

export WEB_GREMLIN_DIR="$FIXTURE"
export WEB_TRANSCRIPT="$FIXTURE/transcript.md"
export WEB_PORT="$PORT"
export WEB_BIND="127.0.0.1"

cleanup() {
  "$WEB_SH" stop >/dev/null 2>&1 || true
  rm -rf "$FIXTURE" "${M1FIX:-}" "${M8FIX:-}"
  rm -rf "$BRIDGE_DIR/.cache"
  rm -f "$BRIDGE_DIR/.cursor" "$BRIDGE_DIR/web.pid" "$BRIDGE_DIR/web.log"
}
trap cleanup EXIT

# Poll until a condition holds (never sleep-and-assert).
poll_until() {  # $1=seconds  $2...=command
  local deadline=$(( $(date +%s) + $1 )); shift
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if "$@"; then return 0; fi
    sleep 0.2
  done
  return 1
}

if "$WEB_SH" start >/dev/null 2>&1 && poll_until 5 curl -fsS -o /dev/null "$URL/"; then
  ok "gremlin web start → server boots"
else
  bad "gremlin web start → server boots"
  echo "  --- web.log ---"; cat "$BRIDGE_DIR/web.log" 2>/dev/null | sed 's/^/  /'
fi

# `/` returns 200 HTML.
if curl -fsS "$URL/" | grep -qi '<!DOCTYPE html>'; then
  ok "GET / → 200 HTML"
else
  bad "GET / → 200 HTML"
fi

# The transcript endpoint returns the seeded turns.
poll_json="$(curl -fsS "$URL/poll?cursor=0")"
if printf '%s' "$poll_json" | grep -q 'Host pwd: /home/bob/repos'; then
  ok "GET /poll → seeded turns present"
else
  bad "GET /poll → seeded turns present"
fi

# Invariant 9: system bodies are verbatim (both the 💌 and ⚠️ lines, unchanged).
if printf '%s' "$poll_json" | grep -q '💌 message: nightly backup ok' \
  && printf '%s' "$poll_json" | grep -q '⚠️ error: empty model reply'; then
  ok "system bodies served verbatim (invariant 9)"
else
  bad "system bodies served verbatim (invariant 9)"
fi

# Invariant 12: the loud error turn is present; a literal <silent> is never a
# turn, so it renders as nothing (absent from the served turns).
if printf '%s' "$poll_json" | grep -q '⚠️ error: empty model reply' \
  && ! printf '%s' "$poll_json" | grep -q '<silent>'; then
  ok "<silent> renders nothing, error renders loudly (invariant 12)"
else
  bad "<silent> renders nothing, error renders loudly (invariant 12)"
fi

# M2: the bridge serves embed markup VERBATIM (rendering is client-side; the
# transcript markup stays the source of truth — never rewritten).
if printf '%s' "$poll_json" | grep -q '🖼️ \[the chart\](https://example.test/chart.png)'; then
  ok "embed markup served verbatim, not rewritten (M2)"
else
  bad "embed markup served verbatim, not rewritten (M2)"
fi

# M2: the renderer asset is served.
if curl -fsS -o /dev/null -w '%{http_code}' "$URL/render.js" | grep -q 200; then
  ok "GET /render.js → 200"
else
  bad "GET /render.js → 200"
fi

# stitch 65: the unread-badge asset is served.
if curl -fsS -o /dev/null -w '%{http_code}' "$URL/badge.js" | grep -q 200; then
  ok "GET /badge.js → 200"
else
  bad "GET /badge.js → 200"
fi

# Append a system line by hand → it appears within a tick.
cat >> "$FIXTURE/transcript.md" <<'EOF'

## system — 2026-06-29T10:01:00Z
⚙️ run: backup.sh ok
EOF
if poll_until 5 bash -c "curl -fsS '$URL/poll?cursor=0' | grep -q '⚙️ run: backup.sh ok'"; then
  ok "appended ## system line appears next tick"
else
  bad "appended ## system line appears next tick"
fi

# A non-loopback Host header is refused (anti-DNS-rebinding).
code="$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: evil.example' "$URL/")"
if [ "$code" = "403" ]; then
  ok "non-loopback Host → 403"
else
  bad "non-loopback Host → 403 (got $code)"
fi

# Listener is bound to loopback only.
if command -v ss >/dev/null 2>&1; then
  if ss -ltn 2>/dev/null | grep -q "127.0.0.1:$PORT"; then
    ok "listener bound to 127.0.0.1 only"
  else
    bad "listener bound to 127.0.0.1 only"
  fi
fi

# Invariant 6: rm -rf the bridge's disposable dotfiles, restart → identical view.
before="$(curl -fsS "$URL/poll?cursor=0")"
"$WEB_SH" stop >/dev/null 2>&1 || true
rm -f "$BRIDGE_DIR/.cursor" "$BRIDGE_DIR/web.pid" "$BRIDGE_DIR/web.log"
if "$WEB_SH" start >/dev/null 2>&1 && poll_until 5 curl -fsS -o /dev/null "$URL/"; then
  after="$(curl -fsS "$URL/poll?cursor=0")"
  if [ "$before" = "$after" ]; then
    ok "rm -rf dotfiles → identical reconstructed view (invariant 6)"
  else
    bad "rm -rf dotfiles → identical reconstructed view (invariant 6)"
  fi
else
  bad "restart after rm -rf dotfiles"
fi

# Stop frees the port.
"$WEB_SH" stop >/dev/null 2>&1 || true
if poll_until 5 bash -c "! curl -fsS -o /dev/null '$URL/' 2>/dev/null"; then
  ok "gremlin web stop → port freed"
else
  bad "gremlin web stop → port freed"
fi

# ============================================================================
echo "== M1 send (the chat round-trip) =="

# A full fixture: a self-contained copy of this .gremlin so the real tender can
# run against it with the deterministic `echo` preset, touching no real state.
GREMLIN_REAL="$(cd "$BRIDGE_DIR/../.." && pwd)"
M1FIX="$(mktemp -d)"
cp -a "$GREMLIN_REAL" "$M1FIX/.gremlin"
M1GREM="$M1FIX/.gremlin"
printf 'echo\n' > "$M1GREM/.model"          # deterministic, no network
: > "$M1GREM/transcript.md"                   # start clean
find "$M1GREM/.nest/in" -mindepth 1 -delete 2>/dev/null || true
rm -f "$M1GREM/.tending.pid"

M1PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
M1URL="http://127.0.0.1:$M1PORT"
ORIGIN="Origin: http://127.0.0.1:$M1PORT"

rm -f "$BRIDGE_DIR/.cursor" "$BRIDGE_DIR/web.pid" "$BRIDGE_DIR/web.log"
export WEB_GREMLIN_DIR="$M1GREM"
export WEB_TRANSCRIPT="$M1GREM/transcript.md"
export WEB_NESTLING="$M1GREM/.nest/nestling.sh"
export WEB_PORT="$M1PORT"

web_items() { find "$M1GREM/.nest/in" -maxdepth 1 -name '*-web-*' 2>/dev/null | wc -l | tr -d ' '; }

if "$WEB_SH" start >/dev/null 2>&1 && poll_until 5 curl -fsS -o /dev/null "$M1URL/"; then
  ok "M1 daemon boots against fixture"
else
  bad "M1 daemon boots against fixture"
  cat "$BRIDGE_DIR/web.log" 2>/dev/null | sed 's/^/  /'
fi

# Empty / whitespace body → 400, nothing written.
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "$ORIGIN" \
  -H 'Content-Type: application/json' --data '{"text":"   "}' "$M1URL/send")"
if [ "$code" = "400" ] && [ "$(web_items)" = "0" ]; then
  ok "empty body → 400, no item written"
else
  bad "empty body → 400, no item written (code $code, items $(web_items))"
fi

# Cross-origin POST → 403 (anti-CSRF), nothing written.
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Origin: http://evil.example:9999' \
  -H 'Content-Type: application/json' --data '{"text":"ping"}' "$M1URL/send")"
if [ "$code" = "403" ] && [ "$(web_items)" = "0" ]; then
  ok "cross-origin POST → 403, no item written"
else
  bad "cross-origin POST → 403, no item written (code $code, items $(web_items))"
fi

# The round-trip: send "ping" → item lands → tender runs → both turns render.
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "$ORIGIN" \
  -H 'Content-Type: application/json' --data '{"text":"ping"}' "$M1URL/send")"
if [ "$code" = "200" ] && [ "$(web_items)" = "1" ]; then
  ok "POST /send ping → bare .md item in .nest/in/"
else
  bad "POST /send ping → bare .md item in .nest/in/ (code $code, items $(web_items))"
fi

# Drive the tender once synchronously (no background-loop race), with the echo
# preset, so the user + assistant turns land deterministically. The acceptance
# is that BOTH turns render — the reply's exact body is the preset's business
# (the shipped echo preset re-emits a prompt tail, not a clean "echo: ping").
"$M1GREM/bin/tend-loop.sh" >/dev/null 2>&1 || true
if poll_until 8 bash -c "curl -fsS '$M1URL/poll?cursor=0' | grep -q '\"role\": \"assistant\"'"; then
  if curl -fsS "$M1URL/poll?cursor=0" | python3 -c 'import sys,json; t=json.load(sys.stdin)["turns"]; sys.exit(0 if any(x["role"]=="user" and x["body"]=="ping" for x in t) and any(x["role"]=="assistant" for x in t) else 1)'; then
    ok "tender round-trip → ## user — ping + new ## assistant — render"
  else
    bad "tender round-trip → both turns render (user 'ping' + assistant)"
  fi
else
  bad "tender round-trip → an assistant turn appears within bound"
fi

# The bridge wrote the inbound item but NOT the transcript turns: the tender is
# the sole transcript writer (invariant 1, behaviorally).
if [ "$(grep -c '^## ' "$M1GREM/transcript.md")" -ge 2 ]; then
  ok "transcript turns authored by the tender, not the bridge (invariant 1)"
else
  bad "transcript turns present after tend (invariant 1)"
fi

# --- slash commands (stitch 21): dispatch via bin/slash.sh, never a turn -------

# /help returns the real command list as a bridge result (JSON), rc 0.
help_json="$(curl -fsS -X POST -H "$ORIGIN" -H 'Content-Type: application/json' \
  --data '{"text":"/help"}' "$M1URL/send")"
if printf '%s' "$help_json" | python3 -c 'import sys,json
d=json.load(sys.stdin)
out=d.get("output","")
sys.exit(0 if d.get("slash") and d.get("rc")==0 and "/help" in out and "/model" in out else 1)'; then
  ok "/help → bridge result with the real command list (rc 0)"
else
  bad "/help → bridge result with the real command list (rc 0): $help_json"
fi

# Slash handling writes NOTHING: no new transcript turn, no new nest item.
turns_before="$(grep -c '^## ' "$M1GREM/transcript.md")"
items_before="$(web_items)"
curl -fsS -X POST -H "$ORIGIN" -H 'Content-Type: application/json' \
  --data '{"text":"/help"}' "$M1URL/send" >/dev/null
if [ "$(grep -c '^## ' "$M1GREM/transcript.md")" = "$turns_before" ] \
  && [ "$(web_items)" = "$items_before" ]; then
  ok "slash command writes no transcript turn and no nest item (invariant 1)"
else
  bad "slash command must not write a transcript turn or nest item"
fi

# An unknown command fails loud: rc 127, guidance toward /help.
unk_json="$(curl -fsS -X POST -H "$ORIGIN" -H 'Content-Type: application/json' \
  --data '{"text":"/frobnicate"}' "$M1URL/send")"
if printf '%s' "$unk_json" | python3 -c 'import sys,json
d=json.load(sys.stdin)
sys.exit(0 if d.get("rc")==127 and d.get("ok") is False and "/help" in d.get("output","") else 1)'; then
  ok "unknown /frobnicate fails loud (rc 127, points at /help)"
else
  bad "unknown /frobnicate fails loud: $unk_json"
fi

# The autocomplete menu (stitch 22) derives from the SAME commands/*.sh source.
cmd_json="$(curl -fsS "$M1URL/api/commands")"
if printf '%s' "$cmd_json" | python3 -c 'import sys,json
env=json.load(sys.stdin)
names=set(x["name"] for x in env["items"])
# every commands/*.sh must appear, and each entry carries name+summary keys
sys.exit(0 if {"help","model","new"} <= names
  and all("name" in x and "summary" in x for x in env["items"]) else 1)'; then
  ok "/api/commands lists commands/*.sh (autocomplete source, stitch 22)"
else
  bad "/api/commands lists commands/*.sh: $cmd_json"
fi

# The menu vocabulary must not diverge from the CLI: /api/commands names match
# exactly the *.sh basenames under commands/.
disk_cmds="$(cd "$M1GREM/commands" && ls *.sh 2>/dev/null | sed 's/\.sh$//' | sort | tr '\n' ' ')"
api_cmds="$(printf '%s' "$cmd_json" | python3 -c 'import sys,json
print(" ".join(sorted(x["name"] for x in json.load(sys.stdin)["items"]))+" ")')"
if [ "$disk_cmds" = "$api_cmds" ]; then
  ok "autocomplete vocabulary matches commands/ exactly (no web-only drift)"
else
  bad "autocomplete vocabulary drift: disk [$disk_cmds] vs api [$api_cmds]"
fi

# Inspector purpose hints (stitch 26): terse (1–3 word) role labels, one per
# inspector primitive.
prim_json="$(curl -fsS "$M1URL/api/primitives")"
if printf '%s' "$prim_json" | python3 -c 'import sys,json
h={x["name"]:x["hint"] for x in json.load(sys.stdin)["items"]}
ok = h.get("groundhog")=="scheduling" and h.get("loom")=="action tracking" \
  and h.get("glean")=="memory" and h.get("lore")=="reference" \
  and all(v and 1 <= len(v.split()) <= 3 for v in h.values())
sys.exit(0 if ok else 1)'; then
  ok "/api/primitives → terse 1–3 word purpose hints (stitch 26)"
else
  bad "/api/primitives hints: $prim_json"
fi

# Activity indicator (stitch 29) data contract: a claimed .nest/in item surfaces
# as in-progress>0 in /api/status (the second honest signal; the first — a live
# .tending.pid ⇒ "thinking" — is covered in the M3 status tests).
touch "$M1GREM/.nest/in/zzz-claim.tending"
if curl -fsS "$M1URL/api/status" | python3 -c 'import sys,json
i=[x for x in json.load(sys.stdin)["items"] if x["name"]=="in-progress"][0]
sys.exit(0 if i["fields"]["tending"]>=1 else 1)'; then
  ok "claimed .nest/in item → in-progress>0 (activity signal, stitch 29)"
else
  bad "in-progress claim not reflected in /api/status (stitch 29)"
fi
rm -f "$M1GREM/.nest/in/zzz-claim.tending"

# A message that is NOT a slash command is still ingested as a nest item.
before_norm="$(web_items)"
curl -fsS -X POST -H "$ORIGIN" -H 'Content-Type: application/json' \
  --data '{"text":"not a slash command"}' "$M1URL/send" >/dev/null
if [ "$(web_items)" = "$((before_norm + 1))" ]; then
  ok "ordinary message still ingested as a nest item (unaffected)"
else
  bad "ordinary message ingest regressed"
fi

"$WEB_SH" stop >/dev/null 2>&1 || true

# ============================================================================
echo "== M8 attachments (multipart → item dir; /media jail) =="

M8FIX="$(mktemp -d)"
M8H="$M8FIX/host"
M8G="$M8H/.gremlin"
mkdir -p "$M8H"
cp -a "$GREMLIN_REAL" "$M8G"
printf 'echo\n' > "$M8G/.model"
: > "$M8G/transcript.md"
find "$M8G/.nest/in" -mindepth 1 -delete 2>/dev/null || true
rm -f "$M8G/.tending.pid"
rm -rf "$BRIDGE_DIR/.cache"

M8PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
M8URL="http://127.0.0.1:$M8PORT"
M8ORIGIN="Origin: http://127.0.0.1:$M8PORT"

rm -f "$BRIDGE_DIR/.cursor" "$BRIDGE_DIR/web.pid" "$BRIDGE_DIR/web.log"
export WEB_GREMLIN_DIR="$M8G"
export WEB_HOST_DIR="$M8H"
export WEB_TRANSCRIPT="$M8G/transcript.md"
export WEB_NESTLING="$M8G/.nest/nestling.sh"
export WEB_PORT="$M8PORT"
export WEB_BIND="127.0.0.1"
export WEB_MAX_UPLOAD=4096
unset WEB_REMOTE_TOKEN

m8_items() { find "$M8G/.nest/in" -maxdepth 1 -name '*-web-*' 2>/dev/null | wc -l | tr -d ' '; }
# Resolve the item a POST created from its response JSON — a name-sort "latest"
# ties when two items land in the same second (the random hex decides, flakily).
m8_item_of() { printf '%s' "$1" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("item",""))
except Exception: print("")'; }
m8_cache_entries() {
  if [ -d "$BRIDGE_DIR/.cache" ]; then
    find "$BRIDGE_DIR/.cache" -mindepth 1 2>/dev/null | wc -l | tr -d ' '
  else
    printf '0'
  fi
}

if "$WEB_SH" start >/dev/null 2>&1 && poll_until 5 curl -fsS -o /dev/null "$M8URL/"; then
  ok "M8 daemon boots against fixture"
else
  bad "M8 daemon boots against fixture"
  cat "$BRIDGE_DIR/web.log" 2>/dev/null | sed 's/^/  /'
fi

printf 'attachment notes\n' > "$M8FIX/notes.txt"
resp="$(curl -s -w '\n%{http_code}' -X POST -H "$M8ORIGIN" \
  -F 'text=see attached' -F "files=@$M8FIX/notes.txt;type=text/plain" "$M8URL/send")"
code="$(printf '%s' "$resp" | tail -n 1)"
item="$M8G/.nest/in/$(m8_item_of "$(printf '%s' "$resp" | sed '$d')")"
legacy_msg="$(printf 'message.%s' md)"
if [ "$code" = "200" ] && [ "$(m8_items)" = "1" ] && [ -d "$item" ] \
  && [ -f "$item/notes.txt" ] && [ -f "$item/instructions.md" ] \
  && grep -q '## attachments' "$item/instructions.md" \
  && grep -q '`notes.txt` (text/plain)' "$item/instructions.md" \
  && grep -q 'see attached' "$item/instructions.md" \
  && [ ! -e "$item/$legacy_msg" ]; then
  ok "multipart text+file → one web item dir with instructions + attachment"
else
  bad "multipart text+file → item dir (code $code, items $(m8_items), item $item)"
fi

"$M8G/bin/tend-loop.sh" >/dev/null 2>&1 || true
if poll_until 8 bash -c "curl -fsS '$M8URL/poll?cursor=0' | grep -q '\"role\": \"assistant\"'"; then
  if curl -fsS "$M8URL/poll?cursor=0" | python3 -c 'import sys,json
t=json.load(sys.stdin)["turns"]
sys.exit(0 if any(x["role"]=="user" for x in t) and any(x["role"]=="assistant" for x in t) else 1)'; then
    ok "attachment tender round-trip → ## user + ## assistant render"
  else
    bad "attachment tender round-trip → both turns render"
  fi
else
  bad "attachment tender round-trip → assistant appears within bound"
fi

before="$(m8_items)"
printf 'pw bytes\n' > "$M8FIX/passwd-src"
resp="$(curl -fsS -X POST -H "$M8ORIGIN" -F 'text=bad name' \
  -F "files=@$M8FIX/passwd-src;filename=../../etc/passwd;type=text/plain" "$M8URL/send")"
item="$M8G/.nest/in/$(m8_item_of "$resp")"
if [ "$(m8_items)" = "$((before + 1))" ] && [ -f "$item/passwd" ] \
  && [ ! -e "$item/../../etc/passwd" ] && [ ! -e "$BRIDGE_DIR/.cache/etc/passwd" ]; then
  ok "filename traversal sanitized to basename inside item dir"
else
  bad "filename traversal sanitized (items $(m8_items), item $item)"
fi

before="$(m8_items)"
printf 'uploaded control bytes\n' > "$M8FIX/uploaded-instructions.md"
resp="$(curl -fsS -X POST -H "$M8ORIGIN" -F 'text=reserved name' \
  -F "files=@$M8FIX/uploaded-instructions.md;filename=instructions.md;type=text/markdown" "$M8URL/send")"
item="$M8G/.nest/in/$(m8_item_of "$resp")"
if [ "$(m8_items)" = "$((before + 1))" ] && [ -f "$item/file.md" ] \
  && grep -q 'uploaded control bytes' "$item/file.md" \
  && grep -q '## attachments' "$item/instructions.md" \
  && ! grep -q 'uploaded control bytes' "$item/instructions.md"; then
  ok "reserved upload name instructions.md → file.md; control instructions preserved"
else
  bad "reserved upload name instructions.md handled"
fi

before="$(m8_items)"
python3 -c 'import sys; open(sys.argv[1],"wb").write(b"x"*5000)' "$M8FIX/big.bin"
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "$M8ORIGIN" \
  -F 'text=too big' -F "files=@$M8FIX/big.bin;type=application/octet-stream" "$M8URL/send")"
if [ "$code" = "413" ] && [ "$(m8_items)" = "$before" ] && [ "$(m8_cache_entries)" = "0" ]; then
  ok "oversize multipart → 413, no item, no cache residue"
else
  bad "oversize multipart → 413/no residue (code $code, items $(m8_items), cache $(m8_cache_entries))"
fi

before="$(m8_items)"
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "$M8ORIGIN" \
  -H 'Content-Type: multipart/form-data' --data 'not really multipart' "$M8URL/send")"
if [ "$code" = "400" ] && [ "$(m8_items)" = "$before" ]; then
  ok "malformed multipart → 400, no item"
else
  bad "malformed multipart → 400, no item (code $code, items $(m8_items))"
fi

before="$(m8_items)"
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Origin: http://evil.example:9999' \
  -F 'text=nope' -F "files=@$M8FIX/notes.txt;type=text/plain" "$M8URL/send")"
if [ "$code" = "403" ] && [ "$(m8_items)" = "$before" ]; then
  ok "cross-origin multipart POST → 403, no item"
else
  bad "cross-origin multipart POST → 403, no item (code $code, items $(m8_items))"
fi

printf 'media bytes\n' > "$M8H/media-ok.txt"
curl -fsS -D "$M8FIX/media.h" -o "$M8FIX/media.out" "$M8URL/media?path=media-ok.txt"
if cmp -s "$M8H/media-ok.txt" "$M8FIX/media.out" \
  && grep -qi '^Content-Disposition:' "$M8FIX/media.h"; then
  ok "/media?path=<rel> → 200 exact bytes + Content-Disposition"
else
  bad "/media?path=<rel> → exact bytes + Content-Disposition"
fi
if curl -fsS -H 'Range: bytes=0-4' "$M8URL/media?path=media-ok.txt" | grep -qx 'media'; then
  ok "/media Range bytes=a-b → 206 body slice"
else
  bad "/media Range bytes=a-b → body slice"
fi

printf 'TOP SECRET\n' > "$M8FIX/secret.txt"
ln -s ../secret.txt "$M8H/escape.txt"
for bad_path in "../../etc/passwd" "..%2f..%2fetc%2fpasswd" "escape.txt" "missing.txt"; do
  body="$(curl -s -o - -w '\n%{http_code}' "$M8URL/media?path=$bad_path")"
  code="$(printf '%s' "$body" | tail -n 1)"
  if [ "$code" != "404" ] || printf '%s' "$body" | grep -q 'TOP SECRET'; then
    bad "/media jail refused $bad_path (got $code)"
    M8MEDIA_BAD=1
  fi
done
[ -z "${M8MEDIA_BAD:-}" ] && ok "/media traversal, symlink escape, missing path → 404 with no secret bytes"

before="$(m8_items)"
resp="$(curl -fsS -X POST -H "$M8ORIGIN" -F 'text=text only multipart' "$M8URL/send")"
item="$M8G/.nest/in/$(m8_item_of "$resp")"
if [ "$(m8_items)" = "$((before + 1))" ] && [ -f "$item" ] && [ ! -d "$item" ] \
  && grep -q 'text only multipart' "$item"; then
  ok "multipart text-only → bare .md item, not a directory"
else
  bad "multipart text-only → bare .md item (items $(m8_items), item $item)"
fi

"$WEB_SH" stop >/dev/null 2>&1 || true
unset WEB_MAX_UPLOAD

# ============================================================================
echo "== M2 renderer (render.js, pure) =="

if command -v node >/dev/null 2>&1; then
  if node "$BRIDGE_DIR/test/render.test.js"; then
    ok "render.js unit tests pass"
  else
    bad "render.js unit tests pass"
  fi
  if node "$BRIDGE_DIR/test/badge.test.js"; then
    ok "badge.js unit tests pass"
  else
    bad "badge.js unit tests pass"
  fi
else
  echo "  skip render.js unit tests (no node)"
  echo "  skip badge.js unit tests (no node)"
fi

# ============================================================================
echo "== M3 inspector: context / status =="

M3FIX="$(mktemp -d)"
mkdir -p "$M3FIX/.gremlin/context/system" "$M3FIX/.gremlin/skills"
: > "$M3FIX/.gremlin/transcript.md"
printf '# gremlin\nidentity body here\n' > "$M3FIX/.gremlin/gremlin.md"
printf 'echo\n' > "$M3FIX/.gremlin/.model"
printf '# a context note\nhello from context\n' > "$M3FIX/.gremlin/context/system/note.md"
M3PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
M3URL="http://127.0.0.1:$M3PORT"

rm -f "$BRIDGE_DIR/.cursor" "$BRIDGE_DIR/web.pid" "$BRIDGE_DIR/web.log"
export WEB_GREMLIN_DIR="$M3FIX/.gremlin"
export WEB_TRANSCRIPT="$M3FIX/.gremlin/transcript.md"
export WEB_PORT="$M3PORT"

m3cleanup() { "$WEB_SH" stop >/dev/null 2>&1 || true; rm -rf "$M3FIX"; }

if "$WEB_SH" start >/dev/null 2>&1 && poll_until 5 curl -fsS -o /dev/null "$M3URL/"; then
  ok "M3 daemon boots against fixture"
else
  bad "M3 daemon boots against fixture"
fi

# Context envelope carries path + source, and a context file renders.
ctx="$(curl -fsS "$M3URL/api/context")"
if printf '%s' "$ctx" | grep -q '"source": "fs"' \
  && printf '%s' "$ctx" | grep -q '"path": "gremlin.md"' \
  && printf '%s' "$ctx" | grep -q 'hello from context'; then
  ok "context envelope: path + source + a context file renders"
else
  bad "context envelope: path + source + a context file renders"
fi

# touch .paused → paused.
touch "$M3FIX/.gremlin/.paused"
if curl -fsS "$M3URL/api/status" | python3 -c 'import sys,json
i=[x for x in json.load(sys.stdin)["items"] if x["name"]=="runner"][0]
sys.exit(0 if i["state"]=="paused" and i["fields"]["paused"] else 1)'; then
  ok "touch .paused → status shows paused"
else
  bad "touch .paused → status shows paused"
fi
rm -f "$M3FIX/.gremlin/.paused"

# A dead pid → idle, stale (not a ghost-busy state) — the kill -0 rule.
echo 999999 > "$M3FIX/.gremlin/.tending.pid"
if curl -fsS "$M3URL/api/status" | python3 -c 'import sys,json
i=[x for x in json.load(sys.stdin)["items"] if x["name"]=="tending"][0]
sys.exit(0 if i["state"]=="stale" and i["fields"]["stale"] and not i["fields"]["alive"] else 1)'; then
  ok "dead pid → idle, stale pid (kill -0 rule)"
else
  bad "dead pid → idle, stale pid (kill -0 rule)"
fi

# A live pid (this shell) → thinking.
echo "$$" > "$M3FIX/.gremlin/.tending.pid"
if curl -fsS "$M3URL/api/status" | python3 -c 'import sys,json
i=[x for x in json.load(sys.stdin)["items"] if x["name"]=="tending"][0]
sys.exit(0 if i["state"]=="thinking" and i["fields"]["alive"] else 1)'; then
  ok "live pid → thinking (alive)"
else
  bad "live pid → thinking (alive)"
fi
rm -f "$M3FIX/.gremlin/.tending.pid"

# The header identifier is the gremlin's host directory name.
exp="$(basename "$M3FIX")"
got="$(curl -fsS "$M3URL/api/identity" | python3 -c 'import sys,json;print(json.load(sys.stdin)["host"])')"
[ "$got" = "$exp" ] && ok "/api/identity → host directory name" || bad "/api/identity host ($got != $exp)"

m3cleanup

# ============================================================================
echo "== M5 inspector: glean (index-first) =="

GFIX="$(mktemp -d)"
GG="$GFIX/.gremlin"
mkdir -p "$GG/.glean/findings" "$GG/.glean/in" "$GG/.glean/out" "$GG/.glean/dropped" "$GG/context"
: > "$GG/transcript.md"
cat > "$GG/.glean/findings/commit-style.md" <<'EOF'
# Commit message convention
Emoji only in the first -m subject; prose body in a second -m.

## Triggers
- commit
## Associations
- [[loom-tracker]]
EOF
cat > "$GG/.glean/findings/loom-tracker.md" <<'EOF'
# Loom action tracker
Uses .loom/ for durable intentions.
EOF
printf -- '- [[commit-style]] — Commit message convention — Emoji only in the first -m subject; prose body in a second -m.\n- [[loom-tracker]] — Loom action tracker — Uses .loom/ for durable intentions.\n' > "$GG/.glean/findings/INDEX.md"
ln -s ../.glean/findings/commit-style.md "$GG/context/commit-style.md"  # promote
echo "raw" > "$GG/.glean/in/note-1.md"

GPORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
GURL="http://127.0.0.1:$GPORT"
rm -f "$BRIDGE_DIR/.cursor" "$BRIDGE_DIR/web.pid" "$BRIDGE_DIR/web.log"
export WEB_GREMLIN_DIR="$GG"
export WEB_TRANSCRIPT="$GG/transcript.md"
export WEB_PORT="$GPORT"

gcleanup() { "$WEB_SH" stop >/dev/null 2>&1 || true; rm -rf "$GFIX"; }

if "$WEB_SH" start >/dev/null 2>&1 && poll_until 5 curl -fsS -o /dev/null "$GURL/"; then
  ok "glean daemon boots against fixture"
else
  bad "glean daemon boots against fixture"
fi

gi="$(curl -fsS "$GURL/api/glean")"
# Index lists exactly the INDEX.md entries (2 findings), with titles from INDEX.
if printf '%s' "$gi" | python3 -c 'import sys,json
items=[x for x in json.load(sys.stdin)["items"] if x["name"]!="workbench"]
ids=sorted(x["name"] for x in items)
sys.exit(0 if ids==["commit-style","loom-tracker"] else 1)'; then
  ok "index lists exactly the INDEX.md entries"
else
  bad "index lists exactly the INDEX.md entries"
fi

# Invariant 11: NO finding body is served by the index endpoint.
if printf '%s' "$gi" | grep -q '"body"'; then
  bad "index must NOT eagerly serve finding bodies (invariant 11)"
else
  ok "index serves no finding bodies — index-first (invariant 11)"
fi

# A promoted finding shows the pill (state/flag).
if printf '%s' "$gi" | python3 -c 'import sys,json
it=[x for x in json.load(sys.stdin)["items"] if x["name"]=="commit-style"][0]
sys.exit(0 if it["fields"]["promoted"] and it["state"]=="promoted" else 1)'; then
  ok "promoted finding (symlinked into context/) flagged"
else
  bad "promoted finding flagged"
fi

# A body loads only when opened (on demand), with its sections intact.
if curl -fsS "$GURL/api/glean/finding/commit-style" | python3 -c 'import sys,json
it=json.load(sys.stdin)["items"][0]
sys.exit(0 if "## Triggers" in it["fields"]["body"] and it["fields"]["promoted"] else 1)'; then
  ok "finding body loads on demand (with sections)"
else
  bad "finding body loads on demand"
fi

# Workbench tray counts.
if printf '%s' "$gi" | python3 -c 'import sys,json
wb=[x for x in json.load(sys.stdin)["items"] if x["name"]=="workbench"][0]
sys.exit(0 if wb["fields"]["in"]==1 and wb["fields"]["out"]==0 else 1)'; then
  ok "workbench tray counts (in/out/dropped)"
else
  bad "workbench tray counts"
fi

# Path-param safety: traversal + a bad id are refused; a missing id 404s.
for bad_path in "..%2f..%2f..%2fetc%2fpasswd" "../../../etc/passwd" "nope"; do
  code="$(curl -s -o /dev/null -w '%{http_code}' "$GURL/api/glean/finding/$bad_path")"
  [ "$code" = "404" ] || { bad "glean finding bad id refused ($bad_path → $code)"; FAILED_BADID=1; }
done
[ -z "${FAILED_BADID:-}" ] && ok "traversal / bad / missing finding id → 404"

gcleanup

# ============================================================================
echo "== M4 inspector: groundhog (shell out to list/due) =="

HFIX="$(mktemp -d)"
HG="$HFIX/.gremlin"
# A self-contained gremlin so groundhog.sh resolves its own root.
cp -a /home/bob/repos/gremlin/.gremlin "$HG"
: > "$HG/transcript.md"
rm -f "$HG/bridges/web/.cursor" "$HG/bridges/web/web.pid" "$HG/bridges/web/web.log"
rm -rf "$HG/bridges/web/__pycache__" "$HG/bridges/web/.cache"
# seed schedule: a paused weekly entry + a fired-today marker + an out/ entry
mkdir -p "$HG/.groundhog/schedule/weekly/sun/09-00/standup.paused"
mkdir -p "$HG/.groundhog/fired/$(date +%Y-%m-%d)/weekly/sun/09-00/standup"
mkdir -p "$HG/.groundhog/out/standup-$(date +%Y-%m-%d)"

HPORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
HURL="http://127.0.0.1:$HPORT"
rm -f "$BRIDGE_DIR/.cursor" "$BRIDGE_DIR/web.pid" "$BRIDGE_DIR/web.log"
export WEB_GREMLIN_DIR="$HG" WEB_TRANSCRIPT="$HG/transcript.md" WEB_PORT="$HPORT" WEB_BIND="127.0.0.1"
unset WEB_REMOTE_TOKEN

hcleanup() { "$WEB_SH" stop >/dev/null 2>&1 || true; rm -rf "$HFIX"; }

if "$WEB_SH" start >/dev/null 2>&1 && poll_until 5 curl -fsS -o /dev/null "$HURL/"; then
  ok "groundhog daemon boots against fixture"
else
  bad "groundhog daemon boots against fixture"
fi

gh="$(curl -fsS "$HURL/api/groundhog")"
# raw is the verbatim `list` tree, with the paused entry tagged by the script.
if printf '%s' "$gh" | python3 -c 'import sys,json
d=json.load(sys.stdin)
sys.exit(0 if d["source"].startswith("groundhog.sh") and "standup" in d["raw"] and "[paused]" in d["raw"] else 1)'; then
  ok "schedule tree shelled out verbatim, paused entry tagged"
else
  bad "schedule tree shelled out verbatim, paused entry tagged"
fi

# fired-today marker surfaces.
if printf '%s' "$gh" | python3 -c 'import sys,json
items=json.load(sys.stdin)["items"]
sys.exit(0 if any(i["state"]=="fired-today" for i in items) else 1)'; then
  ok "fired/<today> marker → fired-today"
else
  bad "fired/<today> marker → fired-today"
fi

# out/ residue surfaces as awaiting-pickup.
if printf '%s' "$gh" | python3 -c 'import sys,json
items=json.load(sys.stdin)["items"]
sys.exit(0 if any(i["state"]=="awaiting-pickup" for i in items) else 1)'; then
  ok "out/ entry → awaiting-pickup"
else
  bad "out/ entry → awaiting-pickup"
fi

hcleanup

# ============================================================================
echo "== M6 inspector: loom (reuse loom.sh, preserve tree) =="

LMFIX="$(mktemp -d)"
LMG="$LMFIX/.gremlin"
cp -a /home/bob/repos/gremlin/.gremlin "$LMG"
: > "$LMG/transcript.md"
rm -f "$LMG/bridges/web/.cursor" "$LMG/bridges/web/web.pid" "$LMG/bridges/web/web.log"
rm -rf "$LMG/bridges/web/__pycache__" "$LMG/bridges/web/.cache"
# seed the gremlin's own loom: one ready loose end + one waiting leaf
LOOM="$LMG/.loom/loom.sh"
"$LOOM" new ship-thing >/dev/null 2>&1 || true
"$LOOM" new parked-thing >/dev/null 2>&1 || true
"$LOOM" wait parked-thing >/dev/null 2>&1 || true

LMPORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
LMURL="http://127.0.0.1:$LMPORT"
rm -f "$BRIDGE_DIR/.cursor" "$BRIDGE_DIR/web.pid" "$BRIDGE_DIR/web.log"
export WEB_GREMLIN_DIR="$LMG" WEB_TRANSCRIPT="$LMG/transcript.md" WEB_PORT="$LMPORT" WEB_BIND="127.0.0.1"
unset WEB_REMOTE_TOKEN

lmcleanup() { "$WEB_SH" stop >/dev/null 2>&1 || true; rm -rf "$LMFIX"; }

if "$WEB_SH" start >/dev/null 2>&1 && poll_until 5 curl -fsS -o /dev/null "$LMURL/"; then
  ok "loom daemon boots against fixture"
else
  bad "loom daemon boots against fixture"
fi

lm="$(curl -fsS "$LMURL/api/loom")"
# A plain leaf is a ready loose end; the .waiting leaf is excluded from it.
if printf '%s' "$lm" | python3 -c 'import sys,json
items=json.load(sys.stdin)["items"]
loose=[i["name"] for i in items if i["state"]=="loose-end"]
waiting=[i["name"] for i in items if i["state"]=="waiting"]
sys.exit(0 if "ship-thing" in loose and not any("parked" in x for x in loose) and any("parked" in x for x in waiting) else 1)'; then
  ok "ready loose end listed; .waiting leaf excluded from NEXT"
else
  bad "ready loose end listed; .waiting leaf excluded from NEXT"
fi

# The thread tree is shelled out verbatim (not flattened) and source is loom.sh.
if printf '%s' "$lm" | python3 -c 'import sys,json
d=json.load(sys.stdin)
sys.exit(0 if d["source"]=="loom.sh status" and "ship-thing" in d["raw"] else 1)'; then
  ok "thread tree served verbatim via loom.sh status"
else
  bad "thread tree served verbatim via loom.sh status"
fi

lmcleanup

# ============================================================================
echo "== M7 inspector: lore (durable, dated; content download) =="

LRFIX="$(mktemp -d)"
LRH="$LRFIX/host"; LRG="$LRH/.gremlin"
mkdir -p "$LRG" "$LRH/.lore/items/2026-06-01-demo/content"
: > "$LRG/transcript.md"
printf '# A demo note\nWhat the council decided.\n\n## Source\nthe session.\n' > "$LRH/.lore/items/2026-06-01-demo/item.md"
printf 'plain text\n' > "$LRH/.lore/items/2026-06-01-demo/content/notes.txt"
printf '\x00\x01binary\x00' > "$LRH/.lore/items/2026-06-01-demo/content/blob.bin"
printf -- '- [2026-06-01-demo](items/2026-06-01-demo/) — A demo note — What the council decided.\n' > "$LRH/.lore/INDEX.md"

LRPORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
LRURL="http://127.0.0.1:$LRPORT"
rm -f "$BRIDGE_DIR/.cursor" "$BRIDGE_DIR/web.pid" "$BRIDGE_DIR/web.log"
export WEB_GREMLIN_DIR="$LRG" WEB_HOST_DIR="$LRH" WEB_TRANSCRIPT="$LRG/transcript.md" WEB_PORT="$LRPORT" WEB_BIND="127.0.0.1"
unset WEB_REMOTE_TOKEN

lrcleanup() { "$WEB_SH" stop >/dev/null 2>&1 || true; rm -rf "$LRFIX"; }

if "$WEB_SH" start >/dev/null 2>&1 && poll_until 5 curl -fsS -o /dev/null "$LRURL/"; then
  ok "lore daemon boots against fixture"
else
  bad "lore daemon boots against fixture"
fi

# Cards match INDEX.md (id, title, date).
if curl -fsS "$LRURL/api/lore" | python3 -c 'import sys,json
i=[x for x in json.load(sys.stdin)["items"] if x["name"]=="2026-06-01-demo"][0]
sys.exit(0 if i["fields"]["title"]=="A demo note" and i["fields"]["date"]=="2026-06-01" else 1)'; then
  ok "cards match INDEX.md (title + date)"
else
  bad "cards match INDEX.md"
fi

# Item shows item.md body + content listing with binary flags.
if curl -fsS "$LRURL/api/lore/item/2026-06-01-demo" | python3 -c 'import sys,json
f=json.load(sys.stdin)["items"][0]["fields"]
c={x["name"]:x["binary"] for x in f["content"]}
sys.exit(0 if "## Source" in f["body"] and c.get("notes.txt")==False and c.get("blob.bin")==True else 1)'; then
  ok "item.md body + content listing (binary detected)"
else
  bad "item.md body + content listing"
fi

# Binary content offers download (attachment); text is inline.
if curl -s -D - -o /dev/null "$LRURL/api/lore/content/2026-06-01-demo/blob.bin" | grep -qi 'content-disposition: attachment' \
  && curl -s -D - -o /dev/null "$LRURL/api/lore/content/2026-06-01-demo/notes.txt" | grep -qi 'content-disposition: inline'; then
  ok "binary → download, text → inline"
else
  bad "binary → download, text → inline"
fi

# Content path traversal refused.
code="$(curl -s -o /dev/null -w '%{http_code}' "$LRURL/api/lore/content/2026-06-01-demo/..%2f..%2fitem.md")"
[ "$code" = "404" ] && ok "lore content traversal → 404" || bad "lore content traversal → 404 (got $code)"

# Absent lore skips gracefully (empty items, no crash).
rm -rf "$LRH/.lore"
if curl -fsS "$LRURL/api/lore" | python3 -c 'import sys,json; sys.exit(0 if json.load(sys.stdin)["items"]==[] else 1)'; then
  ok "absent .lore → empty, graceful"
else
  bad "absent .lore → empty, graceful"
fi

lrcleanup

# ============================================================================
echo "== M-: transcript browser (live + archive, read-only) =="

TBFIX="$(mktemp -d)"
TBG="$TBFIX/.gremlin"
mkdir -p "$TBG/transcript-archive"
printf '## user — 2026-06-29T10:00:00Z\nlive question\n\n## assistant — 2026-06-29T10:00:02Z\nlive answer\n' > "$TBG/transcript.md"
printf '## user — 2026-06-26T08:00:00Z\nold question\n\n## assistant — 2026-06-26T08:00:03Z\narchived answer\n' > "$TBG/transcript-archive/2026-06-26.md"

TBPORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
TBURL="http://127.0.0.1:$TBPORT"
rm -f "$BRIDGE_DIR/.cursor" "$BRIDGE_DIR/web.pid" "$BRIDGE_DIR/web.log"
export WEB_GREMLIN_DIR="$TBG" WEB_TRANSCRIPT="$TBG/transcript.md" WEB_PORT="$TBPORT" WEB_BIND="127.0.0.1"
unset WEB_REMOTE_TOKEN

tbcleanup() { "$WEB_SH" stop >/dev/null 2>&1 || true; rm -rf "$TBFIX"; }

if "$WEB_SH" start >/dev/null 2>&1 && poll_until 5 curl -fsS -o /dev/null "$TBURL/"; then
  ok "transcript daemon boots against fixture"
else
  bad "transcript daemon boots against fixture"
fi

# Live view: turns from transcript.md, archive date listed.
if curl -fsS "$TBURL/api/transcript" | python3 -c 'import sys,json
d=json.load(sys.stdin)
sys.exit(0 if d["file"]=="transcript.md" and any(t["body"]=="live answer" for t in d["turns"]) and "2026-06-26" in d["archives"] else 1)'; then
  ok "live transcript turns + archive date listed"
else
  bad "live transcript turns + archive date listed"
fi

# Archive view: that file renders as a document.
if curl -fsS "$TBURL/api/transcript?archive=2026-06-26" | python3 -c 'import sys,json
d=json.load(sys.stdin)
sys.exit(0 if d["archive"]=="2026-06-26" and any(t["body"]=="archived answer" for t in d["turns"]) else 1)'; then
  ok "archive date → that file renders as a document"
else
  bad "archive date → that file renders as a document"
fi

# Bad archive date → 404; the underlying files are never modified.
before="$(cat "$TBG/transcript.md")"
code="$(curl -s -o /dev/null -w '%{http_code}' "$TBURL/api/transcript?archive=../../etc/passwd")"
[ "$code" = "404" ] && [ "$(cat "$TBG/transcript.md")" = "$before" ] \
  && ok "bad archive arg → 404, file unmodified" || bad "bad archive arg → 404, file unmodified (got $code)"

tbcleanup

# ============================================================================
echo "== 95 remote bind (token-gated, off by default) =="

RFIX="$(mktemp -d)"
RG="$RFIX/.gremlin"
mkdir -p "$RG"
: > "$RG/transcript.md"
printf '## system — 2026-06-29T10:00:00Z\n⚙️ run: hi\n' > "$RG/transcript.md"
RPORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.2",0)); print(s.getsockname()[1]); s.close()')"
# 127.0.0.2 is loopback-range but != 127.0.0.1, so the bridge treats it as remote.
RBIND="127.0.0.2"
RURL="http://$RBIND:$RPORT"
TOKEN="s3cr3t-$$"

rcleanup() { "$WEB_SH" stop >/dev/null 2>&1 || true; rm -rf "$RFIX"; }
rm -f "$BRIDGE_DIR/.cursor" "$BRIDGE_DIR/web.pid" "$BRIDGE_DIR/web.log"
export WEB_GREMLIN_DIR="$RG"
export WEB_TRANSCRIPT="$RG/transcript.md"
export WEB_PORT="$RPORT"
export WEB_BIND="$RBIND"

# Non-loopback bind WITHOUT a token → refuses to start, loud.
unset WEB_REMOTE_TOKEN
if "$WEB_SH" start >/dev/null 2>&1; then
  bad "non-loopback bind without token refuses to start"
  "$WEB_SH" stop >/dev/null 2>&1 || true
else
  ok "non-loopback bind without token refuses to start"
fi

# With a token → serves, and every request must present it.
export WEB_REMOTE_TOKEN="$TOKEN"
if "$WEB_SH" start >/dev/null 2>&1 && poll_until 5 curl -fsS -o /dev/null "$RURL/?t=$TOKEN"; then
  ok "remote bind with token serves"
else
  bad "remote bind with token serves"
  cat "$BRIDGE_DIR/web.log" 2>/dev/null | sed 's/^/  /'
fi

# No token → 401.
code="$(curl -s -o /dev/null -w '%{http_code}' "$RURL/")"
[ "$code" = "401" ] && ok "request without token → 401" || bad "request without token → 401 (got $code)"

# Wrong token → 401.
code="$(curl -s -o /dev/null -w '%{http_code}' "$RURL/?t=wrong")"
[ "$code" = "401" ] && ok "wrong token → 401" || bad "wrong token → 401 (got $code)"

# Query token → 200 and sets a cookie.
hdrs="$(curl -s -D - -o /dev/null "$RURL/?t=$TOKEN")"
if printf '%s' "$hdrs" | grep -qi '^HTTP/.* 200' && printf '%s' "$hdrs" | grep -qi 'Set-Cookie: web_token='; then
  ok "valid query token → 200 + bootstraps cookie"
else
  bad "valid query token → 200 + cookie"
fi

# Cookie alone → 200 (the bootstrapped session).
code="$(curl -s -o /dev/null -w '%{http_code}' -H "Cookie: web_token=$TOKEN" "$RURL/poll?cursor=0")"
[ "$code" = "200" ] && ok "cookie token → 200 on a sub-request" || bad "cookie token → 200 (got $code)"

# Header token → 200.
code="$(curl -s -o /dev/null -w '%{http_code}' -H "X-Web-Token: $TOKEN" "$RURL/api/status")"
[ "$code" = "200" ] && ok "X-Web-Token header → 200" || bad "X-Web-Token header → 200 (got $code)"

# Disallowed Host still refused even with a valid token (anti-rebind holds).
code="$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: evil.example' "$RURL/?t=$TOKEN")"
[ "$code" = "403" ] && ok "disallowed Host → 403 even with token" || bad "disallowed Host → 403 with token (got $code)"

rcleanup

# Loopback default is unaffected: no token required.
LFIX="$(mktemp -d)"; : > "$LFIX/transcript.md"
LPORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
rm -f "$BRIDGE_DIR/.cursor" "$BRIDGE_DIR/web.pid" "$BRIDGE_DIR/web.log"
unset WEB_REMOTE_TOKEN
export WEB_GREMLIN_DIR="$LFIX" WEB_TRANSCRIPT="$LFIX/transcript.md" WEB_PORT="$LPORT" WEB_BIND="127.0.0.1"
if "$WEB_SH" start >/dev/null 2>&1 && poll_until 5 curl -fsS -o /dev/null "http://127.0.0.1:$LPORT/"; then
  ok "loopback default unaffected (no token needed)"
else
  bad "loopback default unaffected (no token needed)"
fi
"$WEB_SH" stop >/dev/null 2>&1 || true
rm -rf "$LFIX"

# ============================================================================
echo "== 28 dash: custom views (serve-only lens + jailed static + CSP) =="

# Static teeth: the new arbitrary-path surface must route through under(), and
# the exact-match STATIC dict must NOT have grown a /dash entry (design §3).
if grep -q 'under(vdir' "$SERVER_PY" && grep -q 'def _serve_dash' "$SERVER_PY"; then
  ok "dash static routes through under() (not the STATIC dict)"
else
  bad "dash static must route through under()"
fi
static_block="$(awk '/^STATIC = \{/{f=1} f{print} f&&/^\}/{exit}' "$SERVER_PY")"
if printf '%s' "$static_block" | grep -q 'dash'; then
  bad "STATIC/exact-match must not carry a /dash key (use the jailed route)"
else
  ok "no exact-match /dash key — arbitrary paths go through the jail"
fi
# The view is mounted in a same-origin iframe (failure isolation, frontend).
if grep -q 'dash-frame' "$BRIDGE_DIR/public/app.js" \
  && grep -q 'allow-scripts allow-same-origin' "$BRIDGE_DIR/public/app.js"; then
  ok "views mount in a sandboxed same-origin iframe (failure isolation)"
else
  bad "views must mount in a sandboxed same-origin iframe"
fi

DFIX="$(mktemp -d)"
DH="$DFIX/host"; DG="$DH/.gremlin"
mkdir -p "$DG" "$DH/.dash/hello" "$DH/.dash/noindex" "$DH/.dash/embedview"
: > "$DG/transcript.md"
printf '<!doctype html><title>Hello Dash</title><body><h1>hi</h1><script src="./view.js"></script>\n' > "$DH/.dash/hello/index.html"
printf 'console.log("view");\n' > "$DH/.dash/hello/view.js"
printf '{"generated_at":"2026-07-03T00:00:00Z"}\n' > "$DH/.dash/hello/dashboard-index.json"
printf '<h1>no index here</h1>\n' > "$DH/.dash/noindex/other.html"
# A view opting into the vetted "youtube" embed profile, plus an unknown one that
# must be ignored (never trusted to name a host).
printf '<!doctype html><title>Embed</title><body><h1>vid</h1>\n' > "$DH/.dash/embedview/index.html"
printf '# opt into vetted embed sources\nyoutube\nnope-not-a-profile\n' > "$DH/.dash/embedview/.embeds"
# A secret outside .dash, plus a symlink from inside a view that escapes the jail.
printf 'TOP SECRET\n' > "$DH/secret.txt"
ln -s ../../secret.txt "$DH/.dash/hello/escape"

DPORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
DURL="http://127.0.0.1:$DPORT"
rm -f "$BRIDGE_DIR/.cursor" "$BRIDGE_DIR/web.pid" "$BRIDGE_DIR/web.log"
export WEB_GREMLIN_DIR="$DG" WEB_HOST_DIR="$DH" WEB_TRANSCRIPT="$DG/transcript.md" WEB_PORT="$DPORT" WEB_BIND="127.0.0.1"
unset WEB_REMOTE_TOKEN

dcleanup() { "$WEB_SH" stop >/dev/null 2>&1 || true; rm -rf "$DFIX"; }

if "$WEB_SH" start >/dev/null 2>&1 && poll_until 5 curl -fsS -o /dev/null "$DURL/"; then
  ok "dash daemon boots against fixture"
else
  bad "dash daemon boots against fixture"
  cat "$BRIDGE_DIR/web.log" 2>/dev/null | sed 's/^/  /'
fi

# Discovery: a <name>/ with an index.html is a view; its <title> is the title.
# A dir without index.html (noindex) is NOT listed (filesystem is the registry).
if curl -fsS "$DURL/api/dash" | python3 -c 'import sys,json
env=json.load(sys.stdin)
names={x["name"] for x in env["items"]}
h=[x for x in env["items"] if x["name"]=="hello"]
sys.exit(0 if names=={"hello","embedview"} and "noindex" not in names and h and h[0]["fields"]["title"]=="Hello Dash" else 1)'; then
  ok "discovery lists index.html views with <title>; index-less dir ignored"
else
  bad "discovery lists index.html views with <title>; index-less dir ignored"
fi

# Serve: a bare "<name>/" serves index.html; a co-located asset serves too.
if curl -fsS "$DURL/dash/hello/" | grep -q '<h1>hi</h1>' \
  && curl -fsS "$DURL/dash/hello/view.js" | grep -q 'console.log'; then
  ok "GET /dash/<name>/ serves index.html; assets serve too"
else
  bad "GET /dash/<name>/ serves index.html; assets serve too"
fi

# The view reads its own co-located data through the same jailed route.
if curl -fsS "$DURL/dash/hello/dashboard-index.json" | grep -q 'generated_at'; then
  ok "co-located dashboard-index.json served through the jailed route"
else
  bad "co-located dashboard-index.json served"
fi

# CSP + no-cache headers present on /dash/* (the new wire policy). A view with no
# .embeds marker gets ONLY the locked base — no frame-src/img-src widening.
dh="$(curl -s -D - -o /dev/null "$DURL/dash/hello/index.html")"
if printf '%s' "$dh" | grep -qi "content-security-policy: default-src 'self'" \
  && printf '%s' "$dh" | grep -qi "frame-ancestors 'self'" \
  && printf '%s' "$dh" | grep -qi 'cache-control: no-cache' \
  && ! printf '%s' "$dh" | grep -qi 'frame-src'; then
  ok "CSP (default-src+frame-ancestors 'self') + no-cache on /dash/*; base has no frame-src"
else
  bad "CSP + no-cache header on /dash/* (base locked)"
fi

# A view that opts into the vetted "youtube" profile gets frame-src/img-src widened
# for youtube ONLY — the exfil boundary (default-src/script-src/connect-src) stays
# locked, and an unknown profile name in the same .embeds is ignored.
ecsp="$(curl -s -D - -o /dev/null "$DURL/dash/embedview/index.html" | grep -i 'content-security-policy')"
if printf '%s' "$ecsp" | grep -qi 'frame-src.*youtube.com' \
  && printf '%s' "$ecsp" | grep -qi 'img-src.*i.ytimg.com' \
  && printf '%s' "$ecsp" | grep -qi "default-src 'self'" \
  && ! printf '%s' "$ecsp" | grep -qi 'script-src' \
  && ! printf '%s' "$ecsp" | grep -qi 'connect-src' \
  && ! printf '%s' "$ecsp" | grep -qi 'nope-not-a-profile'; then
  ok "vetted .embeds (youtube) widens frame-src/img-src only; exfil boundary locked; unknown ignored"
else
  bad "embed profile CSP composition: $ecsp"
fi

# Path jail: encoded + literal traversal, and a symlink escaping .dash, all 404.
for bad_path in "..%2f..%2fsecret.txt" "../../secret.txt" "escape"; do
  code="$(curl -s -o /dev/null -w '%{http_code}' "$DURL/dash/hello/$bad_path")"
  [ "$code" = "404" ] || { bad "dash jail breach ($bad_path → $code)"; DJAIL=1; }
done
# And a bad view name / the .dash root itself must not escape.
for bad_path in "../secret.txt" "..%2fsecret.txt"; do
  code="$(curl -s -o /dev/null -w '%{http_code}' "$DURL/dash/$bad_path")"
  [ "$code" = "404" ] || { bad "dash name jail breach ($bad_path → $code)"; DJAIL=1; }
done
if [ -z "${DJAIL:-}" ]; then
  ok "traversal (encoded + literal) + symlink escape + bad name → 404"
fi
# The secret was never served through any of those.
if curl -s "$DURL/dash/hello/../../secret.txt" | grep -q 'TOP SECRET'; then
  bad "the jail LEAKED a file outside .dash"
else
  ok "no file outside .dash was ever served"
fi

# Empty state: with no .dash dir, discovery is empty (the tab shows the invite).
rm -rf "$DH/.dash"
if curl -fsS "$DURL/api/dash" | python3 -c 'import sys,json; sys.exit(0 if json.load(sys.stdin)["items"]==[] else 1)'; then
  ok "absent .dash → empty discovery (invite state), no crash"
else
  bad "absent .dash → empty discovery"
fi

dcleanup

# ============================================================================
echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]

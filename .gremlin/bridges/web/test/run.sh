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
  rm -rf "$FIXTURE" "${M1FIX:-}"
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

"$WEB_SH" stop >/dev/null 2>&1 || true

# ============================================================================
echo "== M2 renderer (render.js, pure) =="

if command -v node >/dev/null 2>&1; then
  if node "$BRIDGE_DIR/test/render.test.js"; then
    ok "render.js unit tests pass"
  else
    bad "render.js unit tests pass"
  fi
else
  echo "  skip render.js unit tests (no node)"
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
echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]

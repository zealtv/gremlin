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
EOF

export WEB_GREMLIN_DIR="$FIXTURE"
export WEB_TRANSCRIPT="$FIXTURE/transcript.md"
export WEB_PORT="$PORT"
export WEB_BIND="127.0.0.1"

cleanup() {
  "$WEB_SH" stop >/dev/null 2>&1 || true
  rm -rf "$FIXTURE"
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
echo
echo "passed: $pass   failed: $fail"
[ "$fail" -eq 0 ]

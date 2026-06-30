#!/usr/bin/env bash
# web.sh - the web bridge daemon (third sibling of telegram.sh / tui.sh).
#
# A thin bash service wrapper around a Python-stdlib HTTP+SSE server. It is the
# same daemon shape telegram.sh uses (nohup/setsid, pidfile, running_pid) but
# carries no secrets: M0 is a read-only transcript window, so config is optional.
# The HTTP layer is transport, never a runtime — it tails transcript.md and
# serves a browser; it never writes a turn and never calls a model.

set -euo pipefail

BRIDGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve GREMLIN_DIR by walking up to the directory that contains `.nest`
# (depth-independent; works from a groundhog-materialized location), not by
# counting `../`. A test may override the whole root via WEB_GREMLIN_DIR.
find_gremlin_dir() {
  if [ -n "${WEB_GREMLIN_DIR:-}" ]; then
    (cd "$WEB_GREMLIN_DIR" && pwd)
    return 0
  fi
  local dir="$BRIDGE_DIR"
  while [ "$dir" != "/" ]; do
    if [ -e "$dir/.nest" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

GREMLIN_DIR="$(find_gremlin_dir)" || {
  echo "web: could not find the host folder (no .nest above $BRIDGE_DIR)" >&2
  exit 1
}
HOST_DIR="$(cd "$GREMLIN_DIR/.." && pwd)"
CONFIG="$BRIDGE_DIR/config"
LOG="$BRIDGE_DIR/web.log"
PIDFILE="$BRIDGE_DIR/web.pid"
CURSOR="$BRIDGE_DIR/.cursor"
PUBLIC_DIR="$BRIDGE_DIR/public"
CACHE_DIR="$BRIDGE_DIR/.cache"
SERVER="$BRIDGE_DIR/server.py"
TRANSCRIPT="${WEB_TRANSCRIPT:-$GREMLIN_DIR/transcript.md}"
NESTLING="${WEB_NESTLING:-$GREMLIN_DIR/.nest/nestling.sh}"
STOP_TIMEOUT="${WEB_STOP_TIMEOUT:-15}"

# Defaults; config (if present) and the environment may override these.
# WEB_PORT is intentionally left unset here: an unset port is auto-assigned and
# pinned per host on first start (see ensure_port), so multiple gremlins sharing
# a machine don't collide on one number. An explicit WEB_PORT (env or config) is
# honored as-is and still fails loud if it's taken.
WEB_BIND="${WEB_BIND:-127.0.0.1}"

usage() {
  cat <<'USAGE'
usage:
  ./.gremlin/gremlin web start
  ./.gremlin/gremlin web stop
  ./.gremlin/gremlin web status
  ./.gremlin/gremlin web restart
  ./.gremlin/gremlin web run
  ./.gremlin/gremlin web help
USAGE
}

die() {
  echo "web: $*" >&2
  exit 1
}

load_config() {
  # Unlike telegram, config is optional: M0 has no secret to require. When
  # present it may set WEB_BIND / WEB_PORT / WEB_REMOTE_TOKEN (token gating
  # arrives with remote binding, a later stitch).
  [ -f "$CONFIG" ] || return 0
  # shellcheck disable=SC1090
  set -a
  . "$CONFIG"
  set +a
}

is_loopback_bind() {
  case "$WEB_BIND" in
    127.0.0.1 | ::1 | localhost | "") return 0 ;;
    *) return 1 ;;
  esac
}

# Off-by-default remote binding: a non-loopback bind without a token is refused
# loudly, before spawning the daemon (spec §17).
require_remote_safety() {
  if ! is_loopback_bind && [ -z "${WEB_REMOTE_TOKEN:-}" ]; then
    die "refusing to bind non-loopback $WEB_BIND without WEB_REMOTE_TOKEN; set it in $CONFIG (an SSH tunnel / WireGuard is the safer path — see README)."
  fi
}

# First free TCP port at or above $1 on the loopback address, probing a small
# window. Matches how server.py binds (SO_REUSEADDR, like ThreadingHTTPServer's
# allow_reuse_address) so a port held by a *live* listener is correctly skipped
# while a TIME_WAIT one is reusable. Empty output + non-zero on exhaustion.
find_free_port() {
  python3 - "$1" <<'PY'
import socket, sys
start = int(sys.argv[1])
for port in range(start, start + 64):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(("127.0.0.1", port))
    except OSError:
        continue
    finally:
        s.close()
    print(port)
    sys.exit(0)
sys.exit(1)
PY
}

# Assign and persist a web-bridge port the first time, so several gremlins on one
# host coexist and the choice survives reboots and `/update` (config is local
# state the overlay preserves). No-op when WEB_PORT is already set, so an
# explicit port — env or a prior pin — is honored untouched.
#
# The preferred start is derived from the gremlin's identity (its host-dir name,
# the same identifier the web header shows), so each gremlin gravitates to its
# own stable number even before anything is pinned; we then probe upward for the
# first free port and write it back to config.
ensure_port() {
  [ -n "${WEB_PORT:-}" ] && return 0
  local id sum pref port
  id="$(basename "$HOST_DIR")"
  sum="$(printf '%s' "$id" | cksum | cut -d' ' -f1)"
  pref=$(( 8787 + sum % 200 ))
  port="$(find_free_port "$pref")" \
    || die "no free port found in [$pref, $((pref + 64))) for the web bridge; set WEB_PORT in $CONFIG"
  WEB_PORT="$port"
  if [ ! -f "$CONFIG" ]; then
    ( umask 077; printf '# web bridge config (auto-created on first start)\n' > "$CONFIG" )
  fi
  printf 'WEB_PORT=%s\n' "$port" >> "$CONFIG"
  chmod 600 "$CONFIG" 2>/dev/null || true
  echo "web: assigned port $port for '$id' (pinned in $CONFIG)" >&2
}

require_runtime() {
  command -v python3 >/dev/null 2>&1 || die "python3 is required for the web bridge"
  python3 - <<'PY' || die "python3 >= 3.8 is required for the web bridge"
import sys
sys.exit(0 if sys.version_info >= (3, 8) else 1)
PY
  [ -f "$SERVER" ] || die "server not found: $SERVER"
}

pid_is_running() {
  local pid="${1:-}"
  [ -n "$pid" ] || return 1
  kill -0 "$pid" 2>/dev/null
}

read_pid() {
  if [ -s "$PIDFILE" ]; then
    sed -n '1p' "$PIDFILE"
  fi
}

running_pid() {
  local pid
  pid="$(read_pid || true)"
  if pid_is_running "$pid"; then
    printf '%s\n' "$pid"
  fi
}

cmd_run() {
  load_config
  require_runtime
  ensure_port
  require_remote_safety
  export WEB_BIND WEB_PORT WEB_REMOTE_TOKEN WEB_REMOTE_HOST
  export WEB_GREMLIN_DIR="$GREMLIN_DIR"
  export WEB_HOST_DIR="$HOST_DIR"
  export WEB_TRANSCRIPT="$TRANSCRIPT"
  export WEB_CURSOR="$CURSOR"
  export WEB_PUBLIC_DIR="$PUBLIC_DIR"
  export WEB_CACHE_DIR="$CACHE_DIR"
  export WEB_NESTLING="$NESTLING"
  echo "web bridge daemon started"
  echo "bind: $WEB_BIND:$WEB_PORT"
  echo "transcript: $TRANSCRIPT"
  exec python3 "$SERVER"
}

cmd_start() {
  local pid
  pid="$(running_pid || true)"
  if [ -n "$pid" ]; then
    echo "web bridge already running: $pid"
    exit 1
  fi

  load_config
  require_runtime
  ensure_port
  require_remote_safety
  if ! is_loopback_bind; then
    echo "⚠️  binding non-loopback $WEB_BIND:$WEB_PORT — the gremlin's chat + files"
    echo "    will be reachable (with the token) by anyone who can route to that"
    echo "    address. Traffic is cleartext unless tunneled."
  fi

  if command -v setsid >/dev/null 2>&1; then
    nohup setsid "$0" run >> "$LOG" 2>&1 < /dev/null &
  else
    nohup "$0" run >> "$LOG" 2>&1 < /dev/null &
  fi
  pid="$!"
  printf '%s\n' "$pid" > "$PIDFILE"
  disown "$pid" 2>/dev/null || true

  sleep 0.3
  if ! pid_is_running "$pid"; then
    rm -f "$PIDFILE"
    die "web bridge failed to start; see $LOG"
  fi

  echo "started web bridge: $pid"
  echo "url: http://$WEB_BIND:$WEB_PORT"
  echo "log: $LOG"
}

cmd_stop() {
  local pid deadline
  pid="$(running_pid || true)"
  if [ -z "$pid" ]; then
    rm -f "$PIDFILE"
    echo "web bridge not running"
    return 0
  fi

  kill "$pid" 2>/dev/null || true
  deadline=$(( $(date +%s) + STOP_TIMEOUT ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if ! pid_is_running "$pid"; then
      rm -f "$PIDFILE"
      echo "stopped web bridge"
      return 0
    fi
    sleep 0.2
  done

  echo "sent stop signal, but web bridge still appears active: $pid" >&2
  exit 1
}

cmd_status() {
  local pid configured="unconfigured"
  [ -f "$CONFIG" ] && configured="configured"
  load_config
  pid="$(running_pid || true)"
  if [ -n "$pid" ]; then
    echo "web bridge running: $pid ($configured, http://$WEB_BIND:$WEB_PORT)"
  else
    echo "web bridge stopped ($configured)"
  fi
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  start) cmd_start "$@" ;;
  stop) cmd_stop "$@" ;;
  status) cmd_status "$@" ;;
  restart)
    cmd_stop
    cmd_start
    ;;
  run) cmd_run "$@" ;;
  help|-h|--help) usage ;;
  *)
    usage >&2
    exit 2
    ;;
esac

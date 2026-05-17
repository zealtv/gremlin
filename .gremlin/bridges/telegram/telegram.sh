#!/usr/bin/env bash
# telegram.sh - Telegram bridge daemon.
#
# Reads Telegram updates and writes inbound text to .nest/in/. Later
# implementation stitches fill in API polling and transcript fan-out; this file
# first establishes the service shape used by the gremlin wrapper.

set -euo pipefail

if [ "${LC_ALL:-}" = "C.UTF-8" ]; then
  unset LC_ALL
fi

BRIDGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREMLIN_DIR="$(cd "$BRIDGE_DIR/../.." && pwd)"
CONFIG="$BRIDGE_DIR/config"
LOG="$BRIDGE_DIR/telegram.log"
PIDFILE="$BRIDGE_DIR/telegram.pid"
CURSOR="$BRIDGE_DIR/.cursor"
UPDATE_OFFSET="$BRIDGE_DIR/.update-offset"
NESTLING="${TELEGRAM_NESTLING:-$GREMLIN_DIR/.nest/nestling.sh}"
TRANSCRIPT="${TELEGRAM_TRANSCRIPT:-$GREMLIN_DIR/transcript.md}"
POLL_TIMEOUT="${TELEGRAM_POLL_TIMEOUT:-30}"
POLL_SLEEP="${TELEGRAM_POLL_SLEEP:-1}"
OUTBOUND_BACKOFF="${TELEGRAM_OUTBOUND_BACKOFF:-5}"
PUSH_INTERVAL="${TELEGRAM_PUSH_INTERVAL:-1}"
PULSE_INTERVAL="${TELEGRAM_PULSE_INTERVAL:-4}"
STOP_TIMEOUT="${TELEGRAM_STOP_TIMEOUT:-35}"

usage() {
  cat <<'USAGE'
usage:
  ./.gremlin/gremlin telegram start
  ./.gremlin/gremlin telegram stop
  ./.gremlin/gremlin telegram status
  ./.gremlin/gremlin telegram restart
  ./.gremlin/gremlin telegram run
  ./.gremlin/gremlin telegram poll-once
  ./.gremlin/gremlin telegram push-once
  ./.gremlin/gremlin telegram help
USAGE
}

die() {
  echo "telegram: $*" >&2
  exit 1
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

load_config() {
  [ -f "$CONFIG" ] || die "missing config: $CONFIG"

  # shellcheck disable=SC1090
  set -a
  . "$CONFIG"
  set +a

  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] || die "TELEGRAM_BOT_TOKEN is not set in config"
  [ -n "${TELEGRAM_CHAT_ID:-}" ] || die "TELEGRAM_CHAT_ID is not set in config"
}

require_runtime() {
  command -v curl >/dev/null 2>&1 || die "curl is required for the Telegram bridge"
  command -v jq >/dev/null 2>&1 || die "jq is required for the Telegram bridge"
  [ -x "$NESTLING" ] || die "nestling not executable: $NESTLING"
}

read_update_offset() {
  if [ -s "$UPDATE_OFFSET" ]; then
    sed -n '1p' "$UPDATE_OFFSET"
  else
    printf '0\n'
  fi
}

write_update_offset() {
  printf '%s\n' "$1" > "$UPDATE_OFFSET"
}

telegram_api() {
  printf 'https://api.telegram.org/bot%s/%s\n' "$TELEGRAM_BOT_TOKEN" "$1"
}

get_updates() {
  local offset="$1"
  if [ -n "${TELEGRAM_TEST_UPDATES_FILE:-}" ]; then
    cat "$TELEGRAM_TEST_UPDATES_FILE"
    return 0
  fi

  curl -fsS --get \
    --data-urlencode "offset=$offset" \
    --data-urlencode "timeout=$POLL_TIMEOUT" \
    "$(telegram_api getUpdates)"
}

send_message() {
  local text="$1"
  local response ok description

  if [ -n "${TELEGRAM_TEST_SEND_FAIL:-}" ]; then
    echo "telegram: mock send failure" >&2
    return 1
  fi

  if [ -n "${TELEGRAM_TEST_SEND_LOG:-}" ]; then
    {
      printf '%s\n' "---"
      printf '%s\n' "$text"
    } >> "$TELEGRAM_TEST_SEND_LOG"
    return 0
  fi

  response="$(curl -fsS -X POST \
    --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
    --data-urlencode "text=$text" \
    "$(telegram_api sendMessage)")" || return 1

  ok="$(printf '%s\n' "$response" | jq -r '.ok')"
  if [ "$ok" != "true" ]; then
    description="$(printf '%s\n' "$response" | jq -r '.description? // "unknown Telegram API error"')"
    echo "telegram: sendMessage failed: $description" >&2
    return 1
  fi
}

send_chat_action() {
  local action="$1"
  local response ok description

  if [ -n "${TELEGRAM_TEST_SEND_FAIL:-}" ]; then
    echo "telegram: mock chat action failure" >&2
    return 1
  fi

  if [ -n "${TELEGRAM_TEST_SEND_LOG:-}" ]; then
    {
      printf '%s\n' "---"
      printf 'action=%s\n' "$action"
    } >> "$TELEGRAM_TEST_SEND_LOG"
    return 0
  fi

  response="$(curl -fsS -X POST \
    --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
    --data-urlencode "action=$action" \
    "$(telegram_api sendChatAction)")" || return 1

  ok="$(printf '%s\n' "$response" | jq -r '.ok')"
  if [ "$ok" != "true" ]; then
    description="$(printf '%s\n' "$response" | jq -r '.description? // "unknown Telegram API error"')"
    echo "telegram: sendChatAction failed: $description" >&2
    return 1
  fi
}

file_size() {
  local size
  if [ -f "$1" ]; then
    size="$(wc -c < "$1")"
    size="${size//[!0-9]/}"
    printf '%s\n' "${size:-0}"
  else
    printf '0\n'
  fi
}

read_cursor() {
  if [ -s "$CURSOR" ]; then
    sed -n '1p' "$CURSOR"
  else
    printf '%s\n' "$(file_size "$TRANSCRIPT")"
  fi
}

write_cursor() {
  printf '%s\n' "$1" > "$CURSOR"
}

ensure_cursor() {
  if [ ! -s "$CURSOR" ]; then
    write_cursor "$(file_size "$TRANSCRIPT")"
  fi
}

extract_pushable_turns() {
  awk '
    /^## / {
      if (role != "") {
        sub(/\n$/, "", body)
        print body "\034"
      }
      role = ""
      body = ""
      if ($0 ~ /^## assistant[[:space:]]/) {
        role = "assistant"
      } else if ($0 ~ /^## system[[:space:]]/) {
        role = "system"
      }
      next
    }
    role != "" {
      body = body $0 "\n"
    }
    END {
      if (role != "") {
        sub(/\n$/, "", body)
        print body "\034"
      }
    }
  '
}

push_transcript_once() {
  local cursor size chunk sent_any=0 turn

  load_config
  require_runtime

  size="$(file_size "$TRANSCRIPT")"
  ensure_cursor
  cursor="$(read_cursor)"

  if [ "$cursor" -gt "$size" ] 2>/dev/null; then
    cursor="$size"
    write_cursor "$cursor"
  fi

  if [ "$cursor" -eq "$size" ] 2>/dev/null; then
    return 0
  fi

  chunk="$(tail -c +"$((cursor + 1))" "$TRANSCRIPT")"
  while IFS= read -r -d "$(printf '\034')" turn; do
    [ -n "$turn" ] || continue
    send_message "$turn" || return 1
    sent_any=1
  done < <(printf '%s\n' "$chunk" | extract_pushable_turns)

  write_cursor "$size"
  if [ "$sent_any" -eq 1 ]; then
    echo "pushed transcript turns through byte $size"
  fi
}

ingest_text() {
  local update_id="$1"
  local text="$2"
  local tmp name suffix

  tmp="$(mktemp "$BRIDGE_DIR/telegram-inbound.XXXXXX")"
  suffix="$(basename "$tmp")"
  suffix="${suffix#telegram-inbound.}"
  printf '%s\n' "$text" > "$tmp"
  name="$(date -u +%Y%m%dT%H%M%SZ)-telegram-$suffix.md"
  "$NESTLING" ingest "$tmp" "$name" >/dev/null
  rm -f "$tmp"
  echo "ingested telegram text as $name"
}

handle_update() {
  local update="$1"
  local update_id chat_id text next_offset

  update_id="$(printf '%s\n' "$update" | jq -r '.update_id')"
  next_offset=$((update_id + 1))

  chat_id="$(printf '%s\n' "$update" | jq -r '.message.chat.id? // empty')"
  text="$(printf '%s\n' "$update" | jq -r '.message.text? // empty')"

  if [ -z "$chat_id" ]; then
    echo "ignored telegram update: no message chat"
    write_update_offset "$next_offset"
    return 0
  fi

  if [ "$chat_id" != "$TELEGRAM_CHAT_ID" ]; then
    echo "ignored telegram update: chat not configured"
    write_update_offset "$next_offset"
    return 0
  fi

  if [ -z "$text" ]; then
    echo "ignored telegram update: non-text message"
    write_update_offset "$next_offset"
    return 0
  fi

  if [ "${text#/}" != "$text" ]; then
    handle_slash "$update_id" "$text"
    write_update_offset "$next_offset"
    return 0
  fi

  ingest_text "$update_id" "$text"
  write_update_offset "$next_offset"
}

handle_slash() {
  local update_id="$1"
  local text="$2"
  local output rc

  set +e
  output="$("$GREMLIN_DIR/bin/slash.sh" "$text" 2>&1)"
  rc=$?
  set -e

  if [ -z "$output" ]; then
    if [ "$rc" -eq 0 ]; then
      output="(no output)"
    else
      output="(command exited $rc)"
    fi
  fi

  if ! send_message "$output"; then
    echo "telegram: failed to send slash reply for update $update_id" >&2
  fi
  echo "ran telegram slash command (rc=$rc)"
}

poll_once() {
  local offset response updates update ok description

  load_config
  require_runtime

  offset="$(read_update_offset)"
  response="$(get_updates "$offset")"
  ok="$(printf '%s\n' "$response" | jq -r '.ok')"
  if [ "$ok" != "true" ]; then
    description="$(printf '%s\n' "$response" | jq -r '.description? // "unknown Telegram API error"')"
    echo "telegram: getUpdates failed: $description" >&2
    return 1
  fi

  updates="$(printf '%s\n' "$response" | jq -c '.result[]?')"
  if [ -z "$updates" ]; then
    return 0
  fi

  while IFS= read -r update; do
    [ -n "$update" ] || continue
    handle_update "$update"
  done <<EOF_UPDATES
$updates
EOF_UPDATES
}

cmd_status() {
  local pid configured="configured"
  [ -f "$CONFIG" ] || configured="unconfigured"

  pid="$(running_pid || true)"
  if [ -n "$pid" ]; then
    echo "telegram bridge running: $pid ($configured)"
  else
    echo "telegram bridge stopped ($configured)"
  fi
}

cmd_start() {
  local pid
  pid="$(running_pid || true)"
  if [ -n "$pid" ]; then
    echo "telegram bridge already running: $pid"
    exit 1
  fi

  load_config

  nohup "$0" run >> "$LOG" 2>&1 &
  pid="$!"
  printf '%s\n' "$pid" > "$PIDFILE"
  disown "$pid" 2>/dev/null || true

  sleep 0.2
  if ! pid_is_running "$pid"; then
    rm -f "$PIDFILE"
    die "telegram bridge failed to start; see $LOG"
  fi

  echo "started telegram bridge: $pid"
  echo "log: $LOG"
}

cmd_stop() {
  local pid deadline
  pid="$(running_pid || true)"
  if [ -z "$pid" ]; then
    rm -f "$PIDFILE"
    echo "telegram bridge not running"
    return 0
  fi

  kill "$pid" 2>/dev/null || true
  deadline=$(( $(date +%s) + STOP_TIMEOUT ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if ! pid_is_running "$pid"; then
      rm -f "$PIDFILE"
      echo "stopped telegram bridge"
      return 0
    fi
    sleep 0.2
  done

  echo "sent stop signal, but telegram bridge still appears active: $pid" >&2
  exit 1
}

inbound_loop() {
  while :; do
    if ! poll_once; then
      echo "telegram poll failed; retrying after $POLL_SLEEP seconds" >&2
      sleep "$POLL_SLEEP" &
      wait "$!" || true
    fi
  done
}

outbound_loop() {
  while :; do
    if push_transcript_once; then
      sleep "$PUSH_INTERVAL" &
      wait "$!" || true
    else
      echo "telegram outbound failed; retrying after $OUTBOUND_BACKOFF seconds" >&2
      sleep "$OUTBOUND_BACKOFF" &
      wait "$!" || true
    fi
  done
}

pulser_loop() {
  while :; do
    if compgen -G "$GREMLIN_DIR/.nest/in/*-telegram-*.md*" >/dev/null; then
      send_chat_action typing || true
    fi
    sleep "$PULSE_INTERVAL" &
    wait "$!" || true
  done
}

cmd_run() {
  load_config
  require_runtime
  echo "telegram bridge daemon started"
  echo "config: $CONFIG"
  echo "cursor: $CURSOR"
  echo "update offset: $UPDATE_OFFSET"
  echo "transcript: $TRANSCRIPT"
  ensure_cursor

  inbound_loop &
  local inbound_pid=$!
  outbound_loop &
  local outbound_pid=$!
  pulser_loop &
  local pulser_pid=$!

  trap 'echo "telegram bridge daemon stopping"; kill '"$inbound_pid $outbound_pid $pulser_pid"' 2>/dev/null; wait; exit 0' INT TERM

  local pid
  while :; do
    for pid in "$inbound_pid" "$outbound_pid" "$pulser_pid"; do
      if ! kill -0 "$pid" 2>/dev/null; then
        echo "telegram loop $pid exited unexpectedly; shutting down supervisor" >&2
        kill "$inbound_pid" "$outbound_pid" "$pulser_pid" 2>/dev/null || true
        wait || true
        exit 1
      fi
    done
    sleep 1 &
    wait "$!" || true
  done
}

cmd="${1:-help}"
shift || true

case "$cmd" in
  start)
    cmd_start "$@"
    ;;
  stop)
    cmd_stop "$@"
    ;;
  status)
    cmd_status "$@"
    ;;
  restart)
    cmd_stop
    cmd_start
    ;;
  run)
    cmd_run "$@"
    ;;
  poll-once)
    poll_once "$@"
    ;;
  push-once)
    push_transcript_once "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

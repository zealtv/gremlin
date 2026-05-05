#!/usr/bin/env bash
# tui.sh — dependency-free terminal bridge.
#
# Reads transcript.md, writes user messages into .nest/in/, and renders
# slash command output ephemerally. The tender owns transcript writes.

set -euo pipefail

BRIDGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREMLIN_DIR="$(cd "$BRIDGE_DIR/../.." && pwd)"
NESTLING="$GREMLIN_DIR/.nest/nestling.sh"
TRANSCRIPT="$GREMLIN_DIR/transcript.md"
COMMANDS="$GREMLIN_DIR/commands"
CURSOR="$BRIDGE_DIR/.cursor"

POLL_SECS=0.15
MAX_LINES=500

if [ ! -t 0 ] || [ ! -t 1 ]; then
  echo "tui.sh requires an interactive terminal" >&2
  exit 2
fi

if ! command -v tput >/dev/null 2>&1; then
  echo "tui.sh requires tput" >&2
  exit 2
fi

display_lines=()
input=""
pending=""
pending_since=0
status="idle"
tick=0
old_stty="$(stty -g)"

cleanup() {
  stty "$old_stty" 2>/dev/null || true
  tput cnorm 2>/dev/null || true
  tput sgr0 2>/dev/null || true
  tput clear 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM

stty -echo -icanon -ixon min 0 time 0
tput civis

color() {
  tput setaf "$1" 2>/dev/null || true
}

bold() {
  tput bold 2>/dev/null || true
}

dim() {
  tput dim 2>/dev/null || true
}

reset() {
  tput sgr0 2>/dev/null || true
}

face() {
  local frame="$1"
  case "$status:$frame" in
    pending:0) printf '^o_o^' ;;
    pending:1) printf '^-_-^' ;;
    pending:2) printf '^o_-^' ;;
    pending:*) printf '^*_*^' ;;
    *:1) printf '^-_-^' ;;
    *) printf '^o_o^' ;;
  esac
}

append_line() {
  display_lines+=("$1")
  while [ "${#display_lines[@]}" -gt "$MAX_LINES" ]; do
    display_lines=("${display_lines[@]:1}")
  done
}

file_size() {
  if [ -f "$1" ]; then
    wc -c < "$1" | tr -d ' '
  else
    printf '0\n'
  fi
}

read_cursor() {
  local size offset
  size="$(file_size "$TRANSCRIPT")"
  if [ -f "$CURSOR" ]; then
    offset="$(tr -cd '0-9' < "$CURSOR")"
  else
    offset=0
  fi
  [ -n "$offset" ] || offset=0
  if [ "$offset" -gt "$size" ]; then
    offset=0
  fi
  printf '%s\n' "$offset"
}

write_cursor() {
  printf '%s\n' "$1" > "$CURSOR"
}

trim_blank_tail() {
  while [ "${#display_lines[@]}" -gt 0 ]; do
    local last_index last
    last_index=$((${#display_lines[@]} - 1))
    last="${display_lines[$last_index]}"
    [ -n "$last" ] && break
    unset 'display_lines[$last_index]'
    display_lines=("${display_lines[@]}")
  done
}

maybe_clear_pending() {
  local role="$1"
  local body="$2"
  if [ "$role" = "user" ] && [ -n "$pending" ] && [ "$body" = "$pending" ]; then
    pending=""
    pending_since=0
    status="idle"
  fi
}

render_turn() {
  local role="$1"
  local ts="$2"
  local body="$3"
  local label_color=6
  [ "$role" = "assistant" ] && label_color=2

  trim_blank_tail
  append_line ""
  append_line "$(bold)$(color "$label_color")$role$(reset) $(dim)$ts$(reset)"

  if [ -n "$body" ]; then
    while IFS= read -r line; do
      append_line "$line"
    done <<EOF_BODY
$body
EOF_BODY
  fi

  maybe_clear_pending "$role" "$body"
}

poll_transcript() {
  local offset size bytes chunk parsed line turn_role turn_ts turn_body

  offset="$(read_cursor)"
  size="$(file_size "$TRANSCRIPT")"
  [ "$size" -gt "$offset" ] || return 0

  bytes=$((size - offset))
  chunk="$(mktemp)"
  parsed="$(mktemp)"
  tail -c "$bytes" "$TRANSCRIPT" > "$chunk"

  awk '
    function emit() {
      if (role == "") return
      sub(/\n+$/, "", body)
      print "__GREMLIN_TURN__\t" role "\t" ts
      if (body != "") print body
      print "__GREMLIN_END__"
    }
    /^## (user|assistant) — / {
      emit()
      role=$2
      ts=$0
      sub(/^## (user|assistant) — /, "", ts)
      body=""
      next
    }
    role != "" {
      if (body == "") body=$0
      else body=body "\n" $0
    }
    END { emit() }
  ' "$chunk" > "$parsed"

  turn_role=""
  turn_ts=""
  turn_body=""
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "__GREMLIN_TURN__	"*)
        turn_role="${line#*	}"
        turn_ts="${turn_role#*	}"
        turn_role="${turn_role%%	*}"
        turn_body=""
        ;;
      "__GREMLIN_END__")
        render_turn "$turn_role" "$turn_ts" "$turn_body"
        turn_role=""
        turn_ts=""
        turn_body=""
        ;;
      *)
        if [ -n "$turn_role" ]; then
          if [ -z "$turn_body" ]; then
            turn_body="$line"
          else
            turn_body="${turn_body}"$'\n'"$line"
          fi
        fi
        ;;
    esac
  done < "$parsed"
  rm -f "$chunk" "$parsed"

  write_cursor "$size"
}

unique_item_name() {
  local base n candidate
  base="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
  candidate="$base.md"
  n=1
  while [ -e "$GREMLIN_DIR/.nest/in/$candidate" ] || [ -e "$GREMLIN_DIR/.nest/in/$candidate.landing" ]; do
    candidate="$base-$n.md"
    n=$((n + 1))
  done
  printf '%s\n' "$candidate"
}

submit_message() {
  local msg="$1"
  local tmp name
  [ -n "$msg" ] || return 0
  tmp="$(mktemp)"
  printf '%s\n' "$msg" > "$tmp"
  name="$(unique_item_name)"
  if "$NESTLING" ingest "$tmp" "$name" >/dev/null 2>&1; then
    pending="$msg"
    pending_since="$(date +%s)"
    status="pending"
  else
    append_line "$(color 1)failed to submit message$(reset)"
  fi
  rm -f "$tmp"
}

run_slash() {
  local line="$1"
  local rest cmd args output rc
  rest="${line#/}"
  cmd="${rest%% *}"

  if [ -z "$cmd" ]; then
    append_line "$(color 1)usage: /<command> [args...]$(reset)"
    return 0
  fi

  if [ "$cmd" = "$rest" ]; then
    args=()
  else
    # Match the small, space-separated command convention used by scripts.
    # shellcheck disable=SC2206
    args=(${rest#"$cmd "})
  fi

  if [ ! -x "$COMMANDS/$cmd.sh" ]; then
    append_line "$(color 1)unknown command: /$cmd$(reset)"
    append_line "$(dim)try /help$(reset)"
    return 0
  fi

  set +e
  output="$("$COMMANDS/$cmd.sh" "${args[@]}" 2>&1)"
  rc=$?
  set -e

  append_line ""
  append_line "$(bold)$(color 5)/$cmd$(reset) $(dim)command output$(reset)"
  if [ -n "$output" ]; then
    while IFS= read -r out_line; do
      append_line "$out_line"
    done <<EOF_OUTPUT
$output
EOF_OUTPUT
  fi
  if [ "$rc" -ne 0 ]; then
    append_line "$(color 1)command exited $rc$(reset)"
  fi
}

handle_enter() {
  local line="$input"
  input=""
  [ -n "$line" ] || return 0

  case "$line" in
    /*) run_slash "$line" ;;
    *)
      if [ -n "$pending" ]; then
        append_line "$(color 3)message still pending; wait for the user turn to land$(reset)"
        input="$line"
      else
        submit_message "$line"
      fi
      ;;
  esac
}

handle_key() {
  local key="$1"
  case "$key" in
    $'\003'|$'\004'|$'\021')
      exit 0
      ;;
    $'\r'|$'\n')
      handle_enter
      ;;
    $'\177'|$'\b')
      if [ -n "$input" ]; then
        input="${input%?}"
      fi
      ;;
    $'\033')
      # Ignore escape sequences for now.
      read -r -s -n 2 -d '' -t 0.001 _rest || true
      ;;
    *)
      input="$input$key"
      ;;
  esac
}

redraw() {
  local rows cols frame body_rows start i line prompt shown_input mode_text pending_age
  rows="$(tput lines)"
  cols="$(tput cols)"
  [ "$rows" -lt 8 ] && rows=8
  [ "$cols" -lt 30 ] && cols=30

  frame=$((tick % 4))
  tick=$((tick + 1))
  body_rows=$((rows - 4))
  start=0
  if [ "${#display_lines[@]}" -gt "$body_rows" ]; then
    start=$((${#display_lines[@]} - body_rows))
  fi

  tput clear

  printf '%s%s gremlin tui %s%s\n' "$(bold)" "$(color 2)" "$(face "$frame")" "$(reset)"

  i="$start"
  while [ "$i" -lt "${#display_lines[@]}" ] && [ "$i" -lt "$((start + body_rows))" ]; do
    line="${display_lines[$i]}"
    printf '%s\n' "$line"
    i=$((i + 1))
  done

  tput cup "$((rows - 3))" 0
  printf '%s' "$(dim)"
  printf '%*s\n' "$cols" '' | tr ' ' '-'
  printf '%s' "$(reset)"

  tput cup "$((rows - 2))" 0
  mode_text="idle"
  if [ -n "$pending" ]; then
    pending_age=$(( $(date +%s) - pending_since ))
    mode_text="pending ${pending_age}s $(face "$frame")"
  fi
  printf '%s%s%s\n' "$(dim)" "$mode_text" "$(reset)"

  tput cup "$((rows - 1))" 0
  prompt='> '
  shown_input="$input"
  if [ -n "$pending" ]; then
    shown_input="$pending"
    printf '%s%s%s%s' "$prompt" "$(dim)" "$shown_input" "$(reset)"
  else
    printf '%s%s' "$prompt" "$shown_input"
  fi
}

poll_transcript
append_line "$(dim)Ctrl-D exits. Slash commands render here only.$(reset)"

while :; do
  poll_transcript
  redraw
  key=""
  if IFS= read -r -s -n 1 -d '' -t "$POLL_SECS" key; then
    if [ -z "$key" ]; then
      handle_enter
    else
      handle_key "$key"
    fi
  fi
done

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

POLL_SECS=0.15
MAX_LINES=500
MIN_ROWS=10
MIN_COLS=30

if [ ! -t 0 ] || [ ! -t 1 ]; then
  echo "tui.sh requires an interactive terminal" >&2
  exit 2
fi

if ! command -v tput >/dev/null 2>&1; then
  echo "tui.sh requires tput" >&2
  exit 2
fi

raw_lines=()
input=""
pending=""
pending_since=0
status="idle"
tick=0
transcript_offset=0
transcript_size=0
transcript_turns=0
model="default"
rows=24
cols=80
old_stty="$(stty -g)"

cleanup() {
  printf '\033]0;\007'
  tput rmcup 2>/dev/null || true
  stty "$old_stty" 2>/dev/null || true
  tput cnorm 2>/dev/null || true
  tput sgr0 2>/dev/null || true
  tput clear 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT TERM

update_size() {
  local size
  size="$(stty size 2>/dev/null || true)"
  if [ -n "$size" ]; then
    rows="${size%% *}"
    cols="${size##* }"
  fi
  [ "$rows" -lt "$MIN_ROWS" ] && rows="$MIN_ROWS"
  [ "$cols" -lt "$MIN_COLS" ] && cols="$MIN_COLS"
  return 0
}
trap update_size WINCH

tput smcup 2>/dev/null || true
printf '\033]0;gremlin tui\007'
stty -echo -icanon -ixon min 0 time 0
tput civis
update_size

cup() {
  printf '\033[%s;%sH' "$(($1 + 1))" "$(($2 + 1))"
}

el() {
  printf '\033[K'
}

color() {
  printf '\033[38;5;%sm' "$1"
}

bg() {
  printf '\033[48;5;%sm' "$1"
}

bold() {
  printf '\033[1m'
}

dim() {
  printf '\033[2m'
}

reset() {
  printf '\033[0m'
}

face() {
  local frame="$1"
  case "$status:$frame" in
    pending:0) printf '^o_o^' ;;
    pending:1) printf '^-_-^' ;;
    pending:2) printf '^o_-^' ;;
    pending:*) printf '^*_*^' ;;
    *) printf '^o_o^' ;;
  esac
}

append_line() {
  raw_lines+=("$1")
  while [ "${#raw_lines[@]}" -gt "$MAX_LINES" ]; do
    raw_lines=("${raw_lines[@]:1}")
  done
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

current_model() {
  if [ -s "$GREMLIN_DIR/.model" ]; then
    tr -d '[:space:]' < "$GREMLIN_DIR/.model"
  else
    printf 'default\n'
  fi
}

refresh_model() {
  model="$(current_model)"
}

trim_blank_tail() {
  while [ "${#raw_lines[@]}" -gt 0 ]; do
    local last_index last
    last_index=$((${#raw_lines[@]} - 1))
    last="${raw_lines[$last_index]}"
    [ -n "$last" ] && break
    unset 'raw_lines[$last_index]'
    raw_lines=("${raw_lines[@]}")
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
  local label_color=81
  [ "$role" = "assistant" ] && label_color=213

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

  size="$(file_size "$TRANSCRIPT")"
  if [ "$size" -lt "$transcript_offset" ]; then
    raw_lines=()
    transcript_offset=0
    transcript_turns=0
  fi

  offset="$transcript_offset"
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
        transcript_turns=$((transcript_turns + 1))
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

  transcript_offset="$size"
  transcript_size="$size"
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
    append_line "$(color 203)failed to submit message$(reset)"
  fi
  rm -f "$tmp"
}

run_slash() {
  local line="$1"
  local rest cmd args output rc
  rest="${line#/}"
  cmd="${rest%% *}"

  if [ -z "$cmd" ]; then
    append_line "$(color 203)usage: /<command> [args...]$(reset)"
    return 0
  fi

  case "$cmd" in
    exit|quit)
      exit 0
      ;;
  esac

  if [ "$cmd" = "$rest" ]; then
    args=()
  else
    # Match the small, space-separated command convention used by scripts.
    # shellcheck disable=SC2206
    args=(${rest#"$cmd "})
  fi

  if [ ! -x "$COMMANDS/$cmd.sh" ]; then
    append_line "$(color 203)unknown command: /$cmd$(reset)"
    append_line "$(dim)try /help$(reset)"
    return 0
  fi

  set +e
  output="$("$COMMANDS/$cmd.sh" "${args[@]}" 2>&1)"
  rc=$?
  set -e

  append_line ""
  append_line "$(bold)$(color 171)/$cmd$(reset) $(dim)command output$(reset)"
  if [ -n "$output" ]; then
    while IFS= read -r out_line; do
      append_line "$out_line"
    done <<EOF_OUTPUT
$output
EOF_OUTPUT
  fi
  if [ "$rc" -ne 0 ]; then
    append_line "$(color 203)command exited $rc$(reset)"
  fi
  refresh_model
}

handle_enter() {
  local line="$input"
  input=""
  [ -n "$line" ] || return 0

  case "$line" in
    /*) run_slash "$line" ;;
    *)
      if [ -n "$pending" ]; then
        append_line "$(color 226)message still pending; wait for the user turn to land$(reset)"
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

wrap_text_line() {
  local line="$1"
  local width="$2"
  local out word

  if [ -z "$line" ]; then
    printf '\n'
    return 0
  fi

  case "$line" in
    *$'\033'*)
      printf '%s\n' "$line"
      return 0
      ;;
  esac

  out=""
  for word in $line; do
    while [ "${#word}" -gt "$width" ]; do
      if [ -n "$out" ]; then
        printf '%s\n' "$out"
        out=""
      fi
      printf '%s\n' "${word:0:$width}"
      word="${word:$width}"
    done
    if [ -z "$out" ]; then
      out="$word"
    elif [ -z "$word" ]; then
      :
    elif [ "$((${#out} + 1 + ${#word}))" -le "$width" ]; then
      out="$out $word"
    else
      printf '%s\n' "$out"
      out="$word"
    fi
  done
  [ -n "$out" ] && printf '%s\n' "$out"
}

build_wrapped_lines() {
  local width="$1"
  local line wrapped
  wrapped_lines=()

  for line in "${raw_lines[@]}"; do
    while IFS= read -r wrapped || [ -n "$wrapped" ]; do
      wrapped_lines+=("$wrapped")
    done < <(wrap_text_line "$line" "$width")
  done
}

redraw() {
  local frame body_rows start i line prompt shown_input mode_text pending_age
  local status_face status_color bottom_status max_line title title_width title_fill divider
  local row wrapped_count
  printf '\033]0;gremlin tui\007'

  frame=0
  if [ "$status" = "pending" ]; then
    frame=$(( (tick / 3) % 4 ))
  elif [ $((tick % 27)) -eq 26 ]; then
    frame=1
  fi
  if [ "$status" = "idle" ] && [ "$frame" -eq 1 ]; then
    status_face='^-_-^'
  else
    status_face="$(face "$frame")"
  fi
  tick=$((tick + 1))

  # Header, transcript, blank spacer, divider, status, input, bottom bar.
  body_rows=$((rows - 6))
  max_line=$((cols - 1))

  build_wrapped_lines "$max_line"
  wrapped_count="${#wrapped_lines[@]}"

  cup 0 0
  el
  title="    ──────── gremlin tui ──────── "
  title_width=34
  title_fill=$((cols - title_width))
  [ "$title_fill" -lt 0 ] && title_fill=0
  printf '%s%s%s%s' "$(bg 45)" "$(color 16)" "$(bold)" "$title"
  printf '%*s%s' "$title_fill" '' "$(reset)"

  start=0
  if [ "$wrapped_count" -gt "$body_rows" ]; then
    start=$((wrapped_count - body_rows))
  fi

  row=1
  i="$start"
  while [ "$row" -le "$body_rows" ]; do
    cup "$row" 0
    el
    if [ "$i" -lt "$wrapped_count" ]; then
      line="${wrapped_lines[$i]}"
      printf '%s' "${line:0:$max_line}"
    fi
    row=$((row + 1))
    i=$((i + 1))
  done

  cup "$((rows - 5))" 0
  el

  cup "$((rows - 4))" 0
  el
  printf '%s' "$(color 135)"
  printf -v divider '%*s' "$cols" ''
  printf '%s\n' "${divider// /-}"
  printf '%s' "$(reset)"

  cup "$((rows - 3))" 0
  mode_text="idle"
  status_color=81
  if [ -n "$pending" ]; then
    pending_age=$(( $(date +%s) - pending_since ))
    mode_text="pending ${pending_age}s"
    status_color=226
  fi
  el
  printf '%s%s %s%s%s\n' "$(color 226)" "$status_face" "$(color "$status_color")" "$mode_text" "$(reset)"

  cup "$((rows - 2))" 0
  prompt='> '
  shown_input="$input"
  el
  if [ -n "$pending" ]; then
    shown_input="$pending"
    printf '%s%s%s%s' "$prompt" "$(dim)" "${shown_input:0:$((cols - 3))}" "$(reset)"
  else
    printf '%s%s' "$prompt" "${shown_input:0:$((cols - 3))}"
  fi

  bottom_status="model: $model | transcript: ${transcript_size} B, ${transcript_turns} turns"
  cup "$((rows - 1))" 0
  el
  printf '%s%s%s' "$(dim)" "${bottom_status:0:$max_line}" "$(reset)"
}

tput clear
refresh_model
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

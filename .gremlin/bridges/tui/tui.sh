#!/usr/bin/env bash
# tui.sh — dependency-free terminal bridge.
#
# Reads transcript.md, writes user messages into .nest/in/, and renders
# slash command output ephemerally. The tender owns transcript writes.

set -euo pipefail

if [ "${LC_ALL:-}" = "C.UTF-8" ]; then
  unset LC_ALL
fi

BRIDGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREMLIN_DIR="$(cd "$BRIDGE_DIR/../.." && pwd)"
NESTLING="$GREMLIN_DIR/.nest/nestling.sh"
TRANSCRIPT="$GREMLIN_DIR/transcript.md"
COMMANDS="$GREMLIN_DIR/commands"

POLL_SECS=0.15
MAX_LINES=500
MIN_ROWS=10
MIN_COLS=30
INPUT_MAX_ROWS=5
INPUT_MIN_ROWS=2

if [ ! -t 0 ] || [ ! -t 1 ]; then
  echo "tui.sh requires an interactive terminal" >&2
  exit 2
fi

if ! command -v tput >/dev/null 2>&1; then
  echo "tui.sh requires tput" >&2
  exit 2
fi

raw_lines=()
wrapped_lines=()
input_lines=()
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
layout_sig=""
body_rows=0
divider_row=0
status_row=0
input_start_row=0
input_rows=0
footer_row=0
wrap_width=0
chrome_dirty=1
transcript_dirty=1
status_dirty=1
input_dirty=1
footer_dirty=1
wrapped_dirty=1
last_status_text=""
last_status_face=""
last_status_tick=0

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
  local size old_rows old_cols
  old_rows="$rows"
  old_cols="$cols"
  size="$(stty size 2>/dev/null || true)"
  if [ -n "$size" ]; then
    rows="${size%% *}"
    cols="${size##* }"
  fi
  [ "$rows" -lt "$MIN_ROWS" ] && rows="$MIN_ROWS"
  [ "$cols" -lt "$MIN_COLS" ] && cols="$MIN_COLS"
  if [ "$rows" != "$old_rows" ] || [ "$cols" != "$old_cols" ]; then
    chrome_dirty=1
    transcript_dirty=1
    status_dirty=1
    input_dirty=1
    footer_dirty=1
    wrapped_dirty=1
  fi
  return 0
}
trap update_size WINCH

tput smcup 2>/dev/null || true
printf '\033]0;gremlin tui\007'
stty raw -echo min 0 time 0
tput civis 2>/dev/null || true
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
  if [ "$status" = "pending" ]; then
    case "$frame" in
      0) printf '^o_o^' ;;
      1) printf '^-_o^' ;;
      2) printf '^-_-^' ;;
      3) printf '^O_-^' ;;
      4) printf '^o_O^' ;;
      5) printf '^o_o^' ;;
      6) printf '^-_-^' ;;
      7) printf '^O_O^' ;;
      8) printf '^-_-^' ;;
      *) printf '^o_o^' ;;
    esac
  elif [ "$frame" -eq 1 ]; then
    printf '^-_-^'
  else
    printf '^o_o^'
  fi
}

append_line() {
  raw_lines+=("$1")
  while [ "${#raw_lines[@]}" -gt "$MAX_LINES" ]; do
    raw_lines=("${raw_lines[@]:1}")
  done
  transcript_dirty=1
  wrapped_dirty=1
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
  local next
  next="$(current_model)"
  if [ "$next" != "$model" ]; then
    model="$next"
    footer_dirty=1
  else
    model="$next"
  fi
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
  transcript_dirty=1
  wrapped_dirty=1
}

maybe_clear_pending() {
  local role="$1"
  local body="$2"
  if [ "$role" = "user" ] && [ -n "$pending" ] && [ "$body" = "$pending" ]; then
    pending=""
    pending_since=0
    status="idle"
    status_dirty=1
    input_dirty=1
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
  local offset size old_size bytes chunk parsed line turn_role turn_ts turn_body

  old_size="$transcript_size"
  size="$(file_size "$TRANSCRIPT")"
  if [ "$size" -lt "$transcript_offset" ]; then
    raw_lines=()
    wrapped_lines=()
    transcript_offset=0
    transcript_turns=0
    transcript_dirty=1
    wrapped_dirty=1
  fi

  offset="$transcript_offset"
  if [ "$size" -le "$offset" ]; then
    if [ "$size" != "$old_size" ]; then
      transcript_size="$size"
      footer_dirty=1
    fi
    return 0
  fi

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
  footer_dirty=1
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
  [ -n "${msg//[[:space:]]/}" ] || return 0
  tmp="$(mktemp)"
  printf '%s\n' "$msg" > "$tmp"
  name="$(unique_item_name)"
  if "$NESTLING" ingest "$tmp" "$name" >/dev/null 2>&1; then
    pending="$msg"
    pending_since="$(date +%s)"
    status="pending"
    status_dirty=1
    input_dirty=1
  else
    append_line "$(color 203)failed to submit message$(reset)"
  fi
  rm -f "$tmp"
}

run_slash() {
  local line="$1"
  local rest cmd args output_file rc out_line
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

  output_file="$(mktemp)"
  set +e
  if [ "${LC_ALL:-}" = "C.UTF-8" ]; then
    ( cd "$GREMLIN_DIR" && LC_ALL= "$COMMANDS/$cmd.sh" "${args[@]}" </dev/null ) >"$output_file" 2>&1
  else
    ( cd "$GREMLIN_DIR" && "$COMMANDS/$cmd.sh" "${args[@]}" </dev/null ) >"$output_file" 2>&1
  fi
  rc=$?
  set -e

  append_line ""
  append_line "$(bold)$(color 171)/$cmd$(reset) $(dim)command output$(reset)"
  if [ -s "$output_file" ]; then
    while IFS= read -r out_line || [ -n "$out_line" ]; do
      append_line "$out_line"
    done < "$output_file"
  fi
  rm -f "$output_file"
  if [ "$rc" -ne 0 ]; then
    append_line "$(color 203)command exited $rc$(reset)"
  fi
  refresh_model
}

handle_enter() {
  local line="$input"
  line="${line%$'\r'}"
  line="${line%$'\n'}"
  input=""
  input_dirty=1
  [ -n "${line//[[:space:]]/}" ] || return 0

  case "$line" in
    /*) run_slash "$line" ;;
    *)
      if [ -n "$pending" ]; then
        append_line "$(color 226)message still pending; wait for the user turn to land$(reset)"
        input="$line"
        input_dirty=1
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
    $'\r')
      handle_enter
      ;;
    $'\n'|$'\016')
      input="${input}"$'\n'
      input_dirty=1
      ;;
    $'\177'|$'\b')
      if [ -n "$input" ]; then
        input="${input%?}"
        input_dirty=1
      fi
      ;;
    $'\033')
      # Ignore escape sequences for now.
      read -r -s -n 2 -t 0.001 _rest || true
      ;;
    *)
      input="$input$key"
      input_dirty=1
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
  [ "$wrapped_dirty" -eq 0 ] && [ "$width" -eq "$wrap_width" ] && return 0

  wrapped_lines=()
  wrap_width="$width"

  for line in "${raw_lines[@]}"; do
    while IFS= read -r wrapped || [ -n "$wrapped" ]; do
      wrapped_lines+=("$wrapped")
    done < <(wrap_text_line "$line" "$width")
  done
  wrapped_dirty=0
}

hard_wrap_line() {
  local line="$1"
  local width="$2"

  [ "$width" -lt 1 ] && width=1
  if [ -z "$line" ]; then
    printf '\n'
    return 0
  fi

  while [ "${#line}" -gt "$width" ]; do
    printf '%s\n' "${line:0:$width}"
    line="${line:$width}"
  done
  printf '%s\n' "$line"
}

calculate_layout() {
  local next_input_rows sig

  next_input_rows="$INPUT_MAX_ROWS"
  [ "$next_input_rows" -gt "$((rows / 4))" ] && next_input_rows="$((rows / 4))"
  [ "$next_input_rows" -lt "$INPUT_MIN_ROWS" ] && next_input_rows="$INPUT_MIN_ROWS"
  [ "$next_input_rows" -gt "$((rows - 7))" ] && next_input_rows="$((rows - 7))"
  [ "$next_input_rows" -lt 1 ] && next_input_rows=1

  input_rows="$next_input_rows"
  divider_row=$((rows - input_rows - 3))
  status_row=$((divider_row + 1))
  input_start_row=$((status_row + 1))
  footer_row=$((rows - 1))
  body_rows=$((divider_row - 1))
  [ "$body_rows" -lt 1 ] && body_rows=1

  sig="${rows}x${cols}:${input_rows}:${body_rows}"
  if [ "$sig" != "$layout_sig" ]; then
    layout_sig="$sig"
    chrome_dirty=1
    transcript_dirty=1
    status_dirty=1
    input_dirty=1
    footer_dirty=1
    wrapped_dirty=1
  fi
}

build_input_lines() {
  local text="$1"
  local logical wrapped first_width rest_width first

  input_lines=()
  first_width=$((cols - 2))
  rest_width="$cols"
  [ "$first_width" -lt 1 ] && first_width=1
  [ "$rest_width" -lt 1 ] && rest_width=1
  first=1

  while IFS= read -r logical || [ -n "$logical" ]; do
    if [ "$first" -eq 1 ]; then
      while IFS= read -r wrapped || [ -n "$wrapped" ]; do
        input_lines+=("$wrapped")
      done < <(hard_wrap_line "$logical" "$first_width")
      first=0
    else
      while IFS= read -r wrapped || [ -n "$wrapped" ]; do
        input_lines+=("$wrapped")
      done < <(hard_wrap_line "$logical" "$rest_width")
    fi
  done <<< "$text"

  if [ "${#input_lines[@]}" -eq 0 ]; then
    input_lines=("")
  fi
}

status_face_for_tick() {
  local frame="$1"
  face "$frame"
}

maybe_dirty_status_tick() {
  local now frame next_face next_text
  now="$(date +%s)"
  [ "$now" -eq "$last_status_tick" ] && return 0

  frame=0
  if [ "$status" = "pending" ]; then
    frame=$((tick % 10))
  elif [ $((tick % 8)) -eq 7 ]; then
    frame=1
  fi
  next_face="$(status_face_for_tick "$frame")"
  next_text="idle"
  if [ -n "$pending" ]; then
    next_text="pending $((now - pending_since))s"
  fi
  tick=$((tick + 1))
  last_status_tick="$now"

  if [ "$next_face" != "$last_status_face" ] || [ "$next_text" != "$last_status_text" ]; then
    status_dirty=1
  fi
}

draw_chrome() {
  local title title_width title_fill divider

  cup 0 0
  el
  title="    -------- gremlin tui -------- "
  title_width=34
  title_fill=$((cols - title_width))
  [ "$title_fill" -lt 0 ] && title_fill=0
  printf '%s%s%s%s' "$(bg 45)" "$(color 16)" "$(bold)" "$title"
  printf '%*s%s' "$title_fill" '' "$(reset)"

  cup "$divider_row" 0
  el
  printf '%s' "$(color 135)"
  printf -v divider '%*s' "$cols" ''
  printf '%s%s' "${divider// /-}" "$(reset)"

  chrome_dirty=0
}

draw_transcript() {
  local max_line start i row line wrapped_count

  max_line=$((cols - 1))
  build_wrapped_lines "$max_line"
  wrapped_count="${#wrapped_lines[@]}"
  start=0
  if [ "$wrapped_count" -gt "$body_rows" ]; then
    start=$((wrapped_count - body_rows))
  fi

  row=1
  i="$start"
  while [ "$row" -lt "$divider_row" ]; do
    cup "$row" 0
    el
    if [ "$i" -lt "$wrapped_count" ]; then
      line="${wrapped_lines[$i]}"
      printf '%s' "${line:0:$max_line}"
    fi
    row=$((row + 1))
    i=$((i + 1))
  done
  transcript_dirty=0
}

draw_status() {
  local frame status_face status_color mode_text now

  now="$(date +%s)"
  frame=0
  if [ -n "$pending" ]; then
    frame=$(((tick + 9) % 10))
  elif [ $(((tick + 7) % 8)) -eq 7 ]; then
    frame=1
  fi
  status_face="$(status_face_for_tick "$frame")"

  mode_text="idle"
  status_color=81
  if [ -n "$pending" ]; then
    mode_text="pending $((now - pending_since))s"
    status_color=226
  fi

  last_status_face="$status_face"
  last_status_text="$mode_text"

  cup "$status_row" 0
  el
  printf '%s%s %s%s%s' "$(color 226)" "$status_face" "$(color "$status_color")" "$mode_text" "$(reset)"
  status_dirty=0
}

draw_input() {
  local shown_input prompt start i row line visible_count max_line hint

  shown_input="$input"
  if [ -n "$pending" ]; then
    shown_input="$pending"
  fi

  build_input_lines "$shown_input"
  visible_count="${#input_lines[@]}"
  start=0
  if [ "$visible_count" -gt "$input_rows" ]; then
    start=$((visible_count - input_rows))
  fi

  row=0
  i="$start"
  prompt='> '
  max_line=$((cols - 1))
  while [ "$row" -lt "$input_rows" ]; do
    cup "$((input_start_row + row))" 0
    el
    if [ -n "$shown_input" ]; then
      line=""
      [ "$i" -lt "$visible_count" ] && line="${input_lines[$i]}"
      if [ "$i" -eq 0 ]; then
        if [ -n "$pending" ]; then
          printf '%s%s%s%s' "$prompt" "$(dim)" "${line:0:$((cols - 2))}" "$(reset)"
        else
          printf '%s%s' "$prompt" "${line:0:$((cols - 2))}"
        fi
      else
        if [ -n "$pending" ]; then
          printf '%s%s%s' "$(dim)" "${line:0:$max_line}" "$(reset)"
        else
          printf '%s' "${line:0:$max_line}"
        fi
      fi
    elif [ "$row" -eq 0 ]; then
      hint="type message; Ctrl-N newline; Enter sends"
      printf '%s%s%s%s' "$prompt" "$(dim)" "${hint:0:$((cols - 2))}" "$(reset)"
    fi
    row=$((row + 1))
    i=$((i + 1))
  done
  input_dirty=0
}

draw_footer() {
  local bottom_status max_line

  max_line=$((cols - 1))
  bottom_status="model: $model | transcript: ${transcript_size} B, ${transcript_turns} turns"
  cup "$footer_row" 0
  el
  printf '%s%s%s' "$(dim)" "${bottom_status:0:$max_line}" "$(reset)"
  footer_dirty=0
}

draw_dirty() {
  calculate_layout
  if [ "$chrome_dirty" -eq 1 ]; then
    draw_chrome
  fi
  if [ "$transcript_dirty" -eq 1 ] || [ "$wrapped_dirty" -eq 1 ]; then
    draw_transcript
  fi
  if [ "$status_dirty" -eq 1 ]; then
    draw_status
  fi
  if [ "$input_dirty" -eq 1 ]; then
    draw_input
  fi
  if [ "$footer_dirty" -eq 1 ]; then
    draw_footer
  fi
}

drain_keys() {
  local key

  while IFS= read -r -s -n 1 -t 0.001 key; do
    if [ -z "$key" ]; then
      handle_enter
    else
      handle_key "$key"
    fi
  done
}

tput clear 2>/dev/null || true
refresh_model
poll_transcript
calculate_layout
draw_dirty

while :; do
  poll_transcript
  maybe_dirty_status_tick
  draw_dirty

  key=""
  if IFS= read -r -s -n 1 -t "$POLL_SECS" key; then
    if [ -z "$key" ]; then
      handle_enter
    else
      handle_key "$key"
    fi
    drain_keys
    draw_dirty
  fi
done

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
HOST_DIR="$(cd "$GREMLIN_DIR/.." && pwd)"
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

telegram_file_url() {
  printf 'https://api.telegram.org/file/bot%s/%s\n' "$TELEGRAM_BOT_TOKEN" "$1"
}

# download_file <file_id> <dest>: resolve a Telegram file_id to its path via
# getFile, then download the bytes to <dest>. In tests, TELEGRAM_TEST_FILE_SRC
# short-circuits the network by copying a local fixture instead.
download_file() {
  local file_id="$1"
  local dest="$2"
  local response ok file_path

  if [ -n "${TELEGRAM_TEST_FILE_SRC:-}" ]; then
    cp "$TELEGRAM_TEST_FILE_SRC" "$dest"
    return 0
  fi

  response="$(curl -fsS --get \
    --data-urlencode "file_id=$file_id" \
    "$(telegram_api getFile)")" || return 1
  ok="$(printf '%s\n' "$response" | jq -r '.ok')"
  if [ "$ok" != "true" ]; then
    echo "telegram: getFile failed for $file_id" >&2
    return 1
  fi
  file_path="$(printf '%s\n' "$response" | jq -r '.result.file_path? // empty')"
  [ -n "$file_path" ] || { echo "telegram: getFile returned no file_path" >&2; return 1; }

  curl -fsS -o "$dest" "$(telegram_file_url "$file_path")" || return 1
}

# image_resize <src> <dest>: best-effort scaled copy (longest side ~1024px).
# Uses ImageMagick when present; returns non-zero if no resizer is available so
# the caller can fall back to the original.
image_resize() {
  local src="$1" dest="$2"
  if command -v magick >/dev/null 2>&1; then
    magick "$src" -resize '1024x1024>' "$dest" 2>/dev/null
  elif command -v convert >/dev/null 2>&1; then
    convert "$src" -resize '1024x1024>' "$dest" 2>/dev/null
  else
    return 1
  fi
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

# Convert the small Markdown subset that agents emit into Telegram-flavoured
# HTML (parse_mode=HTML). HTML needs only & < > escaped, versus MarkdownV2 with
# its 18 reserved characters, so it survives free-form prose far better. This is
# deliberately agnostic to which agent wrote the text: it keys off Markdown
# markup, never the author. Anything it cannot map cleanly is left as plain
# text; anything it gets wrong is caught by the plain-text fallback in the
# senders, since a malformed entity makes Telegram reject the whole message.
#
# Mappings: # headers -> <b><u>..</u></b>; **bold**/*italic*; ~~strike~~;
# ||spoiler||; `code`; fenced ```lang blocks -> <pre><code class="language-..">;
# > quotes -> <blockquote> (expandable when long); [text](url) -> <a>. Underscore
# emphasis is intentionally NOT supported: snake_case and dunder identifiers are
# common in this codebase-adjacent traffic and must not be mangled into italics.
markdown_to_telegram_html() {
  awk '
  BEGIN { incode = 0; inquote = 0; qbuf = ""; codeclose = "" }

  function esc(s) {
    gsub(/&/, "\\&amp;", s)
    gsub(/</, "\\&lt;", s)
    gsub(/>/, "\\&gt;", s)
    return s
  }

  # Replace each occurrence of a paired single-line marker with open/close tags.
  function wrap(s, re, mlen, o, c,   out, pre, inner) {
    out = ""
    while (match(s, re)) {
      pre = substr(s, 1, RSTART - 1)
      inner = substr(s, RSTART + mlen, RLENGTH - 2 * mlen)
      out = out pre o inner c
      s = substr(s, RSTART + RLENGTH)
    }
    return out s
  }

  function links(s,   out, m, pre, rb, txt, url) {
    out = ""
    while (match(s, /\[[^][]*\]\([^()]*\)/)) {
      m = substr(s, RSTART, RLENGTH)
      pre = substr(s, 1, RSTART - 1)
      rb = index(m, "]")
      txt = substr(m, 2, rb - 2)
      url = substr(m, rb + 2, length(m) - rb - 2)
      out = out pre "<a href=\"" url "\">" txt "</a>"
      s = substr(s, RSTART + RLENGTH)
    }
    return out s
  }

  # Inline formatting for escaped text that holds no inline-code span.
  function fmt(s) {
    s = links(s)
    s = wrap(s, "\\*\\*[^*]+\\*\\*", 2, "<b>", "</b>")
    s = wrap(s, "\\*[^*]+\\*", 1, "<i>", "</i>")
    s = wrap(s, "~~[^~]+~~", 2, "<s>", "</s>")
    s = wrap(s, "\\|\\|[^|]+\\|\\|", 2, "<tg-spoiler>", "</tg-spoiler>")
    return s
  }

  # Inline formatting with backtick code spans protected from fmt.
  function inl(s,   n, arr, i, out) {
    n = split(s, arr, "`")
    if (n % 2 == 0) return fmt(s)   # unbalanced backticks: format literally
    out = ""
    for (i = 1; i <= n; i++) {
      if (i % 2 == 1) out = out fmt(arr[i])
      else out = out "<code>" arr[i] "</code>"
    }
    return out
  }

  function flushquote(   tag) {
    if (!inquote) return
    if (length(qbuf) > 300) tag = "<blockquote expandable>"
    else tag = "<blockquote>"
    print tag qbuf "</blockquote>"
    inquote = 0; qbuf = ""
  }

  {
    line = $0
    if (incode) {
      if (line ~ /^[ \t]*```/) { print copen cbuf codeclose; incode = 0 }
      else cbuf = (cbuf == "" ? esc(line) : cbuf "\n" esc(line))
      next
    }
    if (line ~ /^[ \t]*```/) {
      flushquote()
      lang = line
      sub(/^[ \t]*```[ \t]*/, "", lang)
      gsub(/[^A-Za-z0-9+_-]/, "", lang)
      if (lang != "") { copen = "<pre><code class=\"language-" lang "\">"; codeclose = "</code></pre>" }
      else { copen = "<pre>"; codeclose = "</pre>" }
      cbuf = ""
      incode = 1
      next
    }
    if (line ~ /^[ \t]*>/) {
      q = line
      sub(/^[ \t]*> ?/, "", q)
      q = inl(esc(q))
      if (inquote) qbuf = qbuf "\n" q
      else { qbuf = q; inquote = 1 }
      next
    }
    flushquote()
    if (line ~ /^[ \t]*#+[ \t]+/) {
      h = line
      sub(/^[ \t]*#+[ \t]+/, "", h)
      sub(/[ \t]+#*[ \t]*$/, "", h)
      print "<b><u>" inl(esc(h)) "</u></b>"
      next
    }
    print inl(esc(line))
  }

  END {
    flushquote()
    if (incode) print copen cbuf codeclose   # unterminated fence at EOF
  }
  '
}

# Low-level sendMessage attempt. $2 is an optional parse_mode. Returns non-zero
# on any API failure so the caller can fall back to a plainer attempt.
send_message_api() {
  local text="$1"
  local mode="${2:-}"
  local response ok description

  if [ -n "${TELEGRAM_TEST_SEND_FAIL:-}" ]; then
    echo "telegram: mock send failure" >&2
    return 1
  fi

  # Simulate Telegram rejecting malformed entities, to exercise the fallback.
  if [ "$mode" = "HTML" ] && [ -n "${TELEGRAM_TEST_HTML_FAIL:-}" ]; then
    echo "telegram: mock HTML parse failure" >&2
    return 1
  fi

  if [ -n "${TELEGRAM_TEST_SEND_LOG:-}" ]; then
    {
      printf '%s\n' "---"
      [ -n "$mode" ] && printf 'parse_mode=%s\n' "$mode"
      printf '%s\n' "$text"
    } >> "$TELEGRAM_TEST_SEND_LOG"
    return 0
  fi

  if [ -n "$mode" ]; then
    response="$(curl -fsS -X POST \
      --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
      --data-urlencode "parse_mode=$mode" \
      --data-urlencode "text=$text" \
      "$(telegram_api sendMessage)")" || return 1
  else
    response="$(curl -fsS -X POST \
      --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
      --data-urlencode "text=$text" \
      "$(telegram_api sendMessage)")" || return 1
  fi

  ok="$(printf '%s\n' "$response" | jq -r '.ok')"
  if [ "$ok" != "true" ]; then
    description="$(printf '%s\n' "$response" | jq -r '.description? // "unknown Telegram API error"')"
    echo "telegram: sendMessage failed: $description" >&2
    return 1
  fi
}

send_message() {
  local text="$1"
  local html

  html="$(printf '%s' "$text" | markdown_to_telegram_html)"
  if send_message_api "$html" "HTML"; then
    return 0
  fi

  # The HTML render was rejected (or send failed); retry as plain text so a
  # formatting slip never costs the user the reply itself.
  echo "telegram: retrying message as plain text" >&2
  send_message_api "$text" ""
}

# Low-level sendPhoto attempt with an optional caption parse_mode.
send_photo_api() {
  local photo="$1"
  local caption="$2"
  local mode="${3:-}"
  local response ok description

  if [ -n "${TELEGRAM_TEST_SEND_FAIL:-}" ]; then
    echo "telegram: mock photo failure" >&2
    return 1
  fi

  if [ "$mode" = "HTML" ] && [ -n "${TELEGRAM_TEST_HTML_FAIL:-}" ]; then
    echo "telegram: mock HTML parse failure" >&2
    return 1
  fi

  if [ -n "${TELEGRAM_TEST_SEND_LOG:-}" ]; then
    {
      printf '%s\n' "---"
      printf 'photo=%s\n' "$photo"
      [ -n "$mode" ] && printf 'parse_mode=%s\n' "$mode"
      [ -n "$caption" ] && printf 'caption=%s\n' "$caption"
    } >> "$TELEGRAM_TEST_SEND_LOG"
    return 0
  fi

  # http(s) targets are handed to Telegram as a URL; everything else is a local
  # file uploaded with multipart form data.
  case "$photo" in
    http://* | https://*)
      response="$(curl -fsS -X POST \
        --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
        --data-urlencode "photo=$photo" \
        ${mode:+--data-urlencode "parse_mode=$mode"} \
        --data-urlencode "caption=$caption" \
        "$(telegram_api sendPhoto)")" || return 1
      ;;
    *)
      if [ ! -f "$photo" ]; then
        echo "telegram: photo not found: $photo" >&2
        return 1
      fi
      response="$(curl -fsS -X POST \
        -F "chat_id=$TELEGRAM_CHAT_ID" \
        ${mode:+-F "parse_mode=$mode"} \
        -F "caption=$caption" \
        -F "photo=@$photo" \
        "$(telegram_api sendPhoto)")" || return 1
      ;;
  esac

  ok="$(printf '%s\n' "$response" | jq -r '.ok')"
  if [ "$ok" != "true" ]; then
    description="$(printf '%s\n' "$response" | jq -r '.description? // "unknown Telegram API error"')"
    echo "telegram: sendPhoto failed: $description" >&2
    return 1
  fi
}

send_photo() {
  local photo="$1"
  local caption="${2:-}"
  local html_caption

  # A missing local file is a caller error, not a formatting problem: fail fast
  # rather than burning the HTML attempt and a plain retry on it.
  case "$photo" in
    http://* | https://*) ;;
    *)
      if [ ! -f "$photo" ]; then
        echo "telegram: photo not found: $photo" >&2
        return 1
      fi
      ;;
  esac

  if [ -z "$caption" ]; then
    send_photo_api "$photo" "" ""
    return
  fi

  html_caption="$(printf '%s' "$caption" | markdown_to_telegram_html)"
  if send_photo_api "$photo" "$html_caption" "HTML"; then
    return 0
  fi

  echo "telegram: retrying photo caption as plain text" >&2
  send_photo_api "$photo" "$caption" ""
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

# A pushable turn may embed images as markdown: ![caption](path-or-url).
# Each reference becomes a sendPhoto (caption from the alt text); the remaining
# text, with the image markdown stripped, is sent as a normal message. Local
# paths are resolved against the host folder so the gremlin can reference files
# it created with a relative path.
push_turn() {
  local turn="$1"
  local images text line photo caption

  images="$(printf '%s\n' "$turn" | grep -oE '!\[[^]]*\]\([^)]+\)' || true)"
  text="$(printf '%s\n' "$turn" | sed -E 's/!\[[^]]*\]\([^)]+\)//g')"

  if [ -n "$(printf '%s' "$text" | tr -d '[:space:]')" ]; then
    send_message "$text" || return 1
  fi

  [ -n "$images" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    caption="$(printf '%s' "$line" | sed -E 's/^!\[([^]]*)\].*/\1/')"
    photo="$(printf '%s' "$line" | sed -E 's/^!\[[^]]*\]\(([^)]+)\)$/\1/')"
    case "$photo" in
      http://* | https://* | /*) : ;;
      *) photo="$HOST_DIR/$photo" ;;
    esac
    send_photo "$photo" "$caption" || return 1
  done <<EOF_IMAGES
$images
EOF_IMAGES
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
    push_turn "$turn" || return 1
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

# ingest_photo <file_id> <ext> <caption>: download the photo and ingest it as a
# model-backed nest item directory — source.<ext>, an optional scaled
# preview.<ext>, instructions.md framing the turn, and `.model = image` so the
# tender runs the dedicated image preset.
ingest_photo() {
  local file_id="$1"
  local ext="$2"
  local caption="$3"
  local itemdir src preview name suffix preview_note=""

  itemdir="$(mktemp -d "$BRIDGE_DIR/telegram-photo.XXXXXX")"
  src="$itemdir/source.$ext"

  if ! download_file "$file_id" "$src"; then
    rm -rf "$itemdir"
    echo "telegram: failed to download photo $file_id" >&2
    return 1
  fi

  preview="$itemdir/preview.$ext"
  if image_resize "$src" "$preview"; then
    preview_note="A scaled-down preview is at \`preview.$ext\`; the full-resolution original is at \`source.$ext\`. Look at the preview first and open the original only if you need finer detail."
  else
    rm -f "$preview"
    preview_note="The image is at \`source.$ext\`."
  fi

  {
    printf 'The user sent a photo via Telegram.\n\n'
    [ -n "$caption" ] && printf 'Caption: %s\n\n' "$caption"
    printf '%s\n\n' "$preview_note"
    printf 'Look at the image and respond to the user about it.\n'
  } > "$itemdir/instructions.md"
  printf 'image\n' > "$itemdir/.model"

  suffix="$(basename "$itemdir")"
  suffix="${suffix#telegram-photo.}"
  name="$(date -u +%Y%m%dT%H%M%SZ)-telegram-photo-$suffix"
  "$NESTLING" ingest "$itemdir" "$name" >/dev/null
  rm -rf "$itemdir"
  echo "ingested telegram photo as $name"
}

# ingest_voice <file_id> <ext> <caption>: download an audio note and transcribe
# it via the `voice` model preset (models/voice.sh), then ingest the resulting
# TEXT as a normal item — so the transcript becomes the `## user —` turn and the
# gremlin's normal reply follows. Speech is text, so it belongs in the transcript
# body, mirroring how the bridge already transforms inbound media (image_resize).
# The source audio is kept in the item dir for provenance as a dotfile
# (.source.<ext>) so the tender's `*` glob does not re-attach it to the reply turn
# — the transcript is already the record. STT failure is surfaced to the user,
# never dropped.
ingest_voice() {
  local file_id="$1"
  local ext="$2"
  local caption="$3"
  local itemdir src text name suffix rc detail errf

  # Presence: the user is now waiting through download + STT + the model turn.
  # The pulser only sees items already in the nest, so cover the STT gap here.
  send_chat_action typing || true

  itemdir="$(mktemp -d "$BRIDGE_DIR/telegram-voice.XXXXXX")"
  # Dotfile: kept for provenance but skipped by the tender's `*` attachment glob,
  # so the audio is transcribed once and not re-fed to the reply model.
  src="$itemdir/.source.$ext"

  if ! download_file "$file_id" "$src"; then
    rm -rf "$itemdir"
    echo "telegram: failed to download voice $file_id" >&2
    send_message "🎙️ I couldn't fetch that voice note from Telegram." || true
    return 1
  fi

  # STT stderr goes to a temp file outside the item dir so it is never ingested
  # as an attachment.
  errf="$(mktemp)"
  rc=0
  text="$(printf '%s' "$src" | "$GREMLIN_DIR/models/voice.sh" 2>"$errf")" || rc=$?
  if [ "$rc" -ne 0 ] || [ -z "${text//[[:space:]]/}" ]; then
    detail="$(tail -n 1 "$errf" 2>/dev/null)"
    rm -f "$errf"
    echo "telegram: transcription failed for $file_id: ${detail:-no transcript}" >&2
    send_message "🎙️ I couldn't transcribe that voice note: ${detail:-no transcript produced}" || true
    rm -rf "$itemdir"
    return 1
  fi
  rm -f "$errf"

  {
    printf 'The user sent a voice note via Telegram (transcribed below).\n\n'
    [ -n "$caption" ] && printf 'Caption: %s\n\n' "$caption"
    printf '🎙️ (voice) %s\n' "$text"
  } > "$itemdir/instructions.md"
  # No .model override: this is a normal text turn for the default preset.

  suffix="$(basename "$itemdir")"
  suffix="${suffix#telegram-voice.}"
  name="$(date -u +%Y%m%dT%H%M%SZ)-telegram-voice-$suffix"
  "$NESTLING" ingest "$itemdir" "$name" >/dev/null
  rm -rf "$itemdir"
  echo "ingested telegram voice as $name"
}

handle_update() {
  local update="$1"
  local update_id chat_id text caption photo_id doc_mime doc_id ext next_offset
  local voice_id

  update_id="$(printf '%s\n' "$update" | jq -r '.update_id')"
  next_offset=$((update_id + 1))

  chat_id="$(printf '%s\n' "$update" | jq -r '.message.chat.id? // empty')"
  text="$(printf '%s\n' "$update" | jq -r '.message.text? // empty')"
  caption="$(printf '%s\n' "$update" | jq -r '.message.caption? // empty')"

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

  # Photos arrive as an array of sizes; the last is the largest. Always JPEG.
  photo_id="$(printf '%s\n' "$update" | jq -r '.message.photo[-1].file_id? // empty')"
  if [ -n "$photo_id" ]; then
    if ! ingest_photo "$photo_id" "jpg" "$caption"; then
      echo "telegram: photo ingest failed for update $update_id" >&2
    fi
    write_update_offset "$next_offset"
    return 0
  fi

  # Images can also arrive as documents (sent as a file). Derive the extension
  # from the declared mime type.
  doc_mime="$(printf '%s\n' "$update" | jq -r '.message.document.mime_type? // empty')"
  case "$doc_mime" in
    image/*)
      doc_id="$(printf '%s\n' "$update" | jq -r '.message.document.file_id? // empty')"
      ext="${doc_mime#image/}"
      [ "$ext" = "jpeg" ] && ext="jpg"
      if ! ingest_photo "$doc_id" "$ext" "$caption"; then
        echo "telegram: document image ingest failed for update $update_id" >&2
      fi
      write_update_offset "$next_offset"
      return 0
      ;;
  esac

  # Voice notes arrive as `.message.voice` (OGG/Opus). Transcribed to text at
  # ingest, so they flow on as a normal text turn.
  voice_id="$(printf '%s\n' "$update" | jq -r '.message.voice.file_id? // empty')"
  if [ -n "$voice_id" ]; then
    if ! ingest_voice "$voice_id" "ogg" "$caption"; then
      echo "telegram: voice ingest failed for update $update_id" >&2
    fi
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
  if ! response="$(get_updates "$offset")"; then
    echo "telegram: getUpdates request failed" >&2
    return 1
  fi
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

  if command -v setsid >/dev/null 2>&1; then
    nohup setsid "$0" run >> "$LOG" 2>&1 < /dev/null &
  else
    nohup "$0" run >> "$LOG" 2>&1 < /dev/null &
  fi
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
    if compgen -G "$GREMLIN_DIR/.nest/in/*-telegram-*.md" >/dev/null \
      || find "$GREMLIN_DIR/.nest/in" -maxdepth 1 -type d -name '*-telegram-*' ! -name '*.tending' | read -r _ \
      || { [ -s "$GREMLIN_DIR/.tending.pid" ] && kill -0 "$(sed -n '1p' "$GREMLIN_DIR/.tending.pid")" 2>/dev/null; }; then
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

#!/usr/bin/env bash
# run.sh - outbound chunking suite for the Telegram bridge.
#
# Sources telegram.sh (the dispatcher is guarded, so sourcing only loads the
# functions) and drives send_message through the TELEGRAM_TEST_SEND_LOG harness.
# It proves that:
#   1. a normal short reply is still a single sendMessage;
#   2. a reply over the per-message limit is split into ordered parts, each
#      within budget, that reassemble to the original text;
#   3. a single overlong line is hard-wrapped rather than lost;
#   4. the HTML->plain fallback still runs per part.
#
# Usage: ./.gremlin/bridges/telegram/test/run.sh

set -uo pipefail

BRIDGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TELEGRAM_SH="$BRIDGE_DIR/telegram.sh"

# shellcheck disable=SC1090
source "$TELEGRAM_SH"
set +e   # sourcing enabled `set -e`; the harness manages failures itself.

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# parts_from_log <logfile>: emit each logged message part separated by the FS
# byte (\034), skipping the `---` separators and any parse_mode header, so a
# part's own newlines are preserved. Streams the parts (no associative-array
# `in` test) to stay portable across mawk and gawk.
parts_from_log() {
  awk '
    /^---$/ { if (started) printf "%c", 28; started = 1; first = 1; next }
    /^parse_mode=/ { next }
    { if (first) { printf "%s", $0; first = 0 } else printf "\n%s", $0 }
    END { if (started) printf "%c", 28 }
  ' "$1"
}

# Load the parts of the last send into the `PARTS` array.
declare -a PARTS
load_parts() {
  PARTS=()
  local p
  while IFS= read -r -d "$(printf '\034')" p; do
    PARTS+=("$p")
  done < <(parts_from_log "$1")
}

# ============================================================================
echo "== short message is a single part =="

LOG="$WORK/short.log"
: > "$LOG"
TELEGRAM_TEST_SEND_LOG="$LOG" MESSAGE_LIMIT=3900 \
  send_message "just a short hello" >/dev/null 2>&1
load_parts "$LOG"
if [ "${#PARTS[@]}" -eq 1 ] && [ "${PARTS[0]}" = "just a short hello" ]; then
  ok "one part, unchanged text"
else
  bad "one part, unchanged text (got ${#PARTS[@]} parts)"
fi
if grep -q '^parse_mode=HTML$' "$LOG"; then
  ok "short message still tries HTML first"
else
  bad "short message still tries HTML first"
fi

# ============================================================================
echo "== oversized message splits on line boundaries =="

LOG="$WORK/split.log"
: > "$LOG"
# limit 10: "aaaa"+"bbbb" (9 chars incl. newline) fit together; "cccc" starts a
# new part.
TELEGRAM_TEST_SEND_LOG="$LOG" TELEGRAM_TEST_HTML_FAIL=1 MESSAGE_LIMIT=10 \
  send_message $'aaaa\nbbbb\ncccc' >/dev/null 2>&1
load_parts "$LOG"
if [ "${#PARTS[@]}" -eq 2 ] \
  && [ "${PARTS[0]}" = $'aaaa\nbbbb' ] \
  && [ "${PARTS[1]}" = "cccc" ]; then
  ok "split into 2 ordered parts on the line boundary"
else
  bad "split into 2 ordered parts (got ${#PARTS[@]}: ${PARTS[*]})"
fi
within=1
for p in "${PARTS[@]}"; do
  [ "$(printf '%s' "$p" | wc -m)" -le 10 ] || within=0
done
[ "$within" -eq 1 ] && ok "every part within budget" || bad "every part within budget"
# Line-boundary parts reassemble by restoring the boundary newline.
joined="$(printf '%s\n' "${PARTS[@]}")"; joined="${joined%$'\n'}"
[ "$joined" = $'aaaa\nbbbb\ncccc' ] && ok "parts reassemble to the original" \
  || bad "parts reassemble to the original"

# ============================================================================
echo "== fallback: parts sent as plain text when HTML is rejected =="

if grep -q '^parse_mode=' "$LOG"; then
  bad "each rejected part fell back to plain text"
else
  ok "each rejected part fell back to plain text"
fi

# ============================================================================
echo "== a single overlong line is hard-wrapped =="

LOG="$WORK/wrap.log"
: > "$LOG"
TELEGRAM_TEST_SEND_LOG="$LOG" TELEGRAM_TEST_HTML_FAIL=1 MESSAGE_LIMIT=10 \
  send_message "abcdefghijklmnop" >/dev/null 2>&1
load_parts "$LOG"
# Hard-wrapped pieces are not on line boundaries, so they concatenate directly.
concat=""; for p in "${PARTS[@]}"; do concat+="$p"; done
if [ "${#PARTS[@]}" -eq 2 ] \
  && [ "${PARTS[0]}" = "abcdefghij" ] \
  && [ "$concat" = "abcdefghijklmnop" ]; then
  ok "overlong line wrapped into budget-sized pieces"
else
  bad "overlong line wrapped (got ${#PARTS[@]}: ${PARTS[*]})"
fi

# ============================================================================
echo "== head-of-line: a permanent failure is skipped, not wedged =="

# A chunk with an un-sendable turn (contains POISON) ahead of a normal turn.
CHUNK=$'## assistant — 2026-06-30T01:00:00Z\n\nThis reply contains POISON and cannot be sent.\n\n## assistant — 2026-06-30T01:01:00Z\n\nnormal reply here\n'

LOG="$WORK/perm.log"; ERR="$WORK/perm.err"; : > "$LOG"
TELEGRAM_TEST_SEND_LOG="$LOG" TELEGRAM_TEST_FAIL_MATCH="POISON" \
  push_pushable_turns "$CHUNK" >/dev/null 2>"$ERR"
rc=$?
[ "$rc" -eq 0 ] && ok "chunk reported handled (cursor may advance past both)" \
  || bad "chunk reported handled (rc=$rc)"
grep -q 'normal reply here' "$LOG" && ok "the turn behind the failure was delivered" \
  || bad "the turn behind the failure was delivered"
grep -q 'POISON' "$LOG" && bad "undeliverable turn was not sent" \
  || ok "undeliverable turn was not sent"
grep -q 'DROPPING an undeliverable turn' "$ERR" \
  && ok "permanent failure surfaced loudly" || bad "permanent failure surfaced loudly"

# ============================================================================
echo "== head-of-line: a transient failure holds its turn for retry =="

LOG="$WORK/tran.log"; ERR="$WORK/tran.err"; : > "$LOG"
TELEGRAM_TEST_SEND_LOG="$LOG" TELEGRAM_TEST_TRANSIENT_MATCH="POISON" \
  push_pushable_turns "$CHUNK" >/dev/null 2>"$ERR"
rc=$?
[ "$rc" -eq 1 ] && ok "chunk held (cursor stays for retry)" \
  || bad "chunk held (rc=$rc)"
grep -q 'normal reply here' "$LOG" \
  && bad "later turn correctly withheld until the held turn clears" \
  || ok "later turn correctly withheld until the held turn clears"
grep -q 'holding cursor to retry' "$ERR" \
  && ok "transient failure reported as a hold" || bad "transient failure reported as a hold"

# ============================================================================
echo "== head-of-line: once the transient clears, everything delivers =="

LOG="$WORK/recover.log"; : > "$LOG"
# No failure hook: the previously-held turn now sends, and so does the rest.
TELEGRAM_TEST_SEND_LOG="$LOG" push_pushable_turns "$CHUNK" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] \
  && grep -q 'cannot be sent' "$LOG" \
  && grep -q 'normal reply here' "$LOG"; then
  ok "both turns delivered in order after recovery"
else
  bad "both turns delivered after recovery (rc=$rc)"
fi

# ============================================================================
echo "== multiple same-kind embeds in one turn are all sent, in authored order =="

# The media grammar (docs/media-embeds.md) allows any number of embeds in a
# reply. push_turn must render every one — none lost, same-kind order preserved.
# Real files: send_photo/send_document fail-fast on a missing local path.
IMG1="$WORK/one.png"; IMG2="$WORK/two.png"; printf 'PNG1' > "$IMG1"; printf 'PNG2' > "$IMG2"
TURN=$'here are two images\n🖼️ [first]('"$IMG1"$')\n🖼️ [second]('"$IMG2"$')'

LOG="$WORK/multi-img.log"; : > "$LOG"
TELEGRAM_TEST_SEND_LOG="$LOG" push_turn "$TURN" >/dev/null 2>&1
photos="$(grep '^photo=' "$LOG")"
if [ "$(printf '%s\n' "$photos" | grep -c .)" -eq 2 ] \
  && [ "$(printf '%s\n' "$photos" | sed -n '1p')" = "photo=$IMG1" ] \
  && [ "$(printf '%s\n' "$photos" | sed -n '2p')" = "photo=$IMG2" ]; then
  ok "both images sent as ordered sendPhoto calls"
else
  bad "both images sent in order (got: $(printf '%s' "$photos" | tr '\n' ' '))"
fi
grep -q 'here are two images' "$LOG" && ok "surrounding prose still sent as a message" \
  || bad "surrounding prose still sent as a message"
grep -q 'caption=first' "$LOG" && grep -q 'caption=second' "$LOG" \
  && ok "each image keeps its own caption" || bad "each image keeps its own caption"

# ============================================================================
echo "== a turn mixing text, an image and a file delivers all three (nothing lost) =="

DOC1="$WORK/report.csv"; printf 'a,b\n1,2\n' > "$DOC1"
MIXED=$'summary line\n🖼️ [chart]('"$IMG1"$')\n📎 [data]('"$DOC1"$')'

LOG="$WORK/mixed.log"; : > "$LOG"
TELEGRAM_TEST_SEND_LOG="$LOG" push_turn "$MIXED" >/dev/null 2>&1
have_text=0; have_photo=0; have_doc=0
grep -q 'summary line' "$LOG" && have_text=1
grep -q "^photo=$IMG1$" "$LOG" && have_photo=1
grep -q "^document=$DOC1$" "$LOG" && have_doc=1
if [ "$have_text" -eq 1 ] && [ "$have_photo" -eq 1 ] && [ "$have_doc" -eq 1 ]; then
  ok "text, image and file all delivered from one turn"
else
  bad "mixed turn lost a part (text=$have_text photo=$have_photo doc=$have_doc)"
fi

# NOTE (audit 2026-07-01): push_turn currently renders by *type group* — text,
# then all images, then all docs, then all voices — so a turn authored as
# image→file→image would arrive image→image→file. Cross-type authored ordering
# and mid-turn partial-failure atomicity (a transient failure on the 2nd of 3
# embeds re-sends the 1st on retry; a permanent one silently drops the rest) are
# tracked by the child stitch gremlin--multi-attachment-bridge-audit--tg-outbound-order-and-atomicity,
# which will add a per-embed fail seam and tighten these into assertions.

# ============================================================================
echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]

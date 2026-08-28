#!/usr/bin/env bash
# tell — the gremlin speaks to a human, unprompted.
#
# The other half of `ask`. `ask` is human → gremlin and waits for an answer;
# `tell` is gremlin → human and expects none. Together they are the whole of
# how a gremlin and a person address each other, in one shape — which is what
# makes a moot and a multiplexer tractable later: gremlin → gremlin traffic is
# the same pair pointed somewhere else.
#
# It appends an assistant turn to the transcript. That is the entire mechanism,
# because the transcript is the source of truth and every bridge already fans
# out from it by byte cursor — so a `tell` reaches Telegram, the web view and
# the TUI without any of them knowing this verb exists.
#
# Usage:
#   ./.gremlin/gremlin tell "the backup finished"
#   echo "..." | ./.gremlin/gremlin tell
set -euo pipefail

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRANSCRIPT="$GREMLIN_DIR/transcript.md"

if [ "$#" -gt 0 ]; then
  msg="$*"
else
  msg="$(cat)"
fi

# Refuse to say nothing. A blank tell would be an empty assistant turn that
# bridges dutifully deliver as an empty message.
if [ -z "${msg//[[:space:]]/}" ]; then
  echo "tell: nothing to say (message was empty)" >&2
  exit 2
fi

iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '## assistant — %s\n%s\n\n' "$iso" "$msg" >> "$TRANSCRIPT"
echo "told: $msg"

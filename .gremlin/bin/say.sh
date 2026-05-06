#!/usr/bin/env bash
# say — local one-shot CLI bridge.
#
# Usage:
#   ./.gremlin/bin/say.sh "your message"   # send + wait for reply (default)
#   echo "..." | ./.gremlin/bin/say.sh     # same, message via stdin
#   ./.gremlin/bin/say.sh /foo bar         # slash dispatch: runs commands/foo.sh bar
#
# Send-and-wait writes the message into .nest/in/<ts>.md, then tails
# transcript.md until the next `## assistant —` turn appears past the
# submission point and prints its body. Slash messages dispatch directly
# to commands/<cmd>.sh and bypass both the LLM and the nest.

set -euo pipefail

if [ "${LC_ALL:-}" = "C.UTF-8" ]; then
  unset LC_ALL
fi

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEST="$GREMLIN_DIR/.nest"
NESTLING="$NEST/nestling.sh"
TRANSCRIPT="$GREMLIN_DIR/transcript.md"

TIMEOUT_SECS=60
POLL_SECS=0.5

# --- slash command dispatch --------------------------------------------
if [ "$#" -gt 0 ] && [ "${1#/}" != "$1" ]; then
  exec "$GREMLIN_DIR/bin/slash.sh" "$@"
fi

# --- send + wait (default) ---------------------------------------------
if [ "$#" -gt 0 ]; then
  msg="$*"
else
  msg="$(cat)"
fi

if [ -z "$msg" ]; then
  echo "usage: $0 <message>   (or pipe via stdin)" >&2
  exit 2
fi

# Snapshot transcript size before submission so we can read only what's
# appended after this message lands.
if [ -f "$TRANSCRIPT" ]; then
  start_size=$(wc -c < "$TRANSCRIPT" | tr -d ' ')
else
  start_size=0
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
fname_ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
printf '%s\n' "$msg" > "$tmp"
"$NESTLING" ingest "$tmp" "$fname_ts.md" >/dev/null

deadline=$(( $(date +%s) + TIMEOUT_SECS ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if [ -f "$TRANSCRIPT" ]; then
    cur_size=$(wc -c < "$TRANSCRIPT" | tr -d ' ')
    if [ "$cur_size" -gt "$start_size" ]; then
      tail_bytes=$(( cur_size - start_size ))
      reply=$(tail -c "$tail_bytes" "$TRANSCRIPT" | awk '
        /^## assistant — / { found=1; next }
        found && /^## / { exit }
        found { print }
      ')
      if [ -n "$reply" ]; then
        printf '%s\n' "$reply"
        exit 0
      fi
    fi
  fi
  sleep "$POLL_SECS"
done

echo "say: no reply within ${TIMEOUT_SECS}s" >&2
exit 1

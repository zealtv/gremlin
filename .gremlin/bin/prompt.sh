#!/usr/bin/env bash
# prompt — submit one conversational turn and wait for its response.
#
# Usage:
#   ./.gremlin/bin/prompt.sh "your message"
#   ./.gremlin/bin/prompt.sh --read-only "review this"
#   echo "..." | ./.gremlin/bin/prompt.sh
#
# The read-only option is prompt-level guidance, not an enforced sandbox.
# Slash commands do not dispatch here; shell callers use the gremlin wrapper's
# direct command surface (`gremlin model fast`, `gremlin update`, and so on).

set -euo pipefail

if [ "${LC_ALL:-}" = "C.UTF-8" ]; then
  unset LC_ALL
fi

GREMLIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_DIR="$(cd "$GREMLIN_DIR/.." && pwd)"
NEST="$HOST_DIR/.nest"
NESTLING="$NEST/nestling.sh"
TRANSCRIPT="$GREMLIN_DIR/transcript.md"

TIMEOUT_SECS=60
POLL_SECS=0.5
READ_ONLY_MARKER="gremlin-prompt-contract: read-only"

usage() {
  echo "usage: $0 [--read-only] <message>   (or pipe via stdin)" >&2
}

read_only=0
case "${1:-}" in
  --read-only)
    read_only=1
    shift
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  --)
    shift
    ;;
esac

if [ "$#" -gt 0 ]; then
  msg="$*"
else
  msg="$(cat)"
fi

if [ -z "${msg//[[:space:]]/}" ]; then
  usage
  exit 2
fi

# Snapshot transcript size before submission so we inspect only turns that
# land after this prompt. The transcript does not currently carry correlation
# ids, so this remains a first-subsequent-assistant-turn wait.
if [ -f "$TRANSCRIPT" ]; then
  start_size=$(wc -c < "$TRANSCRIPT" | tr -d ' ')
else
  start_size=0
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
fname_ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
if [ "$read_only" -eq 1 ]; then
  printf '%s\n\n%s\n' "$READ_ONLY_MARKER" "$msg" > "$tmp"
else
  printf '%s\n' "$msg" > "$tmp"
fi
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

echo "prompt: no response within ${TIMEOUT_SECS}s" >&2
exit 1

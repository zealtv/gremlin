#!/usr/bin/env bash
# speech-to-text preset
#
# Contract: stdin is the absolute path to ONE audio file; stdout is the verbatim
# transcript as plain text (never audio). The Telegram bridge runs this when a
# voice note arrives; the transcript becomes a normal `## user —` turn, so the
# gremlin's normal reply follows. This preset only transcribes.
#
# Default: hand the audio to the gremlin's OWN model — the same model it chats
# with (the active .model alias, e.g. codex) via bin/llm.sh — no API key, the way
# the image preset reuses the model for vision. The model MUST be able to HEAR
# audio; if it can't, transcription fails loudly (the bridge tells the user).
# Then override THIS file with a local engine to save tokens, e.g. whisper.cpp:
#
#   #!/usr/bin/env bash
#   set -euo pipefail
#   exec whisper-cli -f "$(cat)" --no-timestamps --output-txt -    # prints text
#
set -euo pipefail

gremlin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
audio="$(cat)"
printf 'Transcribe the audio file below verbatim. Output ONLY the transcript — no preamble, no commentary, no quotes.\n\nAudio file (open it): %s\n' "$audio" \
  | "$gremlin_dir/bin/llm.sh"

#!/usr/bin/env bash
# tts — text-to-speech preset (the audio analogue of models/voice.sh).
#
# Contract: stdin is the text to speak; stdout is the spoken audio as OGG/Opus
# bytes (a Telegram voice message). The Telegram bridge runs this when an
# assistant turn embeds `🔊 [text](tts:)`, captures the audio, and sends it via
# sendVoice; the rest of the turn goes as normal text. This preset only speaks.
#
# Unlike voice.sh (STT), there is no no-API-key way to make the chat model SPEAK,
# so this preset needs a real TTS engine on the host. The default uses espeak-ng
# (or espeak) to synthesize and ffmpeg to encode OGG/Opus — both widely packaged.
# If either is missing it FAILS LOUDLY: the bridge surfaces the error to the user
# and does not silently drop the turn. Override THIS file with a nicer engine to
# improve the voice, e.g. Piper:
#
#   #!/usr/bin/env bash
#   set -euo pipefail
#   piper --model en_US-amy-medium.onnx --output_file - <<<"$(cat)" \
#     | ffmpeg -hide_banner -loglevel error -i - -c:a libopus -f ogg pipe:1
#
set -euo pipefail

text="$(cat)"
[ -n "${text//[[:space:]]/}" ] || { echo "tts: empty text" >&2; exit 1; }

if command -v espeak-ng >/dev/null 2>&1; then
  say=(espeak-ng --stdout)
elif command -v espeak >/dev/null 2>&1; then
  say=(espeak --stdout)
else
  echo "tts: no TTS engine found (install espeak-ng, or override models/tts.sh)" >&2
  exit 1
fi

command -v ffmpeg >/dev/null 2>&1 || {
  echo "tts: ffmpeg is required to encode OGG/Opus (install it, or override models/tts.sh)" >&2
  exit 1
}

# espeak(-ng) reads the text on stdin and writes a WAV to stdout; ffmpeg
# transcodes that to the OGG/Opus a Telegram voice message expects.
printf '%s' "$text" | "${say[@]}" \
  | ffmpeg -hide_banner -loglevel error -i - -c:a libopus -f ogg pipe:1

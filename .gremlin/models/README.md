# models

A model preset is an executable script. The active alias is read from
`.gremlin/.model` (or `default` if absent), and the gremlin runs
`models/<alias>.sh` for every reply.

## Contract

A preset:

- reads the assembled prompt on **stdin**
- writes the reply on **stdout**
- exits **non-zero** on failure

That is the whole interface. Anything that fits — claude, gemini,
codex, pi, opencode, nanocoder, ollama, a Python script wrapping an
HTTP API, or a plain script with no model at all (see `echo.sh`) —
is a valid preset. Different harnesses take different flags; that's
exactly why the invocation lives per-preset.

## File name = alias

`models/fast.sh` -> alias `fast`. Switch at runtime with
`/model fast` in the TUI, or `gremlin say /model fast` from a script.
`/model` lists every `*.sh` in this directory,
marking the active one with `*`.

## Label

The first `# …` comment line after the shebang is the human-readable
label `/model` shows next to the alias. Keep it short.

```bash
#!/usr/bin/env bash
# fast — claude haiku
exec claude -p --model claude-haiku-4-5 --allowedTools "Bash"
```

If a preset has no label line, `/model` shows just the filename.

## Adding a preset

Drop a new file in this directory, make it executable, give it a
label. Three presets ship as starting points:

- `default.sh` — canonical LLM example with commented starter
  invocations for several agent CLIs.
- `memory.sh` — conventional alias for memory-review work. It delegates to
  `default.sh` unless you specialize it.
- `image.sh` — conventional alias for understanding inbound images. The
  Telegram bridge stamps a received photo with `.model = image`, so this preset
  runs for that turn (per-item `.model` override). Point it at a vision-capable
  invocation — for claude, include `Read` in `--allowedTools` so it can open the
  image file; codex/gpt-5.x reads images natively. Delegates to `default.sh`
  until specialized.
- `voice.sh` — speech-to-text preset for inbound voice notes. Unlike the others,
  its **stdin is the absolute path to one audio file** and its stdout is the
  verbatim transcript (text only). The Telegram bridge runs it when a voice note
  arrives; the transcript becomes a normal `## user —` turn, so the gremlin's
  normal reply follows. It defaults to asking the gremlin's active model to hear
  the file (no API key) — override it with a local engine (e.g. whisper.cpp) to
  stop spending tokens on STT, exactly like any preset.
- `tts.sh` — text-to-speech preset for outbound voice, the inverse of `voice.sh`:
  its **stdin is text** and its **stdout is OGG/Opus audio bytes**. The Telegram
  bridge runs it when an assistant turn embeds `🔊 [text](tts:)`, then sends the
  audio as a voice message. Unlike `voice.sh`, there is no no-API-key way to make
  the chat model speak, so it needs a real engine: the default uses
  `espeak-ng`/`espeak` + `ffmpeg` and fails loudly if they are absent. Override it
  with a nicer engine (e.g. Piper) for a better voice.
- `echo.sh` — script-only example that echoes the incoming item
  back, useful as a starting point for routers, fixed-response
  bots, lookup tables, or local rule engines that need a
  deterministic reply without a model.

Runnable per-harness references (claude, codex, gemini, ollama) live in
`models/examples/` — delivered and refreshed by `/update`, unlike the live
`models/*.sh` presets, which are host-owned. Copy one out rather than
editing it in place.

Copy from one, or write your own.

```sh
cp models/default.sh models/local.sh
chmod +x models/local.sh
$EDITOR models/local.sh   # uncomment one block, drop the rest
./.gremlin/gremlin model local
```

## Permissions

There is no enforced sandbox at the gremlin layer. Each harness has
its own permissions model — claude has `--allowedTools`, others have
their equivalents — and the appropriate flag goes inside the preset.
The convention is to host a gremlin in a directory where broad
filesystem reach is acceptable. See `docs/composition.md` for notes on
OS-level isolation.

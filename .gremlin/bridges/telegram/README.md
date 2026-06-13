# telegram bridge

Telegram bridge for a gremlin.

This bridge polls one Telegram bot chat for inbound text messages and writes
them into `.nest/in/`. It also watches `transcript.md` for assistant and system
turns and pushes them back to the configured Telegram chat. User turns are
skipped — the user already sent them.

## Requirements

- `curl`
- `jq`
- a configured gremlin model preset
- one Telegram bot token
- one numeric Telegram chat id

## Setup

Create a bot with BotFather in Telegram and copy the token. Get your numeric
chat id; `@myidbot` is a simple way to ask Telegram for it.

Copy the example config:

```sh
cp ./.gremlin/bridges/telegram/config.example ./.gremlin/bridges/telegram/config
```

Edit `config` with your bot token and the single chat id the bridge should
accept:

```sh
chmod 600 ./.gremlin/bridges/telegram/config
```

`config` is local runtime state and must not be committed. If the token leaks,
regenerate it with BotFather and update this file.

## Run

```sh
./.gremlin/gremlin telegram start
./.gremlin/gremlin telegram status
./.gremlin/gremlin telegram stop
./.gremlin/gremlin telegram restart
```

Runtime state lives beside the bridge:

- `telegram.log`
- `telegram.pid`
- `.cursor`
- `.update-offset`
- `config`

These files are ignored by git.

## Verify

Start the runner and bridge:

```sh
./.gremlin/gremlin start
./.gremlin/gremlin telegram start
./.gremlin/gremlin telegram status
```

Send a normal Telegram text message. It should appear in the TUI/transcript, and
one assistant reply should return to Telegram. Outbound delivery runs on its own
loop, so an assistant turn lands in Telegram within `TELEGRAM_PUSH_INTERVAL`
seconds (default `1`) of being appended to the transcript.

To verify proactive outbound, ask for a short reminder:

```text
remind me in 1 minute to test telegram
```

The reminder should land under `.gremlin/.groundhog/`, appear in the transcript
when fired, and then push to Telegram.

## Loops

The bridge daemon (`telegram run`) is a supervisor that forks three independent
background loops and reaps them on `INT`/`TERM`:

- **inbound poll** — calls `getUpdates` with a long-poll (up to
  `TELEGRAM_POLL_TIMEOUT` seconds, default `30`). On failure it logs and sleeps
  `TELEGRAM_POLL_SLEEP` (default `1`) before retrying. Long-poll keeps inbound
  latency near zero without spinning the Telegram API.
- **outbound push** — tails `transcript.md` and sends new assistant and system
  turns. On success it sleeps `TELEGRAM_PUSH_INTERVAL` (default `1`); on failure
  it sleeps `TELEGRAM_OUTBOUND_BACKOFF` (default `5`). Splitting this from the
  inbound loop means an assistant turn that lands during a long-poll no longer
  waits up to `TELEGRAM_POLL_TIMEOUT` for delivery.
- **typing pulse** — every `TELEGRAM_PULSE_INTERVAL` seconds (default `4`),
  sends `sendChatAction typing` if a telegram-origin nest item is outstanding.

If any loop exits unexpectedly, the supervisor kills the others and exits so
the recorded pid matches reality.

### In-flight inference

The pulser keeps no state. Each tick it globs `.nest/in/*-telegram-*` — matching
text items (`*.md`), claimed items (`*.tending`), and media item directories
alike. When the tender moves the item to `.nest/out/`, the glob goes empty and
the pulser naturally goes quiet. No flag files, no counters, no per-message
bookkeeping.

## Behavior

- Only messages from `TELEGRAM_CHAT_ID` are accepted; other chats are ignored.
- Text messages are written into `.nest/in/` as before.
- Images (a photo, or a document with an `image/*` mime type) are captured: the
  bridge downloads the file into a nest item directory as `source.<ext>`, writes
  an `instructions.md` framing the turn (with any caption), and stamps the item
  with `.model = image` so the tender runs the vision preset (`models/image.sh`).
  If ImageMagick is available, a scaled `preview.<ext>` is added and the model is
  pointed at it first, with the original available on demand; without a resizer
  the original is used directly. The tender appends the attachment's absolute
  path so the model can open it.
- Other non-text updates (stickers, voice, video, …) are still ignored.
- On first launch, a missing `.cursor` initializes to the current end of
  `transcript.md`; old transcript history is not pushed to Telegram.
- Every new assistant or system turn is pushed to the configured chat.
  System turns (`⚙️ run:`, `⚠️ error:`, `💌 message:`, …) go through with their
  emoji+label intact — the body is sent verbatim.
- Images: a turn may embed `![caption](path-or-url)`. Each reference is sent as
  a photo (`sendPhoto`) with the alt text as the caption; the rest of the turn,
  with the image markdown stripped, is sent as a normal message. A relative
  `path` resolves against the host folder (the gremlin's working directory); an
  absolute path or an `http(s)://` URL is used as-is. A missing local file logs
  an error and fails the push rather than sending a broken turn.
- `/start` is not special-cased; Telegram's setup message reaches the gremlin as
  ordinary text.

## Troubleshooting

- `telegram bridge stopped (unconfigured)`: create `bridges/telegram/config`.
- Bad token: Telegram API calls fail; regenerate the token with BotFather if in
  doubt.
- Wrong chat id: messages are ignored because they are not from the configured
  chat.
- No reply: check `./.gremlin/gremlin status`; the runner must be running to tend
  inbound messages.
- Runner paused: messages can be ingested while `.gremlin/.paused` exists, but
  replies wait until it is removed.
- Stop seems slow: `getUpdates` long-polls, so `telegram stop` can take up to
  `TELEGRAM_POLL_TIMEOUT` to return — the supervisor's `TERM` kills the child
  `curl`, and `telegram.sh` honours `TELEGRAM_STOP_TIMEOUT` (default `35`).
- Duplicate old replies after first startup should not happen. A missing
  `.cursor` initializes to the current end of `transcript.md`.

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
one assistant reply should return to Telegram. Telegram delivery is poll-based;
in local testing it lagged the TUI by several seconds.

To verify proactive outbound, ask for a short reminder:

```text
remind me in 1 minute to test telegram
```

The reminder should land under `.gremlin/.groundhog/`, appear in the transcript
when fired, and then push to Telegram.

## Behavior

- Only text messages from `TELEGRAM_CHAT_ID` are accepted.
- Messages from other chats are ignored.
- Non-text updates are ignored.
- On first launch, a missing `.cursor` initializes to the current end of
  `transcript.md`; old transcript history is not pushed to Telegram.
- Every new assistant or system turn is pushed to the configured chat.
  System turns (`⚙️ run:`, `⚠️ error:`, `💌 message:`, …) go through with their
  emoji+label intact — the body is sent verbatim.
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
- Stop seems slow: `getUpdates` long-polls, so `telegram stop` can take up to the
  poll timeout.
- Duplicate old replies after first startup should not happen. A missing
  `.cursor` initializes to the current end of `transcript.md`.

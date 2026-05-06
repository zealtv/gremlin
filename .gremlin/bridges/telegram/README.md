# telegram bridge

Telegram bridge for a gremlin.

This bridge polls a single Telegram bot chat for inbound text messages and
writes them into `.nest/in/`. It also watches `transcript.md` for assistant
turns and pushes them back to the configured Telegram chat.

## Setup

Copy the example config:

```sh
cp ./.gremlin/bridges/telegram/config.example ./.gremlin/bridges/telegram/config
```

Edit `config` with your bot token and the single chat id the bridge should
accept. `config` is local runtime state and must not be committed.

The bridge requires `curl` and `jq`.

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

## Behavior

- Only text messages from `TELEGRAM_CHAT_ID` are accepted.
- Messages from other chats are ignored.
- Non-text updates are ignored.
- On first launch, a missing `.cursor` initializes to the current end of
  `transcript.md`; old transcript history is not pushed to Telegram.
- Every new assistant turn is pushed to the configured chat.

The staged verification stitches under `.loom/threads/stage-11-bridges/` will
turn real local-bot findings into fuller setup and troubleshooting docs.

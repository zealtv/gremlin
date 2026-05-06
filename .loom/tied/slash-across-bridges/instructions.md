# slash-across-bridges

**Outcome.** Slash commands behave consistently across every bridge. They
run `commands/<cmd>.sh`, never reach the model, and never touch the
transcript. The Telegram bridge stops leaking `/foo` into the LLM as
ordinary user text.

## Why this matters

Today the TUI parses `/foo` in `bridges/tui/tui.sh:run_slash` and renders
output ephemerally. `bin/say.sh` does its own inline dispatch. The Telegram
bridge has no slash handling at all — every `/help` or `/new` typed on the
phone gets ingested into `.nest/in/` and the model replies in prose. Three
call sites, two implementations, one missing. Adding bridges multiplies the
problem.

## Strategy

One small dispatcher, `bin/slash.sh`, owns parsing and lookup. Bridges call
it and decide how to surface output:

- **TUI** — capture stdout, render ephemerally in the local buffer
  (existing UX preserved). Keeps its own `exit`/`quit` short-circuit because
  those control the TUI process.
- **say** — `exec` the helper.
- **Telegram** — capture stdout, send back as a chat message, do not ingest
  into `.nest/in/`.

No transcript writes, no nest writes from slash commands on any bridge.

## Children

- `s01-extract-slash-helper` — write `bin/slash.sh`. No call-site changes.
- `s02-rewire-tui-and-say` — make TUI and `say.sh` use the helper. Behavior
  unchanged; this proves the helper's contract on the existing surfaces
  before adding a new one.
- `s03-telegram-shortcircuit` — branch in `handle_update` to call the helper
  and `send_message` the output for `/`-prefixed text.

Order is sequential — name prefixes enforce it.

## Verification (whole-thread gate)

1. TUI `/help`, `/model` — ephemeral output, transcript clean.
2. `bin/say.sh /help` — prints help.
3. Telegram `/help` — chat reply arrives; nothing in transcript or
   `.nest/`.
4. Telegram `/nope` — `unknown command` reply.
5. Telegram plain text still round-trips through the model.
6. Other-chat messages still rejected (chat_id guard runs first).

# system-turn-type

**Outcome.** A third transcript turn type, `## system —`, sits alongside `## user —` and `## assistant —`. Sub-categorisation is by emoji prefix in the body, so the grammar stays stable while the vocabulary grows.

## Why

`/stop` aborts and scheduled run-script output both want to appear in the transcript without pretending to be the assistant. Future statuses (errors, rate-limit notices, tool-use traces, model switches) need a home too. One bucket — `system` — beats inventing a new role per use case.

## Convention

- Header: `## system — <iso>` (same shape as user/assistant).
- Body: first line `<emoji> <label>: <message>`; remaining lines free-form.
- Tender does **not** write system turns. They are written by callers — slash commands (`/stop`), the tick loop (script output), bridges, etc.
- Bridges may style by emoji prefix; they must not eat or rewrite the body.

## Initial sub-categories (extensible)

- `⚙️ run:` — a script ran, or an item was aborted.
- `⚠️ error:` — runtime failure worth surfacing.

Add more as needed; the convention is just "first line, emoji + label + colon."

## Children

- `format-and-docs` — define the convention; document in `docs/protocol.md` and `docs/composition.md`. Unblocks dependants below.
- `tui-render` — TUI bridge styles system turns distinctly.
- `telegram-render` — Telegram bridge passes system turns through (decision: send vs filter).

## Dependants (other threads waiting on this)

- `stop-command/stop-slash-command` — needs the format to write the abort turn.
- `groundhog-run-scripts` — needs the format to surface script output.

These can start once `format-and-docs` is tied; rendering is independent.

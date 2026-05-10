# tui-render

**Outcome.** The TUI renders `## system —` transcript turns visibly distinct from user and assistant turns, while passing the body (including the leading emoji) through.

## Touchpoints

- `bridges/tui/tui.sh` — transcript renderer / role styling.
  - awk role match: `^## (user|assistant) — ` (around lines 271, 277). Add `system`.
  - `render_turn` label colour switch (lines 228–229). Add `system → 226`.

## Steps

1. Extend the awk role regex and the body-matcher to recognise `system` alongside `user` and `assistant`.
2. In `render_turn`, set `label_color=226` when role is `system` — yellow, matching the title bar (`bg 226`) and the gremlin status face (`color 226`). Keeps the visual family coherent: yellow = "voice from outside the conversation".
3. Do not rewrite the body. The emoji+label (`⚙️ run:`, `⚠️ error:`, `💌 message:`, …) is part of the message and carries the sub-category.

## Sub-categories the renderer must pass through

Per `docs/protocol.md` and `format-and-docs`:

- `⚙️ run:` — script ran / item aborted.
- `⚠️ error:` — runtime failure surfaced.
- `💌 message:` — scheduled `message.md` body emitted by the tender. **This is the only system sub-type currently emitted in the wild** (by `bin/tick-loop.sh` for scheduled message items), so it's the live case to verify.

The renderer must not special-case any sub-type — they all render as a yellow `system` header with the body verbatim.

## Verify

- Append a `## system — <iso>\n⚙️ run: hello\n\n` block manually; open the TUI; turn renders with a yellow `system` label, body intact.
- Append a `⚠️ error: ...` system turn; same — yellow header, body intact.
- Schedule a `once/<near-date>/<HH-MM>/<slug>/message.md` groundhog item; let it fire; the resulting `## system — 💌 message: <body>` turn renders yellow with the 💌 line preserved.
- Old transcripts (no system turns) render unchanged.

## Consistency / staleness

- `bridges/tui/README.md` — note the system role rendering if it documents transcript display.
- Sibling: `telegram-render` should make a parallel decision (pass-through vs styled).

Waits on `format-and-docs` only nominally — convention can be inferred from this thread's parent. Safe to claim once the convention is documented.

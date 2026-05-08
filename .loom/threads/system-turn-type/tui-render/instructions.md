# tui-render

**Outcome.** The TUI renders `## system —` transcript turns visibly distinct from user and assistant turns, while passing the body (including the leading emoji) through.

## Touchpoints

- `bridges/tui/tui.sh` — transcript renderer / role styling.

## Steps

1. Find where the TUI matches `## user —` and `## assistant —`. Add the `system` role.
2. Pick a styling that reads as "not conversational" — dim colour, framed line, italic, or just leaving the body as-is with the emoji doing the work. Lean understated.
3. Do not rewrite the body. The emoji+label is part of the message.

## Verify

- Append a `## system — <iso>\n⚙️ run: hello\n\n` block manually; open the TUI; turn renders distinctly.
- Append a `⚠️ error: ...` system turn; same — distinct, body intact.
- Old transcripts (no system turns) render unchanged.

## Consistency / staleness

- `bridges/tui/README.md` — note the system role rendering if it documents transcript display.
- Sibling: `telegram-render` should make a parallel decision (pass-through vs styled).

Waits on `format-and-docs` only nominally — convention can be inferred from this thread's parent. Safe to claim once the convention is documented.

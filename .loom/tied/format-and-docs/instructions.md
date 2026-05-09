# format-and-docs

**Outcome.** The `## system —` transcript turn type is documented and reserved across the codebase. Other threads (`stop-command`, `groundhog-run-scripts`) can start work against this contract.

## Spec

- Header: `## system — <iso>` (matches `## user —` / `## assistant —`).
- Body: first line `<emoji> <label>: <message>`; remaining lines free-form.
- Tender writes user and assistant turns only — never system. Callers (slash commands, tick loop, bridges) write system turns.
- Initial sub-categories: `⚙️ run:`, `⚠️ error:`. Vocabulary grows by adding new emoji+label, never new headers.

## Touchpoints

- `docs/protocol.md` — Transcript section: add the third turn type and the body convention; clarify that the tender does not author it.
- `docs/composition.md` — if it discusses transcript shape, mirror.
- `.gremlin/README.md` — if Quick Start or anywhere shows transcript snippets, sweep.
- No code changes here. `bin/say.sh` does not need to learn `system` (callers append directly).

## Verify

- Manually append a `## system — <iso>\n⚙️ run: hello\n\n` block to a personal copy's `transcript.md`. Tender continues to function (does not crash, does not try to interpret it as a user turn).
- `docs/protocol.md` accurately describes who writes which turn types.

## Consistency / staleness scan

- Anywhere transcript shape is documented (README, dev docs, CLAUDE.md if present).
- Any existing bridge code that splits on `^## ` headings — confirm a third role doesn't break parsing. Note any blockers for `tui-render` / `telegram-render` siblings.
- Search for hard-coded `assistant`/`user` lists that would need `system` adding.

# stage-7-groundhog

**Outcome.** Scheduled outbound messages and scheduled work both flow through the gremlin. Outbound needs no agent invocation.

Tie this stitch when every child is tied and a short note below records what was learned.

## Notes

- s28 routing rule (mirrors README): item with `message.md` → outbound (move file to `.nest/out/<ts>.md`); item without → tending (move whole dir to `.nest/in/`).
- Same-FS `mv` is atomic on POSIX; no `.landing` dance needed for the tick-loop's renames.
- Loom text mentions a `<minute>` axis for `once/`; groundhog has no such axis. The MVP fires immediate scheduled items via bare `once/<item>/` (no date), which fires on the very next tick.
- s30 needed a passive bridge mode — added `say --listen`. Indefinite watcher; prints new files in `.nest/out/` and moves them to `sent/`. Useful for scheduled outbound and any future bridge.
- s31 surfaced a tend-loop bug: dir items only checked for `message.md`. Fixed: prefer `instructions.md` (procedural request — *do* something), fall back to `message.md` (verbatim user text).
- Stage-7 outcome: all four data flows wired — say→tend→reply, scheduled outbound bypassing tender, scheduled tending invoking tender, and the self-pacing follow-up pattern (tender writes a future `instructions.md` via remind-me-style skill).
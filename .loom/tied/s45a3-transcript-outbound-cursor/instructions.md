# s45a3-transcript-outbound-cursor

Implement transcript tailing and outbound Telegram sends with cursor semantics.

## Outcome

The bridge watches `transcript.md`, extracts new assistant turns after `.cursor`, sends each turn to Telegram with `sendMessage`, and advances `.cursor` only after successful sends.

## Scope

- Missing `.cursor` initializes to the current end of `transcript.md` on first launch.
- Cursor is a byte offset into `transcript.md`.
- Push only `## assistant -` / `## assistant —` turns, matching the transcript format in practice.
- Skip user turns.
- Do not advance cursor when `sendMessage` fails.
- Retry failed sends with a modest backoff.
- Handle transcript truncation/rotation by resetting sensibly without replaying old history.

## Verify

1. `bash -n` passes.
2. Local transcript parsing checks cover one assistant turn, multiple turns, and partial trailing turn.
3. Failed outbound send does not advance `.cursor`.
4. Real-bot restart/no-duplicate behavior is left for `s45d-outbound-cursor-verification`.

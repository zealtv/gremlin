# s47d-capture

*(scribble repo)*

`scribble.sh capture <id>` reads stdin and lands the item ready in `in/`. The pipe-friendly inbound seam for tenders and other agents.

## Outcome

`./scribble.sh capture <id>` reads stdin, writes it to `.scribble/in/<id>/note.md`, and lands the item ready in one shot. Replaces the previously-suggested `ingest <id> -` form.

## Scope

- Add `cmd_capture` to `scribble.sh`.
- Validate the id with the existing `validate_id` helper.
- Refuse if `.scribble/in/<id>` or `.scribble/in/<id>.scribbling` already exists.
- Write stdin to `.scribble/in/<id>.scribbling/note.md`, then atomically rename to `.scribble/in/<id>/`. Same two-step idiom as `ingest` + `ready` but without the manual edit window.
- Empty stdin still produces a valid item with an empty `note.md`.
- Update `README.md` and the `usage` block.
- Mention the relationship to `ingest` in the README: `ingest` is for human-edited notes; `capture` is for piped input.

## Verify

1. `printf "x\n" | ./scribble.sh capture sample` lands `.scribble/in/sample/note.md` with that content.
2. Re-running with the same id fails cleanly without clobbering.
3. `printf "" | ./scribble.sh capture empty` produces an empty `note.md` and lands ready.
4. Failure mid-write leaves an `.scribbling` form, never a half-written ready item.

## Notes

The verb is `capture`, not `ingest -`. Distinct verb makes the pipe path discoverable in `--help` without overloading `ingest`'s argument grammar.

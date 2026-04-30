# s06-tend-loop

`bin/tend-loop.sh`:

1. List ready items via `.nest/nestling.sh list`; bail if empty.
2. Claim the oldest item.
3. Build the prompt by concatenating, in order:
   - `gremlin.md` (identity, framing)
   - every file in `context/` matching `*.md`, sorted (skip silently if folder is absent or empty)
   - `transcript.md`
   - the item body
   (Skills `INDEX.md` and `tools/README.md` slot in at stages 5 and 6 — leave the assembly extensible.)
4. Pipe to `bin/llm.sh`; capture reply.
5. Write the reply to `.nest/out/<ts>.md` via `.landing` rename.
6. Append `## assistant — <iso8601>\n<reply>\n\n` to `transcript.md`.
7. Complete the claimed item via `.nest/nestling.sh complete`.

**Verify:** Drop a file in `.nest/in/` by hand, run the loop once, see a reply in `.nest/out/` and the transcript updated. Drop a file into `context/test.md` and confirm the LLM's reply reflects that fact.

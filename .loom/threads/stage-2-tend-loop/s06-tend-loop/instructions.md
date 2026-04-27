# s06-tend-loop

`bin/tend-loop.sh`:

1. List ready items via `.nest/nestling.sh list`; bail if empty.
2. Claim the oldest item.
3. Build the prompt: `tend.md` + `transcript.md` + the item body. (Skills and tools come in later stages — leave hooks for them.)
4. Call `bin/llm.sh`; capture reply.
5. Write the reply to `.nest/out/<ts>.md` via `.landing` rename.
6. Append `## assistant — <iso8601>\n<reply>\n\n` to `transcript.md`.
7. Complete the claimed item.

**Verify:** Drop a file in `.nest/in/` by hand, run the loop once, see a reply in `.nest/out/` and the transcript updated.

# s30-acceptance-7-outbound

Add a `schedule/once/<today>/<minute>/hello/message.md` containing "good morning". On the next tick:

- The file appears in `.nest/out/`.
- A running `say` (in tail mode) prints it.
- No tender invocation occurred (no `## assistant` turn in the transcript for this).

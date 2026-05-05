# tui bridge

Terminal bridge for a gremlin.

Run it beside the gremlin runner:

```sh
./.gremlin/run.sh
./.gremlin/bridges/tui/tui.sh
```

The TUI reads `transcript.md`, writes submitted messages into `.nest/in/`
through `nestling ingest`, and dispatches slash commands from `commands/`.
Slash command output is shown only in the TUI; it is not written to the
transcript.

State lives in `.cursor`, a byte offset into `transcript.md`. If `.cursor`
is missing, the TUI replays transcript history from the beginning. If the
transcript is archived or truncated, the cursor resets to the beginning.

# tui bridge

Terminal bridge for a gremlin.

Run it beside the gremlin runner:

```sh
./.gremlin/run.sh
./.gremlin/bridges/tui/tui.sh
```

The TUI reads `transcript.md` from the beginning on launch, writes submitted
messages into `.nest/in/` through `nestling ingest`, and dispatches slash
commands from `commands/`. Slash command output is shown only in the TUI; it is
not written to the transcript.

The input area wraps long drafts. `Enter` submits the current draft, and
`Ctrl-N` inserts a newline.

`/exit` and `/quit` are local TUI commands. They close the bridge and are not
looked up in `commands/`.

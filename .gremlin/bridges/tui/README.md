# tui bridge

Terminal bridge for a gremlin.

Run it beside the gremlin runner:

```sh
./.gremlin/gremlin start
./.gremlin/gremlin tui
```

The TUI reads `transcript.md` from the beginning on launch, writes submitted
messages into `.nest/in/` through `nestling ingest`, and dispatches slash
commands from `commands/`. Slash command output is shown only in the TUI; it is
not written to the transcript.

The input area wraps long drafts. `Enter` submits the current draft, and
`Ctrl-N` inserts a newline.

`/exit` and `/quit` are local TUI commands. They close the bridge and are not
looked up in `commands/`.

`/stop` is the emergency abort: while a model reply is pending, it kills the
in-flight call, drops the claim, and writes a `## system — ✋ item aborted`
turn. Useful when you've just sent the wrong prompt or the model is on a
runaway tangent.

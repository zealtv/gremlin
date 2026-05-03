# s47-tui-bridge

First proper bridge. Replaces the three-terminal `run.sh` + `say --repl` + `say --listen` workflow with a single terminal running the TUI alongside `run.sh`.

**Library-agnostic for this stitch.** Pick the TUI library at build time. Spec is shape and behaviour, not framework.

## Layout

New folder: `.gremlin/bridges/tui/`. This is also where the bridges convention is established — the first inhabitant. Stitch is permitted to create `bridges/` from scratch.

```
bridges/
  tui/
    tui.sh           # entry point; long-running daemon
    .cursor          # last rendered transcript turn (created at runtime)
    README.md        # what the bridge is, how to launch
```

## Shape

- Two panes:
  - **Upper:** scrolling transcript view. Tails `transcript.md`. Renders `## user` and `## assistant` turns with timestamps.
  - **Lower:** single-line input field.

## Inbound (user types)

- On submit, write the message to `.nest/in/<iso>.md`. Same path `say` uses today. The runner's tend-loop will pick it up.
- Render the user's line immediately in the transcript pane with a *pending* affordance (spinner / dim styling). This is local, not from the file.
- Reconcile when the matching `## user — <iso>` turn appears in `transcript.md`. The pending line is replaced/promoted to a confirmed turn. The file write is the source of truth.
- Slash commands (`/foo bar`) dispatch the same way `say` does today: shell out to `commands/<cmd>.sh` with args. **Slash command output renders ephemerally in the transcript pane and is not written to `transcript.md`.** Exception: a future command may opt in to transcript writes itself; default is ephemeral.

## Outbound (agent replies, scheduled pushes)

- Tail `transcript.md`. Whenever a new `## assistant — <iso>` turn appears past the cursor, render it.
- This covers both regular replies *and* groundhog-fired proactive messages, because s48 routes both through the transcript.
- Bridge does not consume `.nest/out/`.

## Cursor

- File: `bridges/tui/.cursor`.
- Contents: the iso timestamp (or byte offset — pick one and document) of the last turn rendered.
- On startup: read cursor; render nothing already past it; render new turns as they arrive; advance cursor as each is rendered.
- If cursor is missing on first launch: render nothing historical. The user starts fresh. (Alternative: render the last N turns. Decide during build; default is fresh.)

## Out of scope

- Theming / styling beyond minimal legibility.
- Scrollback search.
- Multiline input (single-line only this stitch).
- History recall (up-arrow). Defer.
- Any per-message routing logic. All assistant turns render.

## Verify

1. With `run.sh` running, launch `bridges/tui/tui.sh`.
2. Type `hi` in the input. The line appears immediately in the pane (pending). Within seconds, it firms up as a `## user` turn, and an assistant reply follows.
3. Issue `/help`. Output renders in-pane. `transcript.md` is unchanged by the slash command.
4. Schedule a reminder for one minute from now via natural language.
5. Wait. The reminder appears in the TUI pane as an assistant turn, with no user prompt preceding it. `transcript.md` contains the proactive `## assistant — <iso>` entry.
6. Quit and relaunch the TUI. It does not re-render the entire transcript — only turns past the cursor (none, immediately).
7. `--repl` and `--listen` are not invoked anywhere; user has one terminal for `run.sh` and one for the TUI.

## Dependencies

- s48 must land first (or in lockstep). Without s48, scheduled proactive messages don't reach `transcript.md` and the TUI won't see them.

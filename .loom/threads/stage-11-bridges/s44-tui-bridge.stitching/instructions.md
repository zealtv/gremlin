# s44-tui-bridge

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

- On submit, write the message to `.nest/in/<iso>.md`. **Do not** append to `transcript.md` — the tender owns transcript writes (per stage-11 goal).
- The user's submitted line stays visible in the input field with a *processing* affordance (spinner / dim styling) until it appears in `transcript.md` as a `## user —` turn (the tender will write it at claim time). When that happens, clear the input field; the line is now in the transcript pane via the normal tail path.
- Slash commands (`/foo bar`) dispatch the same way `say` does today: shell out to `commands/<cmd>.sh` with args. **Slash command output renders ephemerally in the transcript pane and is not written to `transcript.md`.** Slash dispatch is synchronous and quick — the input field clears immediately on dispatch (no processing affordance needed). A future command may opt in to transcript writes itself; default is ephemeral.

## Outbound (agent replies, scheduled pushes)

- Tail `transcript.md`. Whenever a new `## assistant — <iso>` turn appears past the cursor, render it.
- This covers both regular replies *and* groundhog-fired proactive messages, because s43 routes both through the transcript.
- Bridge does not consume `.nest/out/`.

## Cursor

- File: `bridges/tui/.cursor`.
- Contents: byte offset into `transcript.md`. This deliberately differs from the original timestamp sketch: byte offsets avoid same-second timestamp collisions and match how the bridge tails the file.
- On startup: read cursor; render content after it; render new turns as they arrive; advance cursor to the transcript size after each poll.
- If cursor is missing on first launch: replay transcript history from the beginning, then save the byte offset.
- If the transcript is archived or truncated and the saved cursor is past EOF, reset to the beginning.

## Out of scope

- Theming / styling beyond minimal legibility.
- Scrollback search.
- Multiline input (single-line only this stitch).
- History recall (up-arrow). Defer.
- Any per-message routing logic. All assistant turns render.

## Verify

1. With `run.sh` running, launch `bridges/tui/tui.sh`.
2. Type `hi` in the input. The line stays in the input field with a processing affordance. Within seconds, the input clears and the `## user` turn appears in the transcript pane (written by the tender at claim time), followed by the assistant reply.
3. Issue `/help`. Output renders in-pane. `transcript.md` is unchanged by the slash command.
4. Schedule a reminder for one minute from now via natural language.
5. Wait. The reminder appears in the TUI pane as an assistant turn, with no user prompt preceding it. `transcript.md` contains the proactive `## assistant — <iso>` entry.
6. Quit and relaunch the TUI. It does not re-render the entire transcript — only turns past the cursor (none, immediately).
7. `--repl` and `--listen` are not invoked anywhere; user has one terminal for `run.sh` and one for the TUI.

## Dependencies

- s43 must land first (or in lockstep). Without s43, scheduled proactive messages don't reach `transcript.md` and the TUI won't see them.

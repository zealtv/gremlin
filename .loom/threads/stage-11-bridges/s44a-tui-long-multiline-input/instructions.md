# s44a-tui-long-multiline-input

Make the TUI input field usable for long and multiline messages, and clean up the rough edges noticed while using the first bridge.

This is a focused follow-up to `s44-tui-bridge`. The initial bridge deliberately shipped a single-line input field, but the current implementation truncates long input visually (`tui.sh` renders only the leading slice of `input`). That makes drafting anything longer than the terminal width lossy from the user's point of view, and prevents natural multiline prompts.

## Problem

- Long input must not disappear off the right edge with no way to see or edit the rest.
- Users need a deliberate way to enter multiline text before submitting it to `.nest/in/`.
- The pending affordance from s44 still needs to work for multiline submissions.
- Stable UI chrome should not flicker. The title bar, divider, and footer/status bar should not be repainted on every idle poll.
- Typing should feel responsive while the bridge is polling transcript changes.
- Slash command output must stay inside the TUI pane. In particular, `/model` must not leak shell/debug-looking output into the alternate screen.

## Shape

- Replace the bottom single-line input affordance with a small wrapping editor area.
- Long lines wrap within the terminal width instead of being cut off.
- Multiline input is supported with `Ctrl-J` to insert a newline and `Enter` to submit. Document it in `bridges/tui/README.md`, and show a dim hint in the empty input area.
- Submission writes the exact entered body to `.nest/in/<iso>.md`, preserving newlines.
- Slash commands still dispatch as commands when the whole input begins with `/`; command output remains ephemeral and is not written to `transcript.md`.
- Keep the TUI dependency-free unless the implementation proves the shell editor path is too brittle. If a dependency is introduced, document why and keep launch/install behaviour clear.
- Remove the startup transcript-pane line `Ctrl-D exits. Slash commands render here only.`
- Split redraws into dirty regions so the title, divider, transcript pane, input area, and footer/status are only repainted when their content or layout changes.
- Capture slash command stdout/stderr to a temporary file before rendering it into the TUI pane.

## Behaviour

- The input area should have a bounded height so it cannot consume the transcript pane completely.
- When input exceeds that height, keep the cursor/editing focus visible by scrolling the input view.
- Backspace, printable input, submit, interrupt/quit, and terminal resize must keep behaving predictably.
- Empty or whitespace-only submissions should not create nest items.
- Pending display should preserve enough of a multiline submission to make it clear what is waiting, without breaking the layout.
- Process all immediately available keypresses before returning to the poll sleep, so fast typing does not queue behind one-key-per-poll behaviour.

## Verify

1. Launch `run.sh` and `bridges/tui/tui.sh`.
2. Type a message longer than the terminal width. It wraps or scrolls visibly; no characters are silently hidden from the editable view.
3. Submit it. The created `.nest/in/<iso>.md` contains the full message.
4. Enter a multiline prompt, submit it, and confirm the nest item preserves line breaks exactly.
5. Confirm the user turn and assistant reply render normally in the transcript pane.
6. Run `/help` from the TUI and confirm it still dispatches as an ephemeral slash command.
7. Resize the terminal while drafting long input; the display remains coherent and the draft is not lost.
8. Leave the TUI idle and pending; the title bar, divider, and footer/status bar do not visibly flicker.
9. Run `/model` and `/model default`; output appears only in the TUI pane, the footer model label updates, and `transcript.md` is unchanged.

## Dependencies

- s44 must already be tied. This stitch is ordered as `s44a` so it lands before the remaining stage-11 bridge work while staying out of the stage-10 `s47-s52` memory range.

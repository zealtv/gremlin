# stage-11-bridges

**Outcome.** Bridges become a first-class concept. The TUI is the first proper bridge. The runner owns outbound. `transcript.md` is the single surface bridges read; `.nest/in/` is the single surface they write. `say --repl` and `say --listen` retire.

**This is the goal stitch only.** Child stitches need their own `instructions.md` before being claimed.

## Strategy

**Bridges fan out from the transcript.**

- Every bridge is a long-running daemon. Many can run simultaneously — a TUI in one terminal, Telegram as a service, future bridges as they arrive.
- Each bridge has the same shape: tail `transcript.md` for assistant turns → render/push to its channel; accept user input → write to `.nest/in/<ts>.md`.
- No bridge consumes `.nest/out/`. That surface is internal to the runner.

**The runner owns outbound.**

- `tick-loop.sh` already classifies groundhog items by structure: `message.md` is a pre-baked turn, `instructions.md` is a thinking task. Today the message branch routes to `.nest/out/`; this stage retargets it to `transcript.md` directly (appended as `## assistant — <ts>`).
- `tend-loop.sh` already writes to `transcript.md`; its parallel write into `.nest/out/` becomes redundant and is removed.
- Net effect: `.nest/out/` retires entirely. Bridges have one input (`transcript.md`) and one output (`.nest/in/`).

**At-least-once and replay.**

- Tailing transcript means bridges must persist a cursor (last delivered turn timestamp or byte offset) so a restart doesn't re-push history. Cursor lives at `bridges/<name>/.cursor`. Each bridge owns its own.
- All bridges always fire. Every channel gets every assistant turn. Per-message routing (Telegram only, not TUI) is explicitly out of scope; revisit if a real need surfaces.

**Routing concern deferred.** Once a real need exists, a frontmatter field on the transcript turn (`target: telegram`) is the lightest way in. Don't pre-design.

## Surgical changes

### TUI (s47)

- New `bridges/tui/` folder. First inhabitant of the bridges convention.
- Two-pane layout: scrolling transcript view above, single-line input field below.
- On submit: write to `.nest/in/<ts>.md`, render the user's line locally with a "pending" affordance, reconcile when the matching `## user` turn appears in `transcript.md`.
- Tail `transcript.md` for new turns; render assistant turns as they appear.
- Slash commands dispatch the same way `say` does (`commands/<cmd>.sh`); output renders ephemerally in the TUI pane, **not** written to `transcript.md`.
- Library-agnostic at this stage. Pick when implementing.
- Cursor convention: `bridges/tui/.cursor` records last rendered turn so restart doesn't re-render the entire transcript.

### Runner / nest (s48)

- `tick-loop.sh`: `message.md` branch appends to `transcript.md` as `## assistant — <iso>` instead of moving into `.nest/out/`.
- `tend-loop.sh`: drop the `.nest/out/` write; transcript append is the only outbound.
- `say`: remove `--repl` and `--listen`. Send-and-wait mode retargets to "tail `transcript.md` until next `## assistant` after the submitted `## user`."
- Atomic-mv claim guard in `say` (`print_and_archive`): deletable.
- `.nest/out/` directory: remove from layout and from `DEVELOPING.md` exclude lists, or keep as an empty/unused artefact (decide during build — probably remove).
- `README.md`: in the scheduled-outbound section near `README.md:114`, add a one-paragraph note distinguishing the two groundhog item shapes:

  > Items materialised by groundhog land in `.groundhog/out/<slug>/`. `tick-loop.sh` routes by structure: `message.md` is a pre-baked turn (appended directly to `transcript.md`); `instructions.md` is a thinking task (moved into `.nest/in/` for the tender).

## Verification gate

End-to-end with TUI as the only bridge:

1. One terminal: `run.sh`. One terminal: TUI bridge.
2. Type a message in the TUI. Assistant reply renders in the TUI. Both turns are in `transcript.md`.
3. Schedule a reminder via the TUI ("remind me in 1 minute").
4. Wait. Reminder fires. It appears in the TUI **and** is present in `transcript.md` as `## assistant`.
5. Restart the TUI. It does not re-render the whole transcript (cursor honoured).
6. `.nest/out/` is gone or untouched throughout.
7. Slash commands (`/help`, `/model`) work in the TUI; their output does not appear in `transcript.md`.

## Suggested child stitches (need their own instructions.md before being claimed)

Order: **s48 → s47 → s49.**

1. `s48-runner-owns-outbound` — retire `.nest/out/`. Move tick-loop's message branch to transcript append. Remove `--repl`/`--listen` from `say`. Update README's scheduled-outbound section. Foundational; everything else assumes the single-surface contract.
2. `s47-tui-bridge` — implement the TUI as the first bridge. Establishes `bridges/<name>/` convention and the `.cursor` file pattern. Validates the new model end-to-end locally before going remote.
3. `s49-telegram-bridge` — second bridge over Telegram Bot API. Reuses the convention from s47. Demonstrates fan-out (TUI + Telegram both fire on every assistant turn).

## Decisions deferred to those child stitches

- TUI library / framework choice.
- Exact pending-affordance for the user's submitted-but-not-yet-ingested line.
- Cursor format: timestamp-based vs byte-offset.
- Whether `.nest/out/` is removed from disk or just left empty.
- Whether `say` survives at all post-stage, or only as inbound-only one-shot for scripts.
- Slash-command output styling in the TUI pane.

## Notes

(filled in as child stitches tie off; record what was learned)

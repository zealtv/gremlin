# stage-11-bridges

**Outcome.** Bridges become a first-class concept. The TUI is the first proper bridge. The runner owns outbound. `transcript.md` is the single surface bridges read; `.nest/in/` is the single surface they write. `say --repl` and `say --listen` retire.

**This is the goal stitch only.** Child stitches need their own `instructions.md` before being claimed.

Implementation order is encoded in stitch numbers across all in-flight threads: s41–s46 are the bridges/models/update sequence, with stage-11's children at s43–s46. `s44a`/`s44b` are TUI follow-ups; `s44c` introduces the user-facing `gremlin` wrapper and lands before s45 so the Telegram daemon ships as `gremlin telegram start/stop/status/restart` from day one. Stage-10's memory work picks up at s47–s52 and lands last on a settled core.

## Strategy

**Bridges fan out from the transcript.**

- Every bridge is a long-running daemon. Many can run simultaneously — a TUI in one terminal, Telegram as a service, future bridges as they arrive.
- Each bridge has the same shape: tail `transcript.md` for assistant turns → render/push to its channel; accept user input → write to `.nest/in/<ts>.md`.
- No bridge consumes `.nest/out/`. That surface is internal to the runner.

**The tender owns all transcript writes.**

- Inbound from any bridge drops a message into `.nest/in/<ts>.md` and nothing else. Bridges do not append to `transcript.md` themselves.
- The tender appends both `## user — <iso>` (at claim time) and `## assistant — <iso>` (after the LLM call). Single owner for transcript writes; bridges fan out by tailing.
- The 0–5s gap between submission and the user turn appearing in transcript is hidden per-bridge: the TUI holds the user's line in the input field with a processing affordance until it appears; Telegram naturally shows the user's own message in the chat already; future bridges decide their own.

**The runner owns outbound.**

- `tick-loop.sh` already classifies groundhog items by structure: `message.md` is a pre-baked turn, `instructions.md` is a thinking task. Today the message branch routes to `.nest/out/`; this stage retargets it to `transcript.md` directly (appended as `## assistant — <ts>`). Groundhog's own `.groundhog/fired/` is the archive for that branch.
- `tend-loop.sh` keeps its `nestling complete` call — `.nest/out/` is preserved as the protocol-aligned per-item archive of completed nestlings, not as a delivery surface.
- Net effect: bridges have one read surface (`transcript.md`) and one write surface (`.nest/in/`). `.nest/out/` is archive only, no bridge reads it. `nestling sweep` and `groundhog sweep` keep the archives bounded.

**At-least-once and replay.**

- Tailing transcript means bridges that push to external channels must persist a cursor so a restart doesn't re-push history. Cursor lives at `bridges/<name>/.cursor`. Each bridge owns its own.
- Cursor format for bridges that need one: byte offset into `transcript.md`, not turn timestamp. Byte offsets avoid same-second timestamp collisions and match the bridge's actual tailing behavior. The TUI intentionally does not persist a cursor; it replays transcript history on launch.
- All bridges always fire. Every channel gets every assistant turn. Per-message routing (Telegram only, not TUI) is explicitly out of scope; revisit if a real need surfaces.

**Routing concern deferred.** Once a real need exists, a frontmatter field on the transcript turn (`target: telegram`) is the lightest way in. Don't pre-design.

## Surgical changes

### TUI (s44)

- New `bridges/tui/` folder. First inhabitant of the bridges convention.
- Two-pane layout: scrolling transcript view above, single-line input field below.
- On submit: write to `.nest/in/<ts>.md`, render the user's line locally with a "pending" affordance, reconcile when the matching `## user` turn appears in `transcript.md`.
- Tail `transcript.md` for new turns; render assistant turns as they appear.
- Slash commands dispatch the same way `say` does (`commands/<cmd>.sh`); output renders ephemerally in the TUI pane, **not** written to `transcript.md`.
- Library-agnostic at this stage. Pick when implementing.
- TUI replay convention: no persisted cursor; on launch it renders transcript history, then tails new content for the lifetime of the process.

### Runner / nest (s43)

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
5. Restart the TUI. It replays transcript history locally, without duplicating anything in `transcript.md`.
6. `.nest/out/` is gone or untouched throughout.
7. Slash commands (`/help`, `/model`) work in the TUI; their output does not appear in `transcript.md`.

## Child stitches (in order)

1. `s43-runner-owns-outbound` — reframe `.nest/out/` as nestling-protocol archive, not a delivery surface. Move tick-loop's message branch to transcript append. Remove `--repl`/`--listen` from `say`. Update README and DEVELOPING. Foundational; everything else assumes the single-read-surface contract.
2. `s44-tui-bridge` — implement the TUI as the first bridge. Establishes `bridges/<name>/` convention. Validates the new model end-to-end locally before going remote.
3. `s44a-tui-long-multiline-input` — make the TUI input area wrap long text and preserve multiline submissions. Follow-up to s44; lands before more bridge surface area is added.
4. `s44b-model-output-noise` — fix `/model` output contamination observed in the TUI. Independent TUI bug-fix.
5. `s44c-gremlin-wrapper` — introduce `./.gremlin/gremlin` as the single user-facing entry point. Moves `run.sh` into `bin/`, renames `bin/say` → `bin/say.sh`, and exposes `start/stop/status/restart/say/tui/help` plus auto-discovered `commands/*.sh`. Reserves the `gremlin <bridge> <verb>` dispatch shape for s45. Direct script invocation remains supported.
6. `s45-telegram-bridge` — second bridge over Telegram Bot API. Reuses the bridges convention from s44, adds persisted cursor state for a push channel, and ships its daemon under `gremlin telegram start/stop/status/restart` via the s44c dispatch convention. Demonstrates fan-out (TUI + Telegram both fire on every assistant turn).
7. `s46-sweep-command` — `/sweep` slash command fanning out to `nestling sweep` and `groundhog sweep`. Strictly after s43.

## Decisions deferred to those child stitches

- TUI library / framework choice.
- Exact pending-affordance for the user's submitted-but-not-yet-ingested line.
- Cursor format for push bridges: byte offset.
- Whether `.nest/out/` is removed from disk or just left empty.
- Whether `say` survives at all post-stage, or only as inbound-only one-shot for scripts.
- Slash-command output styling in the TUI pane.

## Notes

(filled in as child stitches tie off; record what was learned)

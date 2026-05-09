# nest-out-archives-input

**Outcome.** `.nest/out/` holds the *arrived item, archived* — not the assistant reply. The reply continues to live in `transcript.md` only. Glancing at `out/` answers "what was actioned?", as the nestlings protocol intends.

## Why

The nestlings protocol (`.nest/README.md`) is explicit: `out/` is "free logging — you can look at `out/` to see what has been actioned," and "your `out/` is where you put items you have tended." Today `bin/tend-loop.sh` calls `nestling complete <name> <reply_file>`, so `out/` accumulates timestamped reply text. That:

- breaks the audit story (the inbound item is destroyed; only the reply survives),
- duplicates the transcript with worse structure (no role/timestamp header),
- discards item metadata that ought to travel with the archived item (e.g. a per-item `.model` file from `groundhog-model-override`, attachments, `instructions.md`),
- muddies two-nest semantics for any future bridge that reads our `out/` as a reply queue.

Fix it before `stop-command` hardens the abort/drop wording around nest moves.

## Touchpoints

- `bin/tend-loop.sh` — change the `nestling complete` call to archive the *claimed item path*, not the reply file. Drop the `reply_file`/`mktemp` plumbing.
- `docs/protocol.md` Data Flow section — the arrow `tend-loop -> .nest/out/<archive>` stays, but the surrounding prose should make clear that the *item* is archived; the reply is in `transcript.md` only. Sweep for any phrasing that says or implies `out/` holds the reply.
- `.gremlin/README.md` — if it describes `.nest/out/` anywhere, mirror.
- `commands/update.sh` — already excludes `.nest/out/`; no change.
- `bin/archive.sh` — rotates `.nest/out/` already; should still work since it's content-opaque. Verify.

## Mechanism

In `bin/tend-loop.sh`, after the assistant turn is appended to transcript:

```sh
"$NESTLING" complete "$name" "$claimed_path" >/dev/null
```

- Drop `reply_file` and its `mktemp`/trap. Reply lives only in `$TRANSCRIPT`.
- Let `nestling complete` pick the out-name from `$name` (or pass `"$name-$fname_ts"` if collision-avoidance / sortability is wanted — confirm by reading `nestling.sh complete` before deciding).
- The claimed path is currently `.nest/in/<name>.tending`; `nestling complete` will move/copy it under `out/<name>` (or the chosen out-name) with `.landing` write protection per protocol.

## Verify

- Send a message via TUI. After the reply lands: `.nest/out/<name>/` (or `<name>.md` for file items) contains the **inbound** content, not the reply text. `transcript.md` has the assistant turn. No duplicate of the reply on disk.
- Send a directory item with extra files (e.g. a sibling `.model` file or attachment). Archive in `out/` preserves the directory structure.
- Two messages in quick succession — both archive cleanly, no name collision; check whether `nestling complete`'s default naming handles this or if we need the `-<iso>` suffix.
- Old `.nest/out/` entries (timestamp-named reply files from before the change) coexist without breaking anything. Sweep behaviour unchanged.
- `bin/archive.sh` rotates the new shape without complaint.

## Consistency / staleness

- `docs/protocol.md` Data Flow — wording around the `out/` archive.
- `bin/tend-loop.sh` header comment ("filing the reply into `.nest/out/` as the protocol-aligned per-item archive") is currently *wrong on both counts* — it files the reply, and it's not protocol-aligned. Update to match new behaviour.
- Any other docs that show the data-flow diagram (README, composition.md) — sweep.
- `stop-command` parent's verify ("no assistant turn written") reads more naturally under the new shape: aborted items go to `dropped/` with a reason; non-aborted items archive to `out/`. No spec change needed there but worth re-reading the parent stitch's prose after this lands to confirm it still hangs together.

## Sequencing

- Independent of `stop-command/tender-pidfile` mechanically, but cleaner if this lands first — the abort path's "skip the assistant transcript write and exit cleanly" pairs with "and don't archive the item to `out/` either," which is a single rule under the corrected shape ("we never tended it; nothing to archive") rather than two coupled exceptions.
- Independent of `groundhog-model-override`. That stitch becomes strictly easier to verify after this lands (the per-item `.model` survives into `out/`).
- Independent of `system-turn-type/*` and `stage-10-memory`.

## Notes

- Nothing else in the codebase reads `.nest/out/` programmatically (`grep` confirms: only `tend-loop.sh` writes, `update.sh` excludes, `archive.sh` rotates). Blast radius is the audit surface only.
- Personal copies (e.g. `~/Desktop/mygremlin`) will see `.nest/out/` shape change on the next tended item. That's a user-visible change but not breaking.

# s43-runner-owns-outbound

`.nest/out/` is reframed as a nestling-protocol archive, not a bridge surface. The runner appends all outbound — both tend-loop replies and tick-loop proactive messages — directly to `transcript.md`. Bridges read transcript only. `say` loses its async modes.

## Why

Today bridges have two surfaces: `transcript.md` (replies) and `.nest/out/` (proactive). That doubles the bridge contract and leaves orphans — proactive messages that fired while no listener was attached pile up in `.nest/out/` and never deliver.

Single surface — `transcript.md` — collapses the contract. Bridges tail one file. Proactive turns become part of the conversation log, which also gives the agent continuity (it can see "I sent the user a reminder at 9am" on its next turn).

`.nest/out/` is not removed. The nestling protocol's `complete` semantics already use `out/` as a "completed work archive" surface, paired with `nestling.sh sweep` for cleanup. The tender's archival writes there stay. What changes is the *meaning*: `out/` is record-keeping, not delivery. No bridge reads it.

## Changes

### `bin/tick-loop.sh`

The `message.md` branch currently moves the file into `.nest/out/<ts>.md`. Change to: append the body to `transcript.md` as a fresh assistant turn.

```bash
if [ -f "$item/message.md" ]; then
  iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  body="$(cat "$item/message.md")"
  printf '## assistant — %s\n%s\n\n' "$iso" "$body" >> "$TRANSCRIPT"
  rm -rf "$item"
fi
```

Same single-`>>` rule as elsewhere. The `instructions.md` branch is unchanged.

Update the file header comment to match the new behaviour.

### `bin/tend-loop.sh`

Two changes:

1. **Append `## user — <iso>` at claim time.** Today the user turn is written by `say` *before* the message is dropped into `.nest/in/`. With the new bridge contract, bridges only drop into `.nest/in/` and never write to `transcript.md` — the tender owns all transcript writes. After `nestling claim` succeeds and the body is read, prepend a `## user — <iso>` append to the transcript before the LLM call. The assistant turn append (existing) follows after the reply.

   Use the same single-`>>` rule already in place. Iso for the user turn is the moment of claim, not the moment of submission — that's fine; ordering is preserved by claim-order.

2. **Keep the `nestling complete` call.** It files the reply into `.nest/out/` as the protocol-aligned archive. `nestling sweep` keeps it bounded. No bridge reads `.nest/out/`.

### `say` (move to `bin/say`)

`say` survives as a one-shot scripting surface only — pipe stdin, get reply on stdout. Move from `.gremlin/say` to `.gremlin/bin/say` to live alongside the other runner scripts; update `init.sh` and any callers.

- Remove `--repl` mode.
- Remove `--listen` mode.
- Remove `print_and_archive` and the snapshot logic.
- Remove the atomic-mv claim guard.
- Remove the `## user —` transcript append (the tender owns it now).
- Send-and-wait mode (`say "msg"`): write to `.nest/in/<ts>.md`, then **tail `transcript.md`** waiting for the next `## assistant —` turn whose iso is later than the submission moment. Print that turn's body. Same 60s timeout.
- Slash dispatch (`/foo bar`) stays — it's how scripts and other bridges call commands without spinning up a TUI.
- Header comment: keep only the one-shot send-and-wait + slash-dispatch usage.

### `.nest/out/` directory

Stays. Continues to receive completed-item archives via `nestling complete`. No bridge reads it. `nestling sweep` (via `/sweep` in s46) handles cleanup.

The DEVELOPING.md cleanliness checklist currently expects `.nest/out/` to contain only `.gitkeep` between sessions. That assumption changes — `.nest/out/` will accumulate archive entries between sweeps. Update the checklist language: post-sweep, `.nest/out/` should hold only entries newer than the sweep window (default 14 days).

### `README.md`

In the **Scheduled outbound** section, add this paragraph (or fit it into the existing prose):

> Items materialised by groundhog land in `.groundhog/out/<slug>/`. `tick-loop.sh` routes by structure: `message.md` is a pre-baked turn (appended directly to `transcript.md`); `instructions.md` is a thinking task (moved into `.nest/in/` for the tender).

Update the **Data flow** section (where it says "replies into `.nest/out/`") to reflect that the tender's reply goes to `transcript.md`, with an archival copy filed via `nestling complete` into `.nest/out/`.

Update the **Bridges** section: bridges tail `transcript.md` for outbound and write to `.nest/in/` for inbound. `.nest/out/` is the per-item archive of completed nestlings, swept periodically — not a delivery queue.

### `DEVELOPING.md`

Keep `.nest/out/` in the rsync exclude block — it now legitimately holds personal archive data. Soften the cleanliness checklist: instead of "contains only `.gitkeep`," state that `.nest/out/` may contain archive entries newer than the sweep window.

## Verify

1. `run.sh` running. No bridge attached.
2. Schedule a reminder for one minute from now via `say "remind me in one minute to test"`.
3. Wait two minutes. `transcript.md` contains a `## assistant —` turn with the reminder body, timestamped at fire time. `.nest/out/` is unchanged by the proactive message (groundhog archive lives in `.groundhog/fired/`, not nest/out).
4. `say "what did you remind me of?"` returns a reply that references the reminder content (proves the agent saw the proactive turn in its own transcript).
5. `say --repl` exits with "unknown option" or similar — mode is gone.
6. `say --listen` likewise.
7. After a normal exchange via the TUI, an archive entry exists at `.nest/out/<iso>.md` containing the assistant reply (filed by `nestling complete`).

## Dependencies

- None; this is a runner change. Lands before or with s44.
- Coordinate with `nestling.sh complete` semantics — may need a small change there or just a different invocation pattern.

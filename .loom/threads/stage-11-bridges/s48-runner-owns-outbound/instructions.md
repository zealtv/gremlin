# s48-runner-owns-outbound

Retire `.nest/out/` as a bridge surface. The runner appends all outbound — both tend-loop replies and tick-loop proactive messages — directly to `transcript.md`. `say` loses its async modes.

## Why

Today bridges have two surfaces: `transcript.md` (replies) and `.nest/out/` (proactive). That doubles the bridge contract and leaves orphans (proactive messages that fired while no listener was attached pile up in `.nest/out/` and never deliver).

Single surface — `transcript.md` — collapses the contract. Bridges tail one file. Proactive turns become part of the conversation log, which also gives the agent continuity (it can see "I sent the user a reminder at 9am" on its next turn).

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

Today writes the assistant reply to **both** `transcript.md` and `.nest/out/` (via `nestling complete`). Drop the `.nest/out/` write — the transcript append at line ~83 is the only outbound now.

Check `.nest/nestling.sh complete` semantics: if it requires an out-file, either pass `/dev/null` or change the call. Goal: nothing lands in `.nest/out/` from the tender.

### `.gremlin/say`

- Remove `--repl` mode (lines ~76-98).
- Remove `--listen` mode (lines ~100-119).
- Remove `print_and_archive` and the snapshot logic.
- Remove the atomic-mv claim guard.
- Send-and-wait mode (`say "msg"`) retargets: write to `.nest/in/<ts>.md` as today, then **tail `transcript.md`** waiting for the next `## assistant —` turn dated after the submitted `## user —` turn. Print that turn's body. Same 60s timeout.
- Header comment: keep only the one-shot send-and-wait usage.

Decision point: does `say` survive at all? It's still useful as a one-shot scripting surface (pipe stdin, get reply). Keep it slimmed.

### `.nest/out/` directory

Either:
- **Remove entirely** from the canonical layout. Update `init.sh`, `DEVELOPING.md` exclude lists, and any `.gitkeep` references.
- **Leave as empty/unused** for one stage in case anything still writes there inadvertently.

Lean toward full removal — leaving an unused queue is the kind of surface that grows ghosts.

### `README.md`

In the scheduled-outbound section near `README.md:114`, add this paragraph (or fit it into the existing prose):

> Items materialised by groundhog land in `.groundhog/out/<slug>/`. `tick-loop.sh` routes by structure: `message.md` is a pre-baked turn (appended directly to `transcript.md`); `instructions.md` is a thinking task (moved into `.nest/in/` for the tender).

Also update `README.md:14` ("replies into `.nest/out/`") and `README.md:86-94` (bridge description) to reflect the new model: bridges tail `transcript.md`; `.nest/in/` is the inbound queue; there is no outbound queue.

### `DEVELOPING.md`

Drop `.nest/out/` from the rsync exclude block (`DEVELOPING.md:28`) and the cleanliness checklist (`:128`). Keep `.nest/in/`.

## Verify

1. `run.sh` running. No bridge attached.
2. Schedule a reminder for one minute from now via `say "remind me in one minute to test"`.
3. Wait two minutes. `.nest/out/` is empty (or absent). `transcript.md` contains a `## assistant —` turn with the reminder body, timestamped at fire time.
4. `say "what did you remind me of?"` returns a reply that references the reminder content (proves the agent saw the proactive turn in its own transcript).
5. `say --repl` exits with "unknown option" or similar — mode is gone.
6. `say --listen` likewise.
7. `git grep '\.nest/out'` in the gremlin returns no live references (only historical context if any survives).

## Dependencies

- None; this is a runner change. Lands before or with s47.
- Coordinate with `nestling.sh complete` semantics — may need a small change there or just a different invocation pattern.

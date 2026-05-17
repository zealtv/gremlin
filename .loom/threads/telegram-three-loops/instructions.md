# telegram-three-loops

**Outcome.** The Telegram bridge runs as a supervisor of three independent
loops — inbound poll, outbound push, typing pulse. Outbound latency drops from
"up to `POLL_TIMEOUT`" to "`PUSH_INTERVAL`" (~1s). A "typing…" indicator shows
while the assistant is composing a reply, inferred from nest state with no new
state files.

## Strategy

**Why split.** Today `cmd_run` does `poll_once` (blocks up to 30s in the
long-poll) → `push_transcript_once` → `sleep`. Outbound is gated by inbound, so
an assistant turn that lands during a long-poll waits up to `POLL_TIMEOUT` for
delivery. Splitting the loops removes that coupling without losing long-poll's
near-zero inbound latency or its low idle API volume.

**In-flight signal is derived, not stored.** A telegram-origin message in flight
is exactly: a file matching `.nest/in/*-telegram-*.md*` (covers both pending
and `.tending`). When the runner moves the item to `.nest/out/`, the glob goes
empty and the pulser naturally goes quiet. No counters, no flag files, no
PID-per-request.

**Supervisor pattern.** `cmd_run` forks the three loops, traps INT/TERM, kills
the children, waits. Existing PID tracking for `cmd_start`/`cmd_stop` still
uses the parent — children die with it.

## Child stitches

Serial chain; deepest is the first loose end:

```text
s03-acceptance-telegram-responsiveness
└── s02-readme-and-config
    └── s01-split-loops
```

- `s01-split-loops` — refactor `cmd_run` into `inbound_loop`, `outbound_loop`,
  `pulser_loop`, plus a supervisor. New env vars: `TELEGRAM_PUSH_INTERVAL`
  (default 1), `TELEGRAM_PULSE_INTERVAL` (default 4).
- `s02-readme-and-config` — update `bridges/telegram/README.md` with the
  three-loop model, the new env vars, and the in-flight inference.
- `s03-acceptance-telegram-responsiveness` — manual verify on fanta via the
  ssh tmux pane.

## Explicitly out of scope

- Switching from long-poll to webhooks.
- `fswatch`/`inotifywait` on the transcript — plain `sleep` polling at 1s is
  fine and portable.
- Per-message indicator tracking — the pulser is binary: anything outstanding,
  yes/no.
- Any new state files.

## Verification gate

See `s03-acceptance-telegram-responsiveness/instructions.md`. Headline checks:
typing indicator appears within ~4s of ingest and persists through the LLM
call; reply lands without the old long-poll lag; `telegram stop` leaves no
orphan loops.

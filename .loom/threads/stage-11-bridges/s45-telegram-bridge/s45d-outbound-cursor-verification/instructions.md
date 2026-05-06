# s45d-outbound-cursor-verification

Verify outbound fan-out, cursor behavior, and restart semantics on `~/Desktop/mygremlin`.

## Outcome

The Telegram bridge pushes new assistant transcript turns exactly once, handles proactive scheduled messages, and survives bridge/runner restarts without replaying old transcript history.

## Scope

- Use the same local bot setup from `s45b-local-copy-bot-setup`.
- Exercise assistant turns generated from the TUI or `gremlin say`.
- Exercise a scheduled reminder or groundhog-fired `message.md` path that appends an assistant turn to `transcript.md`.
- Restart the Telegram bridge and runner during the test.
- Test paused-runner behavior: inbound Telegram message lands while paused and is processed after unpause.

## Verification Notes

Create or append `verification.md` inside this stitch with:

- cursor value behavior before/after restart, without exposing secrets
- whether startup skipped old transcript history
- whether proactive reminder delivered to Telegram
- whether duplicate sends occurred
- any retry/backoff/logging behavior observed
- docs-relevant findings for setup, troubleshooting, and operations

## Verify

1. Missing `.cursor` on first launch initializes to end of current transcript and does not push history.
2. New assistant turns after startup push to Telegram.
3. Restarting the Telegram bridge does not duplicate already pushed turns.
4. Restarting the runner while the bridge stays up does not break later sends.
5. A reminder/proactive assistant turn reaches Telegram.
6. Paused-runner inbound behavior matches the parent stitch's acceptance test.

If this exposes implementation defects, fix them before tying this stitch.

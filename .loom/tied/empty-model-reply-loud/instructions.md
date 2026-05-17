# empty-model-reply-loud

**Outcome.** When the model preset exits `0` with empty stdout, the tender no
longer writes a silent empty `## assistant —` turn. Instead it emits a loud
`## system — ⚠️ error: empty model reply` turn so the failure is visible in the
transcript and propagates to bridges (Telegram, future bridges) the same way
any other error would.

## Why

Observed on roo (fanta, 2026-05-17): a Telegram food-log message produced an
empty `## assistant —` turn. The bridge correctly declined to push it
(`push_transcript_once` skips empty turns), so the user saw the typing
indicator and then silence. The tender had no idea anything was wrong: `llm.sh`
exited 0 with no stdout, so `tend-loop.sh:175` wrote `printf '## assistant —
%s\n%s\n\n' iso "$reply"` with `$reply` empty, then archived the item.

Claude Code (the harness behind `models/hk.sh` etc.) can legitimately exit 0
with no stdout — refusals, harness-level rate or auth conditions, etc. — and
its diagnostic goes to stderr which the tender doesn't capture. Silent empty
turns are worse than visible errors: the user is left guessing, and the bridge
side correctly chooses not to push noise.

## What to build

In `.gremlin/bin/tend-loop.sh`, after `reply="$(cat "$reply_file")"` and before
the assistant `printf`:

- If `reply` is empty (or whitespace-only), append a `## system — ⚠️ error:
  empty model reply` turn instead of an empty `## assistant —` turn. Body is a
  fixed line — no message tail. Then archive the item as today.
- If `reply` has content, behave exactly as today: `## assistant — <iso>\n<reply>\n\n`.

The system turn format follows the protocol's body convention
(`<emoji> <label>: <message>`) — see `docs/protocol.md` "Body convention". Use
the existing `⚠️ error:` vocabulary; the message text after the label is
`empty model reply` (no period, terse like `✋ item aborted`).

## Don't

- Don't try to capture stderr from the preset — that's a bigger change with
  its own design questions (length cap, sanitization, where it goes). This
  stitch is just "stop being silent."
- Don't change the abort path (rc != 0 with claim missing). That branch is
  already correct and shouldn't be confused with this one.
- Don't add a new role header — `## system —` with an `⚠️ error:` body is the
  documented way to surface non-conversational failures.
- Don't add retry logic. Empty reply is loud-and-archive, same shape as
  `run.sh` exited non-zero.

## Done when

- Empty-reply tend writes `## system — <iso>\n⚠️ error: empty model reply\n\n`
  to the transcript and archives the item to `.nest/out/`.
- Non-empty-reply tend is unchanged.
- The bridge pushes the new system turn (it's non-empty, so the existing
  `push_transcript_once` filter sends it through; system turns are already
  pushable per `extract_pushable_turns`).
- `docs/protocol.md`'s "Initial sub-categories" list adds a one-liner for the
  new `⚠️ error: empty model reply` case under the existing `⚠️ error:`
  vocabulary, or notes that `empty model reply` joins `run.sh exited <code>`
  as a known shape of the error label.

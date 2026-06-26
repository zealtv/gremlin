---
name: long-task
triggers:
  - a task is too big to finish well in a single turn
  - user asks you to work on something step by step, "keep going", or report progress as you go
  - you want to send mid-task progress before the final answer
---

# long-task

Some work outlives a single turn. The instinct is to do it all in one long reply
— but a single turn is opaque while it runs: nothing reaches the user until it
ends, and a crash loses everything. Don't lengthen the turn. **Multiply the
turns.**

A long task is many short ordinary tends. You do one bounded step, reply with
what you just did and what's next, then re-queue yourself for the next step. Each
reply is a real `## assistant` turn, so it reaches the TUI and Telegram the
moment it lands — your progress message *is* the reply of that step. No special
channel, no marker; just finish a small turn and start another.

## How

1. **Break the work into bounded steps**, each finishable inside one tend. Don't
   start anything that can't complete before the tend's watchdog (~900s) — if a
   step is too big, split it.

2. **Do one step.** Then reply with a short line: what you just did, what's next.
   One sentence in your normal voice is plenty.

3. **Re-queue yourself for the next step:**

   ```bash
   ./.gremlin/tools/continue.sh "step 3/5: <the next concrete step>"
   ```

   This drops a note into your own inbox; the next tend picks it up. Carry a
   step counter (e.g. `3/5`) in the note so you — and anyone watching — can see
   the chain's shape and where it ends.

4. **To finish, just reply without calling `continue.sh`.** No re-queue = the
   chain stops. End with a brief done line (a `✅` is fine).

## Cadence — quiet by default

Emit on **milestones, not a clock.** A progress line marks a real step boundary
or a meaningful state change — not "still working." Silence between milestones is
correct, not a dead bot. One line, normal voice. When in doubt, **under-emit**:
say less than feels natural, and only speak up when there's something a human
would actually want to know.

## Termination is your job

There is no kernel guard against a runaway chain — a loop that forgets to stop
burns money forever. So:

- **State an explicit stop condition** before you start ("...until the suite is
  green", "...5 steps", "...until the deploy reports healthy").
- **Carry the step/tick count** in each `continue.sh` note and stop when you hit
  the limit, even if not "done" — then report and ask.
- `/stop` and pausing are the human's backstop, not yours. Owning the off-switch
  is yours.

## Clock-paced goals (later)

For work that should wake on a schedule rather than continue immediately (watch a
deploy, check every 15m), a self-disarming groundhog `every/` goal is the right
shape, paired with a `once/<date>` dead-man's switch and an optional per-goal
`state.md` for memory across ticks. That machinery isn't wired up yet — for now,
`continue.sh` handles immediate step-by-step continuation.

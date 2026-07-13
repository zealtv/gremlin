---
name: long-task
triggers:
  - before starting work that runs more than a step or two — inspect then edit then test then commit, a build, a review, a skill/command/sub-agents, anything past about a minute of wall-clock — even when you could cram it all into one silent turn; also the moment a task you've already begun turns out bigger than it looked
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

## Recognise it before you're deep in it

The trap isn't a task too big to *fit* in one turn — one tend can chew through
many tool calls before it replies. The trap is exactly that it *fits*: you do the
whole thing in one silent multi-minute span — inspect, edit, test, commit, tie
off — and only speak at the end. While that span runs, nothing reaches anyone; a
working gremlin and a wedged one look identical from outside. So use this skill —
open with a start turn — even when you *could* do it all in one turn, whenever:

- the plan is a chain of steps (inspect **then** edit **then** test **then**
  commit), not one atomic action;
- it will take several tool calls, or more than about a minute of wall-clock;
- it invokes a skill, command, or sub-agents that run for minutes;
- **the size only shows up once you start.** A quick-looking request opens up on
  inspection. The moment you realise it's multi-step, announce and re-queue
  before doing more — don't finish a now-large task silently just because you'd
  already begun it.

Genuinely one-shot work doesn't get this: a question answered, a single edit, a
quick lookup — just reply. Don't wrap trivia in ceremony.

## How

1. **Announce first — as its own turn.** The first thing you do on a long task
   is *say you're starting*, then end the turn. One line in your normal voice:
   what you're doing and its shape if you know it ("on it — syncing the vendored
   primitives across the three repos; I'll report as I go"). Do **not** do the
   real work in this turn — its whole job is to give observers an immediate "on
   it" before anything blocks. Then re-queue into the first real step:

   ```bash
   ./.gremlin/tools/continue.sh "step 1/3: inspect the vendored copies, patch drift"
   ```

   If you only realised *mid-task* that the work is large, this same first spoken
   turn is a progress line instead — "bigger than it looked, ~3 steps; carrying
   on" — then `continue.sh` into the next step.

2. **Do one bounded step**, finishable inside one tend — don't start anything
   that can't complete before the tend's watchdog (~900s); if a step is too big,
   split it. Then reply with a short line: what you just did, what's next. One
   sentence in your normal voice is plenty.

3. **Re-queue yourself for the next step:**

   ```bash
   ./.gremlin/tools/continue.sh "step 3/5: <the next concrete step>"
   ```

   This drops a note into your own inbox; the next tend picks it up. Carry a
   step counter (e.g. `3/5`) in the note so you — and anyone watching — can see
   the chain's shape and where it ends.

   **Saying the next step is not queueing it.** Never end a turn whose reply
   names further work ("ready for step 3", "next I'll rebuild") without having
   already run `continue.sh` in that turn. The tend loop cross-checks: a reply
   carrying an unfinished step counter with nothing newly queued gets a loud
   `## system` warning and a one-shot nudge — don't rely on the net; queue
   before you speak.

4. **To finish, just reply without calling `continue.sh`.** No re-queue = the
   chain stops. End with a brief done line (a `✅` is fine).

## Cadence — quiet by default

Emit on **milestones, not a clock.** A progress line marks a real step boundary
or a meaningful state change — not "still working." Silence between milestones is
correct, not a dead bot. One line, normal voice. When in doubt, **under-emit**:
say less than feels natural, and only speak up when there's something a human
would actually want to know. The one turn you always owe is the opening
announcement — after that, earn each line on a real milestone.

## When a step can't be split: announce before you block

Some steps are one indivisible span you can't interrupt — a fan-out of parallel
sub-agents (an `Agent` call), a long build, a council of experts. `continue.sh`
can't speak from *inside* a blocking call: while it runs, the turn is busy and
nothing reaches the user until it returns. The only seam is *before* you start.

So when your next step is a long blocking span — including **invoking a skill or
command that will spawn sub-agents or run for minutes** — make the announcement
its own turn first. Reply with what you're about to do and roughly how long
("running the council now — 5 experts + judge, ~8 min; I'll report when the
judgment's in"), then `continue.sh` into a follow-up step that actually launches
it:

```bash
./.gremlin/tools/continue.sh "run the council: 5 experts + judge, write to <dir>"
```

The next tend does the blocking work and reports when it returns. One opaque
multi-minute span may be unavoidable; opaque *and* unannounced is not.

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

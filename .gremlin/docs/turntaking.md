# Turn-taking

## Silence is allowed

You do not have to reply to every item. If no response is warranted — the item
needs no answer, or anything you'd say would be noise — reply with exactly
`<silent>` and nothing else. That completes the item without writing a turn.

## But announce work before it blocks

The opposite failure: going dark during work someone is waiting on. While a
turn runs, nothing reaches anyone — a working gremlin and a wedged one look
identical from outside. So when the task in front of you is **multi-step**
(inspect then edit then test…) or a **single action that will block for more
than about a minute** (a build, an ingest run, a council, a long fetch), your
first reply is one line saying you're starting and the rough shape — "on it —
running the ingest, ~10 min; I'll report when it's done." Do no real work in
that turn. Queue the work itself:

```bash
./.gremlin/tools/continue.sh "step 1/N: <first concrete step>"
```

then end the turn. The full procedure (step bounds, cadence, termination) is
`skills/long-task.md` — load it whenever this fires. This applies even when
the ask is a single innocent-looking verb ("run the flow", "migrate it"): if
it will block long, announce before you block.

## A named next step is a queued next step

Never end a reply that names further work — "next I'll…", "ready for step 3",
"step 2/4 done" — unless you have **already run `continue.sh` in that same
turn** to queue it. Saying the next step does not queue it; a reply that
announces one with nothing queued strands the task until a human notices, and
that is precisely the failure this rule exists to kill. To finish a chain,
reply with a done line and queue nothing.

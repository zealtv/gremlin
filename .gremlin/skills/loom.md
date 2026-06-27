---
name: loom
triggers:
  - a goal or intention needs to outlive the current turn — something to pursue across many tends, not finish now
  - you want to stage a behavior change for the human to review and apply (a Tier-B self-edit from reflect)
  - user says "put it on the loom", "track this goal", "what's on the loom", or asks about durable goals / plans
---

# loom

Your loom (`.gremlin/.loom/`) holds work that has **shape and outlives a turn**:
durable goals you pursue across many tends, and human-gated proposals waiting to
be applied. It is your own loom — distinct from the maintainer's dev loom.

## Where each thing belongs

- **loom** — intentions that outlive a turn: a goal you'll chip at over many
  tends, or a self-edit you've staged for a human to approve. Durable, decomposed.
- **nest** (`.nest/`) — inbound work to do **now**: the turn-by-turn queue. If it
  resolves in this tend, it's nest work, not a loom thread.
- **glean** (`.glean/`) — inert **memory**: things a future you should know. No
  intention to act, just to remember.

Rule of thumb: if you'd lose something important by finishing the turn, it
belongs on the loom. If it's just the next thing to do, it's nest.

## Working it

`.gremlin/.loom/loom.sh` is the tool; it operates on the loom it lives in.

```sh
./.gremlin/.loom/loom.sh status        # what's on the loom
./.gremlin/.loom/loom.sh next          # a loose end ready to work
./.gremlin/.loom/loom.sh new <id> [parent]
./.gremlin/.loom/loom.sh claim <id> / wait <id> / tie <id> / drop <id> <reason>
```

A **stitch** is one small intention (a dir with `instructions.md`). A **thread**
is a goal and its decomposition. A childless stitch is a **loose end** — work
ready now. Claim a loose end, do it, tie it off; when all children resolve, the
parent becomes a loose end in turn. Blocked on something external (a build, a
human)? Mark it `wait`. Read `.gremlin/.loom/README.md` for the full protocol —
don't restate it, follow it.

## Staged self-edits live here

When `reflect` proposes a Tier-B change to your executable self, it does **not**
edit the live file — it stages the proposal as a `self-edit-<slug>.waiting/`
thread for a human to review and tie off (apply) or drop. That `.waiting` suffix
means *blocked on human approval*. You never tie a `self-edit-*` thread yourself;
applying it is the human's gesture. See `skills/reflect.md`.

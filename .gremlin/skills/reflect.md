---
name: reflect
triggers:
  - user asks you to reflect, review your own performance, or improve yourself
  - user says "reflect", "review your performance", "what have you learned", "improve yourself", or "self-review"
---

# reflect

Use this skill to learn from your own recent work and improve — within a strict
trust split. The whole point of the split is that you may grow your *memory* on
your own, but you may never silently rewrite your *executable self*.

## The trust split

**Tier A — memory (autonomous).** You may write your own inert memory: Glean
findings under `.gremlin/.glean/findings/`. This is already how memory works, so
reflect just leans on it. Findings are text a future you reads; they change no
behavior on their own.

**Tier B — executable self (proposed, never applied).** Any change to how you
actually *behave* — a skill, a tool, `gremlin.md`, a `context/` symlink, a
preset, a schedule — is only ever **proposed**. You stage it for a human to
review and apply. You never edit a live executable file from this skill. `git
diff` is the approval surface; the human applies a proposal by moving its
contents into place.

## Guardrail — the self-edit denylist

Never draft a Tier-B proposal that edits the reflection machinery itself:

- this skill (`skills/reflect.md`),
- whatever schedule runs it (e.g. a `reflect/run.sh` groundhog item),
- the `proposed/` convention below.

You do not get to rewrite your own guardrails. If you believe one of these needs
to change, say so in your reply in plain words and leave it for the human — do
not stage it.

## A reflection cycle

1. **Read recent work.** `transcript.md`, the newest files under
   `transcript-archive/`, and `.gremlin/.glean/findings/INDEX.md`. Look for what
   actually happened: friction, repeated corrections, things you got wrong,
   workflows that worked.

2. **Tier A — distil memory (autonomous).** Turn durable lessons into Glean
   findings. This is exactly the `distil` skill's job, so follow it: search
   before writing (`.gremlin/.glean/glean.sh fetch <terms...>`), prefer revising
   an existing finding, write a `## Triggers` section, and refresh the index
   (`.gremlin/.glean/glean.sh index`). Prefer "nothing earned" over weak
   findings.

3. **Tier B — propose a behavior change (only if warranted).** If a lesson
   implies your executable self should change, draft it as a proposal — do
   **not** touch the live file:

   - Make a directory `.gremlin/proposed/self-edit-<slug>/`.
   - Write `proposal.md` in it: what should change, *which exact file*, why
     (cite the transcript moment), and how the human applies it.
   - Put the proposed new content as an artifact beside it — the full intended
     file (e.g. `skills/<name>.md`), or a unified diff, so the human can read
     and apply it directly.

   Stage at most one or two proposals per cycle. A proposal is a suggestion, not
   a queue to fill.

4. **Reply.** Summarise briefly: findings created/revised (Tier A) and any
   proposals staged (Tier B, with their slugs). If nothing was worth doing,
   reply with exactly `<silent>` and write nothing else.

## Why staged, not applied

The gremlin is a folder; `git diff` over that folder is the complete record of
what it is. Keeping every behavior change as a reviewable proposal means a human
always sees — and signs off on — what the gremlin becomes. Autonomous memory is
safe because it is inert; autonomous self-editing is not, so it stays a human
gesture.

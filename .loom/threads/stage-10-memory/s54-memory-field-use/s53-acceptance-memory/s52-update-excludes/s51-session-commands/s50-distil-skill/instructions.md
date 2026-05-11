# s50-distil-skill

**Outcome.** Gremlin has a triggered skill for memory review and distillation.

This stitch depends on Glean being vendored and initialized below it in the Loom
chain. Only tend it after `s49-init-wires-glean` ties.

## Scope

Add `.gremlin/skills/distil.md` with tight triggers for explicit memory work,
such as:

- "distil"
- "distill"
- "remember this"
- "review this for memory"
- "consolidate findings"

The skill should instruct the agent to:

- read `.gremlin/.glean/distil.md`;
- inspect `.gremlin/.glean/findings/INDEX.md`;
- use `.gremlin/.glean/glean.sh fetch` before creating a new finding;
- prefer revise over create when an existing finding covers the ground;
- create flat markdown findings directly under `.glean/findings/` when earned;
- use `glean.sh complete <id>` for deliberate raw packets in `.glean/in/`;
- use `glean.sh drop <id> "reason"` when retiring findings;
- run `glean.sh index` after creating, revising, or dropping findings;
- mention promotion by symlink into `context/` when a finding should become
  always-loaded.

The skill must support two sources:

- a model-backed memory-review item from `/new-session`, pointing at a transcript
  archive;
- a direct user ask during conversation.

## Constraints

- Do not tell the agent to copy every transcript into `.glean/in/`.
- Do not promise that reviewed material becomes permanent memory.
- Prefer "nothing earned" over weak findings.
- Keep triggers tight enough that ordinary mentions of memory do not constantly
  pull in the full procedure.

## Verification

1. Run `.gremlin/bin/index-skills.sh`.
2. Confirm `skills/INDEX.md` lists the distil skill under triggered skills.
3. Confirm a phrase like "distil this session" would trigger the skill.
4. Confirm the skill body contains the actual Glean commands used by the
   current protocol: `fetch`, `complete`, `drop`, `index`.

## Notes

- Use "distil" in user-facing Gremlin docs if the project prefers that spelling;
  include "distill" as a trigger for users who type the alternate spelling.

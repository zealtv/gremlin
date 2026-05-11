# s50-distil-skill verification

- Added `.gremlin/skills/distil.md` with tight triggers for explicit memory
  work, including "distil", "distill", "remember this", "review this for
  memory", and "consolidate findings".
- The skill supports both archived transcript review items and direct user asks.
- The skill instructs the agent to read `.gremlin/.glean/distil.md`, inspect
  `findings/INDEX.md`, use `fetch` before creating findings, prefer revision,
  complete deliberate inbox packets, drop retired findings, refresh `index`, and
  mention promotion by symlink into `context/`.

Checks run:

```sh
.gremlin/bin/index-skills.sh
bash -n .gremlin/bin/index-skills.sh .gremlin/.glean/glean.sh
sed -n '1,220p' .gremlin/skills/INDEX.md
rg -n "distil|distill|remember this|review this for memory|consolidate findings|fetch|complete|drop|index|ln -s" .gremlin/skills/distil.md .gremlin/skills/INDEX.md
```

`skills/INDEX.md` lists `distil` under triggered skills, and the skill body
contains the current Glean protocol commands: `fetch`, `complete`, `drop`, and
`index`.

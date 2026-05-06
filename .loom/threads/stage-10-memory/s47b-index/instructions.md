# s47b-index

*(scribble repo)*

`scribble.sh index` regenerates `findings/INDEX.md` from each finding. Always-loadable, cheap.

## Outcome

`./scribble.sh index` writes `.scribble/findings/INDEX.md`: one bullet per finding listing the id, the finding's title (first H1), and its `## Claim` line. Mirrors `bin/index-skills.sh` so any tender can `cat` it into a prompt.

## Scope

- Add `cmd_index` to `scribble.sh`.
- Walk `.scribble/findings/*/finding.md` in alphabetical order by id.
- For each: extract the title (first `# ` heading) and the first non-empty line of the `## Claim` section.
- Emit `INDEX.md` with a short header and one bullet per finding. Format suggestion:
  ```
  # findings index

  - `<id>` — <title> — <claim>
  ```
- Empty `findings/` produces a valid INDEX.md with the header and no bullets.
- Update `README.md` to document the command and that `INDEX.md` is derived (regenerated, not hand-edited).
- Update the `usage` block in `scribble.sh`.

## Verify

1. `./scribble.sh finding alpha`, edit `alpha/finding.md` to set a title and Claim, then `./scribble.sh index` writes a sensible `INDEX.md` with one bullet.
2. Add a second finding `beta`; `index` writes both, alphabetical by id.
3. Re-running `index` is idempotent.
4. Empty `findings/` produces an `INDEX.md` containing only the header.
5. A finding missing `## Claim` still appears in the index (claim shown as empty or `—`).

## Depends on

- `s47a-finding-shape` — the section contract this parser reads.

# s47a-finding-shape

*(scribble repo)*

Adopt plain markdown as the finding contract — no YAML, no frontmatter, ever. The shape that `index` and `fetch` will parse.

## Outcome

`finding.md` is a markdown document with a fixed set of optional H2 sections that downstream tools can read without a parser library:

- `## Claim` — the current guidance, in one sentence if possible.
- `## Why` — why this seems worth carrying.
- `## Scope` — where it applies, or does not apply (free prose, or bullets).
- `## Triggers` — bullets of phrases or keywords that should surface this finding via `fetch`.
- `## Associations` — bullets of links to related findings (e.g. `../related-finding/`).

All sections are optional. Tools that read findings must tolerate any subset.

## Scope

- Update the `cmd_finding` template in `scribble.sh` to include a `## Triggers` section between `## Scope` and `## Associations`.
- Update `README.md`:
  - Document the section list and that all are optional.
  - Document the parse rules: section heading is exactly `## <Name>` on its own line; the section body runs until the next H2 or end of file; bullets under `Triggers`, `Scope`, `Associations` are taken as items; free prose elsewhere.
  - State explicitly that frontmatter (YAML or otherwise) is out of scope. Pure markdown.

## Verify

1. `./scribble.sh finding test-shape` produces a `finding.md` containing all five sections in the documented order.
2. README has a "Section contract" subsection naming the five sections and the parse rules.
3. README states that frontmatter is not used.

## Notes

This is the contract that `s47b-index` and `s47c-fetch` rely on. Land this first.

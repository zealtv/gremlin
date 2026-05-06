# s47c-fetch

*(scribble repo)*

`scribble.sh fetch <query...>` returns finding paths matching the query. The prefetch seam.

## Outcome

`./scribble.sh fetch <words...>` prints the path of each finding directory whose id, title, `## Claim`, `## Scope`, or `## Triggers` content matches any of the query words. One path per line; output pipes cleanly into other tools.

## Scope

- Add `cmd_fetch` to `scribble.sh`.
- Match strategy: case-insensitive substring match against the searchable surfaces (id, title H1, Claim line, Scope body, Triggers bullets). A finding hits if **any** query word matches **any** searchable surface.
- Output: one path per line, deduplicated, sorted by id.
- Exit 0 even when there are no matches (empty stdout, no error).
- Refuse if no query words are given.
- Paths printed relative to `$REPO_ROOT` (so output is stable and pipe-friendly across cwd).
- Update `README.md` and the `usage` block.

## Verify

1. Two findings exist; `./scribble.sh fetch <id-substring>` returns the matching one.
2. A finding with `## Triggers` bullet "deploy"; `./scribble.sh fetch deploy` returns its path.
3. Multi-word query returns the union of matches.
4. No matches: exit 0, no stdout.
5. No query words: usage error.

## Depends on

- `s47a-finding-shape` — parser contract.

## Notes

Pure substring match. No embeddings, no ranking, no scoring. Smarter retrieval is a separate concern; this is the minimum viable prefetch seam.

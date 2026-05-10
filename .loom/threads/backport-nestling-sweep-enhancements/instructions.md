# backport-nestling-sweep-enhancements

**Outcome.** `~/repos/nestlings/.nest/nestling.sh` carries the two sweep improvements that currently live only in this repo's vendored copy, so the next vendor refresh from upstream doesn't silently revert them.

## Drift (gremlin-side improvements not yet in upstream)

Discovered 2026-05-10 during a vendor-drift audit. Diff against `~/repos/nestlings/.nest/nestling.sh`:

1. **`sweep 0` sweeps everything regardless of mtime.** The current upstream hardcodes `-mtime +"$days"` into the find call, which means `sweep 0` matches nothing (find treats `+0` as "modified more than 0 days ago" → always false on freshly touched items). Gremlin copy gates the `-mtime` flag behind `days != 0`:

   ```sh
   local find_args=(-mindepth 1 -maxdepth 1)
   if [[ "$days" != "0" ]]; then
     find_args+=(-mtime +"$days")
   fi
   ```

2. **Exclude `.gitkeep` files from sweep**, alongside the existing `.reason.md` exclusion. Lets a nest preserve `.gitkeep` placeholders in `out/` and `dropped/` without sweep clobbering them.

   ```sh
   done < <(find "$dir" "${find_args[@]}" ! -name '.gitkeep' ! -name '*.reason.md' | sort)
   ```

Both changes live around line ~204–214 of the gremlin copy. The upstream version is shorter; the gremlin version replaces the inline find with the `find_args` array form.

## Touchpoints

- `~/repos/nestlings/.nest/nestling.sh` — apply both edits.
- `~/repos/nestlings/README.md` — sweep section, if it documents `0` semantics. Confirm `sweep 0` is now meaningful and describe it.
- `~/repos/nestlings/test.sh` if present — add a case for `sweep 0` and for `.gitkeep` preservation.

## Verify (in `~/repos/nestlings`)

- `nestling.sh sweep 0` against a populated `out/` removes everything (it didn't before).
- A `.gitkeep` placed in `out/` or `dropped/` survives any sweep invocation.
- Existing `sweep 14`-style invocations behave unchanged.

## After upstream lands

- Re-vendor `nestling.sh` into `.gremlin/.nest/` (a clean copy from upstream should now be byte-identical to what's already there). No gremlin-side code change expected.
- Drop this stitch.

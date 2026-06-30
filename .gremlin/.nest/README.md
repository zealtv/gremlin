# 🪺 nestlings

A tiny, file-based protocol for agents that tend a folder.

One script. One folder convention.

When you open `.nest/in/`, you are looking at the work that is ready now.

```
.nest/
  nestling.sh
  in/
  out/
  dropped/
  tend.md
```

## What a nest is for

A nest makes a folder into an active process.

Items arrive in `in/`. A nestling tends to them. Tended items land in `out/`. Dropped items land in `dropped/` with a reason.

This is useful in two ways:

* **As a work tray.** Someone leaves work for the nestling. The nestling does it. The originator collects the result from `out/`.
* **As an autonomous process.** The folder just runs. Items arrive, get tended, and `out/` accumulates as a record of what happened.

Both uses share the same mechanics. Passing items from `in/` to `out/` or `dropped/` is free logging: you can look at `out/` to see what has been actioned.

## How nestlings works

An item can be a file or a directory.

```
.nest/
  in/
    item/
  out/
  dropped/
```

* items arrive in `in/`
* tended items are placed in `out/`
* failed items are placed in `dropped/`
* `.tending` means claimed
* `.landing` means being written

## Rules

1. Write protection: write as `<item>.landing`, then rename to `<item>` when complete.
2. Claim by suffix: `<item>` → `<item>.tending`
3. Tend from `in/`
4. Hatch to `out/`
5. Drop to `dropped/` with a sibling `<item>.reason.md`
6. Retry only directories explicitly marked with `.recoverable`; bounded retry
   state travels with the item as `.attempts` and `.recovery.md`

The file system is the protocol.

## Agent loop

1. Look at `.nest/in/`
2. Pick one ready item
3. Claim it by renaming it with `.tending`
4. Read `.nest/tend.md` if present
5. Work
6. Either:
   * place the result in `.nest/out/` using `.landing`
   * or move the item to `.nest/dropped/` and write a reason file

Never touch anything ending in `.landing` or `.tending`.

An abandoned claim is not inferred from age alone. `stale` reports claimed
items older than a threshold without changing them; the process that owns the
nest decides whether a claim is abandoned and passes it to `resolve`. Resolution
returns a marked directory to `in/` while it is below the retry limit, otherwise
it drops the claim with a reason. Bare files and unmarked directories fail
closed and are dropped.

Set `NEST_MAX_ATTEMPTS` to a non-negative integer to change the default limit
of three. Producers should add `.recoverable` only when repeating the item is
safe. Nestlings does not decide whether a tender process is still alive.

## Communicating between nests

When two agents talk through nests, replies go to the other agent's `in/`, not your own `out/`.

Your `out/` is where you put items you have tended.
Their `in/` is where you put items for them to tend.

## tend.md

`.nest/tend.md` is an optional conventional file that tells a human or agent what to do with items in the nest.

If present, read it before tending.

Keep it short. Keep it concrete.

## Vendoring

To add a nest to another project, copy `nestling.sh` and `README.md` into
the project's `.nest/` directory, then run `./.nest/nestling.sh ensure` to
seed the trays:

```sh
mkdir -p <project>/.nest
cp nestling.sh README.md <project>/.nest/
<project>/.nest/nestling.sh ensure
```

`ensure` creates `in/`, `out/`, and `dropped/` next to itself.
`nestling.sh` operates on the `.nest/` directory it lives in, so each
vendored copy is self-contained.

## Commands

```
./nestling.sh ensure
./nestling.sh list
./nestling.sh ingest <src> [name]
./nestling.sh claim <n>
./nestling.sh complete <n> <result_src> [out_name]
./nestling.sh drop <n> <reason>
./nestling.sh stale [max-age-mins]   # read-only; default 10
./nestling.sh resolve <n> [reason]   # retry marked directories or drop
./nestling.sh sweep [days]   # remove out/dropped older than N days (default 14; pass 0 to sweep everything regardless of mtime). `.gitkeep` placeholders and `*.reason.md` siblings are preserved. Prints one line per item.
```

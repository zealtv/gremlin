# s07-transcript-format

Settle the on-disk transcript format and stick to it everywhere it's written.

```
## user — 2026-04-27T19:42:11Z
hello

## assistant — 2026-04-27T19:42:14Z
hi, what's up?
```

One `>>` append per turn so concurrent appends don't interleave on POSIX.

Two writers right now: the tend loop (assistant turns) and `say` (user turns, in stage 3). Both must use this format.

**Verify:** Two consecutive items processed back to back; transcript reads in order with no interleaving.

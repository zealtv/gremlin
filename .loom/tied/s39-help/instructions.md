# s39-help

`commands/help.sh`: walk `commands/*.sh`, extract each script's first comment line (the convention from s34), print one line per command:

```
/new    — start a fresh transcript (rotates current into transcript-archive/)
/model  — list or set the active model preset
/help   — show this list
```

Skip `commands/help.sh` itself if you'd rather not list it; or include it for symmetry. Either is fine — pick one and document.

**Verify:** `./.gremlin/say "/help"` prints all three commands with their summaries.

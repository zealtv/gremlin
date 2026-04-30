# s15-acceptance-4

Hold a full conversation under `run.sh`:

1. Start `./.gremlin/run.sh` in one terminal.
2. Hold a three-turn conversation via `say` in another.
3. Mid-session, `touch .gremlin/.paused`; verify a new `say` blocks (no reply).
4. `rm .gremlin/.paused`; verify the reply arrives.
5. Ctrl-C the runner; verify clean shutdown.

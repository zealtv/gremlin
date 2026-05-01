# s33-acceptance-8

Acceptance:

1. Hold a two-turn conversation via `say`.
2. Run `bin/archive.sh`.
3. Hold a fresh turn. Verify the new reply uses only the new transcript and does not "remember" the archived turns (e.g. by asking "what did I just ask you?" — it shouldn't know).
4. Verify any pending groundhog items still fire as scheduled.

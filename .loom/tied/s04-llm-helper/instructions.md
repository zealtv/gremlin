# s04-llm-helper

`bin/llm.sh "<prompt>"`: read stdin (or take prompt as arg), call the configured LLM CLI (default `claude -p`), print the reply on stdout. This file is the single seam where everything LLM-specific lives.

Document at the top of the file what would change to swap models.

**Verify:** `echo "say hi" | bin/llm.sh` returns a non-empty reply.

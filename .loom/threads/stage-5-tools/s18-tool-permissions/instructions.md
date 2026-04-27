# s18-tool-permissions

`tend-loop.sh` invokes the tender with `--allowedTools "Bash(./tools/*)"` (or the LLM-equivalent for whichever CLI `bin/llm.sh` wraps). Document the seam at the top of `bin/llm.sh` so swapping LLMs surfaces the equivalent permission flag.

**Verify:** The tender can run a tool without an interactive permission prompt.

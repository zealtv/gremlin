# s40-acceptance

End-to-end gate. With `run.sh` running:

1. `./.gremlin/say "/help"` — lists `/new`, `/model`, `/help`.
2. Hold a one-turn conversation. Confirm a reply.
3. `./.gremlin/say "/new"` — fresh transcript; today's archive file exists.
4. `./.gremlin/say "/model"` — lists presets; `default` is starred.
5. `./.gremlin/say "/model fast"` — switches.
6. Hold one more turn. Confirm the reply (proves the new preset took effect — verify by checking llm.sh's invocation, or by the response style if the model differs noticeably).
7. `./.gremlin/say "/model nonsense"` — errors and exits non-zero.
8. Slash-commands left no `## user` / `## assistant` turns in the transcript (only the conversational turns from steps 2 and 6).

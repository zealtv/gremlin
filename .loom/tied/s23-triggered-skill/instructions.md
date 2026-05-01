# s23-triggered-skill

Write `skills/remind-me.md` with one or two natural-language triggers and a body that explains the groundhog file path to write.

```markdown
---
name: remind-me
triggers:
  - user asks to be reminded of something at a future time
  - user says "remind me", "follow up", "ping me later"
---

# remind-me

When the user asks to be reminded, write a file at:
.groundhog/schedule/once/<YYYY-MM-DD>/<slug>/message.md

The body is the reminder text in the user's voice.
Confirm to the user that the reminder is set, with the date.
```

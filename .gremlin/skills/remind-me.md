---
name: remind-me
triggers:
  - user asks to be reminded of something at a future time
  - user says "remind me", "follow up", "ping me later"
---

# remind-me

When the user asks to be reminded, schedule it by creating a file under `.groundhog/`. Do not just confirm in prose — actually create the file via bash.

## Steps

1. Resolve the date the reminder should fire, in UTC. Use `./tools/now.sh` to anchor relative dates ("tomorrow", "in three days").

2. Pick a kebab-case slug summarising the reminder (e.g. `buy-milk`, `call-jess`, `submit-invoice`).

3. Compose the reminder body — the message you'd want delivered when the reminder fires. Write it in the user's voice (e.g. "buy milk at 9am").

4. Create the file with bash:

   ```bash
   mkdir -p .groundhog/schedule/once/<YYYY-MM-DD>/<slug>
   cat > .groundhog/schedule/once/<YYYY-MM-DD>/<slug>/message.md <<'EOF'
   <reminder body>
   EOF
   ```

5. Confirm to the user that the reminder is set, including the resolved date.

If the user mentions a time of day, include it in the reminder body — schedule resolution here is per-day.

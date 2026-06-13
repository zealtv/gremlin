---
name: send-image
triggers:
  - user asks to send or show an image, photo, picture, chart, or graph
  - user wants a file delivered to them visually rather than as text
---

# send-image

To send an image to the user, write a markdown image reference in your reply:

```text
![a short caption](path/to/file.png)
```

The bridge turns each reference into a real photo. The alt text becomes the
caption; any other text in the same reply is sent alongside as a message.

- A relative path resolves against the gremlin's working directory (the host
  folder) — reference files you created with the same path you wrote them to,
  e.g. `![today's totals](log/2026-06-13/graph.png)`.
- An absolute path (`/...`) or an `http(s)://` URL is used as-is.
- Only send a file that exists; a missing local file fails the send rather than
  delivering a broken reply.

This works for any bridge that understands the convention; the Telegram bridge
sends it with `sendPhoto`.

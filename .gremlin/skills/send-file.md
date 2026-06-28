---
name: send-file
triggers:
  - user asks to send a file, document, zip, log, csv, pdf, export, or attachment
  - you produced a file (export, archive, report) that is more useful delivered than pasted
---

# send-file

To attach a file to the user, write a file embed in your reply:

```text
📎 [a short caption](path/to/file.zip)
```

The bridge turns each embed into a native document. The caption is optional; any
other text in the same reply is sent alongside as a message.

- A relative path resolves against the gremlin's working directory (the host
  folder) — reference files you created with the same path you wrote them to,
  e.g. `📎 [June export](out/june.csv)`.
- An absolute path (`/...`) or an `http(s)://` URL is used as-is.
- Only send a file that exists; a missing local file fails the send rather than
  delivering a broken reply.

Use this for any non-image file — zip, log, csv, pdf, json, text export. For
images use the `send-image` skill (`🖼️`); to speak, use a voice embed (`🔊`). See
`docs/media-embeds.md` for the full grammar. The Telegram bridge sends files with
`sendDocument`.

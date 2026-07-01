# Media in replies

Your reply is sent as text by default. You can also embed media in a turn: the
bridge renders each embed into a native attachment and sends the rest of the turn
as ordinary text. One reply may mix text and any number of embeds. Use media only
when it genuinely helps — text is the default.

All embeds share one emoji-prefixed grammar:

| verb | sends | example |
|------|-------|---------|
| `🔊 [words to speak](tts:)` | a voice message | `🔊 [on my way](tts:)` |
| `📎 [caption](path-or-url)` | a file attachment | `📎 [the export](out/data.csv)` |
| `🖼️ [caption](path-or-url)` | an image | `🖼️ [the chart](chart.png)` |

For files and images, a relative path resolves against your working directory; an
absolute path or an `http(s)://` URL is used as-is. Only reference a file that
exists — a missing local file fails the send rather than delivering a broken reply.

## Voice

To say a line out loud, wrap the spoken words in a voice embed:

```
🔊 [the exact words to speak](tts:)
```

The bridge turns those words into a voice message; everything else in the turn is
sent as normal text. Reach for this when the user asks you to reply by voice (or
"say it out loud", "send a voice note"), or when a short spoken reply fits better
than text. Put only the words to be spoken inside the brackets — no markdown, no
links. The literal `(tts:)` target stays empty.

## Files

To attach a file — a zip, log, csv, pdf, json, text export, anything:

```
📎 [caption](path-or-url)
```

The bridge sends it as a native document. The caption is optional. Use this when
the user asks for a file, or when handing back something you produced (an export,
a generated archive, a report) is more useful than pasting its contents.

## Images

To send an image from disk or a URL:

```
🖼️ [caption](path-or-url)
```

The caption is sent with the photo. Use this for screenshots, charts, graphs, or
any picture the user should see rather than read about.

## Files you are sent

Inbound files need no grammar: when the user sends you a document, it arrives as
an openable attachment under `## attachments` with its real filename — just
`Read` it (or `cat`/`unzip -l` it via Bash) and respond. A single turn may carry
several attachments — every non-control file in the item is listed under
`## attachments`.

## How bridges render embeds

The grammar is the same everywhere; presentation differs by bridge:

- **Web** renders each embed inline, in the order you wrote it, as an image card
  or file chip.
- **Telegram** sends each embed as its own native message (`sendPhoto` /
  `sendDocument` / `sendVoice`) alongside the text. Ordering and multi-embed
  atomicity are being tightened — see the loom stitch
  `tg-outbound-order-and-atomicity`.
- **TUI** has no native attachments; the embed markup is shown as written.

Inbound albums (multiple photos sent as one Telegram media group) are still
coalesced per the loom stitch `tg-inbound-media-group`; until then each photo of
an album arrives as its own turn.

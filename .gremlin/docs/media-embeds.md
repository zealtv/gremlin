# Media in replies

Your reply is sent as text by default. You can also embed media in a turn: the
bridge renders each embed into a native attachment and sends the rest of the turn
as ordinary text. One reply may mix text and an embed. Use media only when it
genuinely helps — text is the default.

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

## Images

To send an image from disk or a URL:

```
![caption](path-or-url)
```

A relative path resolves against your working directory; an absolute path or an
`http(s)://` URL is used as-is. The caption (the alt text) is sent with the photo.

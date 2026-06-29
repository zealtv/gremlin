// render.js - pure turn-body renderer (no DOM), shared by the browser and the
// node test. Turns a transcript body into safe HTML: media embeds become cards,
// a small markdown subset is styled, and everything else is escaped. The
// markup in the transcript stays the source of truth — an unrenderable embed
// degrades to its literal text, never a rewrite (the protocol's render-or-leave
// rule). System bodies are NOT passed through here; they render verbatim.
(function (root, factory) {
  var api = factory();
  root.GremlinRender = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  var SENTINEL = String.fromCharCode(0); // NUL: cannot occur in a transcript body

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  // Media src: http(s) used as-is; a local/relative path points at the (future)
  // /media route — honest-broken until M8 rather than a silent rewrite. A
  // control scheme (javascript:/data:/vbscript:) is refused → unrenderable.
  function safeMediaSrc(src) {
    src = (src || "").trim();
    if (!src) return null;
    if (/^(javascript|data|vbscript):/i.test(src)) return null;
    if (/^https?:\/\//i.test(src)) return src;
    return "/media?path=" + encodeURIComponent(src);
  }

  function safeLinkHref(url) {
    url = (url || "").trim();
    return /^(https?:|mailto:)/i.test(url) ? url : null;
  }

  // A small, safe markdown subset. Escape first, then style; fenced code is
  // pulled aside (behind a NUL sentinel) so inline rules never touch its body.
  function renderProse(text) {
    if (!text) return "";
    var blocks = [];
    text = text.replace(/```[^\n]*\n([\s\S]*?)```/g, function (whole, code) {
      blocks.push("<pre class=\"code\"><code>" + escapeHtml(code.replace(/\n$/, "")) + "</code></pre>");
      return SENTINEL + (blocks.length - 1) + SENTINEL;
    });
    text = escapeHtml(text);
    text = text.replace(/`([^`]+)`/g, "<code>$1</code>");
    text = text.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
    text = text.replace(/\*([^*\n]+)\*/g, "<em>$1</em>");
    text = text.replace(/\[([^\]]*)\]\(([^)]+)\)/g, function (whole, label, url) {
      var href = safeLinkHref(url);
      return href
        ? "<a href=\"" + escapeHtml(href) + "\" target=\"_blank\" rel=\"noopener noreferrer\">" + label + "</a>"
        : whole;
    });
    text = text.replace(new RegExp(SENTINEL + "(\\d+)" + SENTINEL, "g"), function (whole, i) {
      return blocks[+i];
    });
    return text;
  }

  function imageCard(caption, src) {
    var url = safeMediaSrc(src);
    if (!url) return null;
    var cap = caption ? "<figcaption>" + escapeHtml(caption) + "</figcaption>" : "";
    return "<figure class=\"embed embed-image\"><img src=\"" + escapeHtml(url) +
      "\" alt=\"" + escapeHtml(caption || "") + "\" loading=\"lazy\">" + cap + "</figure>";
  }

  function fileChip(caption, src) {
    var url = safeMediaSrc(src);
    if (!url) return null;
    var label = caption || src;
    return "<a class=\"embed embed-file\" href=\"" + escapeHtml(url) +
      "\" download><span class=\"embed-icon\">📎</span><span class=\"embed-label\">" +
      escapeHtml(label) + "</span></a>";
  }

  // Embed grammar (docs/media-embeds.md): 🖼️/📎/🔊 [caption](src), plus the
  // silent ![caption](src) image alias. 🔊 (tts:) is left as text in M2.
  var EMBED_RE = /(🖼️|📎|🔊) \[([^\]]*)\]\(([^)]*)\)|!\[([^\]]*)\]\(([^)]+)\)/g;

  function renderEmbed(emoji, caption, src, literal) {
    var html = null;
    if (emoji === "🖼️") html = imageCard(caption, src);
    else if (emoji === "📎") html = fileChip(caption, src);
    // 🔊 (tts:) audio is deferred to a later milestone → leave as text for now.
    return html !== null ? html : renderProse(literal);
  }

  function renderBodyHTML(text) {
    text = String(text == null ? "" : text);
    var out = "";
    var last = 0;
    var m;
    EMBED_RE.lastIndex = 0;
    while ((m = EMBED_RE.exec(text)) !== null) {
      out += renderProse(text.slice(last, m.index));
      if (m[1]) {
        out += renderEmbed(m[1], m[2], m[3], m[0]);
      } else {
        out += renderEmbed("🖼️", m[4], m[5], m[0]); // ![..](..) alias → image
      }
      last = m.index + m[0].length;
    }
    out += renderProse(text.slice(last));
    return out;
  }

  return {
    renderBodyHTML: renderBodyHTML,
    renderProse: renderProse,
    escapeHtml: escapeHtml,
    safeMediaSrc: safeMediaSrc,
  };
});

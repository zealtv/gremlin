// badge.js - unread-message badge for a hidden tab (stitch 65). Pure state
// transition + title formatting (unit-tested by node), plus a thin DOM layer
// (browser only) that swaps the tab title and favicon. No Notification API
// (no secure context on the fleet), no permissions, no persisted state: a
// reload always starts at 0.
(function (root, factory) {
  var api = factory();
  root.GremlinBadge = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

  // Pure: the next unread count given the current state and an event.
  //   {type:"turn", role, hidden, msSinceReset} — count only a live assistant
  //     turn seen while the tab is hidden. The 2s guard exists because every
  //     SSE `reset` (including auto-reconnects) replays a backfill burst of
  //     old turns that are wire-identical to a live one — those must not count.
  //   {type:"visible"} — the reader looked; clear it.
  function next(state, ev) {
    if (ev.type === "turn") {
      if (ev.role === "assistant" && ev.hidden && ev.msSinceReset > 2000) {
        return { unread: state.unread + 1 };
      }
      return state;
    }
    if (ev.type === "visible") {
      return { unread: 0 };
    }
    return state;
  }

  // Pure: the tab title for a given base + unread count.
  function title(base, unread) {
    return unread > 0 ? "(" + unread + ") " + base : base;
  }

  // --- DOM layer (browser only; guarded so a node require never touches
  // document) ------------------------------------------------------------
  var FAVICON_SIZE = 32;
  var origFaviconHref = null; // captured lazily, restored at unread=0

  function faviconLink() {
    var link = document.querySelector("link[rel~='icon']");
    if (!link) {
      link = document.createElement("link");
      link.rel = "icon";
      document.head.appendChild(link);
    }
    return link;
  }

  function drawBadge(count) {
    var canvas = document.createElement("canvas");
    canvas.width = FAVICON_SIZE;
    canvas.height = FAVICON_SIZE;
    var ctx = canvas.getContext("2d");
    var label = count > 9 ? "9+" : String(count);
    ctx.fillStyle = "#e33";
    ctx.beginPath();
    ctx.arc(FAVICON_SIZE / 2, FAVICON_SIZE / 2, FAVICON_SIZE / 2, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = "#fff";
    ctx.font = "bold " + (label.length > 1 ? 13 : 18) + "px sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(label, FAVICON_SIZE / 2, FAVICON_SIZE / 2 + 1);
    return canvas.toDataURL("image/png");
  }

  // Set document.title + swap the favicon to a badged dot when unread > 0,
  // restoring the original favicon at 0. A drawing failure must never break
  // the app — it's cosmetic, wrapped in try/catch.
  function apply(baseTitle, unread) {
    document.title = title(baseTitle, unread);
    try {
      var link = faviconLink();
      if (origFaviconHref === null) origFaviconHref = link.href || "";
      if (unread > 0) {
        link.href = drawBadge(unread);
      } else if (origFaviconHref) {
        link.href = origFaviconHref;
      } else if (link.parentNode) {
        // The page had no favicon of its own: drop the link we created rather
        // than leave a stale badge (href="" would point the icon at the page).
        link.parentNode.removeChild(link);
      }
    } catch (e) {
      // cosmetic only — never break the app over a favicon draw failure.
    }
  }

  return {
    next: next,
    title: title,
    apply: apply,
  };
});

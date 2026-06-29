// app.js - the M0 data path: tail the transcript over SSE, render turns.
// Vanilla fetch + EventSource, no framework. "live" means only "tailing the
// file." The bridge never invents a turn; everything here came from disk.

(function () {
  "use strict";

  var log = document.getElementById("log");
  var liveLabel = document.getElementById("live-label");
  var liveBox = document.getElementById("live");

  function setLive(state, label) {
    liveBox.className = "live " + state;
    liveLabel.textContent = label;
  }

  // Is the viewport scrolled near the bottom? Only auto-scroll if so, so a
  // reader scrolled up to an older turn is not yanked back down.
  function atBottom() {
    return window.innerHeight + window.scrollY >= document.body.offsetHeight - 80;
  }

  function clear() {
    log.textContent = "";
  }

  function renderTurn(turn) {
    var stick = atBottom();
    var el = document.createElement("div");
    el.className = "turn " + turn.role;

    if (turn.role === "system") {
      // A system turn is a full-width dimmed notice, never a bubble. The body
      // (`⚙️ run:`, `⚠️ error:`, `💌 message:`) is shown verbatim; an error
      // body gets a hairline rule, nothing more.
      var notice = document.createElement("div");
      notice.className = "notice";
      if (/^\s*⚠️/.test(turn.body)) notice.classList.add("error");
      notice.textContent = turn.body;
      el.appendChild(notice);
    } else {
      var bubble = document.createElement("div");
      bubble.className = "bubble";
      bubble.textContent = turn.body; // M0 renders text; markdown lands in M2
      el.appendChild(bubble);
      if (turn.ts) {
        var meta = document.createElement("div");
        meta.className = "meta";
        meta.textContent = turn.ts;
        el.appendChild(meta);
      }
    }

    log.appendChild(el);
    if (stick) window.scrollTo(0, document.body.scrollHeight);
  }

  // --- SSE transport (the primary path) ---------------------------------
  function startSSE() {
    var es = new EventSource("/events");
    es.addEventListener("open", function () {
      setLive("up", "live");
    });
    es.addEventListener("reset", function () {
      // A fresh connection (incl. auto-reconnect) replays the backfill, so
      // clear first to re-render cleanly rather than duplicate.
      clear();
    });
    es.addEventListener("turn", function (e) {
      renderTurn(JSON.parse(e.data));
    });
    es.addEventListener("error", function () {
      setLive("down", "reconnecting…");
      // EventSource reconnects on its own; nothing to do.
    });
  }

  // --- short-poll fallback (no EventSource available) -------------------
  function startPolling() {
    var cursor = 0;
    var first = true;
    function tick() {
      fetch("/poll?cursor=" + cursor)
        .then(function (r) { return r.json(); })
        .then(function (data) {
          if (first) { clear(); first = false; }
          setLive("up", "live");
          (data.turns || []).forEach(renderTurn);
          cursor = data.cursor;
        })
        .catch(function () { setLive("down", "reconnecting…"); })
        .then(function () { setTimeout(tick, 1500); });
    }
    tick();
  }

  // --- copy-path chip ----------------------------------------------------
  var chip = document.getElementById("chip");
  if (chip) {
    chip.addEventListener("click", function () {
      if (navigator.clipboard) {
        navigator.clipboard.writeText("transcript.md").catch(function () {});
      }
    });
  }

  if (typeof window.EventSource !== "undefined") {
    startSSE();
  } else {
    startPolling();
  }
})();

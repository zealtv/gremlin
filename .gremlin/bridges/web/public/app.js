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

  // --- pending echoes ---------------------------------------------------
  // What you typed appears immediately in a muted "pending" style — an honest
  // echo of your own words, not a model turn. It clears when the real
  // `## user —` turn arrives in the tail. No spinner theater.
  var pendings = []; // { text, el, timer }

  function pendingEl(text) {
    var el = document.createElement("div");
    el.className = "turn user pending";
    var bubble = document.createElement("div");
    bubble.className = "bubble";
    bubble.textContent = text;
    el.appendChild(bubble);
    return el;
  }

  function addPending(text) {
    var entry = { text: text, el: pendingEl(text), timer: null };
    // Auto-expire to a loud notice if no turn lands within a generous bound
    // (the tender can be slow). Mirrors `⚠️ error: empty model reply`.
    entry.timer = setTimeout(function () {
      entry.el.classList.add("errored");
      var note = document.createElement("div");
      note.className = "meta error";
      note.textContent = "not delivered — is the gremlin running?";
      entry.el.appendChild(note);
    }, 180000);
    pendings.push(entry);
    log.appendChild(entry.el);
    window.scrollTo(0, document.body.scrollHeight);
  }

  function clearMatchingPending(body) {
    for (var i = 0; i < pendings.length; i++) {
      if (pendings[i].text.trim() === (body || "").trim()) {
        clearTimeout(pendings[i].timer);
        if (pendings[i].el.parentNode) pendings[i].el.parentNode.removeChild(pendings[i].el);
        pendings.splice(i, 1);
        return;
      }
    }
  }

  // Keep pending echoes anchored at the bottom (appendChild moves an existing
  // node), so they stay below the file-derived turns after any render.
  function floatPendings() {
    pendings.forEach(function (p) { log.appendChild(p.el); });
  }

  function clear() {
    log.textContent = "";
    // Pending echoes are client-only (not in the file), so survive a reset/
    // reconnect: re-append them after the file-derived turns are cleared.
    floatPendings();
  }

  function renderTurn(turn) {
    if (turn.role === "user") clearMatchingPending(turn.body);
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
      // Render embeds + a small markdown subset (render.js); the transcript
      // markup stays the source of truth — unrenderable embeds degrade to text.
      if (window.GremlinRender) {
        bubble.innerHTML = window.GremlinRender.renderBodyHTML(turn.body);
      } else {
        bubble.textContent = turn.body;
      }
      el.appendChild(bubble);
      if (turn.ts) {
        var meta = document.createElement("div");
        meta.className = "meta";
        meta.textContent = turn.ts;
        el.appendChild(meta);
      }
    }

    log.appendChild(el);
    floatPendings();
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

  // --- composer (POST /send) -------------------------------------------
  var form = document.getElementById("composer");
  var input = document.getElementById("input");

  function autosize() {
    input.style.height = "auto";
    input.style.height = Math.min(input.scrollHeight, 160) + "px";
  }

  function send() {
    var text = input.value;
    if (!text.trim()) return;
    input.value = "";
    autosize();
    addPending(text);
    fetch("/send", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: text }),
    }).then(function (r) {
      if (!r.ok) {
        // The write was refused; surface it on the pending echo rather than
        // pretending it landed.
        clearMatchingPending(text);
        renderTurn({ role: "system", body: "⚠️ error: message not sent (" + r.status + ")" });
      }
    }).catch(function () {
      clearMatchingPending(text);
      renderTurn({ role: "system", body: "⚠️ error: message not sent (offline)" });
    });
  }

  if (form) {
    form.addEventListener("submit", function (e) {
      e.preventDefault();
      send();
    });
    input.addEventListener("input", autosize);
    // Enter sends; Shift+Enter inserts a newline.
    input.addEventListener("keydown", function (e) {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        send();
      }
    });
  }

  if (typeof window.EventSource !== "undefined") {
    startSSE();
  } else {
    startPolling();
  }
})();

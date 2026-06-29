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

  // Is the log scrolled near the bottom? Only auto-scroll if so, so a reader
  // scrolled up to an older turn is not yanked back down.
  function atBottom() {
    return log.scrollHeight - log.scrollTop - log.clientHeight < 80;
  }
  function scrollToBottom() {
    log.scrollTop = log.scrollHeight;
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
    scrollToBottom();
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
    if (stick) scrollToBottom();
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

  // --- inspector views: the read-only route→read→render(→poll) pattern -------
  var panel = document.getElementById("panel");
  var inspect = document.getElementById("inspect");
  var composer = document.getElementById("composer");
  var tabs = Array.prototype.slice.call(document.querySelectorAll(".tab[data-view]"));
  var statusTimer = null;
  var VIEWS = { chat: log, inspect: inspect, more: panel };

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  function pathChip(p) {
    return el("div", "chip path-chip", "◷ " + p);
  }

  function section(title) {
    var s = el("section", "card");
    s.appendChild(el("h2", "card-title", title));
    return s;
  }

  function field(items, name) {
    for (var i = 0; i < items.length; i++) if (items[i].name === name) return items[i];
    return null;
  }

  function renderStatus(env) {
    var s = section("Status");
    s.appendChild(pathChip(env.protocol === "status" ? ".gremlin/" : ""));
    var runner = field(env.items, "runner") || { state: "?", fields: {} };
    var tend = field(env.items, "tending") || { state: "?", fields: {} };
    var prog = field(env.items, "in-progress");
    var logItem = field(env.items, "run.log");

    var row = el("div", "status-row");
    row.appendChild(el("span", "pill " + (runner.fields.paused ? "warn" : "good"),
      runner.fields.paused ? "paused" : "active"));
    var tstate = tend.state === "thinking" ? "thinking"
      : tend.state === "stale" ? "idle, stale pid" : "idle";
    row.appendChild(el("span", "pill " + (tend.state === "stale" ? "warn" : "muted"), tstate));
    if (prog && prog.fields.tending) {
      row.appendChild(el("span", "pill muted", prog.fields.tending + " in progress"));
    }
    s.appendChild(row);

    if (logItem && logItem.fields.tail && logItem.fields.tail.length) {
      s.appendChild(el("div", "sub", "run.log"));
      s.appendChild(el("pre", "code", logItem.fields.tail.join("\n")));
    }
    return s;
  }

  function renderContext(env) {
    var frag = document.createDocumentFragment();

    var ident = section("Identity");
    ident.appendChild(pathChip("gremlin.md"));
    var g = field(env.items, "gremlin.md");
    if (g && g.fields.body && window.GremlinRender) {
      var b = el("div", "prose");
      b.innerHTML = window.GremlinRender.renderBodyHTML(g.fields.body);
      ident.appendChild(b);
    }
    var model = field(env.items, "model");
    if (model) ident.appendChild(el("div", "sub", "model: " + model.fields.value));
    frag.appendChild(ident);

    var ctx = section("Context");
    ctx.appendChild(pathChip("context/"));
    env.items.forEach(function (it) {
      if (it.state !== "context" || it.name === "model") return;
      var row = el("div", "ctx-row");
      var head = el("div", "ctx-head");
      head.appendChild(el("span", "ctx-name", it.name));
      if (it.fields.symlink && it.fields.target) {
        head.appendChild(el("span", "ctx-target", "→ " + it.fields.target));
      }
      if (it.fields.names) {
        head.appendChild(el("span", "ctx-target", it.fields.names.join(" · ")));
      }
      row.appendChild(head);
      row.appendChild(el("div", "path-chip mono", it.path));
      if (it.fields.body) {
        var body = el("pre", "code ctx-body");
        body.hidden = true;
        body.textContent = it.fields.body;
        head.style.cursor = "pointer";
        head.addEventListener("click", function () { body.hidden = !body.hidden; });
        row.appendChild(body);
      } else if (it.fields.escaped) {
        row.appendChild(el("div", "sub warn", "target outside host — not shown"));
      }
      ctx.appendChild(row);
    });
    frag.appendChild(ctx);
    return frag;
  }

  // --- Glean: index-first list, body fetched on demand --------------------
  var gleanRows = {}; // id → { row, bodyEl, loaded }

  function renderFindingBody(bodyEl, env) {
    var it = env.items[0];
    var html = window.GremlinRender
      ? window.GremlinRender.renderBodyHTML(it.fields.body)
      : it.fields.body;
    // [[id]] wikilinks → in-app navigation between findings.
    html = html.replace(/\[\[([A-Za-z0-9._-]+)\]\]/g,
      "<a class=\"wiki\" data-id=\"$1\">$1</a>");
    bodyEl.innerHTML = html;
  }

  function openFinding(id) {
    var entry = gleanRows[id];
    if (!entry) return;
    if (entry.loaded) {
      entry.bodyEl.hidden = !entry.bodyEl.hidden;
      return;
    }
    entry.bodyEl.textContent = "loading…";
    entry.bodyEl.hidden = false;
    fetch("/api/glean/finding/" + encodeURIComponent(id))
      .then(function (r) { return r.ok ? r.json() : Promise.reject(); })
      .then(function (env) { renderFindingBody(entry.bodyEl, env); entry.loaded = true; })
      .catch(function () { entry.bodyEl.textContent = "could not load finding"; });
  }

  function fieldByName(items, name) {
    for (var i = 0; i < items.length; i++) if (items[i].name === name) return items[i];
    return null;
  }

  function renderGlean(env) {
    gleanRows = {};
    var head = section("Glean — memory");
    head.appendChild(pathChip(".glean/findings/INDEX.md"));

    env.items.forEach(function (it) {
      if (it.name === "workbench") return;
      var row = el("div", "ctx-row");
      var h = el("div", "ctx-head");
      h.style.cursor = "pointer";
      var titleEl = el("span", "ctx-name", it.fields.title || it.name);
      h.appendChild(titleEl);
      if (it.fields.promoted) h.appendChild(el("span", "pill broadcast", "📡 promoted"));
      row.appendChild(h);
      row.appendChild(el("div", "sub", it.fields.desc || ""));
      var body = el("div", "finding-body prose");
      body.hidden = true;
      row.appendChild(body);
      gleanRows[it.name] = { row: row, bodyEl: body, loaded: false };
      h.addEventListener("click", function () { openFinding(it.name); });
      head.appendChild(row);
    });
    inspect.appendChild(head);

    var wb = fieldByName(env.items, "workbench");
    if (wb) {
      var w = section("Workbench");
      w.appendChild(el("div", "sub",
        "in " + wb.fields.in + " · out " + wb.fields.out + " · dropped " + wb.fields.dropped));
      inspect.appendChild(w);
    }
  }

  // --- Groundhog: schedule tree (verbatim from `list`) + derived state ------
  function renderGroundhog(env) {
    var s = section("Groundhog");
    s.appendChild(pathChip(".groundhog/schedule/"));
    if (env.raw && env.raw.trim()) {
      s.appendChild(el("div", "sub", "schedule (groundhog.sh list)"));
      s.appendChild(el("pre", "code", env.raw.replace(/\n+$/, "")));
    } else {
      s.appendChild(el("div", "sub", "nothing scheduled"));
    }
    inspect.appendChild(s);

    var groups = [
      ["due", "Due now"],
      ["fired-today", "Fired today"],
      ["awaiting-pickup", "Awaiting pickup (out/)"],
    ];
    groups.forEach(function (g) {
      var rows = env.items.filter(function (i) { return i.state === g[0]; });
      if (!rows.length) return;
      var c = section(g[1]);
      rows.forEach(function (i) {
        var row = el("div", "ctx-row");
        row.appendChild(el("div", "ctx-name", i.name));
        row.appendChild(el("div", "path-chip mono", i.path));
        c.appendChild(row);
      });
      inspect.appendChild(c);
    });
  }

  // --- Loom: preserve the thread/stitch model; reuse loom.sh (never flatten) -
  function renderLoom(env) {
    var loose = env.items.filter(function (i) { return i.state === "loose-end"; });
    var next = section("Next to tend");
    next.appendChild(pathChip(".loom/threads/"));
    if (loose.length) {
      loose.forEach(function (i) {
        var row = el("div", "ctx-row");
        row.appendChild(el("div", "ctx-name", i.name));
        row.appendChild(el("div", "path-chip mono", i.path));
        next.appendChild(row);
      });
    } else {
      next.appendChild(el("div", "sub", "nothing ready to tend"));
    }
    inspect.appendChild(next);

    if (env.raw && env.raw.trim()) {
      var t = section("Threads (loom.sh status)");
      t.appendChild(el("pre", "code", env.raw.replace(/\n+$/, "")));
      inspect.appendChild(t);
    }
  }

  // --- Inspect hub: index-first inspectors, one screen each (spec §5) -------
  // Emojis match each primitive's own README title.
  var INSPECTORS = [
    { id: "groundhog", emoji: "🦫", label: "Groundhog", api: "/api/groundhog", render: renderGroundhog },
    { id: "loom", emoji: "🪡", label: "Loom", api: "/api/loom", render: renderLoom },
    { id: "glean", emoji: "🔮", label: "Glean", api: "/api/glean", render: renderGlean },
  ];
  var SOON = ["📜 Lore"];

  function backHeader() {
    var b = el("button", "back", "‹ Inspect");
    b.addEventListener("click", renderInspectHub);
    return b;
  }

  function renderInspectHub() {
    inspect.textContent = "";
    var s = section("Inspect");
    INSPECTORS.forEach(function (insp) {
      var row = el("div", "hub-row");
      row.appendChild(el("span", "hub-emoji", insp.emoji));
      row.appendChild(el("span", "hub-label", insp.label));
      row.style.cursor = "pointer";
      row.addEventListener("click", function () { openInspector(insp); });
      s.appendChild(row);
    });
    SOON.forEach(function (label) {
      var row = el("div", "hub-row soon");
      row.appendChild(el("span", "hub-label", label));
      row.appendChild(el("span", "ctx-target", "coming soon"));
      s.appendChild(row);
    });
    inspect.appendChild(s);
  }

  function openInspector(insp) {
    inspect.textContent = "";
    inspect.appendChild(backHeader());
    var loading = el("div", "sub", "loading…");
    inspect.appendChild(loading);
    fetch(insp.api).then(function (r) { return r.json(); })
      .then(function (env) { loading.remove(); insp.render(env); })
      .catch(function () { loading.textContent = "could not load " + insp.label; loading.className = "sub warn"; });
  }

  function loadPanel() {
    Promise.all([
      fetch("/api/status").then(function (r) { return r.json(); }),
      fetch("/api/context").then(function (r) { return r.json(); }),
    ]).then(function (res) {
      panel.textContent = "";
      panel.appendChild(renderStatus(res[0]));
      panel.appendChild(renderContext(res[1]));
    }).catch(function () {
      panel.textContent = "";
      panel.appendChild(el("div", "sub warn", "could not load panel"));
    });
  }

  function showView(name) {
    Object.keys(VIEWS).forEach(function (k) { VIEWS[k].hidden = k !== name; });
    composer.style.display = name === "chat" ? "" : "none";
    tabs.forEach(function (t) {
      var active = t.getAttribute("data-view") === name;
      t.classList.toggle("active", active);
      if (active) t.setAttribute("aria-current", "page");
      else t.removeAttribute("aria-current");
    });
    if (statusTimer) { clearInterval(statusTimer); statusTimer = null; }
    if (name === "more") {
      loadPanel();
      statusTimer = setInterval(loadPanel, 4000); // poll: the inspector shape
    } else if (name === "inspect") {
      renderInspectHub();
    }
  }

  tabs.forEach(function (t) {
    t.addEventListener("click", function () { showView(t.getAttribute("data-view")); });
  });

  // wikilink delegation (registered once): tap [[id]] → open that finding.
  inspect.addEventListener("click", function (e) {
    var a = e.target.closest && e.target.closest("a.wiki");
    if (a) { e.preventDefault(); openFinding(a.getAttribute("data-id")); }
  });

  if (typeof window.EventSource !== "undefined") {
    startSSE();
  } else {
    startPolling();
  }
})();

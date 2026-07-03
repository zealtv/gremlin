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

  // A slash command (leading `/`) is a bridge-level action, not a chat turn:
  // it runs server-side through bin/slash.sh and its output renders as an
  // ephemeral bridge message — never a transcript turn, never a pending echo.
  function isSlash(text) {
    return /^\s*\//.test(text);
  }

  // Bridge message: visually distinct from gremlin turns, client-only and
  // ephemeral (a reset/reconnect drops it). Command + output both go in via
  // textContent, so any HTML in the output is rendered inert.
  function renderBridge(cmd, output, kind) {
    var stick = atBottom();
    var el = document.createElement("div");
    el.className = "turn bridge" + (kind ? " " + kind : "");
    var head = document.createElement("div");
    head.className = "bridge-cmd";
    head.textContent = cmd;
    el.appendChild(head);
    var pre = document.createElement("pre");
    pre.className = "bridge-out code";
    pre.textContent = output;
    el.appendChild(pre);
    var meta = document.createElement("div");
    meta.className = "meta";
    meta.textContent = "bridge · not saved to transcript";
    el.appendChild(meta);
    log.appendChild(el);
    floatPendings();
    if (stick) scrollToBottom();
  }

  function sendSlash(cmd) {
    fetch("/send", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text: cmd }),
    }).then(function (r) {
      return r.text().then(function (t) {
        var d = {};
        try { d = JSON.parse(t); } catch (e) { d = { output: t }; }
        return { ok: r.ok, status: r.status, data: d };
      });
    }).then(function (res) {
      var d = res.data || {};
      if (!res.ok && d.output == null) {
        renderBridge(cmd, "command failed (" + res.status + ")", "error");
        return;
      }
      renderBridge(cmd, d.output || "(no output)", d.rc === 0 ? "" : "error");
    }).catch(function () {
      renderBridge(cmd, "command not sent (offline)", "error");
    });
  }

  function send() {
    var text = input.value;
    if (!text.trim()) return;
    input.value = "";
    hideMenu();
    autosize();
    if (isSlash(text)) { sendSlash(text.trim()); return; }
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

  // --- slash-command autocomplete (stitch 22) ---------------------------------
  // The menu derives from /api/commands — the same commands/*.sh bin/slash.sh
  // dispatches to — so the web vocabulary can never drift from the CLI's.
  var cmdMenu = document.getElementById("cmd-menu");
  var commandList = null; // [{name, summary}], fetched once and cached
  var menuItems = [];     // current filtered subset
  var menuIndex = -1;     // highlighted row

  function loadCommands() {
    if (commandList) return Promise.resolve(commandList);
    return fetch("/api/commands")
      .then(function (r) { return r.json(); })
      .then(function (env) { commandList = env.items || []; return commandList; })
      .catch(function () { commandList = []; return commandList; });
  }

  // The command token being typed: value is `/` + non-space run, nothing after.
  // A space (or a second `/`, i.e. a pasted path) ends command-typing mode.
  function slashToken(value) {
    var m = /^\/([^\s/]*)$/.exec(value);
    return m ? m[1] : null;
  }

  function menuOpen() { return cmdMenu && !cmdMenu.hidden && menuItems.length > 0; }

  function hideMenu() {
    if (!cmdMenu) return;
    cmdMenu.hidden = true;
    cmdMenu.textContent = "";
    menuItems = [];
    menuIndex = -1;
  }

  function renderMenu() {
    if (!cmdMenu) return;
    cmdMenu.textContent = "";
    if (!menuItems.length) { cmdMenu.hidden = true; return; }
    menuItems.forEach(function (c, i) {
      var row = el("div", "cmd-item" + (i === menuIndex ? " active" : ""));
      row.setAttribute("role", "option");
      row.setAttribute("aria-selected", i === menuIndex ? "true" : "false");
      row.appendChild(el("span", "cmd-name", "/" + c.name));
      if (c.summary) row.appendChild(el("span", "cmd-summary", c.summary));
      // mousedown (not click) so completion runs before the textarea blurs.
      row.addEventListener("mousedown", function (e) {
        e.preventDefault();
        completeCommand(c.name);
      });
      cmdMenu.appendChild(row);
    });
    cmdMenu.hidden = false;
  }

  function updateMenu() {
    var token = slashToken(input.value);
    if (token === null) { hideMenu(); return; }
    loadCommands().then(function (list) {
      var t = slashToken(input.value); // may have changed while awaiting
      if (t === null) { hideMenu(); return; }
      var lower = t.toLowerCase();
      menuItems = list.filter(function (c) {
        return c.name.toLowerCase().indexOf(lower) === 0;
      });
      menuIndex = menuItems.length ? 0 : -1;
      renderMenu();
    });
  }

  function completeCommand(name) {
    input.value = "/" + name + " ";
    hideMenu();
    input.focus();
    autosize();
  }

  // Enter behaves differently with a physical keyboard vs an on-screen one. A
  // coarse primary pointer ⇒ a touch-first device (phone/tablet); a fine primary
  // pointer ⇒ a laptop/desktop (a touch-laptop with a trackpad reports fine, so
  // it is correctly treated as a laptop). Evaluated once at load.
  var touchPrimary = !!(window.matchMedia && window.matchMedia("(pointer: coarse)").matches);
  var sendBtn = document.getElementById("send");
  if (sendBtn) {
    sendBtn.title = touchPrimary
      ? "Send"
      : "Send · Enter to send, ⌘/Ctrl+Enter for a newline";
  }

  function insertNewlineAtCursor() {
    var start = input.selectionStart, end = input.selectionEnd, v = input.value;
    input.value = v.slice(0, start) + "\n" + v.slice(end);
    input.selectionStart = input.selectionEnd = start + 1;
    autosize();
  }

  if (form) {
    form.addEventListener("submit", function (e) {
      e.preventDefault();
      hideMenu();
      send();
    });
    input.addEventListener("input", function () { autosize(); updateMenu(); });
    input.addEventListener("blur", function () { hideMenu(); });
    input.addEventListener("keydown", function (e) {
      // When the autocomplete menu is open it owns the navigation/commit keys.
      if (menuOpen()) {
        if (e.key === "ArrowDown") {
          e.preventDefault(); menuIndex = (menuIndex + 1) % menuItems.length; renderMenu(); return;
        }
        if (e.key === "ArrowUp") {
          e.preventDefault(); menuIndex = (menuIndex - 1 + menuItems.length) % menuItems.length; renderMenu(); return;
        }
        // While the menu is open, plain Enter or Tab commits the highlighted
        // command; a modified Enter (⌘/Ctrl) falls through to newline below.
        if ((e.key === "Enter" && !e.ctrlKey && !e.metaKey) || e.key === "Tab") {
          e.preventDefault(); completeCommand(menuItems[menuIndex].name); return;
        }
        if (e.key === "Escape") { e.preventDefault(); hideMenu(); return; }
      }
      // Platform-aware Enter. Touch: leave the on-screen Enter to insert a
      // newline (submit is the send button only), so the return key never fires
      // a half-typed message. Laptop: plain Enter submits; ⌘/Ctrl+Enter inserts
      // a newline. Shift/Alt+Enter stay the browser's default newline either way.
      if (e.key === "Enter" && !touchPrimary && !e.shiftKey && !e.altKey) {
        e.preventDefault();
        if (e.ctrlKey || e.metaKey) insertNewlineAtCursor();
        else send();
      }
    });
  }

  // --- inspector views: the read-only route→read→render(→poll) pattern -------
  var panel = document.getElementById("panel");
  var inspect = document.getElementById("inspect");
  var transcriptView = document.getElementById("transcript");
  var dashView = document.getElementById("dash");
  var composer = document.getElementById("composer");
  var tabs = Array.prototype.slice.call(document.querySelectorAll(".tab[data-view]"));
  var statusTimer = null;
  var VIEWS = { chat: log, transcript: transcriptView, dash: dashView, inspect: inspect, more: panel };

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

  // Which More-panel disclosures the reader has opened, keyed by a stable path.
  // The 4s status poll rebuilds the panel from fresh data (loadPanel wipes and
  // re-renders); this map survives that rebuild so an expanded section — a
  // context body, a tools/skills list — stays open across refreshes. It is
  // client-only session state, so a deliberate page reload starts collapsed.
  var moreExpanded = {};

  function bindDisclosure(head, body, key) {
    head.style.cursor = "pointer";
    body.hidden = !moreExpanded[key];
    head.addEventListener("click", function () {
      body.hidden = !body.hidden;
      moreExpanded[key] = !body.hidden;
    });
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
        // A skills/tools surface (e.g. "Tools"): show the count in the head and
        // move the list into a disclosure body below, so it stays scannable on
        // mobile and its open/shut state persists across the periodic refresh.
        head.appendChild(el("span", "ctx-target", it.fields.names.length + " items"));
      }
      row.appendChild(head);
      row.appendChild(el("div", "path-chip mono", it.path));
      if (it.fields.body) {
        var body = el("pre", "code ctx-body");
        body.textContent = it.fields.body;
        bindDisclosure(head, body, it.path || it.name);
        row.appendChild(body);
      } else if (it.fields.names) {
        var list = el("div", "ctx-body sub");
        list.textContent = it.fields.names.join(" · ");
        bindDisclosure(head, list, it.path || it.name);
        row.appendChild(list);
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

  // --- Lore: durable, dated reference; dark by default (cf. Glean) ----------
  var loreRows = {};

  function loreContentLink(id, c) {
    var a = el("a", "embed embed-file");
    a.href = "/api/lore/content/" + encodeURIComponent(id) + "/" +
      c.name.split("/").map(encodeURIComponent).join("/");
    if (c.binary) a.setAttribute("download", ""); else a.target = "_blank";
    a.appendChild(el("span", "embed-icon", c.binary ? "📦" : "📄"));
    a.appendChild(el("span", "embed-label", c.name + " · " + c.size + " B"));
    return a;
  }

  function openLore(id) {
    var entry = loreRows[id];
    if (!entry) return;
    if (entry.loaded) { entry.bodyEl.hidden = !entry.bodyEl.hidden; return; }
    entry.bodyEl.textContent = "loading…";
    entry.bodyEl.hidden = false;
    fetch("/api/lore/item/" + encodeURIComponent(id))
      .then(function (r) { return r.ok ? r.json() : Promise.reject(); })
      .then(function (env) {
        var f = env.items[0].fields;
        entry.bodyEl.innerHTML = window.GremlinRender
          ? window.GremlinRender.renderBodyHTML(f.body) : f.body;
        if (f.content && f.content.length) {
          entry.bodyEl.appendChild(el("div", "sub", "content/"));
          f.content.forEach(function (c) { entry.bodyEl.appendChild(loreContentLink(id, c)); });
        }
        entry.loaded = true;
      })
      .catch(function () { entry.bodyEl.textContent = "could not load item"; });
  }

  function renderLore(env) {
    loreRows = {};
    var head = section("Lore — reference");
    head.appendChild(pathChip(".lore/INDEX.md"));
    head.appendChild(el("div", "sub", "durable, dated record — not recalled"));
    if (!env.items.length) {
      head.appendChild(el("div", "sub", "no lore here"));
      inspect.appendChild(head);
      return;
    }
    env.items.forEach(function (it) {
      var row = el("div", "ctx-row");
      var h = el("div", "ctx-head");
      h.style.cursor = "pointer";
      h.appendChild(el("span", "ctx-name", it.fields.title || it.name));
      if (it.fields.date) h.appendChild(el("span", "ctx-target", it.fields.date));
      row.appendChild(h);
      row.appendChild(el("div", "sub", it.fields.desc || ""));
      var body = el("div", "finding-body prose");
      body.hidden = true;
      row.appendChild(body);
      loreRows[it.name] = { bodyEl: body, loaded: false };
      h.addEventListener("click", function () { openLore(it.name); });
      head.appendChild(row);
    });
    inspect.appendChild(head);
  }

  // --- Inspect hub: index-first inspectors, one screen each (spec §5) -------
  // Emojis match each primitive's own README title.
  var INSPECTORS = [
    { id: "groundhog", emoji: "🦫", label: "Groundhog", api: "/api/groundhog", render: renderGroundhog },
    { id: "loom", emoji: "🪡", label: "Loom", api: "/api/loom", render: renderLoom },
    { id: "glean", emoji: "🔮", label: "Glean", api: "/api/glean", render: renderGlean },
    { id: "lore", emoji: "🐉", label: "Lore", api: "/api/lore", render: renderLore },
  ];
  var SOON = [];

  // Purpose hints (stitch 26), keyed by primitive id, sourced live from each
  // primitive's own README via /api/primitives — never authored here, so the
  // hub can't drift from canonical docs. Fetched once, then the hub re-renders.
  var primitiveHints = null;

  function loadPrimitiveHints() {
    if (primitiveHints) return Promise.resolve(primitiveHints);
    return fetch("/api/primitives")
      .then(function (r) { return r.json(); })
      .then(function (env) {
        primitiveHints = {};
        (env.items || []).forEach(function (p) { primitiveHints[p.name] = p.hint || ""; });
        return primitiveHints;
      })
      .catch(function () { primitiveHints = {}; return primitiveHints; });
  }

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
      var text = el("span", "hub-text");
      text.appendChild(el("span", "hub-label", insp.label));
      var hint = primitiveHints && primitiveHints[insp.id];
      if (hint) text.appendChild(el("span", "hub-hint", hint));
      row.appendChild(text);
      row.style.cursor = "pointer";
      row.addEventListener("click", function () { openInspector(insp); });
      s.appendChild(row);
    });
    // Transcript is a read-only lens over the conversation record — an inspector
    // in nature (route→read→render), so it lives in the hub rather than the
    // primary thumb-bar (owner steer 2026-07-03). Its own rich renderer (archive
    // switch, search) opens one level down, with a back link to the hub.
    var trow = el("div", "hub-row");
    trow.appendChild(el("span", "hub-emoji", "📝"));
    var ttext = el("span", "hub-text");
    ttext.appendChild(el("span", "hub-label", "Transcript"));
    ttext.appendChild(el("span", "hub-hint", "conversation record"));
    trow.appendChild(ttext);
    trow.style.cursor = "pointer";
    trow.addEventListener("click", function () { showView("transcript"); });
    s.appendChild(trow);
    SOON.forEach(function (label) {
      var row = el("div", "hub-row soon");
      row.appendChild(el("span", "hub-label", label));
      row.appendChild(el("span", "ctx-target", "coming soon"));
      s.appendChild(row);
    });
    inspect.appendChild(s);
    // First visit: hints aren't cached yet — fetch, then repaint the hub in
    // place (only if the user is still looking at it) so hints appear.
    if (!primitiveHints) {
      loadPrimitiveHints().then(function () {
        if (!inspect.hidden && inspect.querySelector(".hub-row")) renderInspectHub();
      });
    }
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

  // --- honest activity indicator (stitch 29) ---------------------------------
  // NOT a fabricated "typing…": the council forbids inventing liveness the files
  // can't justify (designer report §8). This reflects only what build_status
  // derives from disk — the tender is actively handling a turn when .tending.pid
  // is alive ("thinking") or a .nest/in item is claimed. It clears on completion
  // (pid idle), on disconnect (fetch fails), and on leaving Chat. A short linger
  // bridges the idle gap between back-to-back turns so it doesn't flicker.
  var activityEl = document.getElementById("activity");
  var activityTimer = null;
  var lastWorkingAt = 0;

  function setActivity(on) {
    if (!activityEl) return;
    activityEl.hidden = !on;
    activityEl.textContent = on ? "⚙ the gremlin is working…" : "";
  }

  function pollActivity() {
    fetch("/api/status").then(function (r) { return r.json(); }).then(function (env) {
      var items = env.items || [];
      function f(n) { for (var i = 0; i < items.length; i++) if (items[i].name === n) return items[i]; return null; }
      var tend = f("tending"), prog = f("in-progress");
      var working = (tend && tend.state === "thinking") ||
        (prog && prog.fields && prog.fields.tending > 0);
      var now = Date.now();
      if (working) lastWorkingAt = now;
      setActivity(!!working || (now - lastWorkingAt < 3000));
    }).catch(function () { lastWorkingAt = 0; setActivity(false); });
  }

  function startActivity() {
    stopActivity();
    pollActivity();
    activityTimer = setInterval(pollActivity, 2500);
  }
  function stopActivity() {
    if (activityTimer) { clearInterval(activityTimer); activityTimer = null; }
    lastWorkingAt = 0;
    setActivity(false);
  }

  // --- Dash: custom per-gremlin views the bridge serves from HOST_DIR/.dash/ ---
  // The bridge is a lens: it only *serves* views (discovery + jailed static). A
  // view is trusted gremlin-authored code — loading it is a smaller grant than
  // the POST /send every token-holder already wields (design §4). The iframe is
  // failure-isolation (a broken view breaks only its frame), NOT containment.
  function renderDashEmpty() {
    dashView.classList.remove("framed");
    dashView.textContent = "";
    var s = section("Dash");
    s.appendChild(el("div", "sub", "No dashboard yet — ask me in chat to build one."));
    dashView.appendChild(s);
  }

  function mountDashView(name) {
    dashView.textContent = "";
    dashView.classList.add("framed");
    var frame = document.createElement("iframe");
    frame.className = "dash-frame";
    frame.title = name;
    // Trailing slash: relative asset/data refs in the view resolve under
    // /dash/<name>/. Same-origin so the view can read cookie-authed jailed
    // routes; the sandbox suppresses top-nav/popups from a buggy view but is
    // not a containment boundary (it can still reach window.parent).
    frame.src = "/dash/" + encodeURIComponent(name) + "/";
    frame.setAttribute("sandbox", "allow-scripts allow-same-origin");
    dashView.appendChild(frame);
  }

  function renderDashHub(views) {
    dashView.classList.remove("framed");
    dashView.textContent = "";
    var s = section("Dash");
    views.forEach(function (v) {
      var row = el("div", "hub-row");
      row.appendChild(el("span", "hub-emoji", "📊"));
      var text = el("span", "hub-text");
      text.appendChild(el("span", "hub-label", (v.fields && v.fields.title) || v.name));
      row.appendChild(text);
      row.style.cursor = "pointer";
      row.addEventListener("click", function () { mountDashView(v.name); });
      s.appendChild(row);
    });
    dashView.appendChild(s);
  }

  function loadDash() {
    dashView.classList.remove("framed");
    dashView.textContent = "";
    dashView.appendChild(el("div", "sub", "loading…"));
    fetch("/api/dash").then(function (r) { return r.json(); })
      .then(function (env) {
        var views = env.items || [];
        if (!views.length) renderDashEmpty();
        else if (views.length === 1) mountDashView(views[0].name);
        else renderDashHub(views);
      })
      .catch(function () {
        dashView.classList.remove("framed");
        dashView.textContent = "";
        dashView.appendChild(el("div", "sub warn", "could not load dashboard"));
      });
  }

  function showView(name) {
    Object.keys(VIEWS).forEach(function (k) { VIEWS[k].hidden = k !== name; });
    composer.style.display = name === "chat" ? "" : "none";
    tabs.forEach(function (t) {
      // Transcript has no thumb-bar tab of its own — it's a child of Inspect, so
      // keep the Inspect tab lit while its transcript detail is open.
      var dv = t.getAttribute("data-view");
      var active = dv === name || (name === "transcript" && dv === "inspect");
      t.classList.toggle("active", active);
      if (active) t.setAttribute("aria-current", "page");
      else t.removeAttribute("aria-current");
    });
    if (statusTimer) { clearInterval(statusTimer); statusTimer = null; }
    stopActivity();
    if (name === "chat") {
      // Entering Chat always reveals the latest turn + composer (stitch 27) and
      // starts the honest activity poll (stitch 29).
      scrollToBottom();
      startActivity();
    } else if (name === "more") {
      loadPanel();
      statusTimer = setInterval(loadPanel, 4000); // poll: the inspector shape
    } else if (name === "inspect") {
      renderInspectHub();
    } else if (name === "transcript") {
      loadTranscript(null);
    } else if (name === "dash") {
      loadDash();
    }
  }

  // --- Transcript browser: read-only document view + archive switch + search -
  function renderTranscriptTurn(t) {
    var el2 = el("div", "turn " + t.role);
    if (t.role === "system") {
      var n = el("div", "notice");
      if (/^\s*⚠️/.test(t.body)) n.classList.add("error");
      n.textContent = t.body;
      el2.appendChild(n);
    } else {
      var b = el("div", "bubble");
      b.innerHTML = window.GremlinRender ? window.GremlinRender.renderBodyHTML(t.body) : t.body;
      el2.appendChild(b);
      if (t.ts) el2.appendChild(el("div", "meta", t.ts));
    }
    return el2;
  }

  function renderTranscript(env) {
    transcriptView.textContent = "";
    // Transcript lives under Inspect now — a back link returns to the hub.
    var back = el("button", "back", "‹ Inspect");
    back.addEventListener("click", function () { showView("inspect"); });
    transcriptView.appendChild(back);
    var controls = el("div", "tcontrols");
    var sel = document.createElement("select");
    sel.className = "tselect";
    var live = el("option", null, "live");
    live.value = "";
    sel.appendChild(live);
    env.archives.forEach(function (d) {
      var o = el("option", null, d);
      o.value = d;
      sel.appendChild(o);
    });
    sel.value = env.archive || "";
    sel.addEventListener("change", function () { loadTranscript(sel.value || null); });
    controls.appendChild(sel);

    var search = document.createElement("input");
    search.type = "search";
    search.className = "tsearch";
    search.placeholder = "Search…";
    controls.appendChild(search);

    var jump = el("button", "tjump", "↓");
    jump.title = "Jump to bottom";
    jump.addEventListener("click", function () { transcriptView.scrollTop = transcriptView.scrollHeight; });
    controls.appendChild(jump);
    transcriptView.appendChild(controls);
    transcriptView.appendChild(pathChip(env.file));

    var doc = el("div", "tdoc");
    transcriptView.appendChild(doc);

    function paint(filter) {
      doc.textContent = "";
      var f = (filter || "").toLowerCase();
      var lastDate = "";
      env.turns.forEach(function (t) {
        if (f && (t.body || "").toLowerCase().indexOf(f) < 0) return;
        var date = (t.ts || "").slice(0, 10);
        if (date && date !== lastDate) {
          lastDate = date;
          doc.appendChild(el("div", "tdate", date));
        }
        doc.appendChild(renderTranscriptTurn(t));
      });
      if (!doc.children.length) doc.appendChild(el("div", "sub", "no matching turns"));
    }
    paint("");
    search.addEventListener("input", function () { paint(search.value); });
  }

  function loadTranscript(archive) {
    fetch("/api/transcript" + (archive ? "?archive=" + encodeURIComponent(archive) : ""))
      .then(function (r) { return r.json(); })
      .then(renderTranscript)
      .catch(function () {
        transcriptView.textContent = "";
        transcriptView.appendChild(el("div", "sub warn", "could not load transcript"));
      });
  }

  tabs.forEach(function (t) {
    t.addEventListener("click", function () { showView(t.getAttribute("data-view")); });
  });

  // wikilink delegation (registered once): tap [[id]] → open that finding.
  inspect.addEventListener("click", function (e) {
    var a = e.target.closest && e.target.closest("a.wiki");
    if (a) { e.preventDefault(); openFinding(a.getAttribute("data-id")); }
  });

  // Header title = the gremlin's identifier (its host directory name).
  var hostEl = document.getElementById("host");
  if (hostEl) {
    fetch("/api/identity").then(function (r) { return r.json(); })
      .then(function (d) {
        if (d && d.host) {
          hostEl.textContent = d.host;
          hostEl.title = d.path || "";
          document.title = d.host;
        }
      }).catch(function () {});
  }

  if (typeof window.EventSource !== "undefined") {
    startSSE();
  } else {
    startPolling();
  }

  // Chat is the default view (HTML), but normalize through showView so the
  // activity poll (29) and initial scroll-to-latest (27) start on first paint.
  showView("chat");
})();

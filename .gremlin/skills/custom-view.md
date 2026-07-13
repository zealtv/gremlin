---
name: custom-view
triggers:
  - user asks to build, make, or add a dashboard, dash, chart, graph, or custom view
  - user asks to change, modify, extend, or add data to an existing dashboard/view
  - user asks to show their data "on a page", "on the web", or "in the Dash tab"
---

# custom-view

Use this skill when the user asks you to build or change a **Dash view** — a
purpose-built dashboard the web bridge serves in its 📊 Dash tab. You are the sole
author; the bridge only serves what you write. Read the web bridge's
**Custom Dash views** section (`bridges/web/README.md`) for the trust boundary.

## The contract

- A view is a directory `HOST_DIR/.dash/<name>/` (the gremlin home dir, **outside**
  `.gremlin/` — `/update` never touches it). It needs a static `index.html` + any
  assets. Having an `index.html` is what makes it a view; the bridge discovers it —
  there is no manifest and **no scaffold tool**. Name it for what it is
  (`.dash/nutrition/`, `.dash/dashboard/`).
- **Views are dumb; aggregation is a tool.** The `index.html` renders; it does not
  compute. All real state lives in a co-located `dashboard-index.json` produced by a
  per-gremlin `.gremlin/tools/build-<name>-index.sh` (see below). The view
  `fetch('./dashboard-index.json')`s it through the same jailed route it is served
  from. No view-specific bridge route, no new datastore.
- **Charts:** default to **hand-rolled inline SVG** (line, bars, KPI tiles — zero
  deps, themeable). Escape hatch for a dense/interactive case: **one** pinned,
  vendored lib under `bridges/web/public/vendor/` (the alpine/xterm precedent — no
  npm, no build step). Before you write any chart code, **read the `dataviz` skill**
  for palette, marks, and light/dark.

## Embedding video / third-party media

A view's CSP is locked to same-origin by default, so a raw `<iframe src="youtube…">`
or remote `<img>` **will be blocked**. Two ways to show external media:

- **Prefer mirroring same-origin.** Download the asset into the view dir (e.g.
  `.dash/<name>/assets/…`) and reference it with a relative path. No CSP change,
  nothing to maintain — the right default for images.
- **Opt into a vetted embed profile** when you genuinely need a live third-party
  frame (a YouTube player). Drop a `.dash/<name>/.embeds` marker listing profile
  names, one per line (`#` comments allowed):

  ```
  # .dash/<name>/.embeds
  youtube
  ```

  The bridge merges that profile's vetted hosts into *this view's* `frame-src`/
  `img-src` only. Available profiles: **`youtube`** (adds youtube.com /
  youtube-nocookie.com frames + i.ytimg.com thumbnails). You name a profile, never
  a raw host; unknown names are ignored. The exfil boundary — `default-src` /
  `script-src` / `connect-src` — stays `'self'` no matter what, so a view can never
  be given a channel to phone data out. Need a profile that doesn't exist yet? Add
  it to `EMBED_PROFILES` in the bridge (a framework change), not per-view config.

## The build tool

**Location — inside the gremlin.** The tool lives at
`.gremlin/tools/build-<name>-index.sh`, alongside the gremlin's other tools —
**not** at a bare host-level `tools/`. The host dir's gremlin-owned state is all
high-level **dot-dirs** (`.gremlin`, plus gremlin-produced artifact dirs like
`.dash`) so it never collides with the user's own files; the primitives
(`.loom`, `.lore`, `.glean`, `.nest`, `.groundhog`) live *inside* `.gremlin/`,
never at host level (see the Placement section in `docs/protocol.md`). A plain
`tools/` folder at host level breaks that pattern and gets lost. Only the view and its regenerable cache are host-level (`.dash/<name>/`);
the tool is gremlin-owned code, so it lives in `.gremlin/tools/`. Bespoke tools
there survive `/update` (it overlays, never deletes — the gremlin's existing app
tools prove it).

The tool follows the `tools/` contract (args → the file it writes; fail loud,
non-zero on malformed data). It resolves the host dir (the parent of `.gremlin`),
reads the gremlin's raw data (logs, series, progress notes), and writes the
disposable-cache exception `.dash/<name>/dashboard-index.json` there
**atomically** (temp file, then `mv`), always stamping a top-level `generated_at`
(ISO-8601 Z) and emitting named series the view iterates over. Gitignore the
generated `dashboard-index.json`; track the tool and the `index.html`.

## Freshness

Keep the index fresh two ways, both required:

1. **On demand** — rebuild it as the final step of any turn that builds/modifies the
   view *or* mutates the underlying data.
2. **Daily safety net** — a `.groundhog/schedule/` job that reruns the build tool, so
   the dashboard stays current with no chat activity.

The view **renders `generated_at`** so staleness is visible, never silent.

## Idempotent modify — data-driven charts

Charts iterate over whatever series the index lists, keyed by a stable id. This is
what makes modification a one-line edit instead of a rewrite:

- "Add protein to the daily chart" → add a `protein` series to the **build tool**;
  the chart picks it up with **zero HTML change**.
- A genuinely new chart → append one `<section data-chart="<stable-id>">` and render
  by that id; never rewrite the whole file. Edit an existing chart by its id.

Rule: *all real state lives in the index; `index.html` is regenerable and its
changes are additive, keyed to stable `data-chart` ids.*

## The skeleton

Every view starts from this exact `index.html` (fetch wiring + one stubbed SVG
chart, themed for light/dark). Copy it, then add `data-chart` sections and matching
render code — do not start from a blank file.

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="light dark">
<title>My Dashboard</title>
<style>
  :root { color-scheme: light dark; --ink: #1a1a1a; --muted: #6b7280; --line: #e5e7eb; --accent: #2f6df6; }
  @media (prefers-color-scheme: dark) { :root { --ink: #e8e8e8; --muted: #9aa0aa; --line: #2a2d33; --accent: #6ea0ff; } }
  * { box-sizing: border-box; }
  body { margin: 0; padding: 16px; font: 15px/1.5 system-ui, sans-serif; color: var(--ink); }
  h1 { font-size: 18px; margin: 0 0 4px; }
  .stamp { color: var(--muted); font-size: 12px; margin-bottom: 16px; }
  .card { border: 1px solid var(--line); border-radius: 14px; padding: 14px 16px; margin-bottom: 16px; }
  .card h2 { font-size: 14px; margin: 0 0 10px; }
  svg { display: block; width: 100%; height: auto; }
  .err { color: #c0392b; }
</style>
</head>
<body>
  <h1 id="title">My Dashboard</h1>
  <div class="stamp" id="stamp">loading…</div>

  <section class="card" data-chart="weight">
    <h2>Weight</h2>
    <svg id="chart-weight" viewBox="0 0 320 120" preserveAspectRatio="none" aria-label="weight over time"></svg>
  </section>

  <script>
    // The view is dumb: it only renders the index the build tool produced.
    fetch("./dashboard-index.json", { cache: "no-store" })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(render)
      .catch(function (e) {
        document.getElementById("stamp").innerHTML =
          '<span class="err">could not load dashboard-index.json (' + e.message + ')</span>';
      });

    function render(data) {
      document.getElementById("stamp").textContent = "updated " + (data.generated_at || "—");
      // Iterate the series the index lists — new series need no HTML change.
      drawLine("chart-weight", (data.series && data.series.weight) || []);
    }

    // Minimal hand-rolled SVG line — read the dataviz skill before elaborating.
    function drawLine(id, points) {
      var svg = document.getElementById(id);
      if (!svg || !points.length) return;
      var w = 320, h = 120, pad = 8;
      var xs = points.map(function (p) { return p.x; });
      var ys = points.map(function (p) { return p.y; });
      var minY = Math.min.apply(null, ys), maxY = Math.max.apply(null, ys);
      var spanY = (maxY - minY) || 1;
      var d = points.map(function (p, i) {
        var x = pad + (w - 2 * pad) * (i / Math.max(1, points.length - 1));
        var y = h - pad - (h - 2 * pad) * ((p.y - minY) / spanY);
        return (i ? "L" : "M") + x.toFixed(1) + " " + y.toFixed(1);
      }).join(" ");
      var path = document.createElementNS("http://www.w3.org/2000/svg", "path");
      path.setAttribute("d", d);
      path.setAttribute("fill", "none");
      path.setAttribute("stroke", "var(--accent)");
      path.setAttribute("stroke-width", "2");
      svg.appendChild(path);
    }
  </script>
</body>
</html>
```

## Confirm

When the view is built or changed, run the build tool once, then reply in a plain
chat turn naming the tab and its contents:

> Built your nutrition dashboard — open the **Dash** tab. Weight trend, today's
> macros, recent meals.

**Fail loud:** if the build tool errored, say so and do **not** claim the dashboard
is ready. A stale or missing index is a visible error, never a silent success.

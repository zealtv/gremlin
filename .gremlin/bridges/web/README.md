# web bridge

A localhost web lens over Gremlin's files — the third bridge, sibling of
`telegram.sh` and `tui.sh`. Python is the glass; bash and the filesystem are the
only truth. The bridge never writes a `## user —` / `## assistant —` turn, never
calls a model, and serves nothing but its own `public/` assets (M0).

> **M0** — a read-only transcript window that boots, tails `transcript.md`, and
> renders turns in a browser over SSE.
> **M1** — the chat round-trip: a composer + same-origin `POST /send` that writes
> a bare `.md` item via `nestling.sh ingest`, with an honest pending echo cleared
> when the real `## user —` / `## assistant —` turns arrive. The bridge writes the
> inbound item only — never a transcript turn, never a model call.
> **M2** — the mobile-first shell: 4-tab thumb-bar (Chat live; the rest inert
> until their milestones), media-embed rendering (`🖼️` inline image, `📎`
> download chip; `🔊 (tts:)` left as text for now) and a small safe markdown
> subset via `render.js` (escape-first; control-scheme URLs refused). The
> transcript markup stays the source of truth — unrenderable embeds degrade to
> text, never a rewrite. System turns render as full-width dimmed notices,
> bodies verbatim.
> **M3** — the first read-only inspector and the reusable
> route→read→render→poll shape: a **More** panel showing Identity (`gremlin.md`),
> Context (`context/system/*.md` + `context/*.md`, symlinks resolved, targets
> revalidated under the host folder), the active model, and runner Status derived
> from `.paused` + `.tending.pid` (a dead pid reads *idle, stale* via `kill -0`,
> never ghost-busy). `GET /api/context` + `GET /api/status` return the uniform
> `path` + `source` + `raw` envelope.
> **M5** — the Glean memory inspector (the **Inspect** tab), index-first by law:
> `GET /api/glean` parses `findings/INDEX.md` only (no eager body reads); a body
> loads on demand via `GET /api/glean/finding/:id` (id validated + jailed under
> `findings/`). Findings promoted (symlinked) into `context/` wear a 📡 pill;
> `[[wikilinks]]` navigate between findings; workbench tray counts shown.
> This completes the judgment's MVP screen set (Chat + Inspect→Glean).
> **M4** — the Groundhog schedule inspector, behind the **Inspect hub**.
> `GET /api/groundhog` shells out to `groundhog.sh list` (the schedule tree,
> verbatim in `raw`, `[paused]` already tagged) + `due` (never reimplementing
> due-ness, never re-parsing the path grammar), and reads `out/` / `fired/<today>`
> inertly → due-now / fired-today / awaiting-pickup. Inspect is now a hub
> (Groundhog · Glean, with Loom/Lore to come).
> **M6** — the Loom inspector. `GET /api/loom` reuses `loom.sh` for every derived
> fact (the loose-end leaf test is subtle, so never re-derived): the verbatim
> `status` tree in `raw`, NEXT TO TEND = `loose-ends`, `waiting` excluded, counts
> from the script's own summary. Inspect hub emojis match each primitive's README
> (the beaver Groundhog, needle Loom, crystal-ball Glean, scroll Lore); Transcript is the memo tab.
> **M7** — the Lore inspector (reads the host's `.lore/`, skips gracefully if
> absent). `GET /api/lore` lists the dated `INDEX.md` cards (durable/dark — no
> recall, no promotion, cf. Glean); `GET /api/lore/item/:id` returns `item.md` +
> the `content/` file listing; `GET /api/lore/content/:id/*path` serves a content
> byte (jailed under the item; binary → download, text → inline).
> **Transcript browser** — the **📝 Transcript** tab: a read-only document view of
> `transcript.md` + `transcript-archive/*.md`. `GET /api/transcript[?archive=DATE]`
> returns parsed turns (live or a dated archive, date-validated + jailed) plus the
> archive list; the frontend adds a date switcher, in-document search, and
> jump-to-bottom. The file is never modified.
> **Dash (custom views)** — the always-present **📊 Dash** tab. The bridge stays a
> lens: it only *serves* per-gremlin views from `HOST_DIR/.dash/<name>/`.
> `GET /api/dash` discovers each `<name>/` with an `index.html` (the filesystem is
> the registry — no manifest); `GET /dash/<name>/*path` is jailed static served
> through `under(HOST_DIR/.dash)` (**not** the exact-match `STATIC` dict), `no-cache`,
> under a `Content-Security-Policy`. One view mounts in a same-origin iframe; many
> → a hub; none → a calm invite. The tender *authors* views (see below); the bridge
> never writes them. See **Custom Dash views** for the contract + trust boundary.
> The thumb-bar is now **Chat · Dash · Inspect · More**: a custom view is promoted
> to a primary tab, and **Transcript is demoted into the Inspect hub** (📝, a
> read-only lens over the conversation record — an inspector in nature), reachable
> one level down with a back link (owner steer 2026-07-03).

## Run

```sh
./.gremlin/gremlin web start     # daemonize (nohup/setsid, pidfile)
./.gremlin/gremlin web status    # running? where?
./.gremlin/gremlin web stop      # free the port
./.gremlin/gremlin web run       # run in the foreground (no daemon)
```

`start` and `status` print the URL to open. The port is auto-assigned on first
start — a free port derived from the gremlin's host-dir name, so several gremlins
on one machine each get their own stable number — and pinned in `config`, so it
survives restarts, reboots, and `/update`. Set `WEB_PORT` in `config` to fix it
explicitly (then an in-use port fails loud). The default first choice is `8787`.

Open the printed URL (e.g. <http://127.0.0.1:8787/>). Type a message and send it:
it appears as a muted pending echo, the bridge drops a `.nest/in/` item, and when
the tender replies the real turns arrive over the tail and the echo clears.
Appending a `## system —` line to `transcript.md` by hand also appears within a
tick.

## Verify

```sh
./.gremlin/gremlin web start
curl -fsS http://127.0.0.1:8787/ | head -1     # 200 HTML
curl -fsS 'http://127.0.0.1:8787/poll?cursor=0' # JSON turns
./.gremlin/gremlin web stop
```

Run the bridge's own test suite (no real gremlin touched — it builds a throwaway
fixture and picks a free port):

```sh
./.gremlin/bridges/web/test/run.sh
```

## Config

Optional in M0. `cp config.example config` and edit. The runtime `config`,
`*.pid`, `*.log`, `.cursor`, and `.cache/` are gitignored and safe to delete; the
bridge reconstructs its view from `.gremlin/` files alone.

## Security (M0)

- **Loopback only.** Binds `127.0.0.1` by default; a LAN connection is refused at
  the socket. A non-loopback `Host` header is also rejected (anti-DNS-rebinding).
- **One mutating route, same-origin only.** `POST /send` is the sole write; it
  requires a loopback `Origin`/`Referer` on the server's own port (anti-CSRF) and
  writes nothing but a guarded `.nest/in/` item. No GET has a side effect.
- **No generic file-serving path parameter yet** — uploads (`/media`) and the
  §17 path resolver arrive with their own milestones.

Uploads and the file-serving inspectors are later stitches with their own
mitigations (see the design spec §17).

## Custom Dash views

A gremlin exposes purpose-built dashboards through the **📊 Dash** tab. The split
is the design: the **bridge serves, the tender authors**.

- **Layout.** A view is a directory `HOST_DIR/.dash/<name>/` with a static
  `index.html` + assets. It lives in the home dir, **outside** `.gremlin/` — so
  `/update` (which rsyncs the framework overlay) never touches it, and no new
  exclude knob is needed. The regenerable `dashboard-index.json` a view reads is a
  disposable cache (gitignore it); the `index.html` + build tool are code (track
  them). The `<name>/` is discovered by having an `index.html`; the view's
  `<title>` is its on-screen title.
- **Data.** Views are dumb; aggregation is a tool. A per-gremlin
  `.gremlin/tools/build-<name>-index.sh` (gremlin-owned code lives *inside* the
  gremlin, with its other tools — not a bare host-level `tools/`) rolls raw data
  into `.dash/<name>/dashboard-index.json` (atomic, with a `generated_at`); the view
  `fetch('./dashboard-index.json')`s it through the same jailed route. No
  view-specific API, no new datastore.
- **Authoring** is a normal chat turn — "build me a nutrition dashboard" — handled
  by the `custom-view` skill (`skills/custom-view.md`): the `.dash/<name>/` layout,
  the inline `index.html` skeleton, the data-driven-chart idempotent-modify rule,
  and the freshness contract (rebuild on-demand + a daily `.groundhog/` job;
  render `generated_at`).

### Trust boundary

- **A view is trusted gremlin-authored code — no privilege escalation.** It runs
  same-origin in the client's browser, but a read-only view is strictly *weaker*
  than the `POST /send` every token-holder already wields (send triggers the
  gremlin's Bash). Loading a view is a smaller grant than the send you already extend.
- **The iframe is failure-isolation, not containment.** Same-origin (so the view
  can read cookie-authed jailed routes) + `sandbox="allow-scripts allow-same-origin"`
  to suppress top-nav/popups from a buggy view. It can still reach `window.parent`;
  that is fine given no escalation. A broken view breaks only its own frame.
- **CSP pins the wire.** `/dash/*` responses carry a locked base —
  `default-src 'self'; base-uri 'none'; object-src 'none'; frame-ancestors 'self'` —
  which blocks a view from `fetch()`-ing jailed data out to a third party and
  enforces the vendored-assets/no-CDN policy. A view may widen its *own* CSP for
  vetted media by naming an embed profile in a `.dash/<name>/.embeds` marker (see
  the `EMBED_PROFILES` allowlist in `server.py`, e.g. `youtube` → youtube frames +
  ytimg thumbnails). Profiles only ever add `frame-src`/`img-src`/`media-src` hosts;
  `default-src`/`script-src`/`connect-src` stay `'self'` for every view, so the
  exfil boundary can never be widened by view config. A view names a profile, never
  a raw host; new profiles are a framework change, not per-view config.
- **Remote binding** rides the same token gate as everything else (views are *not*
  localhost-only, so a tailnet-bound gremlin's dashboard still works). Traffic is
  cleartext unless tunneled, and the startup warning notes that the bridge now also
  serves view code that runs in the client's browser.

## Remote access (off by default)

The default bind is loopback. To reach the bridge from another device, the
**preferred path is a tunnel** (SSH local-forward, WireGuard, or Tailscale),
which keeps the server loopback-only:

```sh
# on the remote device:
ssh -L 8787:127.0.0.1:8787 <host>   # then browse http://localhost:8787
```

If you genuinely want to bind a non-loopback address (e.g. a tailnet IP), it is
**token-gated and loud**. In `config`:

```sh
WEB_BIND=100.x.y.z
WEB_REMOTE_TOKEN=$(python3 -c 'import secrets;print(secrets.token_urlsafe(18))')
```

A non-loopback `WEB_BIND` without a token **refuses to start**. With one, startup
prints an exposure warning and **every request must present the token** — open
the page once as `/?t=<token>` (it sets an HttpOnly session cookie that carries
onward) or send an `X-Web-Token` header. The Host-allowlist widens to exactly the
configured bind (add a MagicDNS name via `WEB_REMOTE_HOST`); Origin/CSRF still
applies. Traffic is **cleartext** unless tunneled — Tailscale/WireGuard encrypt
at the network layer, plain LAN does not.

## Stack

A thin bash `web.sh` wrapper (the telegram daemon skeleton) execs a single
Python-3-stdlib HTTP+SSE server (`server.py`). No pip, no npm, no build, no
bundler. The frontend (`public/`) is hand-authored, no-build, git-diffable.

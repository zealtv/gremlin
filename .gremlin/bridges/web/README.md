# web bridge

A localhost web lens over Gremlin's files — the third bridge, sibling of
`telegram.sh` and `tui.sh`. Python is the glass; bash and the filesystem are the
only truth. The bridge never writes a `## user —` / `## assistant —` turn, never
calls a model, and serves nothing but its own `public/` assets (M0).

> **Milestone M0** ships here: a read-only transcript window that boots, tails
> `transcript.md`, and renders turns in a browser over SSE. No send, no
> inspectors, no uploads, no model.

## Run

```sh
./.gremlin/gremlin web start     # daemonize (nohup/setsid, pidfile)
./.gremlin/gremlin web status    # running? where?
./.gremlin/gremlin web stop      # free the port
./.gremlin/gremlin web run       # run in the foreground (no daemon)
```

Then open <http://127.0.0.1:8787/>. Append a `## system —` line to
`transcript.md` by hand and it appears in the browser within a tick.

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
- **No GET side effects.** Every M0 route is a read. There is no send, no upload,
  and no generic file-serving path parameter yet — those arrive with their own
  milestones and the §17 path resolver.

Remote binding, uploads, and the file-serving inspectors are later stitches with
their own mitigations (see the design spec §17).

## Stack

A thin bash `web.sh` wrapper (the telegram daemon skeleton) execs a single
Python-3-stdlib HTTP+SSE server (`server.py`). No pip, no npm, no build, no
bundler. The frontend (`public/`) is hand-authored, no-build, git-diffable.

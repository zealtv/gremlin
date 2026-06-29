#!/usr/bin/env python3
# server.py - the gremlin web bridge: a read-only transcript window over SSE.
#
# Python is the glass; bash and the filesystem are the only truth. This server
# never writes a `## user —` / `## assistant —` turn, never calls a model, and
# (in M0) never serves a host file outside its own vendored `public/`. It tails
# transcript.md with a single byte-cursor and fans new turns to every open
# browser tab over Server-Sent Events. With the server stopped, `cat`/`ls`/`git
# diff` still reconstruct the system's full truth.
#
# stdlib only: no pip, no third-party imports. Configured entirely by env vars
# exported from web.sh (WEB_BIND, WEB_PORT, WEB_TRANSCRIPT, WEB_CURSOR,
# WEB_PUBLIC_DIR), so tests can point it at a throwaway fixture.

import json
import os
import queue
import re
import secrets
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs, unquote

BIND = os.environ.get("WEB_BIND", "127.0.0.1")
PORT = int(os.environ.get("WEB_PORT", "8787"))
TRANSCRIPT = os.environ["WEB_TRANSCRIPT"]
CURSOR_FILE = os.environ["WEB_CURSOR"]
PUBLIC_DIR = os.environ["WEB_PUBLIC_DIR"]
GREMLIN_DIR = os.environ.get("WEB_GREMLIN_DIR") or os.path.dirname(os.path.abspath(TRANSCRIPT))
HOST_DIR = os.environ.get("WEB_HOST_DIR") or os.path.dirname(GREMLIN_DIR)
NESTLING = os.environ.get("WEB_NESTLING", "")
CACHE_DIR = os.environ.get(
    "WEB_CACHE_DIR",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cache"),
)
POLL_INTERVAL = float(os.environ.get("WEB_TAIL_INTERVAL", "1.0"))
SSE_PING_INTERVAL = float(os.environ.get("WEB_SSE_PING_INTERVAL", "15.0"))
# Text-only cap for M1's POST /send; real uploads (and WEB_MAX_UPLOAD) are M8.
MAX_SEND_BYTES = int(os.environ.get("WEB_MAX_SEND", str(1 << 20)))

# The transcript turn grammar (docs/protocol.md, spec §16): a header line of
# `## <role> — <ISO8601Z>`, body is everything to the next header. The separator
# is a real em-dash (U+2014) flanked by spaces.
TURN_HEADER = re.compile(r"^## (user|assistant|system) — (.+?)\s*$", re.MULTILINE)

# Only loopback Host headers are honored; a non-loopback Host (DNS rebinding
# keeps the attacker's Host) is refused even though we already bind 127.0.0.1.
LOOPBACK_HOSTS = {"127.0.0.1", "localhost", "[::1]", "::1", ""}
# Same-origin gate for the one mutating route: an Origin/Referer must be a
# loopback host on our own port (a different port is a different origin).
ORIGIN_HOSTS = {"127.0.0.1", "localhost", "::1"}

# The only static assets M0 serves, by exact name — no path parameter, so no
# traversal surface exists yet (the §17 path resolver arrives with /media).
STATIC = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/index.html": ("index.html", "text/html; charset=utf-8"),
    "/app.js": ("app.js", "application/javascript; charset=utf-8"),
    "/render.js": ("render.js", "application/javascript; charset=utf-8"),
    "/styles.css": ("styles.css", "text/css; charset=utf-8"),
}


def log(msg):
    sys.stderr.write("web: %s\n" % msg)
    sys.stderr.flush()


def file_size(path):
    try:
        return os.path.getsize(path)
    except OSError:
        return 0


def read_range(path, start, end):
    """Read bytes [start, end) and decode as UTF-8 (lossy, never crashes)."""
    if end <= start:
        return ""
    try:
        with open(path, "rb") as fh:
            fh.seek(start)
            return fh.read(end - start).decode("utf-8", "replace")
    except OSError:
        return ""


def parse_turns(text):
    """Split a transcript chunk into turns. The body is verbatim — system
    bodies (`⚙️ run:`, `⚠️ error:`, `💌 message:`) are preserved unchanged."""
    turns = []
    matches = list(TURN_HEADER.finditer(text))
    for i, m in enumerate(matches):
        body_start = m.end()
        body_end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        body = text[body_start:body_end].strip("\n")
        turns.append({"role": m.group(1), "ts": m.group(2), "body": body})
    return turns


class TranscriptTail:
    """One server-side byte-cursor over transcript.md, fanned to every tab.

    The cursor separates *what the server has pushed* from *what a tab has seen*:
    a new tab gets a backfill of `[0, cursor)` and then joins the live stream of
    `[cursor, …)`. Reads up to `cursor` go in backfill; reads past it arrive as
    live events — under one lock, so a turn is never both or neither.
    """

    def __init__(self, path, cursor_file, interval):
        self.path = path
        self.cursor_file = cursor_file
        self.interval = interval
        self.lock = threading.Lock()
        # Start at EOF: existing turns reach a tab via backfill, so nothing is
        # re-pushed on restart (spec §10). The .cursor file is disposable; we
        # write it for parity/observability, not correctness.
        self.cursor = file_size(path)
        self.subscribers = []
        self._write_cursor()

    def _write_cursor(self):
        try:
            with open(self.cursor_file, "w") as fh:
                fh.write("%d\n" % self.cursor)
        except OSError:
            pass

    def subscribe(self):
        """Atomically snapshot the backfill and register for live turns."""
        with self.lock:
            backfill = parse_turns(read_range(self.path, 0, self.cursor))
            q = queue.Queue()
            self.subscribers.append(q)
            return backfill, q

    def unsubscribe(self, q):
        with self.lock:
            if q in self.subscribers:
                self.subscribers.remove(q)

    def watch(self):
        while True:
            try:
                size = file_size(self.path)
                with self.lock:
                    # Rotation guard: archive.sh moves transcript.md aside and
                    # touches a fresh empty file, so it shrinks. Reset to the new
                    # size; rotated content is only ever reached via backfill.
                    if self.cursor > size:
                        self.cursor = size
                        self._write_cursor()
                    if size > self.cursor:
                        chunk = read_range(self.path, self.cursor, size)
                        for turn in parse_turns(chunk):
                            for q in list(self.subscribers):
                                q.put(turn)
                        self.cursor = size
                        self._write_cursor()
            except Exception as exc:  # never let the watcher thread die quietly
                log("tail error: %r" % exc)
            time.sleep(self.interval)

    def poll(self, cursor):
        """Short-poll fallback: turns since a byte cursor, plus the new cursor."""
        size = file_size(self.path)
        if cursor < 0 or cursor > size:  # first poll or post-rotation
            cursor = 0
        return parse_turns(read_range(self.path, cursor, size)), size


TAIL = TranscriptTail(TRANSCRIPT, CURSOR_FILE, POLL_INTERVAL)


# --- inspector reads (M3: the route→read→render pattern every inspector copies)

def envelope(protocol, root, items, source="fs", raw=""):
    """The uniform inspector shape (spec §9): path + source + raw, so the UI can
    show how a fact was derived and fall back to verbatim output if a parse lags."""
    return {
        "protocol": protocol,
        "root": root,
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "source": source,
        "items": items,
        "raw": raw,
    }


def under(base, path):
    """Canonicalize `path` and assert it stays at/under `base` — the §17 rule
    (follow symlinks, then revalidate the resolved target). Returns the real
    path, or None if it escapes."""
    try:
        real = os.path.realpath(path)
        base = os.path.realpath(base)
    except OSError:
        return None
    return real if real == base or real.startswith(base + os.sep) else None


def within_host(path):
    return under(HOST_DIR, path)


def read_text(path, limit=256 * 1024):
    real = within_host(path)
    if not real or not os.path.isfile(real):
        return None
    try:
        with open(real, "rb") as fh:
            return fh.read(limit).decode("utf-8", "replace")
    except OSError:
        return None


def pid_alive(pid):
    # The stale-pid rule: a pidfile is not proof of life — `kill -0` is.
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False
    return True


def rel_to_gremlin(path):
    try:
        return os.path.relpath(path, GREMLIN_DIR)
    except ValueError:
        return path


def build_context():
    """gremlin.md + the context the tender loads (context/system/*.md then
    context/*.md, symlinks resolved for display) + the active model + the
    skills/tools surface. Read-only; bodies served only for paths under HOST_DIR."""
    items = []

    body = read_text(os.path.join(GREMLIN_DIR, "gremlin.md"))
    if body is not None:
        items.append({"path": "gremlin.md", "name": "gremlin.md",
                      "state": "identity", "fields": {"body": body}})

    model = read_text(os.path.join(GREMLIN_DIR, ".model"))
    items.append({"path": ".model", "name": "model", "state": "context",
                  "fields": {"value": (model.strip() if model else "default")}})

    seen = set()
    for sub in ("context/system", "context"):
        d = os.path.join(GREMLIN_DIR, sub)
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            if not name.endswith(".md"):
                continue
            full = os.path.join(d, name)
            rp = os.path.realpath(full)
            if rp in seen:
                continue
            seen.add(rp)
            is_link = os.path.islink(full)
            inside = within_host(full)
            fields = {
                "symlink": is_link,
                "target": rel_to_gremlin(rp) if is_link else None,
                "body": read_text(full) if inside else None,
                "escaped": inside is None,
            }
            items.append({"path": rel_to_gremlin(full), "name": name,
                          "state": "context", "fields": fields})

    for kind in ("skills", "tools"):
        d = os.path.join(GREMLIN_DIR, kind)
        if os.path.isdir(d):
            names = sorted(n for n in os.listdir(d) if n.endswith((".md", ".sh")))
            items.append({"path": kind + "/", "name": kind, "state": "context",
                          "fields": {"names": names}})

    return envelope("context", os.path.realpath(GREMLIN_DIR), items)


def build_status():
    """Runner status derived from the filesystem: .paused presence, .tending.pid
    liveness (stale ⇒ idle), in-flight nest claims, and a run.log tail."""
    items = []

    paused = os.path.exists(os.path.join(GREMLIN_DIR, ".paused"))
    items.append({"path": ".paused", "name": "runner",
                  "state": "paused" if paused else "active",
                  "fields": {"paused": paused}})

    pidfile = os.path.join(GREMLIN_DIR, ".tending.pid")
    present = os.path.isfile(pidfile) and os.path.getsize(pidfile) > 0
    alive = False
    if present:
        try:
            with open(pidfile) as fh:
                alive = pid_alive(int(fh.readline().strip()))
        except (OSError, ValueError):
            present = False
    tending_state = "thinking" if alive else ("stale" if present else "idle")
    items.append({"path": ".tending.pid", "name": "tending", "state": tending_state,
                  "fields": {"present": present, "alive": alive,
                             "stale": present and not alive}})

    in_dir = os.path.join(GREMLIN_DIR, ".nest", "in")
    claimed = 0
    if os.path.isdir(in_dir):
        claimed = sum(1 for n in os.listdir(in_dir) if n.endswith(".tending"))
    items.append({"path": ".nest/in", "name": "in-progress", "state": "",
                  "fields": {"tending": claimed}})

    log_text = read_text(os.path.join(GREMLIN_DIR, "run.log"))
    tail = log_text.splitlines()[-20:] if log_text else []
    items.append({"path": "run.log", "name": "run.log", "state": "",
                  "fields": {"tail": tail}})

    return envelope("status", os.path.realpath(GREMLIN_DIR), items)


# --- Glean inspector (index-first: INDEX.md only; bodies on demand) ----------

GLEAN_DIR = os.path.join(GREMLIN_DIR, ".glean")
FINDINGS_DIR = os.path.join(GLEAN_DIR, "findings")
INDEX_LINE = re.compile(r"^- \[\[([^\]]+)\]\] — (.*)$")
SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def promoted_ids():
    """Findings symlinked into top-level context/ are 'promoted' (broadcast).
    Detected by reading context/ listings + link targets — never finding bodies."""
    ids = set()
    ctx = os.path.join(GREMLIN_DIR, "context")
    findings_real = os.path.realpath(FINDINGS_DIR)
    try:
        names = os.listdir(ctx)
    except OSError:
        return ids
    for name in names:
        full = os.path.join(ctx, name)
        if not os.path.islink(full):
            continue
        target = os.path.realpath(full)
        if os.path.dirname(target) == findings_real and target.endswith(".md"):
            ids.add(os.path.basename(target)[:-3])
    return ids


def tray_count(name):
    d = os.path.join(GLEAN_DIR, name)
    try:
        return sum(1 for n in os.listdir(d) if n != ".gitkeep")
    except OSError:
        return 0


def build_glean():
    """Index-first (invariant 11): parse findings/INDEX.md ONLY for the list;
    bodies are fetched per-id on demand. Promotion pill + workbench tray counts."""
    items = []
    promoted = promoted_ids()
    index = read_text(os.path.join(FINDINGS_DIR, "INDEX.md")) or ""
    for line in index.splitlines():
        m = INDEX_LINE.match(line)
        if not m:
            continue
        fid = m.group(1)
        rest = m.group(2)
        title, _, desc = rest.partition(" — ")
        is_promoted = fid in promoted
        items.append({
            "path": "findings/%s.md" % fid,
            "name": fid,
            "state": "promoted" if is_promoted else "finding",
            "fields": {"title": title.strip(), "desc": desc.strip(),
                       "promoted": is_promoted},
        })

    items.append({
        "path": "", "name": "workbench", "state": "",
        "fields": {"in": tray_count("in"), "out": tray_count("out"),
                   "dropped": tray_count("dropped")},
    })
    return envelope("glean", os.path.realpath(GLEAN_DIR), items)


def glean_finding(fid):
    """A single finding body, fetched on demand. The id is validated and the
    resolved file must live under findings/ (the §17 path-param resolver)."""
    if not SAFE_ID.match(fid or "") or fid in (".", ".."):
        return None
    real = under(FINDINGS_DIR, os.path.join(FINDINGS_DIR, fid + ".md"))
    if not real or not os.path.isfile(real):
        return None
    body = read_text(real)
    if body is None:
        return None
    title = ""
    desc = ""
    for line in body.splitlines():
        if not title and line.startswith("# "):
            title = line[2:].strip()
        elif title and not desc and line.strip() and not line.startswith("#"):
            desc = line.strip()
            break
    is_promoted = fid in promoted_ids()
    return envelope("glean", os.path.realpath(GLEAN_DIR), [{
        "path": "findings/%s.md" % fid, "name": fid,
        "state": "promoted" if is_promoted else "finding",
        "fields": {"title": title, "desc": desc, "body": body,
                   "promoted": is_promoted},
    }])


class Handler(BaseHTTPRequestHandler):
    server_version = "gremlin-web/0"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # quiet; the daemon log is for events
        pass

    def _host_ok(self):
        host = self.headers.get("Host", "")
        hostname = host.rsplit(":", 1)[0] if ":" in host and not host.endswith("]") else host
        return hostname in LOOPBACK_HOSTS

    def _send(self, code, body, ctype="text/plain; charset=utf-8", extra=None):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_GET(self):
        if not self._host_ok():
            self._send(403, "forbidden: non-loopback Host\n")
            return
        parsed = urlparse(self.path)
        path = parsed.path

        if path in STATIC:
            self._serve_static(path)
        elif path == "/events":
            self._serve_events()
        elif path == "/poll":
            self._serve_poll(parse_qs(parsed.query))
        elif path == "/api/context":
            self._send_json(build_context())
        elif path == "/api/status":
            self._send_json(build_status())
        elif path == "/api/glean":
            self._send_json(build_glean())
        elif path.startswith("/api/glean/finding/"):
            fid = unquote(path[len("/api/glean/finding/"):])
            env = glean_finding(fid)
            if env is None:
                self._send(404, "no such finding\n")
            else:
                self._send_json(env)
        else:
            self._send(404, "not found\n")

    def _send_json(self, obj):
        self._send(
            200,
            json.dumps(obj, ensure_ascii=False),
            "application/json; charset=utf-8",
        )

    do_HEAD = do_GET

    def do_POST(self):
        # The single mutating route. It writes only an inbound .nest/in/ item via
        # the nestling — never a transcript turn — and only for a same-origin
        # caller on a loopback Host.
        if not self._host_ok():
            self._send(403, "forbidden: non-loopback Host\n")
            return
        if urlparse(self.path).path != "/send":
            self._send(404, "not found\n")
            return
        if not self._origin_ok():
            self._send(403, "forbidden: cross-origin\n")
            return

        text = self._read_send_text()
        if text is None:
            self._send(400, "bad request\n")
            return
        if not text.strip():  # empty / whitespace-only writes nothing (400)
            self._send(400, "empty message\n")
            return

        item = self._ingest_text(text)
        if item is None:
            self._send(500, "ingest failed\n")
            return
        self._send(
            200,
            json.dumps({"ok": True, "item": item}, ensure_ascii=False),
            "application/json; charset=utf-8",
        )

    def _origin_ok(self):
        origin = self.headers.get("Origin") or self.headers.get("Referer")
        if not origin:  # browsers send Origin on same-origin POST; require it
            return False
        p = urlparse(origin)
        if p.scheme not in ("http", "https"):
            return False
        if (p.hostname or "") not in ORIGIN_HOSTS:
            return False
        port = p.port if p.port is not None else (443 if p.scheme == "https" else 80)
        return port == PORT

    def _read_send_text(self):
        try:
            length = int(self.headers.get("Content-Length", "0") or "0")
        except ValueError:
            return None
        if length <= 0 or length > MAX_SEND_BYTES:
            return None
        raw = self.rfile.read(length)
        ctype = self.headers.get("Content-Type", "")
        try:
            if "application/json" in ctype:
                value = json.loads(raw.decode("utf-8")).get("text", "")
                return value if isinstance(value, str) else None
            return (parse_qs(raw.decode("utf-8")).get("text") or [""])[0]
        except (ValueError, UnicodeDecodeError):
            return None

    def _ingest_text(self, text):
        """Stage the text to a temp file and hand it to `nestling.sh ingest` as
        a bare .md item — the same atomic landing/rename tui.sh / telegram.sh use.
        The `-web-` infix lets filters tell web-origin items apart (spec §11)."""
        if not NESTLING:
            log("no nestling configured; refusing /send")
            return None
        name = "%s-web-%s.md" % (
            time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()),
            secrets.token_hex(3),
        )
        try:
            os.makedirs(CACHE_DIR, exist_ok=True)
            fd, tmp = tempfile.mkstemp(prefix="web-send-", dir=CACHE_DIR)
        except OSError as exc:
            log("send stage failed: %r" % exc)
            return None
        try:
            with os.fdopen(fd, "w") as fh:
                fh.write(text.rstrip("\n") + "\n")  # one trailing newline, like tui
            result = subprocess.run(
                [NESTLING, "ingest", tmp, name],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if result.returncode != 0:
                log("nestling ingest failed (rc=%d)" % result.returncode)
                return None
            return name
        finally:
            try:
                os.remove(tmp)
            except OSError:
                pass

    def _serve_static(self, path):
        name, ctype = STATIC[path]
        try:
            with open(os.path.join(PUBLIC_DIR, name), "rb") as fh:
                self._send(200, fh.read(), ctype)
        except OSError:
            self._send(404, "not found\n")

    def _serve_poll(self, params):
        try:
            cursor = int(params.get("cursor", ["0"])[0])
        except ValueError:
            cursor = 0
        turns, new_cursor = TAIL.poll(cursor)
        self._send(
            200,
            json.dumps({"turns": turns, "cursor": new_cursor}, ensure_ascii=False),
            "application/json; charset=utf-8",
        )

    def _serve_events(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()

        backfill, q = TAIL.subscribe()
        try:
            # `reset` tells the client to clear its log, so an SSE auto-reconnect
            # (which re-runs this handler and re-sends the backfill) re-renders
            # cleanly instead of duplicating turns.
            self._sse("reset", {})
            for turn in backfill:
                self._sse("turn", turn)
            while True:
                try:
                    turn = q.get(timeout=SSE_PING_INTERVAL)
                    self._sse("turn", turn)
                except queue.Empty:
                    self.wfile.write(b": ping\n\n")
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            TAIL.unsubscribe(q)

    def _sse(self, event, data):
        payload = "event: %s\ndata: %s\n\n" % (event, json.dumps(data, ensure_ascii=False))
        self.wfile.write(payload.encode("utf-8"))
        self.wfile.flush()


def main():
    threading.Thread(target=TAIL.watch, daemon=True).start()
    try:
        httpd = ThreadingHTTPServer((BIND, PORT), Handler)
    except OSError as exc:
        # Fail loud with the bound address; no auto-bump (spec open question §1).
        log("could not bind %s:%d (%s)" % (BIND, PORT, exc))
        sys.exit(1)
    httpd.daemon_threads = True
    log("serving http://%s:%d (transcript: %s)" % (BIND, PORT, TRANSCRIPT))
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()

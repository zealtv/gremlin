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

import hmac
import http.cookies
import json
import mimetypes
import os
import queue
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from email import policy
from email.parser import BytesParser
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
MAX_UPLOAD_BYTES = int(os.environ.get("WEB_MAX_UPLOAD", str(25 * 1024 * 1024)))
# A slash command that hasn't returned by now is failed loud rather than hung.
SLASH_TIMEOUT = 30.0

# The transcript turn grammar (docs/protocol.md, spec §16): a header line of
# `## <role> — <ISO8601Z>`, body is everything to the next header. The separator
# is a real em-dash (U+2014) flanked by spaces.
TURN_HEADER = re.compile(r"^## (user|assistant|system) — (.+?)\s*$", re.MULTILINE)

# Loopback Host headers are always honored; a non-loopback Host (DNS rebinding
# keeps the attacker's Host) is refused. When bound remotely the allowlist
# widens to exactly the configured host(s) — never wide open (spec §17).
LOOPBACK_HOSTS = {"127.0.0.1", "localhost", "[::1]", "::1", ""}

# Remote binding (off by default): a non-loopback WEB_BIND requires a token, or
# the bridge refuses to start. Every request must then present the token; the
# Host/Origin allowlist widens to the configured host; Origin/CSRF still applies.
REMOTE_TOKEN = os.environ.get("WEB_REMOTE_TOKEN", "")
IS_REMOTE = BIND not in {"127.0.0.1", "localhost", "::1", ""}
EXTRA_HOSTS = set(h.strip() for h in os.environ.get("WEB_REMOTE_HOST", "").split(",") if h.strip())
ALLOWED_HOSTS = set(LOOPBACK_HOSTS)
if IS_REMOTE:
    ALLOWED_HOSTS.add(BIND)
    ALLOWED_HOSTS |= EXTRA_HOSTS

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


def read_byte_range(path, start, end):
    """Read bytes [start, end); callers choose the wire/content semantics."""
    if end <= start:
        return b""
    try:
        with open(path, "rb") as fh:
            fh.seek(start)
            return fh.read(end - start)
    except OSError:
        return None


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


def sanitize_upload_name(name, used):
    """Telegram's §11 upload-name rule: basename, narrow chars, reserve control
    names, then make the result unique inside the staged item directory."""
    base = re.split(r"[/\\]", name or "")[-1]
    ext = re.sub(r"[^A-Za-z0-9._-]", "_", os.path.splitext(base)[1])
    safe = re.sub(r"[^A-Za-z0-9._-]", "_", base)
    if safe in ("", ".", "..", "instructions.md", ".model"):
        safe = "file" + ext
    stem, suffix = os.path.splitext(safe)
    candidate = safe
    n = 2
    while candidate in used:
        candidate = "%s-%d%s" % (stem, n, suffix)
        n += 1
    used.add(candidate)
    return candidate


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


def build_commands():
    """The slash-command vocabulary, derived from the same `commands/*.sh` that
    bin/slash.sh dispatches to (the autocomplete menu, stitch 22). Summary rule
    mirrors help.sh: the first `# ` comment line, minus a leading `<name> — `.
    Read-only listing — never runs a command."""
    items = []
    d = os.path.join(GREMLIN_DIR, "commands")
    if os.path.isdir(d):
        for name in sorted(os.listdir(d)):
            if not name.endswith(".sh"):
                continue
            cmd = name[:-3]
            summary = ""
            try:
                with open(os.path.join(d, name), encoding="utf-8", errors="replace") as fh:
                    for line in fh:
                        if line.startswith("# "):
                            summary = line[2:].strip()
                            break
            except OSError:
                pass
            for prefix in (cmd + " — ", cmd + " -- "):
                if summary.startswith(prefix):
                    summary = summary[len(prefix):]
                    break
            items.append({"name": cmd, "summary": summary})
    return envelope("commands", os.path.realpath(GREMLIN_DIR), items)


# The inspector primitives, in hub order, each with a terse (1–3 word) role hint
# so a newcomer can tell them apart without knowing Gremlin's vocabulary. The
# labels are the role words Gremlin's own docs use for these primitives
# (scheduling / action tracking / memory / reference) — a compression of each
# primitive's README purpose, not a divergent second vocabulary.
PRIMITIVES = [
    {"id": "groundhog", "hint": "scheduling"},
    {"id": "loom", "hint": "action tracking"},
    {"id": "glean", "hint": "memory"},
    {"id": "lore", "hint": "reference"},
]


def build_primitives():
    """Each inspector primitive with its concise purpose hint (stitch 26). An
    unknown/extension primitive simply isn't listed here, so the hub degrades to
    no hint rather than an invented one."""
    items = [{"name": p["id"], "hint": p["hint"]} for p in PRIMITIVES]
    return envelope("primitives", os.path.realpath(GREMLIN_DIR), items)


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


# --- Transcript browser (read-only document view of transcript.md + archive) -

ARCHIVE_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def build_transcript(archive=None):
    """Parsed turns from the live transcript or a dated archive, plus the list of
    available archive dates. Read-only; the file is never modified."""
    arch_dir = os.path.join(GREMLIN_DIR, "transcript-archive")
    archives = []
    if os.path.isdir(arch_dir):
        for name in os.listdir(arch_dir):
            if name.endswith(".md") and ARCHIVE_DATE.match(name[:-3]):
                archives.append(name[:-3])
    archives.sort(reverse=True)

    if archive:
        if not ARCHIVE_DATE.match(archive):
            return None
        real = under(arch_dir, os.path.join(arch_dir, archive + ".md"))
        if not real or not os.path.isfile(real):
            return None
        rel, text = "transcript-archive/%s.md" % archive, read_text(real) or ""
    else:
        rel, text = "transcript.md", read_text(TRANSCRIPT) or ""

    return {"protocol": "transcript", "file": rel, "archive": archive,
            "archives": archives, "turns": parse_turns(text)}


# --- Groundhog inspector (the path IS the schedule; shell out, never re-parse)

def run_readonly(args, timeout=5):
    """Shell out to a family script's READ-ONLY verb and capture stdout. Used for
    rule-derived facts (due-ness, the schedule tree) so we never reimplement them."""
    try:
        r = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           timeout=timeout)
        return r.stdout.decode("utf-8", "replace"), r.returncode
    except (OSError, subprocess.SubprocessError):
        return "", 1


def list_tray(path):
    try:
        return sorted(n for n in os.listdir(path) if n != ".gitkeep")
    except OSError:
        return []


def build_groundhog():
    gh = os.path.join(GREMLIN_DIR, ".groundhog", "groundhog.sh")
    root = os.path.join(GREMLIN_DIR, ".groundhog")
    items = []

    # The schedule tree, verbatim from `list` ([paused] already tagged) — the
    # authoritative rendering. The frontend shows it; we never re-parse the path.
    raw, _ = run_readonly([gh, "list"])

    # Due now: shell out to `due` (honors paused, HH/HH-MM, once back-dating, DST).
    due_out, _ = run_readonly([gh, "due"])
    for line in due_out.splitlines():
        line = line.strip()
        if line:
            items.append({"path": line, "name": os.path.basename(line.rstrip("/")),
                          "state": "due", "fields": {}})

    # Fired, awaiting pickup (inert read of out/).
    for name in list_tray(os.path.join(root, "out")):
        items.append({"path": "out/%s" % name, "name": name,
                      "state": "awaiting-pickup", "fields": {}})

    # Fired today (inert read of fired/<today>/ leaves).
    today = time.strftime("%Y-%m-%d")
    fired_today = os.path.join(root, "fired", today)
    if os.path.isdir(fired_today):
        for dirpath, dirnames, _files in os.walk(fired_today):
            if not dirnames:  # a leaf marker
                rel = os.path.relpath(dirpath, fired_today)
                items.append({"path": "fired/%s/%s" % (today, rel),
                              "name": os.path.basename(dirpath),
                              "state": "fired-today", "fields": {}})

    return envelope("groundhog", os.path.realpath(root), items,
                    source="groundhog.sh list + due", raw=raw)


# --- Lore inspector (durable, dated reference; dark by default) --------------

LORE_DIR = os.path.join(HOST_DIR, ".lore")
LORE_INDEX_LINE = re.compile(r"^- \[([^\]]+)\]\([^)]*\) — (.*)$")

# Custom "Dash" views live at HOST_DIR/.dash/<name>/ — outside the /update overlay,
# derived from WEB_HOST_DIR with no new env knob (design 2026-07-03, §2). The
# filesystem is the registry: a <name>/ with an index.html is a view.
DASH_DIR = os.path.join(HOST_DIR, ".dash")
DASH_TITLE = re.compile(r"<title[^>]*>(.*?)</title>", re.IGNORECASE | re.DOTALL)

# A served view is gremlin-authored code, so its CSP is pinned same-origin: the
# base below blocks third-party exfil of jailed data and pins framing to self.
# The exfil boundary — default-src / script-src / connect-src — is 'self', ALWAYS.
DASH_BASE_CSP = [
    ("default-src", ["'self'"]),
    ("base-uri", ["'none'"]),
    ("object-src", ["'none'"]),
    ("frame-ancestors", ["'self'"]),
]
# Opt-in embed profiles a view enables via a `.dash/<name>/.embeds` marker (one
# profile name per line/space). A profile only ever contributes media-display
# directives — never script-src/connect-src/default-src — so no profile can widen
# the exfil boundary. The host allowlist is fixed here; a view picks a name, never
# a raw host. Grows by adding vetted entries (vimeo, etc.), not by view config.
EMBED_ALLOWED_DIRECTIVES = {"frame-src", "img-src", "media-src"}
EMBED_PROFILES = {
    "youtube": {
        "frame-src": ["https://www.youtube.com", "https://www.youtube-nocookie.com"],
        "img-src": ["data:", "https://i.ytimg.com"],
    },
}
SAFE_PROFILE = re.compile(r"^[a-z0-9][a-z0-9-]*$")


def looks_binary(path):
    try:
        with open(path, "rb") as fh:
            return b"\x00" in fh.read(8192)
    except OSError:
        return True


def build_lore():
    """Append-and-keep cards from the host's .lore/INDEX.md. Skips gracefully if
    there is no lore. Dark by default — no recall, no promotion (cf. Glean)."""
    items = []
    index = read_text(os.path.join(LORE_DIR, "INDEX.md"))
    if index is None:
        return envelope("lore", os.path.realpath(LORE_DIR), [], raw="(no lore here)")
    for line in index.splitlines():
        m = LORE_INDEX_LINE.match(line)
        if not m:
            continue
        lid = m.group(1)
        title, _, desc = m.group(2).partition(" — ")
        date = lid[:10] if re.match(r"\d{4}-\d{2}-\d{2}", lid) else ""
        items.append({"path": "items/%s/" % lid, "name": lid, "state": "item",
                      "fields": {"title": title.strip(), "desc": desc.strip(), "date": date}})
    return envelope("lore", os.path.realpath(LORE_DIR), items)


def lore_item(lid):
    if not SAFE_ID.match(lid or "") or lid in (".", ".."):
        return None
    items_dir = os.path.join(LORE_DIR, "items")
    itemdir = under(items_dir, os.path.join(items_dir, lid))
    if not itemdir or not os.path.isdir(itemdir):
        return None
    body = read_text(os.path.join(itemdir, "item.md")) or ""
    title = desc = ""
    for line in body.splitlines():
        if not title and line.startswith("# "):
            title = line[2:].strip()
        elif title and not desc and line.strip() and not line.startswith("#"):
            desc = line.strip()
            break
    content = []
    cdir = os.path.join(itemdir, "content")
    if os.path.isdir(cdir):
        for dirpath, _dirs, files in os.walk(cdir):
            for name in sorted(files):
                full = os.path.join(dirpath, name)
                rel = os.path.relpath(full, cdir)
                try:
                    size = os.path.getsize(full)
                except OSError:
                    size = 0
                content.append({"name": rel, "size": size, "binary": looks_binary(full)})
    return envelope("lore", os.path.realpath(LORE_DIR), [{
        "path": "items/%s/" % lid, "name": lid, "state": "item",
        "fields": {"title": title, "desc": desc, "body": body, "content": content},
    }])


# --- Loom inspector (preserve the thread/stitch tree; reuse loom.sh) ---------

def build_loom():
    """Reuse loom.sh for every derived fact — the loose-end test (a plain leaf
    with no child dirs, .waiting excluded) is subtle, so never re-derive it. The
    verbatim `status` tree is shown; NEXT TO TEND = loose-ends; counts parsed
    only from the script's own summary line."""
    loom = os.path.join(GREMLIN_DIR, ".loom", "loom.sh")
    root = os.path.join(GREMLIN_DIR, ".loom")
    items = []

    raw, rc = run_readonly([loom, "status"])
    if rc != 0 and not raw:
        return envelope("loom", os.path.realpath(root), [], source="loom.sh status",
                        raw="(no loom here)")

    for verb, state in (("loose-ends", "loose-end"), ("waiting", "waiting")):
        out, _ = run_readonly([loom, verb])
        for line in out.splitlines():
            line = line.strip()
            if line and not line.startswith("("):  # skip "(none)"
                items.append({"path": line, "name": os.path.basename(line.rstrip("/")),
                              "state": state, "fields": {}})

    tied = dropped = 0
    mt = re.search(r"tied:\s*(\d+)", raw)
    md = re.search(r"dropped:\s*(\d+)", raw)
    if mt:
        tied = int(mt.group(1))
    if md:
        dropped = int(md.group(1))
    items.append({"path": "", "name": "counts", "state": "",
                  "fields": {"tied": tied, "dropped": dropped}})

    return envelope("loom", os.path.realpath(root), items, source="loom.sh status", raw=raw)


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


# --- Dash views (custom per-gremlin dashboards; the bridge serves, never writes)

def read_embed_profiles(view_dir):
    """Profile names a view opted into via its `.embeds` marker. Whitespace/newline
    separated; `#` comments and malformed tokens ignored. Names are validated but
    NOT trusted to name hosts — they only select a fixed EMBED_PROFILES entry."""
    path = os.path.join(view_dir, ".embeds")
    if not os.path.isfile(path):
        return []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            text = fh.read(4096)
    except OSError:
        return []
    names = []
    for tok in text.split():
        if tok.startswith("#") or not SAFE_PROFILE.match(tok):
            continue
        if tok not in names:
            names.append(tok)
    return names


def dash_csp(view_dir):
    """Compose a view's CSP: the locked base plus any vetted embed profiles the
    view opted into. Profiles only merge frame-src/img-src/media-src hosts (each
    seeded with 'self'); default-src/script-src/connect-src can never be widened,
    so the exfil boundary holds regardless of what a view requests."""
    directives = {d: list(v) for d, v in DASH_BASE_CSP}  # dict keeps insertion order
    for name in read_embed_profiles(view_dir):
        prof = EMBED_PROFILES.get(name)
        if prof is None:
            log("dash: unknown embed profile %r in %s/.embeds — ignored"
                % (name, os.path.basename(view_dir.rstrip(os.sep))))
            continue
        for directive, hosts in prof.items():
            if directive not in EMBED_ALLOWED_DIRECTIVES:
                continue  # defensive: profiles never touch script-src/connect-src
            bucket = directives.setdefault(directive, ["'self'"])
            for h in hosts:
                if h not in bucket:
                    bucket.append(h)
    return "; ".join("%s %s" % (d, " ".join(v)) for d, v in directives.items())


def build_dash():
    """Discovery: each HOST_DIR/.dash/<name>/ containing an index.html is a view.
    The filesystem is the registry — no manifest. Absent/empty .dash → []. The
    view's <title> (if any) is its screen title; the name is the fallback."""
    items = []
    try:
        names = sorted(os.listdir(DASH_DIR))
    except OSError:
        names = []
    for name in names:
        if not SAFE_ID.match(name) or name in (".", ".."):
            continue
        vdir = under(DASH_DIR, os.path.join(DASH_DIR, name))
        if not vdir or not os.path.isdir(vdir):
            continue
        if not os.path.isfile(os.path.join(vdir, "index.html")):
            continue
        title = name
        head = read_text(os.path.join(vdir, "index.html"), 64 * 1024)
        if head:
            m = DASH_TITLE.search(head)
            if m:
                t = re.sub(r"\s+", " ", m.group(1)).strip()
                if t:
                    title = t
        items.append({"path": "%s/" % name, "name": name, "state": "view",
                      "fields": {"title": title}})
    return envelope("dash", os.path.realpath(DASH_DIR), items)


class Handler(BaseHTTPRequestHandler):
    server_version = "gremlin-web/0"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # quiet; the daemon log is for events
        pass

    def _host_ok(self):
        host = self.headers.get("Host", "")
        hostname = host.rsplit(":", 1)[0] if ":" in host and not host.endswith("]") else host
        return hostname in ALLOWED_HOSTS

    def _supplied_token(self):
        q = parse_qs(urlparse(self.path).query).get("t")
        if q:
            return q[0]
        header = self.headers.get("X-Web-Token")
        if header:
            return header
        raw = self.headers.get("Cookie")
        if raw:
            jar = http.cookies.SimpleCookie()
            try:
                jar.load(raw)
            except http.cookies.CookieError:
                return None
            if "web_token" in jar:
                return jar["web_token"].value
        return None

    def _authed(self):
        # Loopback default: no token. Remote: a token must be presented on every
        # request (query, header, or the cookie bootstrapped from the first load).
        if not IS_REMOTE:
            return True
        supplied = self._supplied_token()
        return bool(supplied) and hmac.compare_digest(supplied, REMOTE_TOKEN)

    def _gate(self):
        """Shared front door for every request: Host allowlist then token. Returns
        True if the request was rejected (and a response already sent)."""
        if not self._host_ok():
            self._send(403, "forbidden: disallowed Host\n")
            return True
        if not self._authed():
            self._send(401, "token required: open this page as /?t=<token>\n")
            return True
        # Bootstrap a cookie when a valid token arrives in the query, so the app
        # shell's sub-requests (assets, /events, /poll, /api/*) carry it onward.
        if IS_REMOTE:
            q = parse_qs(urlparse(self.path).query).get("t")
            if q and hmac.compare_digest(q[0], REMOTE_TOKEN):
                self._cookie = "web_token=%s; Path=/; HttpOnly; SameSite=Strict" % REMOTE_TOKEN
        return False

    def _send(self, code, body, ctype="text/plain; charset=utf-8", extra=None):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        if getattr(self, "_cookie", None):
            self.send_header("Set-Cookie", self._cookie)
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_GET(self):
        self._cookie = None
        if self._gate():
            return
        parsed = urlparse(self.path)
        path = parsed.path

        if path in STATIC:
            self._serve_static(path)
        elif path == "/events":
            self._serve_events()
        elif path == "/poll":
            self._serve_poll(parse_qs(parsed.query))
        elif path == "/media":
            self._serve_media(parse_qs(parsed.query))
        elif path == "/api/identity":
            # The gremlin's identifier is its host directory's name.
            self._send_json({"host": os.path.basename(os.path.realpath(HOST_DIR)),
                             "path": os.path.realpath(HOST_DIR)})
        elif path == "/api/commands":
            self._send_json(build_commands())
        elif path == "/api/primitives":
            self._send_json(build_primitives())
        elif path == "/api/context":
            self._send_json(build_context())
        elif path == "/api/status":
            self._send_json(build_status())
        elif path == "/api/transcript":
            archive = parse_qs(parsed.query).get("archive", [None])[0]
            env = build_transcript(archive)
            self._send(404, "no such archive\n") if env is None else self._send_json(env)
        elif path == "/api/groundhog":
            self._send_json(build_groundhog())
        elif path == "/api/loom":
            self._send_json(build_loom())
        elif path == "/api/lore":
            self._send_json(build_lore())
        elif path.startswith("/api/lore/item/"):
            env = lore_item(unquote(path[len("/api/lore/item/"):]))
            self._send(404, "no such item\n") if env is None else self._send_json(env)
        elif path.startswith("/api/lore/content/"):
            self._serve_lore_content(unquote(path[len("/api/lore/content/"):]))
        elif path == "/api/glean":
            self._send_json(build_glean())
        elif path.startswith("/api/glean/finding/"):
            fid = unquote(path[len("/api/glean/finding/"):])
            env = glean_finding(fid)
            if env is None:
                self._send(404, "no such finding\n")
            else:
                self._send_json(env)
        elif path == "/api/dash":
            self._send_json(build_dash())
        elif path.startswith("/dash/"):
            self._serve_dash(unquote(path[len("/dash/"):]))
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
        self._cookie = None
        if self._gate():
            return
        if urlparse(self.path).path != "/send":
            self._send(404, "not found\n")
            return
        if not self._origin_ok():
            self._send(403, "forbidden: cross-origin\n")
            return

        ctype = self.headers.get("Content-Type", "")
        if "multipart/form-data" in ctype:
            self._handle_multipart_send(ctype)
            return

        text = self._read_send_text()
        if text is None:
            self._send(400, "bad request\n")
            return
        if not text.strip():  # empty / whitespace-only writes nothing (400)
            self._send(400, "empty message\n")
            return

        # A slash command runs through the shared dispatcher and returns an
        # ephemeral bridge result — never a nest item, never a transcript turn.
        # This mirrors telegram.sh `handle_slash`; the tender stays sole writer.
        if text.lstrip().startswith("/"):
            result = self._run_slash(text.strip())
            self._send(
                200,
                json.dumps(result, ensure_ascii=False),
                "application/json; charset=utf-8",
            )
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
        if (p.hostname or "") not in ALLOWED_HOSTS:
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

    def _handle_multipart_send(self, ctype):
        try:
            length = int(self.headers.get("Content-Length", ""))
        except ValueError:
            self._send(413, "upload too large\n")
            return
        if length <= 0 or length > MAX_UPLOAD_BYTES:
            self._send(413, "upload too large\n")
            return
        if "boundary=" not in ctype.lower():
            self._send(400, "bad multipart\n")
            return

        raw = self.rfile.read(length)
        if len(raw) != length:
            self._send(400, "bad multipart\n")
            return

        parsed = self._parse_multipart(ctype, raw)
        if parsed is None:
            self._send(400, "bad multipart\n")
            return
        text, files = parsed
        if not files:
            if not text or not text.strip():
                self._send(400, "empty message\n")
                return
            if text.lstrip().startswith("/"):
                result = self._run_slash(text.strip())
                self._send(
                    200,
                    json.dumps(result, ensure_ascii=False),
                    "application/json; charset=utf-8",
                )
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
            return

        result = self._ingest_attachments(text, files)
        if result is None:
            self._send(500, "ingest failed\n")
            return
        self._send(
            200,
            json.dumps(
                {"ok": True, "item": result["item"], "files": result["files"]},
                ensure_ascii=False,
            ),
            "application/json; charset=utf-8",
        )

    def _parse_multipart(self, ctype, raw):
        try:
            msg = BytesParser(policy=policy.default).parsebytes(
                ("Content-Type: %s\r\nMIME-Version: 1.0\r\n\r\n" % ctype).encode("utf-8")
                + raw
            )
        except Exception:
            return None
        if not msg.is_multipart():
            return None
        parts = list(msg.iter_parts())
        if not parts:
            return None

        text = ""
        files = []
        used = set()
        try:
            for part in parts:
                filename = part.get_filename()
                field = part.get_param("name", header="content-disposition")
                if filename is not None:
                    payload = part.get_payload(decode=True)
                    if payload is None:
                        return None
                    safe = sanitize_upload_name(filename, used)
                    files.append({"name": safe, "bytes": payload})
                elif field == "text":
                    payload = part.get_payload(decode=True)
                    if payload is None:
                        return None
                    text = payload.decode("utf-8")
        except (LookupError, UnicodeDecodeError, ValueError):
            return None
        return text, files

    def _ingest_attachments(self, text, files):
        """Stage an attachment item directory, then let nestling atomically land
        it in `.nest/in/`. The bridge writes only under CACHE_DIR before ingest."""
        if not NESTLING:
            log("no nestling configured; refusing attachment /send")
            return None
        item = "%s-web-%s" % (
            time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()),
            secrets.token_hex(3),
        )
        tmpdir = None
        try:
            os.makedirs(CACHE_DIR, exist_ok=True)
            tmpdir = tempfile.mkdtemp(prefix="web-upload-", dir=CACHE_DIR)
            for f in files:
                with open(os.path.join(tmpdir, f["name"]), "wb") as fh:
                    fh.write(f["bytes"])
            with open(os.path.join(tmpdir, "instructions.md"), "w", encoding="utf-8") as fh:
                fh.write("The user sent a message via web with attachments.\n\n")
                if text:
                    fh.write(text.rstrip("\n") + "\n\n")
                fh.write("## attachments\n")
                for f in files:
                    mt = mimetypes.guess_type(f["name"])[0] or "application/octet-stream"
                    fh.write("- `%s` (%s)\n" % (f["name"], mt))
                fh.write("\nOpen the files above and respond to the user.\n")
            result = subprocess.run(
                [NESTLING, "ingest", tmpdir, item],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if result.returncode != 0:
                log("nestling attachment ingest failed (rc=%d)" % result.returncode)
                return None
            return {"item": item, "files": [f["name"] for f in files]}
        except OSError as exc:
            log("attachment stage failed: %r" % exc)
            return None
        finally:
            if tmpdir:
                shutil.rmtree(tmpdir, ignore_errors=True)

    def _run_slash(self, text):
        """Dispatch a slash command through the shared `bin/slash.sh` — the same
        dispatcher telegram.sh uses — and return its output + exit code. This
        writes nothing to the transcript or `.nest/in/`: a slash command is a
        bridge-level action, not a conversational turn. An unknown command fails
        loud (slash.sh returns 127 with `try /help`); output is returned raw and
        rendered inert (escaped) by the client."""
        slash = os.path.join(GREMLIN_DIR, "bin", "slash.sh")
        if not os.path.isfile(slash):
            log("no slash dispatcher at bin/slash.sh; refusing /command")
            return {"slash": True, "ok": False, "rc": 127,
                    "output": "slash dispatcher not available"}
        try:
            result = subprocess.run(
                [slash, text],
                cwd=GREMLIN_DIR,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                timeout=SLASH_TIMEOUT,
            )
        except subprocess.TimeoutExpired:
            log("slash command timed out (>%ds): %r" % (int(SLASH_TIMEOUT), text))
            return {"slash": True, "ok": False, "rc": 124,
                    "output": "command timed out after %ds" % int(SLASH_TIMEOUT)}
        except OSError as exc:
            log("slash dispatch failed: %r" % exc)
            return {"slash": True, "ok": False, "rc": 1,
                    "output": "slash dispatch failed"}
        out = result.stdout.decode("utf-8", "replace")
        if not out.strip():
            out = ("(no output)" if result.returncode == 0
                   else "(command exited %d)" % result.returncode)
        return {"slash": True, "ok": result.returncode == 0,
                "rc": result.returncode, "output": out}

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

    def _serve_lore_content(self, rest):
        # rest = "<id>/<subpath>"; serve a lore content byte, jailed under that
        # item's content/ dir. Binary → download; text/markdown → inline.
        lid, _, sub = rest.partition("/")
        if not SAFE_ID.match(lid) or lid in (".", "..") or not sub:
            self._send(404, "not found\n")
            return
        cdir = os.path.join(LORE_DIR, "items", lid, "content")
        real = under(cdir, os.path.join(cdir, sub))
        if not real or not os.path.isfile(real):
            self._send(404, "not found\n")
            return
        ctype = mimetypes.guess_type(real)[0] or "application/octet-stream"
        disposition = "inline" if ctype.startswith("text/") else "attachment"
        try:
            with open(real, "rb") as fh:
                body = fh.read()
        except OSError:
            self._send(404, "not found\n")
            return
        self._send(200, body, ctype, {
            "Content-Disposition": '%s; filename="%s"' % (disposition, os.path.basename(real)),
        })

    def _serve_media(self, params):
        vals = params.get("path") or []
        rel = vals[0] if vals else ""
        # Refuse traversal lexically as well as after realpath resolution: the
        # route is an outbound bytes lens over HOST_DIR, not a path normalizer.
        parts = re.split(r"[\\/]+", rel)
        if not rel or os.path.isabs(rel) or ".." in parts:
            self._send(404, "not found\n")
            return
        real = under(HOST_DIR, os.path.join(HOST_DIR, rel))
        if not real or not os.path.isfile(real):
            self._send(404, "not found\n")
            return

        try:
            size = os.path.getsize(real)
        except OSError:
            self._send(404, "not found\n")
            return
        ctype = mimetypes.guess_type(real)[0] or "application/octet-stream"
        disposition = "inline" if ctype.startswith(("text/", "image/", "audio/", "video/")) else "attachment"
        filename = os.path.basename(real).replace('"', "_")
        headers = {"Content-Disposition": '%s; filename="%s"' % (disposition, filename)}

        range_header = self.headers.get("Range", "")
        m = re.match(r"^bytes=(\d+)-(\d*)$", range_header)
        if m:
            start = int(m.group(1))
            end = int(m.group(2)) + 1 if m.group(2) else size
            if start < size and end > start:
                end = min(end, size)
                body = read_byte_range(real, start, end)
                if body is None:
                    self._send(404, "not found\n")
                    return
                headers["Content-Range"] = "bytes %d-%d/%d" % (start, end - 1, size)
                self._send(206, body, ctype, headers)
                return

        try:
            with open(real, "rb") as fh:
                body = fh.read()
        except OSError:
            self._send(404, "not found\n")
            return
        self._send(200, body, ctype, headers)

    def _serve_dash(self, rest):
        # rest = "<name>/<subpath>"; serve a Dash view file, jailed under that
        # view's HOST_DIR/.dash/<name>/ dir. This is the bridge's first
        # arbitrary-path static surface — it routes through under(), NOT the
        # exact-match STATIC dict. A bare "<name>/" (or a dir path) serves index.html.
        name, _, sub = rest.partition("/")
        if not SAFE_ID.match(name) or name in (".", ".."):
            self._send(404, "not found\n")
            return
        if not sub or sub.endswith("/"):
            sub += "index.html"
        vdir = os.path.join(DASH_DIR, name)
        real = under(vdir, os.path.join(vdir, sub))
        if not real or not os.path.isfile(real):
            self._send(404, "not found\n")
            return
        ctype = mimetypes.guess_type(real)[0] or "application/octet-stream"
        try:
            with open(real, "rb") as fh:
                body = fh.read()
        except OSError:
            self._send(404, "not found\n")
            return
        # no-cache: a stale gremlin build must never be cached. CSP pins the
        # gremlin-authored view same-origin (design §3), widened only by the
        # view's own vetted `.embeds` profiles (never script-src/connect-src).
        self._send(200, body, ctype, {
            "Cache-Control": "no-cache",
            "Content-Security-Policy": dash_csp(vdir),
        })

    def _serve_static(self, path):
        name, ctype = STATIC[path]
        try:
            with open(os.path.join(PUBLIC_DIR, name), "rb") as fh:
                # no-cache: assets are tiny and files are the truth; always fresh.
                self._send(200, fh.read(), ctype, {"Cache-Control": "no-cache"})
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
    # Remote binding is token-gated and off by default (spec §17).
    if IS_REMOTE and not REMOTE_TOKEN:
        log("refusing to bind non-loopback %s without WEB_REMOTE_TOKEN — set it "
            "in config (an SSH tunnel / WireGuard is the safer path)." % BIND)
        sys.exit(2)
    if IS_REMOTE:
        log("WARNING: serving the gremlin's files and chat to the network on "
            "%s:%d — anyone who can reach this port and present the token can read "
            "the transcript and send messages the gremlin acts on. The Dash tab "
            "also serves gremlin-authored view code (HTML/JS) that runs in the "
            "client's browser. Traffic is cleartext unless tunneled." % (BIND, PORT))

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

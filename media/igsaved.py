#!/usr/bin/env python3
"""
igsaved.py — download your Instagram saved posts (bookmarks) from a data export,
one folder per author, with the collection name in each filename.

Input is the "Download your information" export from Instagram, JSON or HTML
format, requested with date range "All time" (the default "Last year" silently
drops older bookmarks and collections). Point this at the ZIP(s) or the
extracted folder; it finds your_instagram_activity/saved/saved_posts.* and
saved_collections.* wherever they are inside.

For each saved post it runs gallery-dl (images, videos and carousels), falling
back to yt-dlp for videos if gallery-dl fails. Files land in:

    OUT/<author>/<author>_<collection>_<YYYYMMDD>_<shortcode>_<nn>.<ext>

A post saved in several collections gets them joined with "+". A post that
is saved but in no collection has no collection segment.

With --pad, every author folder that received new videos is handed to
igpad.sh (same folder as this script) so reels get padded to the 4:5 feed
size. Originals are kept; igpad writes <name>-out.mp4 beside them.

Progress is recorded in OUT/.igsaved/ so re-running only fetches what's new.
Nothing in the export is ever modified.

Usage:  igsaved.py EXPORT [EXPORT ...] -o OUT --cookies FILE [options]
        igsaved.py --help
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import random
import re
import shutil
import subprocess
import sys
import time
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

SHORTCODE_RE = re.compile(
    r"instagram\.com/(?:[^/?#]+/)?(?:p|reel|reels|tv)/([A-Za-z0-9_-]+)")
# Letters and digits in any script are kept (so "Café" stays "Café");
# spaces, emoji and punctuation become "-".
SAFE_RE = re.compile(r"[^\w.-]+")
VIDEO_EXT = {".mp4", ".m4v", ".mov", ".MP4", ".M4V", ".MOV"}

# gallery-dl exit codes (see gallery-dl docs, "Exit status").
GDL_AUTH = 16


# --------------------------------------------------------------------------
# Export parsing
# --------------------------------------------------------------------------

def unmojibake(s: str) -> str:
    """Instagram exports write UTF-8 bytes as if they were Latin-1 code
    points, so "café" arrives as "cafÃ©". Undo that; leave plain text alone."""
    if not s:
        return s
    try:
        return s.encode("latin-1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return s


def sanitize(s: str, fallback: str = "untitled") -> str:
    # Trim stray dashes/dots at the ends, but keep underscores: handles like
    # "boh_dance_" are real usernames and the folder should match them.
    s = SAFE_RE.sub("-", unmojibake(s)).strip("-.")
    return s or fallback


def shortcode_of(url: str) -> str | None:
    m = SHORTCODE_RE.search(url or "")
    return m.group(1) if m else None


@dataclass
class Post:
    shortcode: str
    url: str
    user: str
    saved_at: int = 0
    collections: list[str] = field(default_factory=list)
    caption: str = ""

    @property
    def folder(self) -> str:
        return sanitize(self.user, "unknown-user")

    @property
    def prefix(self) -> str:
        parts = [self.folder]
        if self.collections:
            parts.append("+".join(sanitize(c) for c in sorted(set(self.collections))))
        return "_".join(parts)


def iter_export_files(paths: list[Path]):
    """Yield (display_name, bytes) for every saved_posts.json /
    saved_collections.json found inside the given ZIPs or folders."""
    wanted = {"saved_posts.json", "saved_collections.json",
              "saved_posts.html", "saved_collections.html"}
    for p in paths:
        if not p.exists():
            sys.exit(f"Error: no such file or folder: {p}")
        if p.is_file() and zipfile.is_zipfile(p):
            with zipfile.ZipFile(p) as z:
                for info in z.infolist():
                    if Path(info.filename).name in wanted:
                        yield f"{p}:{info.filename}", z.read(info)
        elif p.is_dir():
            for f in p.rglob("*"):
                if f.name in wanted:
                    yield str(f), f.read_bytes()
        elif p.is_file() and p.name in wanted:
            yield str(p), p.read_bytes()
        else:
            sys.exit(f"Error: {p} is not a ZIP, a folder, or a saved_*.json/.html file")


def first_href(smd: dict) -> tuple[str | None, int]:
    """Legacy format: string_map_data keys are localised ("Saved on", "Name",
    ...), so find the first entry carrying an href rather than trusting the key."""
    for v in smd.values():
        if isinstance(v, dict) and v.get("href"):
            return v["href"], int(v.get("timestamp") or 0)
    return None, 0


# -- 2026 "label_values" format -------------------------------------------
#
# Each entry is {"timestamp", "media": [], "label_values": [...], "fbid"}.
# label_values mixes two shapes:
#   {"label": "URL", "value": ..., "href": ...}     plain fields
#   {"title": "Owner", "dict": [ {"title": "", "dict": [plain fields...]} ]}
#                                                   nested groups
# A saved post has a top-level URL label and an Owner group holding the
# author's Username. A collection has a Name label and a "Media" group whose
# members are themselves post label_values lists.

def lv_value(lvs: list, label: str) -> str:
    for lv in lvs:
        if lv.get("label") == label:
            return lv.get("href") or lv.get("value") or ""
    return ""


def lv_groups(lvs: list, title: str) -> list[list]:
    for lv in lvs:
        if lv.get("title") == title:
            return [g.get("dict", []) for g in lv.get("dict", [])]
    return []


def lv_post(lvs: list) -> tuple[str, str, str] | None:
    """(url, username, caption) from a post's label_values, or None."""
    url = lv_value(lvs, "URL")
    if not url:
        return None
    user = ""
    for owner in lv_groups(lvs, "Owner"):
        user = lv_value(owner, "Username")
        if user:
            break
    return url, user, lv_value(lvs, "Caption")


# -- HTML export ------------------------------------------------------------
#
# Same information as the JSON, rendered as nested tables. Rather than walk
# the DOM we tokenise the handful of cells we care about, in document order,
# and run a small state machine over them. The HTML is machine-generated and
# very regular; the patterns below are anchored on its exact cell markup.

HTML_TOKEN_RE = re.compile(
    r'<td class="_a6_q">Name</td><td class="_2piu _a6_r">(?P<collection>[^<]*)</td></tr>'
    r'<tr><td class="_a6_q">Type</td>'
    r'|URL<div><a target="_blank" href="(?P<url>https://www\.instagram\.com/[^"]+)"'
    r'|<td class="_a6_q">Caption</td><td class="_2piu _a6_r">(?P<caption>.*?)</td>'
    r'|<td class="_a6_q">Username</td><td class="_2piu _a6_r">(?P<username>[^<]*)</td>'
    r'|<div class="_3-94 _a6-o">(?P<when>[^<]*)</div>', re.S)


def parse_html_when(text: str) -> int:
    """"Jan 25, 2024 12:54 am" -> epoch seconds (treated as UTC)."""
    import calendar
    from datetime import datetime
    for fmt in ("%b %d, %Y %I:%M %p", "%b %d, %Y %H:%M"):
        try:
            return calendar.timegm(datetime.strptime(text.strip(), fmt).timetuple())
        except ValueError:
            pass
    return 0


def parse_html(text: str, add) -> None:
    """Feed every post found in saved_posts.html / saved_collections.html to
    add(url, user, ts, collection, caption)."""
    import html as htmlmod
    collection: str | None = None
    cur: dict | None = None

    # The page header carries the generation time twice: a machine-readable
    # UTC attribute and a rendered time labelled "UTC" that is actually in
    # Meta's local (Pacific) zone. The difference is the offset every other
    # rendered date on the page needs, DST included.
    tz_offset = 0
    hdr = re.search(r'<time datetime="(\d{4}-\d\d-\d\dT\d\d:\d\d)Z">([^<]*)</time>', text)
    if hdr:
        from datetime import datetime
        import calendar
        true_utc = calendar.timegm(datetime.strptime(hdr.group(1), "%Y-%m-%dT%H:%M").timetuple())
        shown = re.search(r"(\d{1,2}):(\d\d) UTC", hdr.group(2))
        if shown:
            shown_utc = true_utc - (true_utc % 86400) + int(shown.group(1)) * 3600 + int(shown.group(2)) * 60
            if shown_utc > true_utc:          # rendered time fell on the previous day
                shown_utc -= 86400
            tz_offset = true_utc - shown_utc

    def flush():
        if cur and cur.get("url"):
            add(cur["url"], cur.get("user", ""), cur.get("ts", 0), collection, cur.get("caption", ""))

    for m in HTML_TOKEN_RE.finditer(text):
        kind = m.lastgroup
        val = htmlmod.unescape(m.group(kind))
        if kind == "collection":
            flush(); cur = None
            collection = val.strip() or "untitled"
        elif kind == "url":
            flush()
            cur = {"url": val}
        elif cur is None:
            continue
        elif kind == "username":
            cur.setdefault("user", val.strip())
        elif kind == "caption":
            cur.setdefault("caption", val)
        elif kind == "when" and collection is None:
            # Only saved_posts.html has a date per post. In the collections
            # file the single date after each block is the collection's own.
            ts = parse_html_when(val)
            cur["ts"] = ts + tz_offset if ts else 0
    flush()


def parse_exports(paths: list[Path]) -> dict[str, Post]:
    posts: dict[str, Post] = {}
    found_any = False

    def add(url: str, user: str, ts: int, collection: str | None, caption: str = ""):
        code = shortcode_of(url)
        if not code:
            return
        p = posts.get(code)
        if p is None:
            p = posts[code] = Post(code, url, unmojibake(user or ""), ts)
        if not p.user and user:
            p.user = unmojibake(user)
        if ts and (not p.saved_at or ts < p.saved_at):
            p.saved_at = ts
        if caption and not p.caption:
            p.caption = unmojibake(caption)
        if collection and collection not in p.collections:
            p.collections.append(collection)

    for name, raw in iter_export_files(paths):
        found_any = True
        if name.endswith(".html"):
            parse_html(raw.decode("utf-8", "replace"), add)
            continue
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as e:
            sys.exit(f"Error: {name} is not valid JSON: {e}")

        # ---- legacy format (string_map_data) ----
        if isinstance(data, dict) and "saved_saved_media" in data:
            for item in data["saved_saved_media"]:
                href, ts = first_href(item.get("string_map_data", {}))
                if href:
                    add(href, item.get("title", ""), ts, None)
            continue

        if isinstance(data, dict) and "saved_saved_collections" in data:
            # Flat list: a collection header (no href) is followed by the
            # posts that belong to it, until the next header.
            current: str | None = None
            for item in data["saved_saved_collections"]:
                smd = item.get("string_map_data", {})
                href, ts = first_href(smd)
                if href is None:
                    name_entry = smd.get("Name") or {}
                    current = unmojibake(name_entry.get("value") or item.get("title") or "")
                    continue
                user = item.get("title") or (smd.get("Name") or {}).get("value") or ""
                add(href, user, ts, current)
            continue

        # ---- 2026 format (label_values) ----
        # A single collection is written as a bare object, several as a list.
        entries = data if isinstance(data, list) else [data]
        for entry in entries:
            if not isinstance(entry, dict) or "label_values" not in entry:
                continue
            lvs = entry["label_values"]
            ts = int(entry.get("timestamp") or 0)
            post = lv_post(lvs)
            if post:
                add(post[0], post[1], ts, None, post[2])
                continue
            members = lv_groups(lvs, "Media")
            cname = unmojibake(lv_value(lvs, "Name"))
            if cname or members:
                for member in members:
                    mp = lv_post(member)
                    if mp:
                        add(mp[0], mp[1], 0, cname or "untitled", mp[2])

    if not found_any:
        sys.exit("Error: no saved_posts.json/.html or saved_collections.json/.html found "
                 "in the given export(s).")
    return posts


# --------------------------------------------------------------------------
# State
# --------------------------------------------------------------------------

class State:
    def __init__(self, out: Path):
        self.dir = out / ".igsaved"
        self.path = self.dir / "state.json"
        self.gdl_archive = self.dir / "gallery-dl-archive.sqlite3"
        self.ytdlp_archive = self.dir / "yt-dlp-archive.txt"
        self.data: dict = {"posts": {}}
        if self.path.exists():
            self.data = json.loads(self.path.read_text())

    def get(self, code: str) -> dict | None:
        return self.data["posts"].get(code)

    def set(self, code: str, **kw):
        kw["when"] = int(time.time())
        self.data["posts"][code] = kw
        self.save()

    def save(self):
        self.dir.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.data, indent=1, sort_keys=True))
        os.replace(tmp, self.path)


# --------------------------------------------------------------------------
# Downloading
# --------------------------------------------------------------------------

def snapshot(d: Path) -> set[str]:
    return {f.name for f in d.iterdir() if f.is_file()} if d.exists() else set()


def cookie_args(a) -> list[str]:
    if a.cookies:
        return ["--cookies", str(a.cookies)]
    if a.cookies_from_browser:
        return ["--cookies-from-browser", a.cookies_from_browser]
    return []


def run(cmd: list[str], verbose: bool) -> tuple[int, str]:
    if verbose:
        print("       $ " + " ".join(repr(c) if " " in c else c for c in cmd))
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return r.returncode, r.stdout


def gallery_dl(post: Post, dest: Path, st: State, a) -> tuple[int, str]:
    # Filename: prefix is built here from the export (so the collection is
    # known); the rest comes from gallery-dl's own metadata.
    fmt = f"{post.prefix}_{{date:%Y%m%d}}_{{post_shortcode}}_{{num:>02}}.{{extension}}"
    cmd = ["gallery-dl", "-D", str(dest), "-f", fmt,
           "--download-archive", str(st.gdl_archive),
           "--sleep-request", "1.0-3.0", "-R", "3",
           *cookie_args(a),
           f"https://www.instagram.com/p/{post.shortcode}/"]
    return run(cmd, a.verbose)


def yt_dlp(post: Post, dest: Path, st: State, a) -> tuple[int, str]:
    out = str(dest / f"{post.prefix}_%(upload_date)s_%(id)s_%(playlist_index|1)s.%(ext)s")
    cmd = ["yt-dlp", "-S", "res,vcodec:h264,ext:mp4:m4a", "--merge-output-format", "mp4",
           "--download-archive", str(st.ytdlp_archive), "--sleep-requests", "2",
           "--no-warnings", "--no-progress", *cookie_args(a), "-o", out, post.url]
    return run(cmd, a.verbose)


def parse_sleep(spec: str) -> tuple[float, float]:
    try:
        if "-" in spec:
            lo, hi = (float(x) for x in spec.split("-", 1))
        else:
            lo = hi = float(spec)
    except ValueError:
        sys.exit(f"Error: --sleep wants SECONDS or MIN-MAX, got '{spec}'")
    if lo > hi or lo < 0:
        sys.exit(f"Error: bad --sleep range '{spec}'")
    return lo, hi


def parse_when(spec: str, name: str) -> int:
    """--since/--until value -> epoch seconds. Accepts YYYY-MM-DD, or a
    relative age like 90d, 12w, 3m (months) counted back from today."""
    from datetime import date, datetime, timedelta
    import calendar
    m = re.fullmatch(r"(\d+)([dwm])", spec)
    if m:
        n, unit = int(m.group(1)), m.group(2)
        today = date.today()
        if unit == "d":
            d = today - timedelta(days=n)
        elif unit == "w":
            d = today - timedelta(weeks=n)
        else:
            month = today.month - n
            year = today.year + (month - 1) // 12
            month = (month - 1) % 12 + 1
            d = today.replace(year=year, month=month,
                              day=min(today.day, calendar.monthrange(year, month)[1]))
        return calendar.timegm(d.timetuple())
    try:
        return calendar.timegm(datetime.strptime(spec, "%Y-%m-%d").timetuple())
    except ValueError:
        sys.exit(f"Error: {name} wants YYYY-MM-DD or an age like 90d / 12w / 3m, got '{spec}'")


def fmt_day(ts: int) -> str:
    return time.strftime("%Y-%m-%d", time.gmtime(ts)) if ts else "????-??-??"


def summarise_error(output: str) -> str:
    lines = [l.strip() for l in output.splitlines() if l.strip()]
    for l in reversed(lines):
        if "error" in l.lower() or "ERROR" in l:
            return l[:200]
    return (lines[-1] if lines else "no output")[:200]


# --------------------------------------------------------------------------
# igpad
# --------------------------------------------------------------------------

def run_igpad(folders: set[Path], a):
    script = Path(a.igpad) if a.igpad else Path(__file__).resolve().parent / "igpad.sh"
    if not script.exists():
        print(f"\nWarning: igpad.sh not found at {script}; skipping --pad", file=sys.stderr)
        return
    print(f"\nPadding videos with {script.name} (-m {a.pad_mode} -f {a.pad_fill}):")
    for d in sorted(folders):
        print(f"-----> {d}")
        rc = subprocess.run(["bash", str(script), "-d", str(d),
                             "-m", a.pad_mode, "-f", a.pad_fill]).returncode
        if rc != 0:
            print(f"       igpad.sh exited {rc}", file=sys.stderr)


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="igsaved.py",
        description=__doc__.split("Usage:")[0].strip(),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""\
Examples:
  igsaved.py ~/Downloads/instagram-rob-2026-11-08.zip -o ~/ig-saved --list
  igsaved.py ~/Downloads/instagram-*.zip -o ~/ig-saved --cookies ~/ig-cookies.txt --dry-run
  igsaved.py ~/Downloads/instagram-*.zip -o ~/ig-saved --cookies ~/ig-cookies.txt -n 40
  igsaved.py export/ -o ~/ig-saved --cookies-from-browser chrome --collection Events --pad
  igsaved.py export.zip -o ~/ig-saved --cookies FILE --collection Events --since 3m   # recent only

Dates: --since/--until filter on when YOU saved the post (that is what the
export records). The date in each filename is when the post was published.

Requires: gallery-dl (brew install gallery-dl); yt-dlp and ffmpeg for the
fallback and --pad (brew install yt-dlp ffmpeg).""")
    p.add_argument("export", nargs="+", type=Path,
                   help="export ZIP(s), extracted folder(s), or the saved_*.json files")
    p.add_argument("-o", "--out", type=Path, default=Path("ig-saved"),
                   help="output root; one subfolder per author (default: ./ig-saved)")
    auth = p.add_mutually_exclusive_group()
    auth.add_argument("-c", "--cookies", type=Path, help="Netscape cookies.txt for instagram.com")
    auth.add_argument("-b", "--cookies-from-browser", metavar="BROWSER",
                      help="e.g. chrome, firefox, 'chrome:Profile 1' (needs Full Disk Access on macOS)")
    p.add_argument("--collection", action="append", default=[], metavar="NAME",
                   help="only posts in this collection (repeatable, case-insensitive)")
    p.add_argument("--user", action="append", default=[], metavar="NAME",
                   help="only posts by this author (repeatable, case-insensitive)")
    p.add_argument("--since", metavar="WHEN",
                   help="only posts saved on/after WHEN: YYYY-MM-DD, or an age like 90d, 12w, 3m")
    p.add_argument("--until", metavar="WHEN", help="only posts saved before WHEN (same forms)")
    p.add_argument("--order", default="newest", choices=["newest", "oldest", "author"],
                   help="processing order: most recently saved first (default), oldest first, "
                        "or alphabetical by author")
    p.add_argument("-n", "--limit", type=int, default=0, metavar="N",
                   help="stop after N download attempts (keeps batches small; re-run to continue)")
    p.add_argument("--sleep", default="4-10", metavar="MIN-MAX",
                   help="seconds to wait between posts (default: 4-10)")
    p.add_argument("--max-failures", type=int, default=5, metavar="N",
                   help="abort after N consecutive failures — usually rate limiting (default: 5)")
    p.add_argument("--retry-failed", action="store_true", help="re-attempt posts that failed before")
    p.add_argument("--no-fallback", action="store_true", help="don't try yt-dlp when gallery-dl fails")
    p.add_argument("--list", action="store_true", help="show collections and authors with counts, then exit")
    p.add_argument("--dry-run", action="store_true", help="show what would be downloaded, write nothing")
    p.add_argument("--pad", action="store_true",
                   help="after downloading, run igpad.sh on each folder that got new videos")
    p.add_argument("--pad-mode", default="feed", choices=["feed", "reel"], help="igpad -m (default: feed)")
    p.add_argument("--pad-fill", default="black", choices=["black", "blur"], help="igpad -f (default: black)")
    p.add_argument("--igpad", metavar="PATH", help="igpad.sh location (default: beside this script)")
    p.add_argument("-v", "--verbose", action="store_true", help="show the commands being run")
    return p


def main(argv: list[str]) -> int:
    # Line-buffer stdout so our progress lines interleave correctly with
    # igpad/ffmpeg output when piped to a file or tee.
    sys.stdout.reconfigure(line_buffering=True)
    parser = build_parser()
    if not argv:
        parser.print_help()
        return 0
    a = parser.parse_args(argv)

    posts = parse_exports(a.export)
    if a.order == "author":
        key = lambda p: (p.folder.lower(), p.saved_at)
    else:
        key = lambda p: (p.saved_at, p.folder.lower())
    all_posts = sorted(posts.values(), key=key, reverse=(a.order == "newest"))

    # Filters
    want_c = {c.lower() for c in a.collection}
    want_u = {u.lower() for u in a.user}
    since = parse_when(a.since, "--since") if a.since else 0
    until = parse_when(a.until, "--until") if a.until else 0
    selected = [p for p in all_posts
                if (not want_c or any(c.lower() in want_c for c in p.collections))
                and (not want_u or p.user.lower() in want_u)
                and (not since or p.saved_at >= since)
                and (not until or p.saved_at < until)]
    window = ""
    if since or until:
        window = f"   saved {fmt_day(since) if since else '...'} to {fmt_day(until) if until else 'now'}"

    if a.list:
        colls: dict[str, int] = {}
        users: dict[str, int] = {}
        uncollected = 0
        for p in all_posts:
            users[p.user or "(unknown)"] = users.get(p.user or "(unknown)", 0) + 1
            if not p.collections:
                uncollected += 1
            for c in p.collections:
                colls[c] = colls.get(c, 0) + 1
        print(f"{len(all_posts)} saved posts from {len(users)} authors, "
              f"saved {fmt_day(min(p.saved_at for p in all_posts))} to "
              f"{fmt_day(max(p.saved_at for p in all_posts))}\n")
        months: dict[str, int] = {}
        for p in all_posts:
            mo = time.strftime("%Y-%m", time.gmtime(p.saved_at)) if p.saved_at else "unknown"
            months[mo] = months.get(mo, 0) + 1
        print("Saved per month (last 12):")
        for mo in sorted(months)[-12:]:
            print(f"  {months[mo]:5d}  {mo}")
        print("\nCollections:")
        for c, n in sorted(colls.items(), key=lambda kv: -kv[1]):
            print(f"  {n:5d}  {c}")
        print(f"  {uncollected:5d}  (not in any collection)")
        print("\nAuthors:")
        for u, n in sorted(users.items(), key=lambda kv: -kv[1]):
            print(f"  {n:5d}  {u}")
        return 0

    for tool in ("gallery-dl",) + (() if a.no_fallback else ("yt-dlp",)):
        if not a.dry_run and shutil.which(tool) is None:
            sys.exit(f"Error: {tool} not found. Install it with:  brew install {tool}")
    if a.pad and shutil.which("ffmpeg") is None and not a.dry_run:
        sys.exit("Error: --pad needs ffmpeg. Install it with:  brew install ffmpeg")
    if not a.cookies and not a.cookies_from_browser:
        print("Warning: no cookies given. Instagram needs a logged-in session for almost "
              "everything now; expect failures. See download.md → Cookies.", file=sys.stderr)
    if a.cookies and not a.cookies.exists():
        sys.exit(f"Error: cookies file not found: {a.cookies}")

    st = State(a.out)
    lo, hi = parse_sleep(a.sleep)

    todo = []
    already = 0
    for p in selected:
        s = st.get(p.shortcode)
        if s and s["status"] == "ok":
            already += 1
            continue
        if s and s["status"] == "failed" and not a.retry_failed:
            continue
        todo.append(p)
    failed_before = sum(1 for p in selected if (st.get(p.shortcode) or {}).get("status") == "failed")

    print(f"Saved posts in export: {len(all_posts)}   selected: {len(selected)}{window}\n"
          f"Done earlier: {already}   failed earlier: {failed_before}"
          f"{'' if a.retry_failed else ' (use --retry-failed)'}")
    print(f"To fetch now: {min(len(todo), a.limit) if a.limit else len(todo)}"
          f"{f' of {len(todo)} (limit {a.limit})' if a.limit and a.limit < len(todo) else ''}")
    print(f"Output: {a.out.resolve()}\n")

    if a.dry_run:
        for p in todo[: a.limit or None]:
            colls = ", ".join(p.collections) if p.collections else "-"
            print(f"{fmt_day(p.saved_at)}  {p.folder}/{p.prefix}_<date>_{p.shortcode}_<nn>.<ext>")
            print(f"            {p.url}   [{colls}]")
        return 0

    if not todo:
        print("Nothing to do.")
        return 0

    a.out.mkdir(parents=True, exist_ok=True)
    ok = failed = 0
    consecutive = 0
    touched_video_folders: set[Path] = set()
    attempts = 0

    try:
        for p in todo:
            if a.limit and attempts >= a.limit:
                print(f"\nReached limit of {a.limit}; re-run to continue.")
                break
            if attempts:
                time.sleep(random.uniform(lo, hi))
            attempts += 1
            dest = a.out / p.folder
            dest.mkdir(exist_ok=True)
            before = snapshot(dest)
            print(f"-----> [{attempts}/{len(todo)}] saved {fmt_day(p.saved_at)}  {p.folder}  "
                  f"{p.shortcode}  [{', '.join(p.collections) or '-'}]")

            rc, out = gallery_dl(p, dest, st, a)
            tool = "gallery-dl"
            new = sorted(snapshot(dest) - before)
            if rc != 0 and not a.no_fallback:
                print(f"       gallery-dl failed ({summarise_error(out)}); trying yt-dlp")
                rc2, out2 = yt_dlp(p, dest, st, a)
                new = sorted(snapshot(dest) - before)
                if rc2 == 0 and new:
                    rc, out, tool = rc2, out2, "yt-dlp"
                else:
                    out = out + "\n" + out2

            if rc == 0:
                ok += 1
                consecutive = 0
                st.set(p.shortcode, status="ok", tool=tool, folder=p.folder, files=new)
                if new:
                    for f in new:
                        print(f"       {f}")
                    if any(Path(f).suffix in VIDEO_EXT for f in new):
                        touched_video_folders.add(dest)
                else:
                    print("       nothing new (already in archive)")
            else:
                failed += 1
                consecutive += 1
                err = summarise_error(out)
                st.set(p.shortcode, status="failed", error=err, folder=p.folder, url=p.url)
                print(f"       FAILED: {err}")
                if not before and not snapshot(dest):
                    dest.rmdir()   # don't leave an empty author folder behind
                if rc == GDL_AUTH or "login" in err.lower():
                    print("\nInstagram wants a login. Refresh your cookies and re-run with "
                          "--retry-failed.", file=sys.stderr)
                    break
                if consecutive >= a.max_failures:
                    print(f"\n{consecutive} failures in a row — probably rate limited. "
                          "Wait an hour or so, then re-run with --retry-failed.", file=sys.stderr)
                    break
    except KeyboardInterrupt:
        print("\nInterrupted. Progress so far is saved; re-run to continue.")

    write_manifest(a.out, all_posts, st)

    print(f"\nDone. {ok} fetched, {failed} failed, {already} already had.")
    print(f"Manifest: {a.out / 'saved-posts.csv'}")

    if a.pad and touched_video_folders:
        run_igpad(touched_video_folders, a)
    elif a.pad:
        print("No new videos, nothing to pad.")
    return 1 if failed and not ok else 0


def write_manifest(out: Path, posts: list[Post], st: State):
    """CSV of every saved post and its status — handy for checking in a
    spreadsheet which bookmarks are still missing."""
    path = out / "saved-posts.csv"
    with path.open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["author", "shortcode", "collections", "saved_at", "url", "status",
                    "files_or_error", "caption"])
        for p in posts:
            s = st.get(p.shortcode) or {}
            detail = "; ".join(s.get("files", [])) if s.get("status") == "ok" else s.get("error", "")
            w.writerow([p.user, p.shortcode, " + ".join(p.collections),
                        time.strftime("%Y-%m-%d", time.gmtime(p.saved_at)) if p.saved_at else "",
                        p.url, s.get("status", "pending"), detail,
                        " ".join(p.caption.split())[:300]])


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except BrokenPipeError:
        # e.g. `igsaved.py ... --list | head`; exit quietly like a Unix tool should
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        sys.exit(0)

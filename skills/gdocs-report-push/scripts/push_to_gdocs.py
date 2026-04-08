#!/usr/bin/env python3
"""Push local markdown files to a Google Doc as tabs.

Sync semantics:
  - Each .md file becomes a tab whose title is the file stem.
  - New files → new tabs (create).
  - Existing tabs with matching names → update when content differs (with --force),
    skip when unchanged.
  - Tabs that have no matching local file → deleted when --delete-stale is set,
    otherwise left alone (archive behavior).

Document addressing (pick one):
  --doc-id 1abc...                 Direct, unambiguous.
  --doc-name "My Docs"             Looked up by name in Drive (first match).
  --doc-name "My Docs" --folder-id 1xyz...
                                   Looked up by name, scoped to a Drive folder
                                   (use this to disambiguate duplicate names).

Markdown support:
  Headings (#..######), bold (**...**), italic (*...*), inline code (`...`),
  fenced code blocks (```), bullet lists (-), numbered lists (1.), links
  ([text](url)). Syntax characters are stripped from the rendered text; Google
  Docs character and paragraph styles are applied to the correct ranges.

Usage:
  python3 push_to_gdocs.py --source-dir docs/reports --doc-name "My Reports" --token TOKEN
  python3 push_to_gdocs.py --source-dir docs/api --doc-id 1abc... --token TOKEN --delete-stale
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

API_DRIVE = "https://www.googleapis.com/drive/v3"
API_DOCS = "https://docs.googleapis.com/v1"
RETRY_STATUSES = {408, 425, 429, 500, 502, 503, 504}
MAX_RETRIES = 5
BATCH_CHUNK = 50  # Google Docs batchUpdate request chunk size


# ---------------------------------------------------------------------------
# HTTP with retry/backoff
# ---------------------------------------------------------------------------

def api_request(url: str, token: str, method: str = "GET", body: dict | None = None) -> dict:
    """Make a Docs/Drive API request with exponential backoff on 429 and 5xx."""
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    data = json.dumps(body).encode() if body is not None else None

    for attempt in range(MAX_RETRIES):
        req = urllib.request.Request(url, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read().decode()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            if e.code in RETRY_STATUSES and attempt < MAX_RETRIES - 1:
                # Respect Retry-After if present, otherwise exponential backoff.
                retry_after = e.headers.get("Retry-After") if e.headers else None
                delay = _parse_retry_after(retry_after) if retry_after else _backoff(attempt)
                time.sleep(delay)
                continue
            error_body = e.read().decode() if e.fp else ""
            print(f"Error: API {method} {url} -> {e.code}: {error_body}", file=sys.stderr)
            raise
        except urllib.error.URLError as e:
            if attempt < MAX_RETRIES - 1:
                time.sleep(_backoff(attempt))
                continue
            print(f"Error: network failure contacting {url}: {e}", file=sys.stderr)
            raise


def _backoff(attempt: int) -> float:
    """Exponential backoff with jitter (0.5s, 1s, 2s, 4s, ...)."""
    return (2 ** attempt) * 0.5 + random.uniform(0, 0.25)


def _parse_retry_after(value: str) -> float:
    try:
        return max(0.0, float(value))
    except (TypeError, ValueError):
        return 2.0


# ---------------------------------------------------------------------------
# Drive / Docs operations
# ---------------------------------------------------------------------------

def find_document(name: str, token: str, folder_id: str | None = None) -> list[dict]:
    """Return all docs matching `name`. Optionally scoped to a Drive folder.

    Returning a list (not just the first match) lets callers warn about
    ambiguity instead of silently writing to the wrong document.
    """
    clauses = [
        f"name = '{name.replace(chr(39), chr(92) + chr(39))}'",
        "mimeType = 'application/vnd.google-apps.document'",
        "trashed = false",
    ]
    if folder_id:
        clauses.append(f"'{folder_id}' in parents")
    q = urllib.parse.quote(" and ".join(clauses))
    r = api_request(f"{API_DRIVE}/files?q={q}&fields=files(id,name,parents)", token)
    return r.get("files", [])


def create_document(name: str, token: str, folder_id: str | None = None) -> str:
    body: dict = {"name": name, "mimeType": "application/vnd.google-apps.document"}
    if folder_id:
        body["parents"] = [folder_id]
    r = api_request(f"{API_DRIVE}/files", token, "POST", body)
    return r["id"]


def get_doc_with_tabs(doc_id: str, token: str) -> dict:
    return api_request(f"{API_DOCS}/documents/{doc_id}?includeTabsContent=true", token)


def batch_update(doc_id: str, requests: list[dict], token: str) -> dict:
    if not requests:
        return {}
    return api_request(
        f"{API_DOCS}/documents/{doc_id}:batchUpdate",
        token,
        "POST",
        {"requests": requests},
    )


def batch_update_chunked(doc_id: str, requests: list[dict], token: str) -> None:
    """Send requests in chunks of BATCH_CHUNK to stay under API limits."""
    for i in range(0, len(requests), BATCH_CHUNK):
        batch_update(doc_id, requests[i:i + BATCH_CHUNK], token)


def collect_tabs(tabs: list[dict]) -> list[dict]:
    """Flatten nested childTabs into a single list."""
    result: list[dict] = []
    for t in tabs:
        result.append(t)
        for c in t.get("childTabs", []):
            result.append(c)
    return result


def tab_text(tab: dict) -> str:
    parts: list[str] = []
    for elem in tab.get("documentTab", {}).get("body", {}).get("content", []):
        for pe in elem.get("paragraph", {}).get("elements", []):
            parts.append(pe.get("textRun", {}).get("content", ""))
    return "".join(parts)


def tab_end_index(tab: dict) -> int:
    content = tab.get("documentTab", {}).get("body", {}).get("content", [])
    return content[-1].get("endIndex", 1) if content else 1


def resolve_doc(args) -> tuple[str, bool]:
    """Find or create the target document. Returns (doc_id, was_created)."""
    if args.doc_id:
        # Trust it; verify existence by fetching metadata.
        api_request(f"{API_DRIVE}/files/{args.doc_id}?fields=id,name", args.token)
        return args.doc_id, False

    matches = find_document(args.doc_name, args.token, folder_id=args.folder_id)
    if len(matches) > 1:
        scope = f" in folder {args.folder_id}" if args.folder_id else ""
        print(
            f"Error: found {len(matches)} documents named '{args.doc_name}'{scope}.",
            file=sys.stderr,
        )
        print("Disambiguate with --doc-id or --folder-id. Matches:", file=sys.stderr)
        for m in matches:
            print(f"  {m['id']}  (parents: {m.get('parents', [])})", file=sys.stderr)
        sys.exit(2)

    if matches:
        return matches[0]["id"], False

    if args.dry_run:
        return "<would-be-created>", True

    doc_id = create_document(args.doc_name, args.token, folder_id=args.folder_id)
    return doc_id, True


# ---------------------------------------------------------------------------
# Markdown → Google Docs build
# ---------------------------------------------------------------------------

@dataclass
class Span:
    text: str
    bold: bool = False
    italic: bool = False
    code: bool = False
    link: str | None = None


@dataclass
class Block:
    kind: str  # p | h1..h6 | bullet | numbered | code_line | blank
    level: int = 0  # list nesting level
    spans: list[Span] = field(default_factory=list)
    raw: str = ""  # used for code_line


INLINE_CODE_FONT = "Consolas"


def parse_inline(text: str, *, bold: bool = False, italic: bool = False) -> list[Span]:
    """Parse inline markdown into styled spans.

    Handles inline code first (opaque — no further processing inside backticks),
    then bold, italic, and links. Syntax characters are removed from `.text` so
    the document doesn't show raw markdown.
    """
    spans: list[Span] = []
    buf: list[str] = []
    i = 0
    n = len(text)

    def flush_plain() -> None:
        if buf:
            spans.append(Span(text="".join(buf), bold=bold, italic=italic))
            buf.clear()

    while i < n:
        ch = text[i]

        # Inline code: `code` — don't recurse into it
        if ch == "`":
            close = text.find("`", i + 1)
            if close != -1:
                flush_plain()
                spans.append(Span(
                    text=text[i + 1:close],
                    bold=bold, italic=italic, code=True,
                ))
                i = close + 1
                continue

        # Links: [text](url)
        if ch == "[":
            mid = text.find("](", i + 1)
            if mid != -1:
                end = text.find(")", mid + 2)
                if end != -1:
                    flush_plain()
                    link_text = text[i + 1:mid]
                    url = text[mid + 2:end]
                    # Apply inline styles inside link text, then tag with URL.
                    inner = parse_inline(link_text, bold=bold, italic=italic)
                    for s in inner:
                        s.link = url
                    spans.extend(inner)
                    i = end + 1
                    continue

        # Bold: **text** or __text__
        if text[i:i + 2] in ("**", "__"):
            marker = text[i:i + 2]
            close = text.find(marker, i + 2)
            if close != -1:
                flush_plain()
                inner = parse_inline(text[i + 2:close], bold=True, italic=italic)
                spans.extend(inner)
                i = close + 2
                continue

        # Italic: *text* or _text_ (but not ** already handled)
        if ch in ("*", "_"):
            # Avoid matching intra-word underscores (snake_case).
            if ch == "_" and i > 0 and text[i - 1].isalnum():
                buf.append(ch)
                i += 1
                continue
            close = text.find(ch, i + 1)
            if close != -1 and close > i + 1:
                flush_plain()
                inner = parse_inline(text[i + 1:close], bold=bold, italic=True)
                spans.extend(inner)
                i = close + 1
                continue

        buf.append(ch)
        i += 1

    flush_plain()
    return spans


def parse_blocks(md: str) -> list[Block]:
    """Parse markdown into a flat list of blocks."""
    blocks: list[Block] = []
    in_code = False

    for line in md.split("\n"):
        stripped = line.lstrip()

        # Code fence
        if stripped.startswith("```"):
            in_code = not in_code
            continue

        if in_code:
            blocks.append(Block(kind="code_line", raw=line))
            continue

        if not line.strip():
            blocks.append(Block(kind="blank"))
            continue

        # Heading
        m = re.match(r"^(#{1,6})\s+(.*)", line)
        if m:
            level = len(m.group(1))
            spans = parse_inline(m.group(2).rstrip())
            blocks.append(Block(kind=f"h{level}", spans=spans))
            continue

        # Bullet list
        m = re.match(r"^(\s*)[-*+]\s+(.*)", line)
        if m:
            level = len(m.group(1)) // 2
            spans = parse_inline(m.group(2))
            blocks.append(Block(kind="bullet", level=level, spans=spans))
            continue

        # Numbered list
        m = re.match(r"^(\s*)\d+\.\s+(.*)", line)
        if m:
            level = len(m.group(1)) // 2
            spans = parse_inline(m.group(2))
            blocks.append(Block(kind="numbered", level=level, spans=spans))
            continue

        # Paragraph
        spans = parse_inline(line)
        blocks.append(Block(kind="p", spans=spans))

    return blocks


@dataclass
class BuiltDoc:
    text: str
    para_ops: list[tuple[int, int, str]]  # (start, end, namedStyleType)
    text_ops: list[tuple[int, int, dict]]  # (start, end, text_style_fields)
    bullet_ops: list[tuple[int, int, str]]  # (start, end, glyph_preset)
    link_ops: list[tuple[int, int, str]]  # (start, end, url)


def build_doc(md: str) -> BuiltDoc:
    """Convert markdown source into clean text + style operations.

    All positions are 1-indexed (Docs API uses 1-based indices; the document
    "start" is index 1, and inserted text occupies [start, end)).
    """
    blocks = parse_blocks(md)
    parts: list[str] = []
    para_ops: list[tuple[int, int, str]] = []
    text_ops: list[tuple[int, int, dict]] = []
    bullet_ops: list[tuple[int, int, str]] = []
    link_ops: list[tuple[int, int, str]] = []

    pos = 1  # current 1-indexed offset
    pending_bullet: tuple[int, str] | None = None  # (start, kind)

    def flush_bullets(end_pos: int) -> None:
        nonlocal pending_bullet
        if pending_bullet is None:
            return
        start, kind = pending_bullet
        glyph = (
            "NUMBERED_DECIMAL_ALPHA_ROMAN"
            if kind == "numbered"
            else "BULLET_DISC_CIRCLE_SQUARE"
        )
        bullet_ops.append((start, end_pos, glyph))
        pending_bullet = None

    def emit_spans(spans: list[Span]) -> None:
        nonlocal pos
        for span in spans:
            start = pos
            parts.append(span.text)
            pos += len(span.text)
            end = pos
            style: dict = {}
            fields: list[str] = []
            if span.bold:
                style["bold"] = True
                fields.append("bold")
            if span.italic:
                style["italic"] = True
                fields.append("italic")
            if span.code:
                style["weightedFontFamily"] = {"fontFamily": INLINE_CODE_FONT}
                fields.append("weightedFontFamily")
            if span.link:
                link_ops.append((start, end, span.link))
            if fields:
                text_ops.append((start, end, {"style": style, "fields": ",".join(fields)}))

    for block in blocks:
        if block.kind == "blank":
            flush_bullets(pos)
            parts.append("\n")
            pos += 1
            continue

        if block.kind == "code_line":
            flush_bullets(pos)
            start = pos
            parts.append(block.raw)
            pos += len(block.raw)
            parts.append("\n")
            pos += 1
            end = pos
            # Style the line as monospace.
            text_ops.append((
                start, end - 1,  # exclude the trailing newline from font styling
                {"style": {"weightedFontFamily": {"fontFamily": INLINE_CODE_FONT}},
                 "fields": "weightedFontFamily"},
            ))
            continue

        # For non-list blocks, close any open bullet run first.
        if block.kind not in ("bullet", "numbered"):
            flush_bullets(pos)

        line_start = pos
        emit_spans(block.spans)
        parts.append("\n")
        pos += 1
        line_end = pos

        if block.kind.startswith("h") and block.kind[1:].isdigit():
            level = int(block.kind[1:])
            para_ops.append((line_start, line_end, f"HEADING_{level}"))
        elif block.kind in ("bullet", "numbered"):
            if pending_bullet is None:
                pending_bullet = (line_start, block.kind)
            elif pending_bullet[1] != block.kind:
                flush_bullets(line_start)
                pending_bullet = (line_start, block.kind)
            # else: extend the existing run

    flush_bullets(pos)

    # Ensure there's trailing content — Docs API refuses empty inserts.
    text = "".join(parts)
    if not text:
        text = "\n"

    return BuiltDoc(
        text=text,
        para_ops=para_ops,
        text_ops=text_ops,
        bullet_ops=bullet_ops,
        link_ops=link_ops,
    )


# ---------------------------------------------------------------------------
# Tab operations
# ---------------------------------------------------------------------------

def add_tab(doc_id: str, title: str, token: str) -> str:
    r = batch_update(
        doc_id,
        [{"createDocumentTab": {"tabProperties": {"title": title}}}],
        token,
    )
    replies = r.get("replies", [])
    if replies:
        created = replies[0].get("createDocumentTab", {})
        tab_id = (
            created.get("tabId")
            or created.get("tabProperties", {}).get("tabId", "")
        )
        if tab_id:
            return tab_id
    # Some tenants still use the legacy addDocumentTab kind. Fall back.
    r = batch_update(
        doc_id,
        [{"addDocumentTab": {"tabProperties": {"title": title}}}],
        token,
    )
    replies = r.get("replies", [])
    if replies:
        added = replies[0].get("addDocumentTab", {})
        return added.get("tabId") or added.get("tabProperties", {}).get("tabId", "")
    return ""


def delete_tab(doc_id: str, tab_id: str, token: str) -> None:
    try:
        batch_update(
            doc_id,
            [{"deleteDocumentTab": {"tabId": tab_id}}],
            token,
        )
    except urllib.error.HTTPError as e:
        print(f"Warning: failed to delete tab {tab_id}: {e}", file=sys.stderr)


def clear_tab_content(doc_id: str, tab_id: str, end_idx: int, token: str) -> None:
    if end_idx <= 2:
        return
    batch_update(
        doc_id,
        [{"deleteContentRange": {
            "range": {"tabId": tab_id, "startIndex": 1, "endIndex": end_idx - 1},
        }}],
        token,
    )


def write_tab(doc_id: str, tab_id: str, built: BuiltDoc, existing_end: int, token: str) -> None:
    """Replace a tab's content with the built markdown."""
    clear_tab_content(doc_id, tab_id, existing_end, token)

    # Step 1: insert the clean text.
    batch_update(
        doc_id,
        [{"insertText": {
            "location": {"tabId": tab_id, "index": 1},
            "text": built.text,
        }}],
        token,
    )

    # Step 2: apply paragraph styles.
    para_requests = [
        {"updateParagraphStyle": {
            "range": {"tabId": tab_id, "startIndex": s, "endIndex": e},
            "paragraphStyle": {"namedStyleType": named},
            "fields": "namedStyleType",
        }}
        for s, e, named in built.para_ops
    ]

    # Step 3: apply text styles (bold/italic/code fonts).
    text_requests = [
        {"updateTextStyle": {
            "range": {"tabId": tab_id, "startIndex": s, "endIndex": e},
            "textStyle": op["style"],
            "fields": op["fields"],
        }}
        for s, e, op in built.text_ops
    ]

    # Step 4: apply link styles separately (fields="link").
    link_requests = [
        {"updateTextStyle": {
            "range": {"tabId": tab_id, "startIndex": s, "endIndex": e},
            "textStyle": {"link": {"url": url}},
            "fields": "link",
        }}
        for s, e, url in built.link_ops
    ]

    # Step 5: apply bullet lists.
    bullet_requests = [
        {"createParagraphBullets": {
            "range": {"tabId": tab_id, "startIndex": s, "endIndex": e},
            "bulletPreset": glyph,
        }}
        for s, e, glyph in built.bullet_ops
    ]

    batch_update_chunked(
        doc_id,
        para_requests + text_requests + link_requests + bullet_requests,
        token,
    )


# ---------------------------------------------------------------------------
# File discovery & planning
# ---------------------------------------------------------------------------

def extract_date(filename: str) -> str:
    m = re.search(r"(\d{4}-\d{2}-\d{2})", filename)
    return m.group(1) if m else ""


def sort_by_date_desc(files: list[Path]) -> list[Path]:
    return sorted(files, key=lambda f: extract_date(f.name) or "", reverse=True)


def discover_files(src: Path, pattern: str, explicit: str) -> list[Path]:
    if explicit:
        selected = [src / f.strip() for f in explicit.split(",") if f.strip()]
        selected = [f for f in selected if f.exists()]
    else:
        selected = list(src.glob(pattern))
    return sort_by_date_desc(selected)


def plan_actions(
    files: list[Path],
    existing_tabs: dict[str, dict],
    delete_stale: bool,
) -> dict[str, list[str]]:
    """Work out which files are new/updated/skipped and which tabs are stale."""
    local_names = {f.stem for f in files}
    actions = {"create": [], "update": [], "skip": [], "delete": []}

    for f in files:
        name = f.stem
        content = f.read_text(encoding="utf-8")
        if name not in existing_tabs:
            actions["create"].append(name)
            continue
        existing_text = tab_text(existing_tabs[name])
        if _content_equal(existing_text, content):
            actions["skip"].append(name)
        else:
            actions["update"].append(name)

    if delete_stale:
        for name in existing_tabs:
            if name not in local_names:
                actions["delete"].append(name)

    return actions


def _content_equal(remote: str, local: str) -> bool:
    """Compare by hash of normalized text.

    Remote text has styling stripped away, so an exact byte-for-byte match
    against the original markdown is impossible. Instead compare the "rendered"
    forms: strip markdown syntax from local and trailing whitespace from both.
    """
    return _normalize(remote) == _normalize(_render_plain(local))


def _render_plain(md: str) -> str:
    """Render markdown to the same plain text the doc will contain.

    This must match what `build_doc` produces in `text`, so that
    repeated pushes of an unchanged file are detected as "skip".
    """
    return build_doc(md).text


def _normalize(s: str) -> str:
    return hashlib.sha256(
        "\n".join(line.rstrip() for line in s.rstrip().splitlines()).encode()
    ).hexdigest()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Push local markdown files to a Google Doc as tabs.",
    )
    p.add_argument("--source-dir", required=True)
    p.add_argument("--token", required=True)

    doc_group = p.add_mutually_exclusive_group(required=True)
    doc_group.add_argument("--doc-id", help="Target document ID (unambiguous)")
    doc_group.add_argument("--doc-name", help="Target document name (looked up in Drive)")

    p.add_argument("--folder-id", default=None,
                   help="Scope name lookup (and auto-creation) to this Drive folder")
    p.add_argument("--pattern", default="*.md",
                   help="Glob pattern for files to include (default: *.md)")
    p.add_argument("--files", default="",
                   help="Comma-separated explicit file list (overrides --pattern)")
    p.add_argument("--force", action="store_true",
                   help="Update tabs even when content appears unchanged")
    p.add_argument("--delete-stale", action="store_true",
                   help="Delete tabs that have no matching local file")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--verbose", action="store_true")
    return p.parse_args()


def main() -> int:
    args = parse_args()

    src = Path(args.source_dir)
    if not src.is_dir():
        print(f"Error: {args.source_dir} not found", file=sys.stderr)
        return 1

    files = discover_files(src, args.pattern, args.files)
    if not files:
        print(f"[PUSH] No files matching {args.pattern!r} in {src}.")
        return 0

    if args.verbose:
        print(f"[PUSH] Found {len(files)} file(s):")
        for f in files:
            print(f"  {f.name}")

    # Resolve target document.
    doc_id, created = resolve_doc(args)
    if created and args.dry_run:
        print(f"[PUSH] Would create document: {args.doc_name}")
    elif created:
        print(f"[PUSH] Created document: {args.doc_name} (id: {doc_id})")
    elif args.verbose:
        label = args.doc_id or args.doc_name
        print(f"[PUSH] Target document: {label} (id: {doc_id})")

    # Enumerate existing tabs — skipped if we just created the doc in dry-run.
    if created and args.dry_run:
        existing_tabs: dict[str, dict] = {}
    else:
        doc_data = get_doc_with_tabs(doc_id, args.token)
        existing_list = collect_tabs(doc_data.get("tabs", []))
        existing_tabs = {
            t.get("tabProperties", {}).get("title", ""): t for t in existing_list
        }

    # Plan actions against the real doc state.
    actions = plan_actions(files, existing_tabs, args.delete_stale)

    # --force promotes skips to updates (explicit rewrite).
    if args.force:
        actions["update"].extend(actions["skip"])
        actions["skip"] = []

    # Dry-run: just report the plan and exit.
    if args.dry_run:
        _print_summary(actions, prefix="Would")
        if not created:
            _print_url(doc_id)
        return 0

    # Execute.
    for name in actions["delete"]:
        tab = existing_tabs[name]
        if args.verbose:
            print(f"[PUSH] Deleting stale tab: {name}")
        delete_tab(doc_id, tab["tabProperties"]["tabId"], args.token)

    for name in actions["update"]:
        tab = existing_tabs[name]
        md_file = next(f for f in files if f.stem == name)
        if args.verbose:
            print(f"[PUSH] Updating: {name}")
        built = build_doc(md_file.read_text(encoding="utf-8"))
        write_tab(
            doc_id,
            tab["tabProperties"]["tabId"],
            built,
            tab_end_index(tab),
            args.token,
        )

    for name in actions["create"]:
        md_file = next(f for f in files if f.stem == name)
        if args.verbose:
            print(f"[PUSH] Creating tab: {name}")
        tab_id = add_tab(doc_id, name, args.token)
        if not tab_id:
            print(f"Error: failed to create tab '{name}'", file=sys.stderr)
            continue
        # Re-fetch to get accurate end index for the fresh tab.
        fresh = get_doc_with_tabs(doc_id, args.token)
        new_tab = next(
            (t for t in collect_tabs(fresh.get("tabs", []))
             if t.get("tabProperties", {}).get("tabId") == tab_id),
            None,
        )
        if not new_tab:
            print(f"Warning: created tab '{name}' but couldn't locate it", file=sys.stderr)
            continue
        built = build_doc(md_file.read_text(encoding="utf-8"))
        write_tab(doc_id, tab_id, built, tab_end_index(new_tab), args.token)

    _print_summary(actions, prefix="")
    _print_url(doc_id)
    return 0


def _print_summary(actions: dict[str, list[str]], prefix: str) -> None:
    parts = [
        f"{prefix + ' ' if prefix else ''}New: {len(actions['create'])}",
        f"Updated: {len(actions['update'])}",
        f"Skipped: {len(actions['skip'])}",
    ]
    if actions["delete"]:
        parts.append(f"Deleted: {len(actions['delete'])}")
    print("[PUSH] " + ", ".join(parts))


def _print_url(doc_id: str) -> None:
    if doc_id and not doc_id.startswith("<"):
        print(f"[PUSH] URL: https://docs.google.com/document/d/{doc_id}/edit")


if __name__ == "__main__":
    sys.exit(main())

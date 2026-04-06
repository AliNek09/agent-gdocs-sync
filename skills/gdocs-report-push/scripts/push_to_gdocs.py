#!/usr/bin/env python3
"""Push local markdown reports to a Google Doc as tabs.

Simple logic:
1. Find doc by name (never delete, never recreate)
2. Check which tabs already exist
3. Add only NEW files as new tabs
4. Tab name = file stem (e.g. REPORT-2026-04-02)
5. Files sorted by date in filename (newest first)
6. --force updates changed tabs

Usage:
  python3 push_to_gdocs.py --source-dir docs/reports --doc-name "My Reports" --token TOKEN
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path


def api_request(url: str, token: str, method: str = "GET", body: dict | None = None) -> dict:
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        error_body = e.read().decode() if e.fp else ""
        print(f"Error: API {method} {url} -> {e.code}: {error_body}", file=sys.stderr)
        raise


def find_document(name: str, token: str) -> str | None:
    q = urllib.request.quote(f"name='{name}' and mimeType='application/vnd.google-apps.document' and trashed=false")
    r = api_request(f"https://www.googleapis.com/drive/v3/files?q={q}&fields=files(id,name)", token)
    return r["files"][0]["id"] if r.get("files") else None


def create_document(name: str, token: str) -> str:
    r = api_request("https://www.googleapis.com/drive/v3/files", token, "POST",
                    {"name": name, "mimeType": "application/vnd.google-apps.document"})
    return r["id"]


def get_doc_with_tabs(doc_id: str, token: str) -> dict:
    return api_request(f"https://docs.googleapis.com/v1/documents/{doc_id}?includeTabsContent=true", token)


def batch_update(doc_id: str, requests: list[dict], token: str) -> dict:
    return api_request(f"https://docs.googleapis.com/v1/documents/{doc_id}:batchUpdate", token, "POST",
                       {"requests": requests})


def collect_tabs(tabs: list[dict]) -> list[dict]:
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


def add_tab(doc_id: str, title: str, token: str) -> str:
    r = batch_update(doc_id, [{"addDocumentTab": {"tabProperties": {"title": title}}}], token)
    replies = r.get("replies", [])
    if replies:
        a = replies[0].get("addDocumentTab", {})
        return a.get("tabId", "") or a.get("tabProperties", {}).get("tabId", "")
    return ""


def clear_tab(doc_id: str, tab_id: str, end_idx: int, token: str) -> None:
    if end_idx <= 2:
        return
    batch_update(doc_id, [{"deleteContentRange": {"range": {"tabId": tab_id, "startIndex": 1, "endIndex": end_idx - 1}}}], token)


def insert_in_tab(doc_id: str, tab_id: str, text: str, token: str) -> None:
    if not text.strip():
        return
    batch_update(doc_id, [{"insertText": {"location": {"tabId": tab_id, "index": 1}, "text": text}}], token)


def apply_styles(doc_id: str, tab_id: str, text: str, token: str) -> None:
    requests: list[dict] = []
    ci = 1
    style_map = {1: "HEADING_1", 2: "HEADING_2", 3: "HEADING_3", 4: "HEADING_4", 5: "HEADING_5", 6: "HEADING_6"}
    for line in text.split("\n"):
        ll = len(line) + 1
        hm = re.match(r"^(#{1,6})\s+", line)
        if hm:
            requests.append({"updateParagraphStyle": {
                "range": {"tabId": tab_id, "startIndex": ci, "endIndex": ci + ll},
                "paragraphStyle": {"namedStyleType": style_map.get(len(hm.group(1)), "HEADING_1")},
                "fields": "namedStyleType"}})
        for m in re.finditer(r"\*\*(.+?)\*\*", line):
            requests.append({"updateTextStyle": {
                "range": {"tabId": tab_id, "startIndex": ci + m.start(), "endIndex": ci + m.end()},
                "textStyle": {"bold": True}, "fields": "bold"}})
        ci += ll
    if requests:
        for i in range(0, len(requests), 50):
            batch_update(doc_id, requests[i:i + 50], token)


def write_tab(doc_id: str, tab_id: str, content: str, end_idx: int, token: str) -> None:
    clear_tab(doc_id, tab_id, end_idx, token)
    insert_in_tab(doc_id, tab_id, content, token)
    try:
        apply_styles(doc_id, tab_id, content, token)
    except Exception as e:
        print(f"Warning: formatting failed: {e}", file=sys.stderr)


def extract_date(filename: str) -> str:
    """Extract date from filename like REPORT-2026-04-02.md -> 2026-04-02"""
    m = re.search(r"(\d{4}-\d{2}-\d{2})", filename)
    return m.group(1) if m else ""


def sort_by_date_desc(files: list[Path]) -> list[Path]:
    """Sort files by date in filename, newest first. Files without dates go last."""
    def key(f: Path) -> str:
        d = extract_date(f.name)
        # Invert date for descending sort (newest first)
        # Files without date get empty string -> sorted last
        return d if d else ""
    return sorted(files, key=key, reverse=True)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--source-dir", required=True)
    p.add_argument("--doc-name", required=True)
    p.add_argument("--token", required=True)
    p.add_argument("--force", action="store_true", help="Update changed tabs too")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--verbose", action="store_true")
    p.add_argument("--files", default="")
    args = p.parse_args()

    src = Path(args.source_dir)
    if not src.is_dir():
        print(f"Error: {args.source_dir} not found", file=sys.stderr)
        return 1

    # Collect files sorted by date in filename (newest first)
    if args.files:
        md_files = [src / f.strip() for f in args.files.split(",") if (src / f.strip()).exists()]
        md_files = sort_by_date_desc(md_files)
    else:
        md_files = sort_by_date_desc(list(src.glob("*.md")))

    if not md_files:
        print("[PUSH] No .md files found.")
        return 0

    if args.verbose:
        print(f"[PUSH] Found {len(md_files)} file(s):")
        for f in md_files:
            print(f"  {f.name}")

    if args.dry_run:
        for f in md_files:
            print(f"[PUSH] Would push: {f.name} -> tab '{f.stem}'")
        return 0

    # Find or create document (NEVER delete existing)
    doc_id = find_document(args.doc_name, args.token)
    if doc_id:
        if args.verbose:
            print(f"[PUSH] Found doc: {args.doc_name} (id: {doc_id})")
    else:
        doc_id = create_document(args.doc_name, args.token)
        print(f"[PUSH] Created doc: {args.doc_name} (id: {doc_id})")

    # Get existing tabs
    doc_data = get_doc_with_tabs(doc_id, args.token)
    existing = collect_tabs(doc_data.get("tabs", []))
    tab_map: dict[str, dict] = {}
    for t in existing:
        title = t.get("tabProperties", {}).get("title", "")
        tab_map[title] = t

    new_count = 0
    updated_count = 0
    skipped_count = 0

    for md_file in md_files:
        name = md_file.stem
        content = md_file.read_text(encoding="utf-8")

        if name in tab_map:
            # Tab exists
            if not args.force:
                if args.verbose:
                    print(f"[PUSH] Skipping (exists): {name}")
                skipped_count += 1
                continue

            # --force: update if content changed
            et = tab_map[name]
            if hashlib.md5(tab_text(et).encode()).hexdigest() == hashlib.md5(content.encode()).hexdigest():
                if args.verbose:
                    print(f"[PUSH] Skipping (unchanged): {name}")
                skipped_count += 1
                continue

            tid = et["tabProperties"]["tabId"]
            if args.verbose:
                print(f"[PUSH] Updating: {name}")
            write_tab(doc_id, tid, content, tab_end_index(et), args.token)
            updated_count += 1
        else:
            # New tab
            if args.verbose:
                print(f"[PUSH] Creating tab: {name}")
            tid = add_tab(doc_id, name, args.token)
            if not tid:
                print(f"Error: failed to create tab '{name}'", file=sys.stderr)
                continue
            fresh = get_doc_with_tabs(doc_id, args.token)
            for t in collect_tabs(fresh.get("tabs", [])):
                if t["tabProperties"]["tabId"] == tid:
                    write_tab(doc_id, tid, content, tab_end_index(t), args.token)
                    break
            new_count += 1

    url = f"https://docs.google.com/document/d/{doc_id}/edit"
    print(f"[PUSH] New: {new_count}, Updated: {updated_count}, Skipped: {skipped_count}")
    print(f"[PUSH] URL: {url}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

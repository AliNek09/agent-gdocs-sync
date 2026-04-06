#!/usr/bin/env python3
"""Parse a Google Docs JSON and sync to local markdown files.

Supports both tabs-based documents (each tab → separate .md file) and
single-page documents (entire doc → one .md file).

Reads JSON from stdin. For each tab:
  - If tab title contains a completion marker → delete corresponding local .md file
  - Otherwise → convert tab content to markdown and save

Usage:
  echo "$JSON" | python3 parse_and_sync.py --output-dir docs/ [--force] [--dry-run] [--verbose] [--completed-markers "✅,DONE"]
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


def clean_title(title: str, markers: list[str] | None = None) -> str:
    """Convert tab/document title to a safe filename (without extension)."""
    cleaned = title
    if markers:
        for m in markers:
            cleaned = cleaned.replace(m, "")
    cleaned = cleaned.strip()
    # Replace non-alphanumeric chars (except hyphens, underscores, dots) with underscores
    cleaned = re.sub(r"[^\w\-.]", "_", cleaned)
    # Collapse multiple underscores
    cleaned = re.sub(r"_+", "_", cleaned)
    # Strip leading/trailing underscores
    cleaned = cleaned.strip("_")
    return cleaned


def extract_text_run(text_run: dict) -> str:
    """Convert a textRun element to markdown-formatted text."""
    content = text_run.get("content", "")
    if not content or content == "\n":
        return content

    style = text_run.get("textStyle", {})
    text = content

    # Don't apply formatting to whitespace-only strings
    stripped = text.strip()
    if not stripped:
        return text

    leading = text[: len(text) - len(text.lstrip())]
    trailing = text[len(text.rstrip()) :]
    inner = stripped

    # Check for monospace font (code)
    font_family = style.get("weightedFontFamily", {}).get("fontFamily", "")
    is_code = font_family in ("Courier New", "Consolas", "monospace", "Source Code Pro")

    # Links
    link = style.get("link", {}).get("url")

    if is_code and not link:
        return f"{leading}`{inner}`{trailing}"

    # Bold + italic
    is_bold = style.get("bold", False)
    is_italic = style.get("italic", False)

    if is_bold and is_italic:
        inner = f"***{inner}***"
    elif is_bold:
        inner = f"**{inner}**"
    elif is_italic:
        inner = f"*{inner}*"

    if link:
        inner = f"[{inner}]({link})"

    return f"{leading}{inner}{trailing}"


def get_heading_prefix(named_style: str) -> str:
    """Map Google Docs named style to markdown heading prefix."""
    mapping = {
        "HEADING_1": "# ",
        "HEADING_2": "## ",
        "HEADING_3": "### ",
        "HEADING_4": "#### ",
        "HEADING_5": "##### ",
        "HEADING_6": "###### ",
    }
    return mapping.get(named_style, "")


def convert_paragraph(paragraph: dict, list_state: dict) -> tuple[str, bool]:
    """Convert a single paragraph element to markdown."""
    para_style = paragraph.get("paragraphStyle", {})
    named_style = para_style.get("namedStyleType", "NORMAL_TEXT")

    elements = paragraph.get("elements", [])
    text_parts = []
    is_all_code = True

    for elem in elements:
        text_run = elem.get("textRun")
        if text_run:
            style = text_run.get("textStyle", {})
            font = style.get("weightedFontFamily", {}).get("fontFamily", "")
            content = text_run.get("content", "")
            if content.strip() and font not in (
                "Courier New", "Consolas", "monospace", "Source Code Pro",
            ):
                is_all_code = False
            text_parts.append(extract_text_run(text_run))
        elif elem.get("inlineObjectElement"):
            text_parts.append("[image]")
            is_all_code = False

    line = "".join(text_parts).rstrip("\n")

    # Handle bullet/list items
    bullet = paragraph.get("bullet")
    if bullet:
        nesting = bullet.get("nestingLevel", 0)
        indent = "  " * nesting
        list_id = bullet.get("listId", "")

        if list_id not in list_state:
            list_state[list_id] = {}
        if nesting not in list_state[list_id]:
            list_state[list_id][nesting] = 0
        list_state[list_id][nesting] += 1

        prefix = f"{indent}- "
        return f"{prefix}{line}", is_all_code

    # Heading
    heading = get_heading_prefix(named_style)
    if heading:
        return f"{heading}{line}", False

    return line, is_all_code


def convert_table(table: dict) -> str:
    """Convert a table element to markdown table format."""
    rows = table.get("tableRows", [])
    if not rows:
        return ""

    md_rows: list[list[str]] = []
    for row in rows:
        cells = row.get("tableCells", [])
        cell_texts: list[str] = []
        for cell in cells:
            cell_content: list[str] = []
            for content_elem in cell.get("content", []):
                para = content_elem.get("paragraph")
                if para:
                    elements = para.get("elements", [])
                    parts = [
                        extract_text_run(e["textRun"])
                        for e in elements
                        if "textRun" in e
                    ]
                    cell_content.append("".join(parts).strip())
            cell_texts.append(" ".join(cell_content))
        md_rows.append(cell_texts)

    if not md_rows:
        return ""

    # Normalize column count
    max_cols = max(len(r) for r in md_rows)
    for r in md_rows:
        while len(r) < max_cols:
            r.append("")

    lines: list[str] = []
    # Header row
    lines.append("| " + " | ".join(md_rows[0]) + " |")
    # Separator
    lines.append("| " + " | ".join("---" for _ in range(max_cols)) + " |")
    # Data rows
    for row in md_rows[1:]:
        lines.append("| " + " | ".join(row) + " |")

    return "\n".join(lines)


def convert_tab_to_markdown(tab: dict) -> str:
    """Convert a Google Docs tab to markdown content."""
    doc_tab = tab.get("documentTab", {})
    body = doc_tab.get("body", {})
    content_elements = body.get("content", [])

    lines: list[str] = []
    list_state: dict = {}
    in_code_block = False
    code_block_lines: list[str] = []

    for elem in content_elements:
        paragraph = elem.get("paragraph")
        table = elem.get("table")

        if table:
            # Flush any pending code block
            if in_code_block:
                lines.append("```")
                lines.extend(code_block_lines)
                lines.append("```")
                code_block_lines = []
                in_code_block = False
            lines.append(convert_table(table))
            lines.append("")
            continue

        if not paragraph:
            continue

        line, is_all_code = convert_paragraph(paragraph, list_state)

        # Handle consecutive monospace paragraphs as fenced code blocks
        if is_all_code and line.strip():
            # Strip inline code backticks since we'll fence it
            clean = re.sub(r"^`|`$", "", line.strip().strip("`"))
            if not in_code_block:
                in_code_block = True
                code_block_lines = []
            code_block_lines.append(clean)
            continue

        if in_code_block:
            lines.append("```")
            lines.extend(code_block_lines)
            lines.append("```")
            code_block_lines = []
            in_code_block = False

        lines.append(line)

    # Flush trailing code block
    if in_code_block:
        lines.append("```")
        lines.extend(code_block_lines)
        lines.append("```")

    return "\n".join(lines).strip() + "\n"


def collect_tabs(tabs: list[dict]) -> list[dict]:
    """Recursively collect all tabs including childTabs."""
    result: list[dict] = []
    for tab in tabs:
        result.append(tab)
        child_tabs = tab.get("childTabs", [])
        if child_tabs:
            result.extend(collect_tabs(child_tabs))
    return result


def parse_markers(markers_str: str) -> list[str]:
    """Parse comma-separated completion markers string."""
    return [m.strip() for m in markers_str.split(",") if m.strip()]


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Sync Google Docs tabs to local markdown files",
    )
    parser.add_argument(
        "--output-dir", required=True, help="Directory for markdown files",
    )
    parser.add_argument(
        "--force", action="store_true", help="Re-download all tabs",
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Preview without writing",
    )
    parser.add_argument(
        "--verbose", action="store_true", help="Verbose output",
    )
    parser.add_argument(
        "--completed-markers", default="✅",
        help="Comma-separated completion markers (default: ✅)",
    )
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    markers = parse_markers(args.completed_markers)

    # Read JSON from stdin
    try:
        doc = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error: invalid JSON input: {e}", file=sys.stderr)
        return 1

    tabs = doc.get("tabs", [])
    all_tabs = collect_tabs(tabs)
    doc_title = doc.get("title", "document")

    # Single-doc mode: if only 1 tab, use the document title as filename
    single_doc_mode = len(all_tabs) == 1

    if args.verbose:
        mode = "single-doc" if single_doc_mode else "multi-tab"
        print(f"[SYNC] Found {len(all_tabs)} tab(s) — {mode} mode")

    new_count = 0
    deleted_count = 0
    skipped_count = 0

    for tab in all_tabs:
        props = tab.get("tabProperties", {})
        title = props.get("title", "Untitled")

        # In single-doc mode, use document title for filename
        display_title = doc_title if single_doc_mode else title
        filename = clean_title(display_title, markers) + ".md"
        filepath = output_dir / filename

        # Check for completion marker
        if any(m in title for m in markers):
            if filepath.exists():
                if args.verbose:
                    print(f"[SYNC] Deleting (completed): {filename}")
                if not args.dry_run:
                    filepath.unlink()
                deleted_count += 1
            else:
                if args.verbose:
                    print(f"[SYNC] Already gone (completed): {filename}")
            continue

        # Check if file already exists (skip unless --force)
        if filepath.exists() and not args.force:
            if args.verbose:
                print(f"[SYNC] Skipping (exists): {filename}")
            skipped_count += 1
            continue

        # Convert and write
        if args.verbose:
            action = "Overwriting" if filepath.exists() else "Creating"
            print(f"[SYNC] {action}: {filename}")

        markdown = convert_tab_to_markdown(tab)

        if not args.dry_run:
            output_dir.mkdir(parents=True, exist_ok=True)
            filepath.write_text(markdown, encoding="utf-8")

        new_count += 1

    print(f"[SYNC] New: {new_count}, Deleted: {deleted_count}, Skipped: {skipped_count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

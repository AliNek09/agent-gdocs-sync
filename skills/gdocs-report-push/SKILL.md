---
name: gdocs-report-push
description: >-
  Push local markdown files to a tabs-based Google Doc. Each .md file becomes a
  separate tab. Creates the document automatically if it doesn't exist. Existing
  tabs are updated with --force. Use when user wants to upload reports to Google Docs,
  push markdown files, export reports, or sync local content to Google Docs.
allowed-tools: Bash Read Write Edit Glob Grep
metadata:
  openclaw:
    requires:
      bins: [gcloud, python3]
---

# Google Docs Report Push

Pushes local markdown files to a Google Doc as tabs. Reverse of `gdocs-md-sync`.

- Each `.md` file in the source directory becomes a **tab** in the Google Doc
- If the document doesn't exist, it's created automatically
- Existing tabs are updated (with `--force`), new files create new tabs
- Files removed locally are NOT deleted from the doc (archive behavior)

## Prerequisites

Google Cloud CLI must be installed and authenticated with Drive access:

```bash
gcloud auth login --enable-gdrive-access
```

Verify with:

```bash
gcloud auth print-access-token
```

See `<SKILL_DIR>/references/setup-guide.md` for detailed setup instructions.

## First-Time Setup

Run the config wizard to create `.gdocs-report-push.conf` in your project root:

```bash
bash <SKILL_DIR>/scripts/init-config.sh
```

Then edit `.gdocs-report-push.conf` and set your `DOC_NAME`.

## Commands

### Push reports (default)

```bash
bash <SKILL_DIR>/scripts/push.sh
```

### Dry run (preview what would be pushed)

```bash
bash <SKILL_DIR>/scripts/push.sh --dry-run
```

### Force update all tabs (overwrite even if unchanged)

```bash
bash <SKILL_DIR>/scripts/push.sh --force
```

### Push specific files only

```bash
bash <SKILL_DIR>/scripts/push.sh --files "report-2026-04-01.md,report-2026-04-02.md"
```

### Verbose output

```bash
bash <SKILL_DIR>/scripts/push.sh --verbose
```

## Configuration

The `.gdocs-report-push.conf` file in your project root supports these fields:

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `DOC_NAME` | Yes | — | Name of the Google Doc (created if it doesn't exist) |
| `SOURCE_DIR` | No | `docs/reports` | Source directory with `.md` files (relative to repo root) |
| `FOLDER_ID` | No | — | Google Drive folder ID to create doc in (empty = My Drive root) |
| `FILE_PATTERN` | No | `*.md` | Glob pattern for files to include |

## Output

Prints a summary after push:

```
[PUSH] New: 3, Updated: 1, Skipped: 2
[PUSH] URL: https://docs.google.com/document/d/1abc.../edit
```

## How It Works

1. Searches Google Drive for a document with the configured name
2. If not found, creates a new document
3. Reads all matching files from the source directory
4. For each file:
   - If a tab with matching name exists → skips (or updates with `--force`)
   - If no matching tab → creates a new tab
5. Converts markdown to Google Docs formatting (headings, bold, italic, code, tables, lists)

---
name: gdocs-report-push
description: >-
  Push local markdown files to Google Docs as tabs. Supports multiple folder-to-doc
  mappings: each folder pushes to its own Google Doc. Ad-hoc overrides let you push
  files from any folder to any doc. Creates documents automatically if they don't exist.
  Use when user wants to upload reports, push docs, export markdown, or sync content
  to Google Docs.
allowed-tools: Bash Read Write Edit Glob Grep
metadata:
  openclaw:
    requires:
      bins: [gcloud, python3]
---

# Google Docs Report Push

Pushes local markdown files to Google Docs as tabs. Supports multiple folder→doc mappings for large projects with separate documentation areas.

- Each `.md` file in a source directory becomes a **tab** in the mapped Google Doc
- Multiple folders can map to different Google Docs
- Ad-hoc overrides let you push files from any folder to any doc
- Documents are created automatically if they don't exist
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

Then edit `.gdocs-report-push.conf` and configure your mappings.

## Configuration

The `.gdocs-report-push.conf` supports folder→doc mappings:

```bash
# Each mapping: "source_dir|doc_name"
PUSH_MAPPINGS=(
  "docs/api|API Documentation"
  "docs/frontend|Frontend Specs"
  "docs/reports|Weekly Reports"
)
FILE_PATTERN="*.md"
```

Or use the simple single-mapping mode:

```bash
DOC_NAME="My Reports"
SOURCE_DIR="docs/reports"
```

## Commands

### Push all mappings

```bash
bash <SKILL_DIR>/scripts/push.sh
```

### Push a single mapping (by source folder)

```bash
bash <SKILL_DIR>/scripts/push.sh --mapping docs/api
```

### Ad-hoc push (any folder → any doc)

```bash
bash <SKILL_DIR>/scripts/push.sh --source-dir docs/api --doc-name "Other Doc"
```

### Push specific files to a specific doc

```bash
bash <SKILL_DIR>/scripts/push.sh --source-dir docs/api --doc-name "Other Doc" --files "spec.md,endpoints.md"
```

### Dry run / Force / Verbose

```bash
bash <SKILL_DIR>/scripts/push.sh --dry-run
bash <SKILL_DIR>/scripts/push.sh --force
bash <SKILL_DIR>/scripts/push.sh --verbose
```

## Output

Prints a summary per mapping:

```
[gdocs-push] Pushing docs/api → "API Documentation"
[PUSH] New: 3, Updated: 1, Skipped: 2
[PUSH] URL: https://docs.google.com/document/d/1abc.../edit
[gdocs-push] Pushing docs/frontend → "Frontend Specs"
[PUSH] New: 1, Updated: 0, Skipped: 5
[PUSH] URL: https://docs.google.com/document/d/2def.../edit
```

## How It Works

1. Reads folder→doc mappings from config
2. For each mapping, searches Google Drive for the named document
3. If not found, creates a new document
4. Reads all matching `.md` files from the source directory
5. For each file:
   - If a tab with matching name exists → skips (or updates with `--force`)
   - If no matching tab → creates a new tab
6. Converts markdown to Google Docs formatting (headings, bold, italic, code, tables, lists)

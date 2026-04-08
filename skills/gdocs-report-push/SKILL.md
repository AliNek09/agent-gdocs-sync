---
name: gdocs-report-push
description: >-
  Push local markdown files to Google Docs as tabs. Supports multiple folder-to-doc
  mappings so large projects can route different documentation areas to different
  Google Docs. Ad-hoc overrides let you push any folder to any doc without touching
  config. True sync mode with stale-tab deletion, direct doc-id addressing, and
  folder-scoped lookup for ambiguous doc names. Use when user wants to upload reports,
  push markdown to Google Docs, sync documentation, or export local docs.
allowed-tools: Bash Read Write Edit Glob Grep
metadata:
  openclaw:
    requires:
      bins: [gcloud, python3]
---

# Google Docs Report Push

Pushes local markdown files to Google Docs as tabs. Every `.md` file becomes a tab whose title is the file stem.

## What it does

- **Create** a tab for each new local file
- **Update** a tab when its content differs from local (with `--force` or when local differs from remote)
- **Skip** tabs whose content already matches (detected via hash of the rendered text)
- **Delete** stale tabs that no longer have a local counterpart (only when `--delete-stale` is set — default is archive-safe)
- **Auto-create** the target document if it doesn't exist (unless addressing by `--doc-id`)

## Markdown support

The converter strips markdown syntax characters and applies Google Docs styling on the correct ranges, so `# Heading` shows up as a real heading and `**bold**` as real bold text (not literal asterisks in the document).

Supported:
- Headings (`#` through `######`)
- **Bold** (`**text**` / `__text__`)
- *Italic* (`*text*` / `_text_`, snake_case not treated as italic)
- `Inline code` (backticks) — rendered in a monospace font
- Fenced code blocks (```` ``` ````)
- Bullet lists (`-`, `*`, `+`)
- Numbered lists (`1.`, `2.`, ...)
- Links (`[text](url)`)

Not supported: tables, images, blockquotes, nested list reformatting. These pass through as plain text.

## Prerequisites

Google Cloud CLI installed and authenticated with Drive access:

```bash
gcloud auth login --enable-gdrive-access
```

Verify with:

```bash
gcloud auth print-access-token
```

See `<SKILL_DIR>/references/setup-guide.md` for detailed setup instructions.

## First-Time Setup (optional — ad-hoc mode works without config)

Run the config wizard to create `.gdocs-report-push.conf` in your project root:

```bash
bash <SKILL_DIR>/scripts/init-config.sh
```

Then edit the file and configure your mappings.

## Configuration

The config file uses a `PUSH_MAPPINGS` array. Each entry is pipe-separated:

```bash
# "source_dir | doc_name | folder_id | doc_id"
# folder_id and doc_id are optional.

PUSH_MAPPINGS=(
  "docs/api|API Documentation"                  # by name, My Drive root
  "docs/api|API Documentation|0AFolderID"       # by name, scoped to folder
  "docs/api||0AFolderID|1DocID"                 # by id, name ignored
)

FILE_PATTERN="*.md"
```

Legacy single-mapping mode also works:

```bash
DOC_NAME="My Reports"
SOURCE_DIR="docs/reports"
FOLDER_ID=""   # optional
DOC_ID=""      # optional
```

## Commands

### Push every mapping

```bash
bash <SKILL_DIR>/scripts/push.sh
```

### Push one mapping (by source folder)

```bash
bash <SKILL_DIR>/scripts/push.sh --mapping docs/api
```

### Ad-hoc push — no config file needed

```bash
# Push to a doc found by name
bash <SKILL_DIR>/scripts/push.sh --source-dir docs/api --doc-name "API Docs"

# Push to a specific doc by ID (unambiguous, no lookup)
bash <SKILL_DIR>/scripts/push.sh --source-dir docs/api --doc-id 1aBcDeF...

# Scope the name lookup to a Drive folder
bash <SKILL_DIR>/scripts/push.sh --source-dir docs/api --doc-name "API Docs" --folder-id 0AFolderID
```

### True sync — delete stale tabs

```bash
bash <SKILL_DIR>/scripts/push.sh --delete-stale
```

### Dry run — diff local vs remote, report the plan

```bash
bash <SKILL_DIR>/scripts/push.sh --dry-run --verbose
```

Reports:

```
[PUSH] Would New: 2, Updated: 1, Skipped: 3
[PUSH] URL: https://docs.google.com/document/d/.../edit
```

With `--delete-stale`, stale tabs show up as `Deleted` in the plan.

### Force update tabs even if content looks unchanged

```bash
bash <SKILL_DIR>/scripts/push.sh --force
```

### Push specific files only

```bash
bash <SKILL_DIR>/scripts/push.sh --source-dir docs/api --doc-name "API Docs" --files "spec.md,endpoints.md"
```

## Ambiguity and safety

- If multiple Google Docs share the same name, the push fails fast with a list of candidate IDs — it does not silently write to the wrong one. Disambiguate with `--doc-id` or `--folder-id`.
- Tabs are never deleted without `--delete-stale`. Removing a local file leaves its tab in the doc by default.
- Network errors, rate limits (429) and transient 5xx responses are automatically retried with exponential backoff.

## How It Works

1. Discover local files matching `FILE_PATTERN` (or the explicit `--files` list)
2. Resolve the target document (by ID, or by name, optionally scoped to a folder)
3. Fetch the current doc state (existing tabs and their content)
4. Compute a plan: `create`, `update`, `skip`, `delete` for each tab
5. With `--dry-run`, stop here and print the plan
6. Otherwise execute the plan: delete stale tabs, update existing ones, create new ones
7. Report the summary and the document URL

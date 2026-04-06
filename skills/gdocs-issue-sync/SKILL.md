---
name: gdocs-issue-sync
description: >-
  Sync bug/task issues from a tabs-based Google Doc to local markdown files.
  Downloads new tabs as .md files, deletes files for completed tabs (marked with
  completion emoji in title). Use when user asks to sync issues, check for new bugs,
  pull tasks from Google Doc, setup issue sync cron, or download latest issues.
allowed-tools: Bash Read Write Edit Glob Grep
metadata:
  openclaw:
    requires:
      bins: [gcloud, python3, curl]
---

# Google Docs Issue Sync

Syncs bug/task issues from a tabs-based Google Doc to local markdown files.

- **New tabs** → downloaded as `.md` files
- **Completed tabs** (emoji marker in title, e.g. ✅) → local `.md` deleted

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

Run the config wizard to create `.gdocs-issue-sync.conf` in your project root:

```bash
bash <SKILL_DIR>/scripts/init-config.sh
```

Then edit `.gdocs-issue-sync.conf` and set your `DOC_ID`.

## Commands

### Manual sync (default)

```bash
bash <SKILL_DIR>/scripts/sync.sh
```

### Dry run (preview actions without writing)

```bash
bash <SKILL_DIR>/scripts/sync.sh --dry-run
```

### Force re-download all tabs

```bash
bash <SKILL_DIR>/scripts/sync.sh --force
```

### Verbose output

```bash
bash <SKILL_DIR>/scripts/sync.sh --verbose
```

## Cron Setup

### Install daily sync (system crontab)

```bash
bash <SKILL_DIR>/scripts/setup-cron.sh --install
```

### Custom schedule

```bash
bash <SKILL_DIR>/scripts/setup-cron.sh --install --schedule "0 */6 * * *"
```

### Check status / Remove

```bash
bash <SKILL_DIR>/scripts/setup-cron.sh --status
bash <SKILL_DIR>/scripts/setup-cron.sh --remove
```

## Configuration

The `.gdocs-issue-sync.conf` file in your project root supports these fields:

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `DOC_ID` | Yes | — | Google Doc ID from the document URL |
| `COMPLETED_MARKERS` | No | `✅` | Comma-separated markers that indicate completed tabs |
| `OUTPUT_DIR` | No | `docs/issues` | Output directory relative to repo root |

## Output

Files are written to the configured output directory. The sync prints a summary:

```
[SYNC] New: 3, Deleted: 1, Skipped: 4
```

---
name: gdocs-md-sync
description: >-
  Sync content from any Google Doc to local markdown files. For tabs-based documents,
  each tab becomes a separate .md file; for single-page docs, the whole document becomes
  one .md file. Tabs marked with completion emoji (e.g. ✅) get their local files deleted.
  Use this skill when users want to sync Google Docs content, pull document tabs as markdown,
  convert Google Docs to markdown, set up Google Docs integration, download doc content
  locally, or manage recurring doc sync via cron.
allowed-tools: Bash Read Write Edit Glob Grep
---

# Google Docs → Markdown Sync

Syncs content from any Google Doc to local markdown files.

- **Tabs-based docs**: each tab → separate `.md` file
- **Single-page docs**: entire document → one `.md` file
- **Completed tabs** (marker in title, e.g. ✅) → local `.md` deleted

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

Run the config wizard to create `.gdocs-sync.conf` in your project root:

```bash
bash <SKILL_DIR>/scripts/init-config.sh
```

Then edit `.gdocs-sync.conf` and set your `DOC_ID`.

## Commands

### Sync (default — downloads new tabs, skips existing)

```bash
bash <SKILL_DIR>/scripts/sync.sh
```

### Dry run (preview without writing)

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

### Combined flags

```bash
bash <SKILL_DIR>/scripts/sync.sh --force --verbose
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

### Check status

```bash
bash <SKILL_DIR>/scripts/setup-cron.sh --status
```

### Remove cron job

```bash
bash <SKILL_DIR>/scripts/setup-cron.sh --remove
```

## Configuration

The `.gdocs-sync.conf` file in your project root supports these fields:

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `DOC_ID` | Yes | — | Google Doc ID from the document URL |
| `COMPLETED_MARKERS` | No | `✅` | Comma-separated markers that indicate completed tabs |
| `OUTPUT_DIR` | No | `docs/gdocs-sync` | Output directory relative to repo root |

## Output

Files are written to the configured output directory. The sync prints a summary:

```
[SYNC] New: 3, Deleted: 1, Skipped: 4
```

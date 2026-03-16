# agent-gdocs-sync

Sync content from any Google Doc to local markdown files. Works with 40+ AI coding agents via the [skills.sh](https://skills.sh) ecosystem.

## Installation

```bash
npx skills add AliNek09/agent-gdocs-sync
```

Or install globally (available across all projects):

```bash
npx skills add --global AliNek09/agent-gdocs-sync
```

## Supported Agents

Works with any agent that supports [Vercel Agent Skills](https://skills.sh): Claude Code, Cursor, GitHub Copilot, Cline, Windsurf, Aider, and more.

## Setup

### 1. Install & authenticate gcloud

```bash
gcloud auth login --enable-gdrive-access
```

### 2. Create project config

Run the init wizard in your project:

```bash
bash .skills/gdocs-md-sync/scripts/init-config.sh
```

Or create `.gdocs-sync.conf` manually in your project root:

```bash
DOC_ID="your-google-doc-id-here"
COMPLETED_MARKERS="✅"
OUTPUT_DIR="docs/gdocs-sync"
```

### 3. Add to .gitignore

```bash
echo '.gdocs-sync.conf' >> .gitignore
```

## Configuration

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `DOC_ID` | Yes | — | Google Doc ID from the URL (`docs.google.com/document/d/<ID>/edit`) |
| `COMPLETED_MARKERS` | No | `✅` | Comma-separated markers for completed tabs |
| `OUTPUT_DIR` | No | `docs/gdocs-sync` | Output directory (relative to repo root) |

## Usage

Just ask your AI agent to "sync google docs" or "pull latest from google doc" — it will invoke the skill automatically.

Or run manually:

| Command | Description |
|---------|-------------|
| `sync.sh` | Download new tabs, skip existing |
| `sync.sh --force` | Re-download all tabs |
| `sync.sh --dry-run` | Preview without writing |
| `sync.sh --verbose` | Show detailed progress |
| `setup-cron.sh --install` | Add daily cron job (10:00 UTC) |
| `setup-cron.sh --install --schedule "0 */6 * * *"` | Custom cron schedule |
| `setup-cron.sh --status` | Check cron status |
| `setup-cron.sh --remove` | Remove cron job |

## How It Works

1. Fetches the Google Doc via the Docs API v1 (using your gcloud OAuth token)
2. **Tabs-based docs** (multiple tabs): each tab becomes a separate `.md` file
3. **Single-page docs** (one tab): the entire document becomes one `.md` file named after the doc title
4. Tabs with a completion marker (e.g. ✅) in the title → the corresponding local `.md` file is deleted
5. Converts headings, bold, italic, inline code, code blocks, tables, links, and lists to markdown

## Requirements

- `bash` (4.0+)
- `python3` (3.8+)
- `curl`
- `gcloud` CLI (for authentication)
- `git` (must run inside a git repository)

## License

MIT

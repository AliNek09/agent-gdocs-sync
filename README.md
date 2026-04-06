# agent-gdocs-sync

Google Docs sync skills for AI coding agents. Pull documents to markdown, push markdown to documents, track issues via tabs.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Skills

| Skill | Direction | Description |
|-------|-----------|-------------|
| **gdocs-md-sync** | Pull | Sync any Google Doc → local markdown files (tabs or single-page) |
| **gdocs-issue-sync** | Pull | Sync issue/task tabs → local markdown with completion tracking |
| **gdocs-report-push** | Push | Push local markdown files → Google Doc tabs |

## Installation

### Via skills CLI ([vercel-labs/skills](https://github.com/vercel-labs/skills))

```bash
npx skills add AliNek09/agent-gdocs-sync
```

Select which skills to install when prompted, or install all:

```bash
npx skills add AliNek09/agent-gdocs-sync --skill '*'
```

### Via ClawHub ([openclaw/clawhub](https://github.com/openclaw/clawhub))

```bash
clawhub install gdocs-md-sync
clawhub install gdocs-issue-sync
clawhub install gdocs-report-push
```

### Manual

```bash
git clone https://github.com/AliNek09/agent-gdocs-sync.git
cp -r agent-gdocs-sync/skills/gdocs-md-sync .claude/skills/
# or .agents/skills/ depending on your agent
```

## Prerequisites

- **gcloud CLI** — [Install guide](https://cloud.google.com/sdk/docs/install)
- **Python 3.8+**
- **curl**
- **git** (must run inside a git repository)

## Quick Start

### 1. Authenticate with Google

```bash
gcloud auth login --enable-gdrive-access
```

### 2. Create config for the skill you need

```bash
# For pulling any Google Doc
bash <skill-path>/gdocs-md-sync/scripts/init-config.sh

# For pulling issue tabs
bash <skill-path>/gdocs-issue-sync/scripts/init-config.sh

# For pushing markdown to a Google Doc
bash <skill-path>/gdocs-report-push/scripts/init-config.sh
```

### 3. Set your Google Doc ID / name in the generated config file

Each skill creates a config file in your project root (`.gdocs-sync.conf`, `.gdocs-issue-sync.conf`, or `.gdocs-report-push.conf`). Edit it and set the required fields.

### 4. Run

Just ask your AI agent to "sync google docs", "pull issues", or "push reports" — it will invoke the skill automatically.

Or run manually:

```bash
bash <skill-path>/gdocs-md-sync/scripts/sync.sh
bash <skill-path>/gdocs-issue-sync/scripts/sync.sh
bash <skill-path>/gdocs-report-push/scripts/push.sh
```

## Agent Compatibility

Works with any agent that supports the [Agent Skills Specification](https://agentskills.io):

Claude Code, Codex, OpenCode, Cursor, GitHub Copilot, Cline, Windsurf, Gemini CLI, Aider, Continue, Goose, Kiro, Roo, Trae, and [40+ more](https://skills.sh).

## Configuration

Each skill uses a project-root config file (gitignored by default):

| Skill | Config File | Required Field |
|-------|------------|----------------|
| gdocs-md-sync | `.gdocs-sync.conf` | `DOC_ID` |
| gdocs-issue-sync | `.gdocs-issue-sync.conf` | `DOC_ID` |
| gdocs-report-push | `.gdocs-report-push.conf` | `DOC_NAME` |

**Finding your Google Doc ID:**

```
https://docs.google.com/document/d/1aBcDeFgHiJkLmNoPqRsTuVwXyZ/edit
                                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                     This is your DOC_ID
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -m 'feat: add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

## License

[MIT](LICENSE)

# Agent Instructions

This repository contains three Google Docs skills for AI coding agents. Each skill is a self-contained directory under `skills/`.

## Available Skills

| Skill | Direction | Description |
|-------|-----------|-------------|
| `skills/gdocs-md-sync/` | Pull | Sync any Google Doc → local markdown files |
| `skills/gdocs-issue-sync/` | Pull | Sync issue/task tabs → local markdown (with completion tracking) |
| `skills/gdocs-report-push/` | Push | Push local markdown files → Google Doc tabs |

## How to Use

Each skill has a `SKILL.md` file with full usage instructions. Read the relevant `SKILL.md` for the skill you need.

All skills require:
- `gcloud` CLI installed and authenticated (`gcloud auth login --enable-gdrive-access`)
- `python3` (3.8+)
- A project-root config file created by running the skill's `scripts/init-config.sh`

## For Agent Framework Developers

Skills follow the [Agent Skills Specification](https://agentskills.io). Each `SKILL.md` contains YAML frontmatter with `name`, `description`, and optional `allowed-tools` and `metadata` fields.

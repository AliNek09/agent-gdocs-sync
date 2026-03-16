#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "Error: must run inside a git repository." >&2
  exit 1
fi

CONF_FILE="$REPO_ROOT/.gdocs-sync.conf"

# If config already exists, show it and exit
if [[ -f "$CONF_FILE" ]]; then
  echo "Configuration already exists at: $CONF_FILE"
  echo ""
  cat "$CONF_FILE"
  exit 0
fi

# Create default config
cat > "$CONF_FILE" <<'CONF'
# Google Docs → Markdown Sync configuration
# Docs: https://github.com/AliNek09/agent-gdocs-sync

# Google Doc ID (required)
# Find it in the document URL: https://docs.google.com/document/d/<DOC_ID>/edit
DOC_ID=""

# Emoji markers in tab title that indicate completed/resolved tabs
# Comma-separated for multiple markers (e.g. "✅,DONE,archived")
COMPLETED_MARKERS="✅"

# Local directory for synced markdown files (relative to repo root)
OUTPUT_DIR="docs/gdocs-sync"
CONF

echo "Created $CONF_FILE with default settings."
echo ""
echo "Next steps:"
echo "  1. Edit $CONF_FILE and set DOC_ID to your Google Doc ID"
echo "  2. Authenticate with Google: gcloud auth login --enable-gdrive-access"

# Check gcloud status
echo ""
if command -v gcloud &>/dev/null; then
  ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"
  if [[ -n "$ACCOUNT" ]]; then
    echo "gcloud: authenticated as $ACCOUNT"
  else
    echo "gcloud: installed but not authenticated"
    echo "  Run: gcloud auth login --enable-gdrive-access"
  fi
else
  echo "gcloud: not installed"
  echo "  Install: https://cloud.google.com/sdk/docs/install"
fi

# Suggest adding to .gitignore
echo ""
if [[ -f "$REPO_ROOT/.gitignore" ]]; then
  if ! grep -qF '.gdocs-sync.conf' "$REPO_ROOT/.gitignore"; then
    echo "Tip: Add .gdocs-sync.conf to your .gitignore:"
    echo "  echo '.gdocs-sync.conf' >> $REPO_ROOT/.gitignore"
  fi
else
  echo "Tip: Add .gdocs-sync.conf to your .gitignore to keep config out of version control."
fi

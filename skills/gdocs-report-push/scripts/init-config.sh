#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "Error: must run inside a git repository." >&2
  exit 1
fi

CONF_FILE="$REPO_ROOT/.gdocs-report-push.conf"

# If config already exists, show it and exit
if [[ -f "$CONF_FILE" ]]; then
  echo "Configuration already exists at: $CONF_FILE"
  echo ""
  cat "$CONF_FILE"
  exit 0
fi

# Create default config
cat > "$CONF_FILE" <<'CONF'
# Google Docs Report Push configuration
# Docs: https://github.com/AliNek09/agent-gdocs-sync

# Document name (required — will be created if it doesn't exist)
DOC_NAME=""

# Google Drive folder ID to create the doc in (empty = root of My Drive)
FOLDER_ID=""

# Local directory with .md reports (relative to repo root)
SOURCE_DIR="docs/reports"

# File pattern to include (glob)
FILE_PATTERN="*.md"
CONF

echo "Created $CONF_FILE with default settings."
echo ""
echo "Next steps:"
echo "  1. Edit $CONF_FILE and set DOC_NAME to your desired document name"
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
  if ! grep -qF '.gdocs-report-push.conf' "$REPO_ROOT/.gitignore"; then
    echo "Tip: Add .gdocs-report-push.conf to your .gitignore:"
    echo "  echo '.gdocs-report-push.conf' >> $REPO_ROOT/.gitignore"
  fi
else
  echo "Tip: Add .gdocs-report-push.conf to your .gitignore to keep config out of version control."
fi

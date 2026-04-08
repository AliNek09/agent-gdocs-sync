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

cat > "$CONF_FILE" <<'CONF'
# Google Docs Report Push configuration
# Docs: https://github.com/AliNek09/agent-gdocs-sync
#
# Each mapping links a local folder to a Google Doc.
# Format (pipe-separated, fields 3 and 4 optional):
#
#   "source_dir | doc_name | folder_id | doc_id"
#
# - source_dir: required. Local directory relative to repo root.
# - doc_name:   name of the Google Doc. Used to look it up in Drive
#               (first match wins unless folder_id disambiguates it).
# - folder_id:  optional. Drive folder ID to scope the lookup and to use
#               when auto-creating the doc. Leave empty for My Drive root.
# - doc_id:     optional. Direct document ID — unambiguous, no lookup.
#               When set, doc_name is ignored.
#
# Examples:
#   "docs/api|API Documentation"                      # by name, My Drive
#   "docs/api|API Documentation|0AFolderIDHere"       # by name, scoped folder
#   "docs/api||0AFolderIDHere|1DocIDHere"             # by ID, no name lookup

PUSH_MAPPINGS=(
  "docs/reports|My Reports"
)

# File pattern to include (glob). Used by every mapping.
FILE_PATTERN="*.md"

# --- Alternative: simple single-mapping mode ---
# Instead of PUSH_MAPPINGS, you can set one target globally:
#
# DOC_NAME="My Reports"
# SOURCE_DIR="docs/reports"
# FOLDER_ID=""
# DOC_ID=""
CONF

echo "Created $CONF_FILE with default settings."
echo ""
echo "Next steps:"
echo "  1. Edit $CONF_FILE and configure your folder → Google Doc mappings"
echo "  2. Authenticate with Google: gcloud auth login --enable-gdrive-access"
echo ""
echo "Tip: you can skip the config entirely and use ad-hoc mode:"
echo "  bash $(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")/push.sh \\"
echo "       --source-dir docs/api --doc-name 'My Doc'"

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

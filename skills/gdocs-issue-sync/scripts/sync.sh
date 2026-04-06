#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  sync.sh [--force] [--dry-run] [--verbose]

Options:
  --force      Re-download all tabs (overwrite existing files)
  --dry-run    Preview actions without writing or deleting files
  --verbose    Print detailed progress information
  -h, --help   Show this help
USAGE
}

log() {
  printf '[gdocs-issue-sync] %s\n' "$*"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "$REPO_ROOT" ]]; then
  echo "Error: must run inside a git repository." >&2
  exit 1
fi

# Source configuration from project root
CONF_FILE="$REPO_ROOT/.gdocs-issue-sync.conf"
if [[ ! -f "$CONF_FILE" ]]; then
  echo "Error: No .gdocs-issue-sync.conf found in project root ($REPO_ROOT)." >&2
  echo "" >&2
  echo "Create one by running:" >&2
  echo "  bash $SCRIPT_DIR/init-config.sh" >&2
  echo "" >&2
  echo "Or create it manually with at minimum:" >&2
  echo '  DOC_ID="your-google-doc-id"' >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$CONF_FILE"

if [[ -z "${DOC_ID:-}" ]]; then
  echo "Error: DOC_ID is empty in $CONF_FILE." >&2
  echo "" >&2
  echo "Edit the file and set DOC_ID to your Google Doc ID." >&2
  echo "You can find it in the document URL:" >&2
  echo "  https://docs.google.com/document/d/<DOC_ID>/edit" >&2
  exit 1
fi

# Defaults from config (with fallbacks)
OUTPUT_DIR="${OUTPUT_DIR:-docs/issues}"
COMPLETED_MARKERS="${COMPLETED_MARKERS:-✅}"

# Parse flags
FORCE=0
DRY_RUN=0
VERBOSE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)   FORCE=1;   shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --verbose) VERBOSE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# Get OAuth token
TOKEN="$(gcloud auth print-access-token 2>/dev/null || true)"
if [[ -z "$TOKEN" ]]; then
  echo "Error: failed to get access token." >&2
  echo "" >&2
  echo "Run the following to authenticate:" >&2
  echo "  gcloud auth login --enable-gdrive-access" >&2
  echo "" >&2
  echo "Then verify with:" >&2
  echo "  gcloud auth print-access-token" >&2
  exit 1
fi

if [[ "$VERBOSE" == "1" ]]; then
  log "Authenticated successfully"
fi

# Ensure output directory exists
OUTPUT_PATH="$REPO_ROOT/$OUTPUT_DIR"
if [[ "$DRY_RUN" == "0" ]]; then
  mkdir -p "$OUTPUT_PATH"
fi

# Fetch the Google Doc with tabs content
if [[ "$VERBOSE" == "1" ]]; then
  log "Fetching document $DOC_ID ..."
fi

DOC_JSON="$(curl -sf --max-time 30 \
  "https://docs.googleapis.com/v1/documents/${DOC_ID}?includeTabsContent=true" \
  -H "Authorization: Bearer $TOKEN")" || {
  echo "Error: failed to fetch Google Doc." >&2
  echo "Check that DOC_ID is correct and you have access." >&2
  exit 1
}

if [[ "$VERBOSE" == "1" ]]; then
  log "Document fetched successfully"
fi

# Build python flags
PY_FLAGS=("--output-dir" "$OUTPUT_PATH")
if [[ "$FORCE" == "1" ]]; then
  PY_FLAGS+=("--force")
fi
if [[ "$DRY_RUN" == "1" ]]; then
  PY_FLAGS+=("--dry-run")
fi
if [[ "$VERBOSE" == "1" ]]; then
  PY_FLAGS+=("--verbose")
fi
PY_FLAGS+=("--completed-markers" "$COMPLETED_MARKERS")

# Pipe JSON to Python parser
echo "$DOC_JSON" | python3 "$SCRIPT_DIR/parse_and_sync.py" "${PY_FLAGS[@]}"
exit $?

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  push.sh [--force] [--dry-run] [--verbose] [--files "file1.md,file2.md"]

Options:
  --force      Update tabs with changed content
  --dry-run    Preview actions without writing
  --verbose    Print detailed progress
  --files      Comma-separated list of specific files to push
  -h, --help   Show this help
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "$REPO_ROOT" ]]; then
  echo "Error: must run inside a git repository." >&2
  exit 1
fi

# Source configuration from project root
CONF_FILE="$REPO_ROOT/.gdocs-report-push.conf"
if [[ ! -f "$CONF_FILE" ]]; then
  echo "Error: No .gdocs-report-push.conf found in project root ($REPO_ROOT)." >&2
  echo "" >&2
  echo "Create one by running:" >&2
  echo "  bash $SCRIPT_DIR/init-config.sh" >&2
  echo "" >&2
  echo "Or create it manually with at minimum:" >&2
  echo '  DOC_NAME="your-document-name"' >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$CONF_FILE"

if [[ -z "${DOC_NAME:-}" ]]; then
  echo "Error: DOC_NAME is empty in $CONF_FILE." >&2
  echo "" >&2
  echo "Edit the file and set DOC_NAME to the name of your Google Doc." >&2
  exit 1
fi

# Defaults from config (with fallbacks)
SOURCE_DIR="${SOURCE_DIR:-docs/reports}"
FILE_PATTERN="${FILE_PATTERN:-*.md}"

FORCE=0
DRY_RUN=0
VERBOSE=0
FILES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)   FORCE=1;   shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --verbose) VERBOSE=1; shift ;;
    --files)   FILES="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

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
  printf '[gdocs-push] Authenticated\n'
fi

SOURCE_PATH="$REPO_ROOT/$SOURCE_DIR"
if [[ ! -d "$SOURCE_PATH" ]]; then
  echo "Error: $SOURCE_DIR not found in project root." >&2
  echo "" >&2
  echo "Create the directory or update SOURCE_DIR in $CONF_FILE." >&2
  exit 1
fi

PY_FLAGS=("--source-dir" "$SOURCE_PATH" "--doc-name" "$DOC_NAME" "--token" "$TOKEN")
[[ "$FORCE" == "1" ]] && PY_FLAGS+=("--force")
[[ "$DRY_RUN" == "1" ]] && PY_FLAGS+=("--dry-run")
[[ "$VERBOSE" == "1" ]] && PY_FLAGS+=("--verbose")
[[ -n "$FILES" ]] && PY_FLAGS+=("--files" "$FILES")

python3 "$SCRIPT_DIR/push_to_gdocs.py" "${PY_FLAGS[@]}"
exit $?

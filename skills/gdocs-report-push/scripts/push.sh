#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  push.sh [options]

Modes:
  push.sh                                   Push all configured mappings
  push.sh --mapping docs/api                Push only one mapping (by source dir)
  push.sh --source-dir X --doc-name Y       Ad-hoc push (override mappings)

Options:
  --force      Update tabs with changed content
  --dry-run    Preview actions without writing
  --verbose    Print detailed progress
  --files      Comma-separated list of specific files to push
  --mapping    Push only the mapping whose source dir matches this value
  --source-dir Ad-hoc source directory (requires --doc-name)
  --doc-name   Ad-hoc document name (requires --source-dir)
  -h, --help   Show this help
USAGE
}

log() {
  printf '[gdocs-push] %s\n' "$*"
}

run_push() {
  local src_dir="$1" doc_name="$2"
  local source_path="$REPO_ROOT/$src_dir"

  if [[ ! -d "$source_path" ]]; then
    echo "Warning: $src_dir not found, skipping." >&2
    return 0
  fi

  if [[ "$VERBOSE" == "1" ]]; then
    log "Pushing $src_dir → \"$doc_name\""
  fi

  local py_flags=("--source-dir" "$source_path" "--doc-name" "$doc_name" "--token" "$TOKEN")
  [[ "$FORCE" == "1" ]] && py_flags+=("--force")
  [[ "$DRY_RUN" == "1" ]] && py_flags+=("--dry-run")
  [[ "$VERBOSE" == "1" ]] && py_flags+=("--verbose")
  [[ -n "$FILES" ]] && py_flags+=("--files" "$FILES")

  python3 "$SCRIPT_DIR/push_to_gdocs.py" "${py_flags[@]}"
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
  exit 1
fi

# shellcheck source=/dev/null
source "$CONF_FILE"

# Parse flags
FORCE=0
DRY_RUN=0
VERBOSE=0
FILES=""
MAPPING_FILTER=""
ADHOC_SOURCE=""
ADHOC_DOC=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)      FORCE=1;          shift ;;
    --dry-run)    DRY_RUN=1;        shift ;;
    --verbose)    VERBOSE=1;        shift ;;
    --files)      FILES="$2";       shift 2 ;;
    --mapping)    MAPPING_FILTER="$2"; shift 2 ;;
    --source-dir) ADHOC_SOURCE="$2"; shift 2 ;;
    --doc-name)   ADHOC_DOC="$2";   shift 2 ;;
    -h|--help)    usage; exit 0 ;;
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

# --- Ad-hoc mode: --source-dir + --doc-name override everything ---
if [[ -n "$ADHOC_SOURCE" && -n "$ADHOC_DOC" ]]; then
  run_push "$ADHOC_SOURCE" "$ADHOC_DOC"
  exit $?
fi

if [[ -n "$ADHOC_SOURCE" || -n "$ADHOC_DOC" ]]; then
  echo "Error: --source-dir and --doc-name must be used together." >&2
  exit 1
fi

# --- Mappings mode ---
# Support both new PUSH_MAPPINGS array and legacy single DOC_NAME+SOURCE_DIR
if [[ ${#PUSH_MAPPINGS[@]:-0} -eq 0 ]]; then
  # Legacy / simple config: single DOC_NAME + SOURCE_DIR
  if [[ -z "${DOC_NAME:-}" ]]; then
    echo "Error: No PUSH_MAPPINGS or DOC_NAME configured in $CONF_FILE." >&2
    echo "" >&2
    echo "Add mappings to your config. See:" >&2
    echo "  bash $SCRIPT_DIR/init-config.sh" >&2
    exit 1
  fi
  SOURCE_DIR="${SOURCE_DIR:-docs/reports}"
  run_push "$SOURCE_DIR" "$DOC_NAME"
  exit $?
fi

# Process each mapping
EXIT_CODE=0
MATCHED=0

for entry in "${PUSH_MAPPINGS[@]}"; do
  IFS='|' read -r src_dir doc_name _folder_id <<< "$entry"
  src_dir="$(echo "$src_dir" | xargs)"
  doc_name="$(echo "$doc_name" | xargs)"

  if [[ -z "$src_dir" || -z "$doc_name" ]]; then
    echo "Warning: invalid mapping entry '$entry', skipping." >&2
    continue
  fi

  # Filter if --mapping was specified
  if [[ -n "$MAPPING_FILTER" && "$src_dir" != "$MAPPING_FILTER" ]]; then
    continue
  fi

  MATCHED=1
  run_push "$src_dir" "$doc_name" || EXIT_CODE=$?
done

if [[ -n "$MAPPING_FILTER" && "$MATCHED" -eq 0 ]]; then
  echo "Error: no mapping found for '$MAPPING_FILTER'." >&2
  echo "" >&2
  echo "Available mappings:" >&2
  for entry in "${PUSH_MAPPINGS[@]}"; do
    IFS='|' read -r src_dir doc_name _ <<< "$entry"
    echo "  $src_dir → $doc_name" >&2
  done
  exit 1
fi

exit $EXIT_CODE

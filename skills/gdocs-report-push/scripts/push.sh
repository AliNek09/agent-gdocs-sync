#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  push.sh [options]

Modes:
  push.sh                                 Push every mapping in config
  push.sh --mapping docs/api              Push only the mapping whose source dir matches
  push.sh --source-dir X --doc-name Y     Ad-hoc push by name (no config required)
  push.sh --source-dir X --doc-id Z       Ad-hoc push by doc ID (no config required)

Options:
  --force          Update tabs even when content appears unchanged
  --delete-stale   Delete tabs that have no matching local file (true sync mode)
  --dry-run        Fetch the doc, diff against local files, print the plan — no writes
  --verbose        Print detailed progress
  --files LIST     Comma-separated file list (overrides FILE_PATTERN)
  --mapping DIR    Push only the mapping whose source dir equals DIR
  --source-dir DIR Ad-hoc source directory (pair with --doc-name or --doc-id)
  --doc-name NAME  Ad-hoc document name (looked up in Drive)
  --doc-id ID      Ad-hoc document ID (unambiguous, no lookup)
  --folder-id ID   Scope name lookup / auto-creation to a Drive folder
  -h, --help       Show this help

Mapping format in .gdocs-report-push.conf:
  PUSH_MAPPINGS=(
    "docs/api|API Docs"                              # by name
    "docs/api|API Docs|FOLDER_ID"                    # by name, scoped to folder
    "docs/api||FOLDER_ID|DOC_ID"                     # by id (name ignored)
  )

USAGE
}

log() {
  printf '[gdocs-push] %s\n' "$*"
}

# --- Global flag state (set by parse_flags) ---
FORCE=0
DRY_RUN=0
VERBOSE=0
DELETE_STALE=0
FILES=""
MAPPING_FILTER=""
ADHOC_SOURCE=""
ADHOC_DOC_NAME=""
ADHOC_DOC_ID=""
ADHOC_FOLDER_ID=""

parse_flags() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force)        FORCE=1; shift ;;
      --delete-stale) DELETE_STALE=1; shift ;;
      --dry-run)      DRY_RUN=1; shift ;;
      --verbose)      VERBOSE=1; shift ;;
      --files)        FILES="$2"; shift 2 ;;
      --mapping)      MAPPING_FILTER="$2"; shift 2 ;;
      --source-dir)   ADHOC_SOURCE="$2"; shift 2 ;;
      --doc-name)     ADHOC_DOC_NAME="$2"; shift 2 ;;
      --doc-id)       ADHOC_DOC_ID="$2"; shift 2 ;;
      --folder-id)    ADHOC_FOLDER_ID="$2"; shift 2 ;;
      -h|--help)      usage; exit 0 ;;
      *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

# run_push SRC_DIR [DOC_NAME] [FOLDER_ID] [DOC_ID]
# Empty string means "unused". Either DOC_NAME or DOC_ID must be non-empty.
run_push() {
  local src_dir="$1" doc_name="${2:-}" folder_id="${3:-}" doc_id="${4:-}"
  local source_path="$REPO_ROOT/$src_dir"

  if [[ ! -d "$source_path" ]]; then
    echo "Warning: $src_dir not found, skipping." >&2
    return 0
  fi

  if [[ -z "$doc_name" && -z "$doc_id" ]]; then
    echo "Error: mapping for $src_dir has neither doc_name nor doc_id." >&2
    return 1
  fi

  if [[ "$VERBOSE" == "1" ]]; then
    local target="${doc_id:-$doc_name}"
    log "Pushing $src_dir → \"$target\""
  fi

  local py_flags=("--source-dir" "$source_path" "--token" "$TOKEN")

  if [[ -n "$doc_id" ]]; then
    py_flags+=("--doc-id" "$doc_id")
  else
    py_flags+=("--doc-name" "$doc_name")
  fi

  [[ -n "$folder_id" ]] && py_flags+=("--folder-id" "$folder_id")
  [[ -n "${FILE_PATTERN:-}" ]] && py_flags+=("--pattern" "$FILE_PATTERN")
  [[ -n "$FILES" ]] && py_flags+=("--files" "$FILES")
  [[ "$FORCE" == "1" ]] && py_flags+=("--force")
  [[ "$DELETE_STALE" == "1" ]] && py_flags+=("--delete-stale")
  [[ "$DRY_RUN" == "1" ]] && py_flags+=("--dry-run")
  [[ "$VERBOSE" == "1" ]] && py_flags+=("--verbose")

  python3 "$SCRIPT_DIR/push_to_gdocs.py" "${py_flags[@]}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"

# Early --help check (before sourcing config so help works without setup).
for arg in "$@"; do
  case "$arg" in -h|--help) usage; exit 0 ;; esac
done

# Parse flags FIRST — ad-hoc mode must work without any config file.
parse_flags "$@"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "Error: must run inside a git repository." >&2
  exit 1
fi

# Get OAuth token (required by both modes).
TOKEN="$(gcloud auth print-access-token 2>/dev/null || true)"
if [[ -z "$TOKEN" ]]; then
  echo "Error: failed to get access token." >&2
  echo "" >&2
  echo "Run the following to authenticate:" >&2
  echo "  gcloud auth login --enable-gdrive-access" >&2
  exit 1
fi

if [[ "$VERBOSE" == "1" ]]; then
  log "Authenticated successfully"
fi

# --- Ad-hoc mode: --source-dir with --doc-name or --doc-id. No config needed. ---
if [[ -n "$ADHOC_SOURCE" ]]; then
  if [[ -z "$ADHOC_DOC_NAME" && -z "$ADHOC_DOC_ID" ]]; then
    echo "Error: --source-dir requires either --doc-name or --doc-id." >&2
    exit 1
  fi
  run_push "$ADHOC_SOURCE" "$ADHOC_DOC_NAME" "$ADHOC_FOLDER_ID" "$ADHOC_DOC_ID"
  exit $?
fi

# Catch orphan --doc-name / --doc-id (without --source-dir).
if [[ -n "$ADHOC_DOC_NAME" || -n "$ADHOC_DOC_ID" ]]; then
  echo "Error: --doc-name / --doc-id require --source-dir to know what to push." >&2
  exit 1
fi

# --- Config-driven mode: read mappings from project root. ---
CONF_FILE="$REPO_ROOT/.gdocs-report-push.conf"
if [[ ! -f "$CONF_FILE" ]]; then
  echo "Error: No .gdocs-report-push.conf found in project root ($REPO_ROOT)." >&2
  echo "" >&2
  echo "Either use ad-hoc mode:" >&2
  echo "  bash $0 --source-dir docs/api --doc-name 'My Doc'" >&2
  echo "" >&2
  echo "Or create a config:" >&2
  echo "  bash $SCRIPT_DIR/init-config.sh" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$CONF_FILE"

# Legacy single-mapping mode: DOC_NAME + SOURCE_DIR (no PUSH_MAPPINGS).
if [[ ${#PUSH_MAPPINGS[@]:-0} -eq 0 ]]; then
  if [[ -z "${DOC_NAME:-}" && -z "${DOC_ID:-}" ]]; then
    echo "Error: No PUSH_MAPPINGS, DOC_NAME, or DOC_ID configured in $CONF_FILE." >&2
    echo "" >&2
    echo "Edit the config or re-run:" >&2
    echo "  bash $SCRIPT_DIR/init-config.sh" >&2
    exit 1
  fi
  SOURCE_DIR="${SOURCE_DIR:-docs/reports}"
  run_push "$SOURCE_DIR" "${DOC_NAME:-}" "${FOLDER_ID:-}" "${DOC_ID:-}"
  exit $?
fi

# Process each mapping entry: "src|name|folder_id|doc_id" (fields 3, 4 optional).
EXIT_CODE=0
MATCHED=0

for entry in "${PUSH_MAPPINGS[@]}"; do
  IFS='|' read -r src_dir m_doc_name m_folder_id m_doc_id <<< "$entry"
  src_dir="$(echo "${src_dir:-}" | xargs)"
  m_doc_name="$(echo "${m_doc_name:-}" | xargs)"
  m_folder_id="$(echo "${m_folder_id:-}" | xargs)"
  m_doc_id="$(echo "${m_doc_id:-}" | xargs)"

  if [[ -z "$src_dir" ]]; then
    echo "Warning: mapping entry '$entry' missing source_dir, skipping." >&2
    continue
  fi
  if [[ -z "$m_doc_name" && -z "$m_doc_id" ]]; then
    echo "Warning: mapping entry '$entry' has no doc_name or doc_id, skipping." >&2
    continue
  fi

  # Filter if --mapping was specified
  if [[ -n "$MAPPING_FILTER" && "$src_dir" != "$MAPPING_FILTER" ]]; then
    continue
  fi

  MATCHED=1
  run_push "$src_dir" "$m_doc_name" "$m_folder_id" "$m_doc_id" || EXIT_CODE=$?
done

if [[ -n "$MAPPING_FILTER" && "$MATCHED" -eq 0 ]]; then
  echo "Error: no mapping found for '$MAPPING_FILTER'." >&2
  echo "" >&2
  echo "Available mappings:" >&2
  for entry in "${PUSH_MAPPINGS[@]}"; do
    IFS='|' read -r src_dir m_doc_name _ _ <<< "$entry"
    echo "  $src_dir → ${m_doc_name:-'<by id>'}" >&2
  done
  exit 1
fi

exit $EXIT_CODE

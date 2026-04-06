#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  setup-cron.sh [--install | --remove | --status] [--schedule "CRON_EXPR"]

Options:
  --install              Add sync crontab entry
  --remove               Remove the sync crontab entry
  --status               Show current crontab entry
  --schedule "EXPR"      Cron schedule expression (default: "0 10 * * *" = daily at 10:00 UTC)
  -h, --help             Show this help
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "Error: must run inside a git repository." >&2
  exit 1
fi

CRON_MARKER="# gdocs-issue-sync"
SYNC_SCRIPT="$SCRIPT_DIR/sync.sh"
SCHEDULE="0 10 * * *"
ACTION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)  ACTION="install"; shift ;;
    --remove)   ACTION="remove";  shift ;;
    --status)   ACTION="status";  shift ;;
    --schedule) SCHEDULE="$2";    shift 2 ;;
    -h|--help)  usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$ACTION" ]]; then
  echo "Error: specify --install, --remove, or --status" >&2
  usage >&2
  exit 1
fi

CRON_CMD="$SCHEDULE cd $REPO_ROOT && $SYNC_SCRIPT >> /tmp/gdocs-issue-sync.log 2>&1 $CRON_MARKER"

case "$ACTION" in
  install)
    # Idempotent: remove existing entry first, then add
    CURRENT="$(crontab -l 2>/dev/null || true)"
    FILTERED="$(echo "$CURRENT" | grep -v "$CRON_MARKER" || true)"
    UPDATED="$(printf '%s\n%s\n' "$FILTERED" "$CRON_CMD")"
    echo "$UPDATED" | crontab -
    echo "Cron job installed: $SCHEDULE"
    echo "  Log: /tmp/gdocs-issue-sync.log"
    ;;
  remove)
    CURRENT="$(crontab -l 2>/dev/null || true)"
    FILTERED="$(echo "$CURRENT" | grep -v "$CRON_MARKER" || true)"
    if [[ "$FILTERED" != "$CURRENT" ]]; then
      echo "$FILTERED" | crontab -
      echo "Cron job removed."
    else
      echo "No gdocs-issue-sync cron job found."
    fi
    ;;
  status)
    ENTRY="$(crontab -l 2>/dev/null | grep "$CRON_MARKER" || true)"
    if [[ -n "$ENTRY" ]]; then
      echo "Active cron entry:"
      echo "  $ENTRY"
    else
      echo "No gdocs-issue-sync cron job installed."
    fi
    ;;
esac

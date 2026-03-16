#!/usr/bin/env bash
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$TESTS_DIR")"
SCRIPT="$REPO_ROOT/skills/gdocs-md-sync/scripts/parse_and_sync.py"
INIT_SCRIPT="$REPO_ROOT/skills/gdocs-md-sync/scripts/init-config.sh"
SYNC_SCRIPT="$REPO_ROOT/skills/gdocs-md-sync/scripts/sync.sh"
FIXTURES="$TESTS_DIR/fixtures"
EXPECTED="$TESTS_DIR/expected"

PASS=0
FAIL=0
TOTAL=0

pass() {
  PASS=$((PASS + 1))
  TOTAL=$((TOTAL + 1))
  printf '  \033[32mPASS\033[0m %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  TOTAL=$((TOTAL + 1))
  printf '  \033[31mFAIL\033[0m %s\n' "$1"
  if [[ -n "${2:-}" ]]; then
    printf '       %s\n' "$2"
  fi
}

section() {
  printf '\n\033[1m%s\033[0m\n' "$1"
}

# ── Test 1: Multi-tab document ──────────────────────────────────────
section "Test 1: Multi-tab document"

TMPOUT="$(mktemp -d)"
trap 'rm -rf "$TMPOUT"' EXIT

cat "$FIXTURES/multi_tab_doc.json" | python3 "$SCRIPT" --output-dir "$TMPOUT" --force --verbose 2>&1 | head -1 | grep -q "multi-tab mode"
if [[ $? -eq 0 ]]; then
  pass "detected multi-tab mode"
else
  fail "should detect multi-tab mode"
fi

# Compare each expected file
ALL_MATCH=true
for expected_file in "$EXPECTED/multi_tab/"*.md; do
  fname="$(basename "$expected_file")"
  actual="$TMPOUT/$fname"
  if [[ ! -f "$actual" ]]; then
    fail "missing output file: $fname"
    ALL_MATCH=false
    continue
  fi
  if diff -q "$expected_file" "$actual" > /dev/null 2>&1; then
    pass "output matches: $fname"
  else
    fail "output differs: $fname" "$(diff "$expected_file" "$actual" | head -5)"
    ALL_MATCH=false
  fi
done

# ✅ tab should NOT produce a file
if [[ ! -f "$TMPOUT/Old_Feature.md" ]]; then
  pass "completed tab (✅) did not create file"
else
  fail "completed tab (✅) should not create file"
fi

rm -rf "$TMPOUT"
TMPOUT="$(mktemp -d)"

# ── Test 2: Single-tab document ─────────────────────────────────────
section "Test 2: Single-tab document"

cat "$FIXTURES/single_tab_doc.json" | python3 "$SCRIPT" --output-dir "$TMPOUT" --force --verbose 2>&1 | head -1 | grep -q "single-doc mode"
if [[ $? -eq 0 ]]; then
  pass "detected single-doc mode"
else
  fail "should detect single-doc mode"
fi

if [[ -f "$TMPOUT/Project_Notes.md" ]]; then
  if diff -q "$EXPECTED/single_tab/Project_Notes.md" "$TMPOUT/Project_Notes.md" > /dev/null 2>&1; then
    pass "output matches: Project_Notes.md"
  else
    fail "output differs: Project_Notes.md" "$(diff "$EXPECTED/single_tab/Project_Notes.md" "$TMPOUT/Project_Notes.md" | head -5)"
  fi
else
  fail "missing output file: Project_Notes.md (single-doc mode should use doc title)"
fi

rm -rf "$TMPOUT"
TMPOUT="$(mktemp -d)"

# ── Test 3: Rich content ────────────────────────────────────────────
section "Test 3: Rich content (headings, bold, italic, code, tables, links, lists)"

cat "$FIXTURES/rich_content_doc.json" | python3 "$SCRIPT" --output-dir "$TMPOUT" --force

if diff -q "$EXPECTED/rich_content/Rich_Content_Demo.md" "$TMPOUT/Rich_Content_Demo.md" > /dev/null 2>&1; then
  pass "rich content output matches"
else
  fail "rich content output differs" "$(diff "$EXPECTED/rich_content/Rich_Content_Demo.md" "$TMPOUT/Rich_Content_Demo.md" | head -10)"
fi

rm -rf "$TMPOUT"
TMPOUT="$(mktemp -d)"

# ── Test 4: Empty document ──────────────────────────────────────────
section "Test 4: Empty document"

cat "$FIXTURES/empty_doc.json" | python3 "$SCRIPT" --output-dir "$TMPOUT" --force

if [[ -f "$TMPOUT/Empty_Document.md" ]]; then
  pass "empty doc produced output file"
  # File should be essentially empty (just a newline)
  SIZE="$(wc -c < "$TMPOUT/Empty_Document.md" | tr -d ' ')"
  if [[ "$SIZE" -le 2 ]]; then
    pass "empty doc file is minimal ($SIZE bytes)"
  else
    fail "empty doc file should be minimal, got $SIZE bytes"
  fi
else
  fail "empty doc should produce Empty_Document.md"
fi

rm -rf "$TMPOUT"
TMPOUT="$(mktemp -d)"

# ── Test 5: Dry-run flag ────────────────────────────────────────────
section "Test 5: Dry-run flag"

cat "$FIXTURES/single_tab_doc.json" | python3 "$SCRIPT" --output-dir "$TMPOUT" --dry-run

FILE_COUNT="$(find "$TMPOUT" -name '*.md' | wc -l | tr -d ' ')"
if [[ "$FILE_COUNT" -eq 0 ]]; then
  pass "dry-run wrote no files"
else
  fail "dry-run should write no files, found $FILE_COUNT"
fi

rm -rf "$TMPOUT"
TMPOUT="$(mktemp -d)"

# ── Test 6: Force flag (overwrite) ──────────────────────────────────
section "Test 6: Force flag (overwrite existing)"

echo "old content" > "$TMPOUT/Project_Notes.md"
cat "$FIXTURES/single_tab_doc.json" | python3 "$SCRIPT" --output-dir "$TMPOUT" --force

if grep -q "old content" "$TMPOUT/Project_Notes.md" 2>/dev/null; then
  fail "force should overwrite existing file"
else
  pass "force overwrote existing file"
fi

rm -rf "$TMPOUT"
TMPOUT="$(mktemp -d)"

# ── Test 7: Custom completed markers ────────────────────────────────
section "Test 7: Custom completed markers"

# Pre-create a file matching the ✅ tab
echo "should be deleted" > "$TMPOUT/Old_Feature.md"
cat "$FIXTURES/multi_tab_doc.json" | python3 "$SCRIPT" --output-dir "$TMPOUT" --force --completed-markers "✅"

if [[ -f "$TMPOUT/Old_Feature.md" ]]; then
  fail "file for ✅ tab should be deleted"
else
  pass "completed tab file deleted with custom marker"
fi

rm -rf "$TMPOUT"
TMPOUT="$(mktemp -d)"

# Test with comma-separated markers
echo "should be deleted" > "$TMPOUT/Old_Feature.md"
cat "$FIXTURES/multi_tab_doc.json" | python3 "$SCRIPT" --output-dir "$TMPOUT" --force --completed-markers "✅,DONE"

if [[ -f "$TMPOUT/Old_Feature.md" ]]; then
  fail "file for ✅ tab should be deleted with multi-marker"
else
  pass "completed tab file deleted with comma-separated markers"
fi

rm -rf "$TMPOUT"
TMPOUT="$(mktemp -d)"

# ── Test 8: Tab deletion flow ───────────────────────────────────────
section "Test 8: Tab deletion flow"

# Pre-create a file that matches the completed tab title
echo "old data" > "$TMPOUT/Old_Feature.md"
OUTPUT="$(cat "$FIXTURES/multi_tab_doc.json" | python3 "$SCRIPT" --output-dir "$TMPOUT" --force --verbose 2>&1)"

if echo "$OUTPUT" | grep -q "Deleting (completed): Old_Feature.md"; then
  pass "verbose output shows deletion"
else
  fail "verbose output should show deletion"
fi

if [[ ! -f "$TMPOUT/Old_Feature.md" ]]; then
  pass "completed tab file was deleted"
else
  fail "completed tab file should be deleted"
fi

rm -rf "$TMPOUT"
TMPOUT="$(mktemp -d)"

# ── Test 9: init-config.sh ──────────────────────────────────────────
section "Test 9: init-config.sh"

# Create a temp git repo
TMPREPO="$(mktemp -d)"
(cd "$TMPREPO" && git init -q)

(cd "$TMPREPO" && bash "$INIT_SCRIPT") > /dev/null 2>&1

if [[ -f "$TMPREPO/.gdocs-sync.conf" ]]; then
  pass "init-config created .gdocs-sync.conf"
else
  fail "init-config should create .gdocs-sync.conf"
fi

# Check DOC_ID is empty
if grep -q 'DOC_ID=""' "$TMPREPO/.gdocs-sync.conf"; then
  pass "DOC_ID is empty in generated config"
else
  fail "DOC_ID should be empty in generated config"
fi

# Run again — should show existing config and exit 0
(cd "$TMPREPO" && bash "$INIT_SCRIPT") > /dev/null 2>&1
if [[ $? -eq 0 ]]; then
  pass "re-run exits 0 with existing config"
else
  fail "re-run should exit 0 with existing config"
fi

rm -rf "$TMPREPO"

# ── Test 10: sync.sh error handling ─────────────────────────────────
section "Test 10: sync.sh error handling"

# Test missing config
TMPREPO="$(mktemp -d)"
(cd "$TMPREPO" && git init -q)

OUTPUT="$(cd "$TMPREPO" && bash "$SYNC_SCRIPT" 2>&1 || true)"
EXIT_CODE=0
(cd "$TMPREPO" && bash "$SYNC_SCRIPT" > /dev/null 2>&1) || EXIT_CODE=$?

if [[ "$EXIT_CODE" -ne 0 ]]; then
  pass "sync.sh exits non-zero without config"
else
  fail "sync.sh should exit non-zero without config"
fi

if echo "$OUTPUT" | grep -qi "no .gdocs-sync.conf"; then
  pass "sync.sh shows missing config error"
else
  fail "sync.sh should mention missing .gdocs-sync.conf"
fi

# Test empty DOC_ID
cat > "$TMPREPO/.gdocs-sync.conf" <<'EOF'
DOC_ID=""
OUTPUT_DIR="docs"
EOF

OUTPUT="$(cd "$TMPREPO" && bash "$SYNC_SCRIPT" 2>&1 || true)"
EXIT_CODE=0
(cd "$TMPREPO" && bash "$SYNC_SCRIPT" > /dev/null 2>&1) || EXIT_CODE=$?

if [[ "$EXIT_CODE" -ne 0 ]]; then
  pass "sync.sh exits non-zero with empty DOC_ID"
else
  fail "sync.sh should exit non-zero with empty DOC_ID"
fi

if echo "$OUTPUT" | grep -qi "DOC_ID is empty"; then
  pass "sync.sh shows empty DOC_ID error"
else
  fail "sync.sh should mention DOC_ID is empty"
fi

rm -rf "$TMPREPO"

# ── Summary ─────────────────────────────────────────────────────────
printf '\n\033[1m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\033[0m\n'
printf '\033[1mResults: %d passed, %d failed, %d total\033[0m\n' "$PASS" "$FAIL" "$TOTAL"

if [[ "$FAIL" -gt 0 ]]; then
  printf '\033[31mSome tests failed!\033[0m\n'
  exit 1
else
  printf '\033[32mAll tests passed!\033[0m\n'
  exit 0
fi

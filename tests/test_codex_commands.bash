#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — /codex-stop + /codex-history command doc tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
STOP="${PLUGIN_DIR}/commands/codex-stop.md"
HISTORY="${PLUGIN_DIR}/commands/codex-history.md"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

[ -f "${STOP}" ]    || { echo "ERROR: ${STOP} missing";    exit 1; }
[ -f "${HISTORY}" ] || { echo "ERROR: ${HISTORY} missing"; exit 1; }

echo "=== test_stop_frontmatter_complete ==="
if grep -q '^name: codex-stop' "${STOP}" \
  && grep -q '^description:'   "${STOP}"; then
  assert_pass "test_stop_frontmatter_complete"
else
  assert_fail "test_stop_frontmatter_complete" "missing name/description"
fi

echo "=== test_stop_checks_marker_file ==="
if grep -q '\.codex-delegation-active' "${STOP}"; then
  assert_pass "test_stop_checks_marker_file"
else
  assert_fail "test_stop_checks_marker_file" "no marker file reference"
fi

echo "=== test_stop_confirms_deactivation ==="
if grep -qiE 'deactivat|restored|direct mode' "${STOP}"; then
  assert_pass "test_stop_confirms_deactivation"
else
  assert_fail "test_stop_confirms_deactivation" "no deactivation confirmation message"
fi

echo "=== test_stop_preserves_idx ==="
if grep -q 'conversations.idx' "${STOP}" \
  && grep -qiE 'preserv|retain|not delet' "${STOP}"; then
  assert_pass "test_stop_preserves_idx"
else
  assert_fail "test_stop_preserves_idx" "no idx preservation note"
fi

echo "=== test_history_frontmatter_complete ==="
if grep -q '^name: codex-history' "${HISTORY}" \
  && grep -q '^description:'      "${HISTORY}"; then
  assert_pass "test_history_frontmatter_complete"
else
  assert_fail "test_history_frontmatter_complete" "missing name/description"
fi

echo "=== test_history_documents_pruning_and_idx ==="
if grep -qE '30[[:space:]]*days?' "${HISTORY}" \
  && grep -q '.codex/conversations.idx' "${HISTORY}" \
  && grep -q 'CLAUDE_PROJECT_DIR' "${HISTORY}" \
  && grep -q 'tail -n 20' "${HISTORY}"; then
  assert_pass "test_history_documents_pruning_and_idx"
else
  assert_fail "test_history_documents_pruning_and_idx" "missing pruning, idx, or 20-row cap guidance"
fi

echo "=== test_history_mentions_native_history ==="
if grep -q '~/.code/history.jsonl' "${HISTORY}" \
  && grep -q '~/.codex/history.jsonl' "${HISTORY}"; then
  assert_pass "test_history_mentions_native_history"
else
  assert_fail "test_history_mentions_native_history" "native history references missing"
fi

echo "=== test_history_prune_awk_logic_works ==="
TMP="$(mktemp -d)"
IDX="${TMP}/conversations.idx"
OLD1="2020-01-01T00:00:00Z"
OLD2="2020-06-15T12:34:56Z"
OLD3="2021-12-31T23:59:59Z"
NOW="$(date -u +%FT%TZ)"
RECENT1="$(date -u -v-2d +%FT%TZ 2>/dev/null || date -u -d '2 days ago' +%FT%TZ)"
{
  printf '%s\t%s\t%s\t%s\n' "$OLD1"    "00000000-0000-0000-0000-000000000001" "codex-0-aaaaaaaa" "old task 1"
  printf '%s\t%s\t%s\t%s\n' "$OLD2"    "00000000-0000-0000-0000-000000000002" "codex-0-bbbbbbbb" "old task 2"
  printf '%s\t%s\t%s\t%s\n' "$OLD3"    "00000000-0000-0000-0000-000000000003" "codex-0-cccccccc" "old task 3"
  printf '%s\t%s\t%s\t%s\n' "$RECENT1" "00000000-0000-0000-0000-000000000004" "codex-0-dddddddd" "recent task 1"
  printf '%s\t%s\t%s\t%s\n' "$NOW"     "00000000-0000-0000-0000-000000000005" "codex-0-eeeeeeee" "recent task 2"
} > "${IDX}"

CUTOFF="$(date -u -v-30d +%FT%TZ 2>/dev/null || date -u -d '30 days ago' +%FT%TZ)"
awk -v cutoff="$CUTOFF" -F'\t' '$1 >= cutoff' "$IDX" > "$IDX.tmp" && mv "$IDX.tmp" "$IDX"

post_count=$(wc -l < "${IDX}" | tr -d ' ')
if [ "${post_count}" -eq 2 ] \
   && ! grep -q 'old task' "${IDX}" \
   && grep -q 'recent task 1' "${IDX}" \
   && grep -q 'recent task 2' "${IDX}"; then
  assert_pass "test_history_prune_awk_logic_works"
else
  assert_fail "test_history_prune_awk_logic_works" "post_count=${post_count} idx=$(cat "${IDX}")"
fi
rm -rf "${TMP}"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

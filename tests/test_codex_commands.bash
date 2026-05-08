#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — /codex-stop + /codex-history command wrapper + skill tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
STOP="${PLUGIN_DIR}/commands/codex-stop.md"
HISTORY="${PLUGIN_DIR}/commands/codex-history.md"
STOP_SKILL="${PLUGIN_DIR}/skills/codex-stop/SKILL.md"
HISTORY_SKILL="${PLUGIN_DIR}/skills/codex-history/SKILL.md"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

[ -f "${STOP}" ]    || { echo "ERROR: ${STOP} missing";    exit 1; }
[ -f "${HISTORY}" ] || { echo "ERROR: ${HISTORY} missing"; exit 1; }
[ -f "${STOP_SKILL}" ]    || { echo "ERROR: ${STOP_SKILL} missing"; exit 1; }
[ -f "${HISTORY_SKILL}" ] || { echo "ERROR: ${HISTORY_SKILL} missing"; exit 1; }

echo "=== test_stop_frontmatter_complete ==="
if grep -q '^name: codex-stop' "${STOP}" \
  && grep -q '^description:'   "${STOP}"; then
  assert_pass "test_stop_frontmatter_complete"
else
  assert_fail "test_stop_frontmatter_complete" "missing name/description"
fi

echo "=== test_stop_is_thin_wrapper ==="
if grep -q 'skills/codex-stop/SKILL.md' "${STOP}" \
  && grep -qiE 'wrapper|source of truth|slash-command UX' "${STOP}"; then
  assert_pass "test_stop_is_thin_wrapper"
else
  assert_fail "test_stop_is_thin_wrapper" "stop command does not point to the canonical skill"
fi

echo "=== test_stop_skill_is_canonical ==="
if grep -q '^name: codex-stop' "${STOP_SKILL}" \
  && grep -q '\.codex-delegation-active' "${STOP_SKILL}" \
  && grep -qiE 'deactivat|restored|direct mode' "${STOP_SKILL}" \
  && grep -q 'conversations.idx' "${STOP_SKILL}" \
  && grep -qiE 'preserv|retain|not delet' "${STOP_SKILL}"; then
  assert_pass "test_stop_skill_is_canonical"
else
  assert_fail "test_stop_skill_is_canonical" "canonical stop workflow missing from skill file"
fi

echo "=== test_history_frontmatter_complete ==="
if grep -q '^name: codex-history' "${HISTORY}" \
  && grep -q '^description:'      "${HISTORY}"; then
  assert_pass "test_history_frontmatter_complete"
else
  assert_fail "test_history_frontmatter_complete" "missing name/description"
fi

echo "=== test_history_is_thin_wrapper ==="
if grep -q 'skills/codex-history/SKILL.md' "${HISTORY}" \
  && grep -qiE 'wrapper|source of truth|slash-command UX' "${HISTORY}"; then
  assert_pass "test_history_is_thin_wrapper"
else
  assert_fail "test_history_is_thin_wrapper" "history command does not point to the canonical skill"
fi

echo "=== test_history_skill_documents_pruning_and_idx ==="
if grep -qE '30[[:space:]]*days?' "${HISTORY_SKILL}" \
  && grep -q '.codex/conversations.idx' "${HISTORY_SKILL}" \
  && grep -q 'CLAUDE_PROJECT_DIR' "${HISTORY_SKILL}" \
  && grep -q 'tail -n 20' "${HISTORY_SKILL}" \
  && grep -q '~/.code/history.jsonl' "${HISTORY_SKILL}" \
  && grep -q '~/.codex/history.jsonl' "${HISTORY_SKILL}"; then
  assert_pass "test_history_skill_documents_pruning_and_idx"
else
  assert_fail "test_history_skill_documents_pruning_and_idx" "canonical history workflow missing from skill file"
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

echo "=== test_codex_skill_bridges_point_to_canonical_skill ==="
if grep -q 'skills/codex-stop/SKILL.md' "${STOP}" \
  && grep -q 'skills/codex-history/SKILL.md' "${HISTORY}" \
  && grep -qiE 'source of truth|thin slash-command wrapper' "${STOP}" \
  && grep -qiE 'source of truth|thin slash-command wrapper' "${HISTORY}"; then
  assert_pass "test_codex_skill_bridges_point_to_canonical_skill"
else
  assert_fail "test_codex_skill_bridges_point_to_canonical_skill" "wrapper text missing"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

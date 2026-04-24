#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — /forge-stop + /forge-history command doc tests
# =============================================================================
# Structural tests on the command markdown files (no live Forge invocation).
# Asserts that both commands have the expected frontmatter, procedure
# contracts, and key behavioral guarantees so Claude Code can render them
# and Claude can follow them.  Plus one test exercises the history pruning
# logic inline.

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
STOP="${PLUGIN_DIR}/commands/forge-stop.md"
HISTORY="${PLUGIN_DIR}/commands/forge-history.md"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

[ -f "${STOP}" ]    || { echo "ERROR: ${STOP} missing";    exit 1; }
[ -f "${HISTORY}" ] || { echo "ERROR: ${HISTORY} missing"; exit 1; }

# -----------------------------------------------------------------------------
echo "=== test_stop_frontmatter_complete ==="
if grep -q '^name: forge-stop' "${STOP}" \
  && grep -q '^description:'   "${STOP}"; then
  assert_pass "test_stop_frontmatter_complete"
else
  assert_fail "test_stop_frontmatter_complete" "missing name/description"
fi

# -----------------------------------------------------------------------------
echo "=== test_stop_checks_marker_file ==="
if grep -q '\.forge-delegation-active' "${STOP}"; then
  assert_pass "test_stop_checks_marker_file"
else
  assert_fail "test_stop_checks_marker_file" "no marker file reference"
fi

# -----------------------------------------------------------------------------
echo "=== test_stop_confirms_deactivation ==="
if grep -qiE 'deactivat|restored|direct mode' "${STOP}"; then
  assert_pass "test_stop_confirms_deactivation"
else
  assert_fail "test_stop_confirms_deactivation" "no deactivation confirmation message"
fi

# -----------------------------------------------------------------------------
echo "=== test_stop_preserves_idx ==="
# The command must note that conversations.idx is preserved (not deleted).
if grep -q 'conversations.idx' "${STOP}" \
  && grep -qiE 'preserv|retain|not delet' "${STOP}"; then
  assert_pass "test_stop_preserves_idx"
else
  assert_fail "test_stop_preserves_idx" "no idx preservation note"
fi

# -----------------------------------------------------------------------------
echo "=== test_history_frontmatter_complete ==="
if grep -q '^name: forge-history' "${HISTORY}" \
  && grep -q '^description:'      "${HISTORY}"; then
  assert_pass "test_history_frontmatter_complete"
else
  assert_fail "test_history_frontmatter_complete" "missing name/description"
fi

# -----------------------------------------------------------------------------
echo "=== test_history_documents_30_day_pruning ==="
# REPLAY-03: history must prune entries older than 30 days each call.
if grep -qE '30[[:space:]]*days?'       "${HISTORY}" \
  && grep -q 'conversations.idx'         "${HISTORY}"; then
  assert_pass "test_history_documents_30_day_pruning"
else
  assert_fail "test_history_documents_30_day_pruning" "no 30-day pruning or idx reference"
fi

# -----------------------------------------------------------------------------
echo "=== test_history_reads_project_idx ==="
if grep -q 'CLAUDE_PROJECT_DIR' "${HISTORY}" \
  && grep -q '.forge/conversations.idx' "${HISTORY}"; then
  assert_pass "test_history_reads_project_idx"
else
  assert_fail "test_history_reads_project_idx" "does not reference project idx"
fi

# -----------------------------------------------------------------------------
echo "=== test_history_tail_20_cap ==="
if grep -qE 'tail -n 20|last 20'  "${HISTORY}"; then
  assert_pass "test_history_tail_20_cap"
else
  assert_fail "test_history_tail_20_cap" "no 20-row cap documented"
fi

# -----------------------------------------------------------------------------
echo "=== test_history_prune_awk_logic_works ==="
# Stand up a fake idx with mixed-age rows and execute the pruning snippet
# from the doc. Asserts post-prune only has rows within the cutoff window.
TMP="$(mktemp -d)"
IDX="${TMP}/conversations.idx"
# 3 old (> 30 days), 2 recent.
OLD1="2020-01-01T00:00:00Z"
OLD2="2020-06-15T12:34:56Z"
OLD3="2021-12-31T23:59:59Z"
NOW="$(date -u +%FT%TZ)"
RECENT1="$(date -u -v-2d +%FT%TZ 2>/dev/null || date -u -d '2 days ago' +%FT%TZ)"
{
  printf '%s\t%s\t%s\t%s\n' "$OLD1"    "00000000-0000-0000-0000-000000000001" "sidekick-0-aaaaaaaa" "old task 1"
  printf '%s\t%s\t%s\t%s\n' "$OLD2"    "00000000-0000-0000-0000-000000000002" "sidekick-0-bbbbbbbb" "old task 2"
  printf '%s\t%s\t%s\t%s\n' "$OLD3"    "00000000-0000-0000-0000-000000000003" "sidekick-0-cccccccc" "old task 3"
  printf '%s\t%s\t%s\t%s\n' "$RECENT1" "00000000-0000-0000-0000-000000000004" "sidekick-0-dddddddd" "recent task 1"
  printf '%s\t%s\t%s\t%s\n' "$NOW"     "00000000-0000-0000-0000-000000000005" "sidekick-0-eeeeeeee" "recent task 2"
} > "${IDX}"

# Execute the exact pruning logic documented in forge-history.md.
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

# -----------------------------------------------------------------------------
echo "=== test_commands_registered_in_plugin_json ==="
MANIFEST="${PLUGIN_DIR}/.claude-plugin/plugin.json"
# "commands": "./commands/" directory-style reference
if grep -q '"commands"[[:space:]]*:[[:space:]]*"\./commands/"' "${MANIFEST}"; then
  assert_pass "test_commands_registered_in_plugin_json"
else
  assert_fail "test_commands_registered_in_plugin_json" "commands directory not registered"
fi

# -----------------------------------------------------------------------------
echo "=== test_output_style_registered_in_plugin_json ==="
if grep -q '"outputStyles"[[:space:]]*:[[:space:]]*"\./output-styles/"' "${MANIFEST}"; then
  assert_pass "test_output_style_registered_in_plugin_json"
else
  assert_fail "test_output_style_registered_in_plugin_json" "outputStyles directory not registered"
fi

# -----------------------------------------------------------------------------
echo "=== test_posttooluse_hook_registered ==="
if python3 -c "
import json, sys
d=json.load(open('${MANIFEST}'))
post=d.get('hooks',{}).get('PostToolUse',[])
if not post: sys.exit(1)
ok=any('forge-progress-surface' in h.get('command','')
       for entry in post for h in entry.get('hooks',[]))
sys.exit(0 if ok else 1)
"; then
  assert_pass "test_posttooluse_hook_registered"
else
  assert_fail "test_posttooluse_hook_registered" "PostToolUse hook missing"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — hooks/forge-progress-surface.sh Tests (Phase 7)
# =============================================================================
# Covers SURF-01..05 + ACT-04 (style marker visibility).
# All tests sandbox HOME so the real marker file is never touched.

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
HOOK_FILE="${PLUGIN_DIR}/hooks/forge-progress-surface.sh"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

if [ ! -f "${HOOK_FILE}" ]; then
  echo "ERROR: ${HOOK_FILE} not found"
  exit 1
fi

HOME_SANDBOX="$(mktemp -d)"
trap 'rm -rf "${HOME_SANDBOX}"' EXIT
mkdir -p "${HOME_SANDBOX}/.claude"

run_hook() {
  local json="$1"
  HOME="${HOME_SANDBOX}" bash "${HOOK_FILE}" <<< "${json}" 2>/dev/null
}

# -----------------------------------------------------------------------------
echo "=== test_noop_when_marker_absent ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"x\""},"tool_response":{"output":"STATUS: SUCCESS\nFILES_CHANGED: [foo]\nASSUMPTIONS: []\nPATTERNS_DISCOVERED: []"}}')"
if [ -z "${_out}" ]; then
  assert_pass "test_noop_when_marker_absent"
else
  assert_fail "test_noop_when_marker_absent" "expected empty, got: '${_out}'"
fi

# Activate marker for all remaining tests.
touch "${HOME_SANDBOX}/.claude/.forge-delegation-active"

# -----------------------------------------------------------------------------
echo "=== test_noop_when_tool_not_bash ==="
_out="$(run_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x"},"tool_response":{"output":"STATUS: SUCCESS"}}')"
if [ -z "${_out}" ]; then
  assert_pass "test_noop_when_tool_not_bash"
else
  assert_fail "test_noop_when_tool_not_bash" "got: '${_out}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_noop_when_command_lacks_forge_p ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git status"},"tool_response":{"output":"nothing to commit"}}')"
if [ -z "${_out}" ]; then
  assert_pass "test_noop_when_command_lacks_forge_p"
else
  assert_fail "test_noop_when_command_lacks_forge_p" "got: '${_out}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_noop_when_output_lacks_status ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"x\""},"tool_response":{"output":"[FORGE] working...\n[FORGE] still working"}}')"
if [ -z "${_out}" ]; then
  assert_pass "test_noop_when_output_lacks_status"
else
  assert_fail "test_noop_when_output_lacks_status" "got: '${_out}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_emits_summary_when_status_block_present ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge --conversation-id 12345678-aaaa-bbbb-cccc-1234567890ab --verbose -p \"Refactor utils\""},"tool_response":{"output":"[FORGE] Reading utils.py...\n[FORGE] STATUS: SUCCESS\n[FORGE] FILES_CHANGED: [utils.py]\n[FORGE] ASSUMPTIONS: []\n[FORGE] PATTERNS_DISCOVERED: []"}}')"
_ctx="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
if echo "${_ctx}" | grep -q 'STATUS: SUCCESS' \
    && echo "${_ctx}" | grep -q 'FILES_CHANGED: \[utils.py\]' \
    && echo "${_ctx}" | grep -q '/forge:replay 12345678-aaaa-bbbb-cccc-1234567890ab' \
    && echo "${_ctx}" | grep -q '\[FORGE-SUMMARY\]'; then
  assert_pass "test_emits_summary_when_status_block_present"
else
  assert_fail "test_emits_summary_when_status_block_present" "ctx='${_ctx}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_ansi_stripped_before_status_parse ==="
# Embed ANSI color codes in the output; expect them stripped from the summary.
_ansi_output=$'\x1b[31m[FORGE] STATUS: SUCCESS\x1b[0m\n\x1b[32m[FORGE] FILES_CHANGED: [foo.py]\x1b[0m\n[FORGE] ASSUMPTIONS: []\n[FORGE] PATTERNS_DISCOVERED: []'
_json="$(jq -cn --arg o "$_ansi_output" '{tool_name:"Bash",tool_input:{command:"forge -p \"x\""},tool_response:{output:$o}}')"
_out="$(run_hook "$_json")"
_ctx="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
# Assert no raw ESC byte in the context.
if [ -n "${_ctx}" ] && ! printf '%s' "${_ctx}" | grep -q $'\x1b'; then
  assert_pass "test_ansi_stripped_before_status_parse"
else
  assert_fail "test_ansi_stripped_before_status_parse" "ctx='${_ctx}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_replay_hint_absent_when_no_conversation_id ==="
# Command with forge -p but no --conversation-id (unusual, but possible if a
# different hook or direct call slipped through). Summary should still emit,
# just without a replay hint.
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"x\""},"tool_response":{"output":"STATUS: SUCCESS\nFILES_CHANGED: []\nASSUMPTIONS: []\nPATTERNS_DISCOVERED: []"}}')"
_ctx="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
if echo "${_ctx}" | grep -q 'STATUS: SUCCESS' \
    && echo "${_ctx}" | grep -q 'no conversation-id captured'; then
  assert_pass "test_replay_hint_absent_when_no_conversation_id"
else
  assert_fail "test_replay_hint_absent_when_no_conversation_id" "ctx='${_ctx}'"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

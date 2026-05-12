#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — hooks/codex-progress-surface.sh Tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
HOOK_FILE="${PLUGIN_DIR}/hooks/codex-progress-surface.sh"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

if [ ! -f "${HOOK_FILE}" ]; then
  echo "ERROR: ${HOOK_FILE} not found"
  exit 1
fi

HOME_SANDBOX="$(mktemp -d)"
TEST_SESSION_ID="codex-test-$$"
MARKER_DIR="${HOME_SANDBOX}/.kay/sessions/${TEST_SESSION_ID}"
MARKER_FILE="${MARKER_DIR}/.kay-delegation-active"
trap 'rm -rf "${HOME_SANDBOX}"' EXIT
mkdir -p "${MARKER_DIR}"

run_hook() {
  local json="$1"
  HOME="${HOME_SANDBOX}" SIDEKICK_PROJECT_DIR="${HOME_SANDBOX}" SIDEKICK_TEST_SESSION_ID="${TEST_SESSION_ID}" bash "${HOOK_FILE}" <<< "${json}" 2>/dev/null
}

echo "=== test_noop_when_marker_absent ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"codex exec \"x\""},"tool_response":{"output":"STATUS: SUCCESS\nFILES_CHANGED: [foo]\nASSUMPTIONS: []\nPATTERNS_DISCOVERED: []"}}')"
if [ -z "${_out}" ]; then
  assert_pass "test_noop_when_marker_absent"
else
  assert_fail "test_noop_when_marker_absent" "expected empty, got: '${_out}'"
fi

touch "${MARKER_FILE}"

echo "=== test_noop_when_tool_not_bash ==="
_out="$(run_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x"},"tool_response":{"output":"STATUS: SUCCESS"}}')"
if [ -z "${_out}" ]; then
  assert_pass "test_noop_when_tool_not_bash"
else
  assert_fail "test_noop_when_tool_not_bash" "got: '${_out}'"
fi

echo "=== test_noop_when_command_lacks_codex_exec ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git status"},"tool_response":{"output":"nothing to commit"}}')"
if [ -z "${_out}" ]; then
  assert_pass "test_noop_when_command_lacks_codex_exec"
else
  assert_fail "test_noop_when_command_lacks_codex_exec" "got: '${_out}'"
fi

echo "=== test_noop_when_output_lacks_status ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"codex exec \"x\""},"tool_response":{"output":"[KAY] working...\n[KAY] still working"}}')"
if [ -z "${_out}" ]; then
  assert_pass "test_noop_when_output_lacks_status"
else
  assert_fail "test_noop_when_output_lacks_status" "got: '${_out}'"
fi

echo "=== test_emits_summary_when_status_block_present ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"codex exec --full-auto \"Refactor utils\""},"tool_response":{"output":"[KAY] Reading utils.py...\n[KAY] STATUS: SUCCESS\n[KAY] FILES_CHANGED: [utils.py]\n[KAY] ASSUMPTIONS: []\n[KAY] PATTERNS_DISCOVERED: []"}}')"
_ctx="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
if echo "${_ctx}" | grep -q 'STATUS: SUCCESS' \
    && echo "${_ctx}" | grep -q 'FILES_CHANGED: \[utils.py\]' \
    && echo "${_ctx}" | grep -q '/kay-stop' \
    && echo "${_ctx}" | grep -q '\[KAY-SUMMARY\]' \
    && echo "${_ctx}" | grep -q '\[UNTRUSTED\]'; then
  assert_pass "test_emits_summary_when_status_block_present"
else
  assert_fail "test_emits_summary_when_status_block_present" "ctx='${_ctx}'"
fi

echo "=== test_env_prefix_before_exec_is_handled ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"FOO=bar codex exec --full-auto \"Refactor utils\""},"tool_response":{"output":"[KAY] STATUS: SUCCESS\n[KAY] FILES_CHANGED: [utils.py]\n[KAY] ASSUMPTIONS: []\n[KAY] PATTERNS_DISCOVERED: []"}}')"
_ctx="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
if echo "${_ctx}" | grep -q 'STATUS: SUCCESS' \
    && echo "${_ctx}" | grep -q '/kay-stop' \
    && echo "${_ctx}" | grep -q '\[KAY-SUMMARY\]'; then
  assert_pass "test_env_prefix_before_exec_is_handled"
else
  assert_fail "test_env_prefix_before_exec_is_handled" "ctx='${_ctx}'"
fi

echo "=== test_ansi_stripped_before_status_parse ==="
_ansi_output=$'\x1b[31m[KAY] STATUS: SUCCESS\x1b[0m\n\x1b[32m[KAY] FILES_CHANGED: [foo.py]\x1b[0m\n[KAY] ASSUMPTIONS: []\n[KAY] PATTERNS_DISCOVERED: []'
_json="$(jq -cn --arg o "$_ansi_output" '{tool_name:"Bash",tool_input:{command:"codex exec \"x\""},tool_response:{output:$o}}')"
_out="$(run_hook "$_json")"
_ctx="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
if [ -n "${_ctx}" ] && ! printf '%s' "${_ctx}" | grep -q $'\x1b'; then
  assert_pass "test_ansi_stripped_before_status_parse"
else
  assert_fail "test_ansi_stripped_before_status_parse" "ctx='${_ctx}'"
fi

echo "=== test_redacts_secrets ==="
_secret_output=$'STATUS: SUCCESS\nAuthorization: Bearer super-secret-token\napi_key=abc1234567890\nFILES_CHANGED: []\nASSUMPTIONS: []\nPATTERNS_DISCOVERED: []'
_json_secret="$(jq -cn --arg o "$_secret_output" '{tool_name:"Bash",tool_input:{command:"codex exec \"x\""},tool_response:{output:$o}}')"
_out="$(run_hook "$_json_secret")"
_ctx="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
if ! printf '%s' "${_ctx}" | grep -qi 'super-secret-token' \
    && ! printf '%s' "${_ctx}" | grep -qi 'abc1234567890'; then
  assert_pass "test_redacts_secrets"
else
  assert_fail "test_redacts_secrets" "ctx='${_ctx}'"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

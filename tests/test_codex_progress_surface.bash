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
KAY_MARKER_DIR="${HOME_SANDBOX}/.kay/sessions/${TEST_SESSION_ID}"
KAY_MARKER_FILE="${KAY_MARKER_DIR}/.kay-delegation-active"
CODEX_MARKER_DIR="${HOME_SANDBOX}/.codex/sessions/${TEST_SESSION_ID}"
CODEX_MARKER_FILE="${CODEX_MARKER_DIR}/.codex-delegation-active"
ACTIVE_MODE_DIR="${HOME_SANDBOX}/.sidekick/sessions/${TEST_SESSION_ID}"
trap 'rm -rf "${HOME_SANDBOX}"' EXIT
mkdir -p "${KAY_MARKER_DIR}" "${CODEX_MARKER_DIR}" "${ACTIVE_MODE_DIR}"

run_hook() {
  local json="$1"
  HOME="${HOME_SANDBOX}" SIDEKICK_PROJECT_DIR="${HOME_SANDBOX}" SIDEKICK_TEST_SESSION_ID="${TEST_SESSION_ID}" bash "${HOOK_FILE}" <<< "${json}" 2>/dev/null
}

extract_context() {
  printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // .additional_context // empty' 2>/dev/null
}

echo "=== test_noop_when_marker_absent ==="
out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"kay exec \"x\""},"tool_response":{"output":"STATUS: SUCCESS\nFILES_CHANGED: [foo]\nASSUMPTIONS: []\nPATTERNS_DISCOVERED: []"}}')"
if [ -z "${out}" ]; then
  assert_pass "test_noop_when_marker_absent"
else
  assert_fail "test_noop_when_marker_absent" "expected empty, got: '${out}'"
fi

touch "${KAY_MARKER_FILE}"
printf '%s\n' "kay" > "${ACTIVE_MODE_DIR}/active-sidekick"

echo "=== test_noop_when_tool_not_bash ==="
out="$(run_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x"},"tool_response":{"output":"STATUS: SUCCESS"}}')"
if [ -z "${out}" ]; then
  assert_pass "test_noop_when_tool_not_bash"
else
  assert_fail "test_noop_when_tool_not_bash" "got: '${out}'"
fi

echo "=== test_noop_when_command_lacks_kay_exec ==="
out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git status"},"tool_response":{"output":"nothing to commit"}}')"
if [ -z "${out}" ]; then
  assert_pass "test_noop_when_command_lacks_kay_exec"
else
  assert_fail "test_noop_when_command_lacks_kay_exec" "got: '${out}'"
fi

echo "=== test_noop_when_output_lacks_status ==="
out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"kay exec \"x\""},"tool_response":{"output":"[KAY] working...\n[KAY] still working"}}')"
if [ -z "${out}" ]; then
  assert_pass "test_noop_when_output_lacks_status"
else
  assert_fail "test_noop_when_output_lacks_status" "got: '${out}'"
fi

echo "=== test_kay_mode_emits_summary_when_status_block_present ==="
out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"kay exec --full-auto \"Refactor utils\""},"tool_response":{"output":"[KAY] Reading utils.py...\n[KAY] STATUS: SUCCESS\n[KAY] FILES_CHANGED: [utils.py]\n[KAY] ASSUMPTIONS: []\n[KAY] PATTERNS_DISCOVERED: []"}}')"
ctx="$(extract_context "${out}")"
if echo "${ctx}" | grep -q 'STATUS: SUCCESS' \
  && echo "${ctx}" | grep -q 'FILES_CHANGED: \[utils.py\]' \
  && echo "${ctx}" | grep -q '/sidekick:kay-stop' \
  && echo "${ctx}" | grep -q '\[KAY-SUMMARY\]' \
  && echo "${ctx}" | grep -q '\[UNTRUSTED\]'; then
  assert_pass "test_kay_mode_emits_summary_when_status_block_present"
else
  assert_fail "test_kay_mode_emits_summary_when_status_block_present" "ctx='${ctx}'"
fi

echo "=== test_kay_mode_accepts_safe_runner_command_shape ==="
cmd="bash /tmp/hooks/lib/sidekick-safe-runner.sh kay kay exec --full-auto 'Refactor utils'"
json_safe="$(jq -cn --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c},tool_response:{output:"[KAY] STATUS: SUCCESS\n[KAY] FILES_CHANGED: []\n[KAY] ASSUMPTIONS: []\n[KAY] PATTERNS_DISCOVERED: []"}}')"
out="$(run_hook "${json_safe}")"
ctx="$(extract_context "${out}")"
if echo "${ctx}" | grep -q '\[KAY-SUMMARY\]' \
  && echo "${ctx}" | grep -q 'STATUS: SUCCESS'; then
  assert_pass "test_kay_mode_accepts_safe_runner_command_shape"
else
  assert_fail "test_kay_mode_accepts_safe_runner_command_shape" "ctx='${ctx}'"
fi

echo "=== test_surface_caps_status_block_at_20_lines ==="
big="[KAY] STATUS: SUCCESS"
for i in $(seq 1 30); do
  big="${big}"$'\n'"[KAY] extra line ${i}"
done
big="${big}"$'\n'"[KAY] PATTERNS_DISCOVERED: []"
json_big="$(jq -cn --arg o "$big" '{tool_name:"Bash",tool_input:{command:"kay exec \"x\""},tool_response:{output:$o}}')"
out="$(run_hook "${json_big}")"
ctx="$(extract_context "${out}")"
body_lines="$(printf '%s\n' "${ctx}" | grep -c '^\[KAY-SUMMARY\] \[UNTRUSTED\] \[KAY\]' || true)"
if [ "${body_lines}" -eq 20 ]; then
  assert_pass "test_surface_caps_status_block_at_20_lines"
else
  assert_fail "test_surface_caps_status_block_at_20_lines" "body_lines=${body_lines} ctx='${ctx}'"
fi

echo "=== test_redacts_secrets ==="
secret_output=$'STATUS: SUCCESS\nAuthorization: Bearer super-secret-token\napi_key=abc1234567890\nOPENAI_API_KEY=access123\nGITHUB_TOKEN: refresh456\nANTHROPIC_API_KEY="client789"\nMY_PASSWORD=hunter2\nsecret: hidden\nFILES_CHANGED: []\nASSUMPTIONS: []\nPATTERNS_DISCOVERED: []'
json_secret="$(jq -cn --arg o "$secret_output" '{tool_name:"Bash",tool_input:{command:"kay exec \"x\""},tool_response:{output:$o}}')"
out="$(run_hook "${json_secret}")"
ctx="$(extract_context "${out}")"
if ! printf '%s' "${ctx}" | grep -qi 'super-secret-token' \
  && ! printf '%s' "${ctx}" | grep -qi 'abc1234567890' \
  && ! printf '%s' "${ctx}" | grep -Eq 'access123|refresh456|client789|hunter2|hidden'; then
  assert_pass "test_redacts_secrets"
else
  assert_fail "test_redacts_secrets" "ctx='${ctx}'"
fi

rm -f "${ACTIVE_MODE_DIR}/active-sidekick" "${KAY_MARKER_FILE}"
touch "${CODEX_MARKER_FILE}"
printf '%s\n' "codex" > "${ACTIVE_MODE_DIR}/active-sidekick"

echo "=== test_codex_mode_emits_codex_summary_and_stop_hint ==="
out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"codex exec -m gpt-5.4-mini --sandbox workspace-write \"Refactor utils\""},"tool_response":{"output":"[CODEX] STATUS: SUCCESS\n[CODEX] FILES_CHANGED: [utils.py]\n[CODEX] ASSUMPTIONS: []\n[CODEX] PATTERNS_DISCOVERED: []"}}')"
ctx="$(extract_context "${out}")"
if echo "${ctx}" | grep -q '\[CODEX-SUMMARY\]' \
  && echo "${ctx}" | grep -q 'STATUS: SUCCESS' \
  && echo "${ctx}" | grep -q '/sidekick:codex-stop'; then
  assert_pass "test_codex_mode_emits_codex_summary_and_stop_hint"
else
  assert_fail "test_codex_mode_emits_codex_summary_and_stop_hint" "ctx='${ctx}'"
fi

echo "=== test_codex_mode_accepts_safe_runner_command_shape ==="
cmd="bash /tmp/hooks/lib/sidekick-safe-runner.sh codex codex exec -m gpt-5.4-mini -c model_reasoning_effort=xhigh --sandbox workspace-write --ask-for-approval never 'Refactor utils'"
json_safe="$(jq -cn --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c},tool_response:{output:"[CODEX] STATUS: SUCCESS\n[CODEX] FILES_CHANGED: []\n[CODEX] ASSUMPTIONS: []\n[CODEX] PATTERNS_DISCOVERED: []"}}')"
out="$(run_hook "${json_safe}")"
ctx="$(extract_context "${out}")"
if echo "${ctx}" | grep -q '\[CODEX-SUMMARY\]' \
  && echo "${ctx}" | grep -q 'STATUS: SUCCESS'; then
  assert_pass "test_codex_mode_accepts_safe_runner_command_shape"
else
  assert_fail "test_codex_mode_accepts_safe_runner_command_shape" "ctx='${ctx}'"
fi

echo "=== test_cursor_kay_mode_emits_additional_context_for_shell ==="
touch "${KAY_MARKER_FILE}"
printf '%s\n' "kay" > "${ACTIVE_MODE_DIR}/active-sidekick"
rm -f "${CODEX_MARKER_FILE}"
out="$(HOME="${HOME_SANDBOX}" SIDEKICK_PROJECT_DIR="${HOME_SANDBOX}" SIDEKICK_HOOK_HOST=cursor SIDEKICK_TEST_SESSION_ID="${TEST_SESSION_ID}" \
  bash "${HOOK_FILE}" <<< '{"conversation_id":"'"${TEST_SESSION_ID}"'","tool_name":"Shell","tool_input":{"command":"kay exec --full-auto \"Refactor utils\""},"tool_response":{"output":"[KAY] STATUS: SUCCESS\n[KAY] FILES_CHANGED: [utils.py]\n[KAY] ASSUMPTIONS: []\n[KAY] PATTERNS_DISCOVERED: []"}}' 2>/dev/null)"
if printf '%s' "${out}" | jq -e '.additional_context | length > 0' >/dev/null 2>&1; then
  assert_pass "test_cursor_kay_mode_emits_additional_context_for_shell"
else
  assert_fail "test_cursor_kay_mode_emits_additional_context_for_shell" "out='${out}'"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

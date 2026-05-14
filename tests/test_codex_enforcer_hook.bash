#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — hooks/codex-delegation-enforcer.sh Tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
HOOK_FILE="${PLUGIN_DIR}/hooks/codex-delegation-enforcer.sh"

green='\033[0;32m'; red='\033[0;31m'; yellow='\033[0;33m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }
skip()        { echo -e "${yellow}SKIP${reset} $1: $2"; SKIP=$((SKIP+1)); }

if [ ! -f "${HOOK_FILE}" ]; then
  echo "ERROR: ${HOOK_FILE} not found"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not in PATH — skipping codex enforcer tests"
  exit 0
fi

HOME_SANDBOX="$(mktemp -d)"
PROJECT_SANDBOX="$(mktemp -d)"
CODEX_STUB_DIR="${HOME_SANDBOX}/bin"
TEST_SESSION_ID="codex-test-$$"
MARKER_DIR="${HOME_SANDBOX}/.kay/sessions/${TEST_SESSION_ID}"
MARKER_FILE="${MARKER_DIR}/.kay-delegation-active"
trap 'rm -rf "${HOME_SANDBOX}" "${PROJECT_SANDBOX}"' EXIT
mkdir -p "${MARKER_DIR}" "${CODEX_STUB_DIR}"

cat > "${CODEX_STUB_DIR}/kay" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "${CODEX_STUB_DIR}/kay"
ln -sf kay "${CODEX_STUB_DIR}/code"
ln -sf kay "${CODEX_STUB_DIR}/codex"
ln -sf kay "${CODEX_STUB_DIR}/coder"

STUB_PATH="${CODEX_STUB_DIR}:${PATH}"

run_hook() {
  local json="$1"
  local extra_env="${2:-}"
  if [ -n "${extra_env}" ]; then
    HOME="${HOME_SANDBOX}" SIDEKICK_PROJECT_DIR="${PROJECT_SANDBOX}" PATH="${STUB_PATH}" \
      env SIDEKICK_TEST_SESSION_ID="${TEST_SESSION_ID}" ${extra_env} bash "${HOOK_FILE}" <<< "${json}" 2>/dev/null
  else
    HOME="${HOME_SANDBOX}" SIDEKICK_PROJECT_DIR="${PROJECT_SANDBOX}" PATH="${STUB_PATH}" \
      SIDEKICK_TEST_SESSION_ID="${TEST_SESSION_ID}" \
      bash "${HOOK_FILE}" <<< "${json}" 2>/dev/null
  fi
}

echo "=== test_noop_when_marker_absent ==="
_out="$(run_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x","content":"y"}}')"
if [ -z "${_out}" ]; then
  assert_pass "test_noop_when_marker_absent"
else
  assert_fail "test_noop_when_marker_absent" "expected empty, got: '${_out}'"
fi

touch "${MARKER_FILE}"

_assert_deny_with_kay_reason() {
  local name="$1" tool_name="$2"
  local _out _dec _rsn
  _out="$(run_hook "{\"tool_name\":\"${tool_name}\",\"tool_input\":{\"file_path\":\"/tmp/x\",\"content\":\"y\"}}")"
  _dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  _rsn="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
  if [ "${_dec}" = "deny" ] && echo "${_rsn}" | grep -qi 'kay'; then
    assert_pass "${name}"
  else
    assert_fail "${name}" "dec='${_dec}' reason='${_rsn}'"
  fi
}

echo "=== test_deny_write_when_active ==="
_assert_deny_with_kay_reason "test_deny_write_when_active" "Write"

echo "=== test_deny_edit_when_active ==="
_assert_deny_with_kay_reason "test_deny_edit_when_active" "Edit"

echo "=== test_deny_notebook_edit_when_active ==="
_assert_deny_with_kay_reason "test_deny_notebook_edit_when_active" "NotebookEdit"

echo "=== test_rewrite_codex_exec_injects_full_auto_and_prefixes ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"kay exec \"Refactor utils.py\""}}' 'SIDEKICK_TEST_UUID_OVERRIDE=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
_cmd="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null)"
if [ "${_dec}" = "allow" ] \
    && echo "${_cmd}" | grep -Eq -- '^kay exec --full-auto' \
    && echo "${_cmd}" | grep -q "sed 's/\^/\[KAY\] /'" \
    && echo "${_cmd}" | grep -q "sed 's/\^/\[KAY-LOG\] /'"; then
  assert_pass "test_rewrite_codex_exec_injects_full_auto_and_prefixes"
else
  assert_fail "test_rewrite_codex_exec_injects_full_auto_and_prefixes" "dec='${_dec}' cmd='${_cmd}'"
fi

echo "=== test_rewrite_codex_exec_quotes_shell_metacharacters ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"kay exec \"Refactor utils.py; rm -rf /tmp/evil\""}}' 'SIDEKICK_TEST_UUID_OVERRIDE=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
_cmd="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null)"
if [ "${_dec}" = "allow" ] \
    && echo "${_cmd}" | grep -q "'Refactor utils.py; rm -rf /tmp/evil'"; then
  assert_pass "test_rewrite_codex_exec_quotes_shell_metacharacters"
else
  assert_fail "test_rewrite_codex_exec_quotes_shell_metacharacters" "dec='${_dec}' cmd='${_cmd}'"
fi

echo "=== test_rewrite_codex_exec_rejects_shell_tail ==="
_tail_json="$(jq -cn --arg c 'kay exec "Refactor utils.py"; rm -rf /tmp/evil' '{tool_name:"Bash", tool_input:{command:$c}}')"
_out="$(run_hook "${_tail_json}" 'SIDEKICK_TEST_UUID_OVERRIDE=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ "${_dec}" = "deny" ]; then
  assert_pass "test_rewrite_codex_exec_rejects_shell_tail"
else
  assert_fail "test_rewrite_codex_exec_rejects_shell_tail" "dec='${_dec}' out='${_out}'"
fi

echo "=== test_idx_created_on_first_rewrite ==="
if [ -f "${PROJECT_SANDBOX}/.kay/conversations.idx" ]; then
  assert_pass "test_idx_created_on_first_rewrite"
else
  assert_fail "test_idx_created_on_first_rewrite" "idx not created"
fi

echo "=== test_idx_row_format_and_hint ==="
_line="$(head -n 1 "${PROJECT_SANDBOX}/.kay/conversations.idx" 2>/dev/null || echo '')"
if echo "${_line}" | grep -Eq $'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z\taaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\tkay-[0-9]+-[0-9a-f]{8}\tRefactor utils\.py$'; then
  assert_pass "test_idx_row_format_and_hint"
else
  assert_fail "test_idx_row_format_and_hint" "line='${_line}'"
fi

echo "=== test_readonly_bash_passthrough ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git status"}}')"
if [ -z "${_out}" ]; then
  assert_pass "test_readonly_bash_passthrough"
else
  assert_fail "test_readonly_bash_passthrough" "expected empty, got: '${_out}'"
fi

echo "=== test_mutating_bash_denied ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"rm foo"}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
_rsn="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
if [ "${_dec}" = "deny" ] \
    && echo "${_rsn}" | grep -q 'kay exec --full-auto' \
    && ! echo "${_rsn}" | grep -q 'code exec'; then
  assert_pass "test_mutating_bash_denied"
else
  assert_fail "test_mutating_bash_denied" "dec='${_dec}' reason='${_rsn}' out='${_out}'"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

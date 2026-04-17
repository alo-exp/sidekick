#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — hooks/forge-delegation-enforcer.sh Tests (Phase 6)
# =============================================================================
# Phase 6 foundation assertions. Plans 06-02 and 06-03 append further tests.
# All tests sandbox HOME so the real ~/.claude/.forge-delegation-active is
# never read or written.

set -euo pipefail

PASS=0; FAIL=0; SKIP=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
HOOK_FILE="${PLUGIN_DIR}/hooks/forge-delegation-enforcer.sh"

green='\033[0;32m'; red='\033[0;31m'; yellow='\033[0;33m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }
skip()        { echo -e "${yellow}SKIP${reset} $1: $2"; SKIP=$((SKIP+1)); }

if [ ! -f "${HOOK_FILE}" ]; then
  echo "ERROR: ${HOOK_FILE} not found"
  exit 1
fi

# Sandbox HOME so the real marker file is untouched.
HOME_SANDBOX="$(mktemp -d)"
trap 'rm -rf "${HOME_SANDBOX}"' EXIT
mkdir -p "${HOME_SANDBOX}/.claude"

# -----------------------------------------------------------------------------
echo "=== test_noop_when_marker_absent ==="
# With no marker file present, hook must exit 0 with empty stdout + stderr.
set +e
_out="$(HOME="${HOME_SANDBOX}" bash "${HOOK_FILE}" \
  <<< '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x","content":"y"}}' \
  2>/tmp/enf_err_$$)"
_rc=$?
_err="$(cat /tmp/enf_err_$$ 2>/dev/null || true)"
rm -f /tmp/enf_err_$$
set -e
if [ "${_rc}" -eq 0 ] && [ -z "${_out}" ] && [ -z "${_err}" ]; then
  assert_pass "test_noop_when_marker_absent"
else
  assert_fail "test_noop_when_marker_absent" "rc=${_rc} out='${_out}' err='${_err}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_exit2_on_malformed_json ==="
set +e
_out="$(HOME="${HOME_SANDBOX}" bash "${HOOK_FILE}" <<< 'not json' 2>/tmp/enf_err_$$)"
_rc=$?
_err="$(cat /tmp/enf_err_$$ 2>/dev/null || true)"
rm -f /tmp/enf_err_$$
set -e
if [ "${_rc}" -eq 2 ] && echo "${_err}" | grep -q 'malformed'; then
  assert_pass "test_exit2_on_malformed_json"
else
  assert_fail "test_exit2_on_malformed_json" "rc=${_rc} err='${_err}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_gen_uuid_format ==="
# Source the hook (source-guard prevents main() from running) and call gen_uuid.
_uuid="$(bash -c "source '${HOOK_FILE}'; gen_uuid")"
if echo "${_uuid}" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
  assert_pass "test_gen_uuid_format (uuid=${_uuid})"
else
  assert_fail "test_gen_uuid_format" "bad uuid format: '${_uuid}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_gen_uuid_honors_test_override ==="
# See <test_injection_contract> in 06-01-hook-foundation.md:
# SIDEKICK_TEST_UUID_OVERRIDE forces gen_uuid to echo its value verbatim,
# enabling 06-03's idx-dedup test to exercise the append_idx_row dedup branch.
_fixed="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
_uuid="$(SIDEKICK_TEST_UUID_OVERRIDE="${_fixed}" bash -c "source '${HOOK_FILE}'; gen_uuid")"
if [ "${_uuid}" = "${_fixed}" ]; then
  assert_pass "test_gen_uuid_honors_test_override"
else
  assert_fail "test_gen_uuid_honors_test_override" "expected '${_fixed}' got '${_uuid}'"
fi

# Activate marker for decision-logic tests.
touch "${HOME_SANDBOX}/.claude/.forge-delegation-active"

# Helper: pipe stdin JSON to the hook with sandboxed HOME, capture stdout + rc.
run_hook() {
  local json="$1"
  local extra_env="${2:-}"
  if [ -n "${extra_env}" ]; then
    HOME="${HOME_SANDBOX}" env "${extra_env}" bash "${HOOK_FILE}" <<< "${json}" 2>/dev/null
  else
    HOME="${HOME_SANDBOX}" bash "${HOOK_FILE}" <<< "${json}" 2>/dev/null
  fi
}

# -----------------------------------------------------------------------------
_assert_deny_with_forge_reason() {
  local name="$1" tool_name="$2"
  local _out _dec _rsn
  _out="$(run_hook "{\"tool_name\":\"${tool_name}\",\"tool_input\":{\"file_path\":\"/tmp/x\",\"content\":\"y\"}}")"
  _dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  _rsn="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
  if [ "${_dec}" = "deny" ] && echo "${_rsn}" | grep -q 'forge -p'; then
    assert_pass "${name}"
  else
    assert_fail "${name}" "dec='${_dec}' reason='${_rsn}'"
  fi
}

echo "=== test_deny_write_when_active ==="
_assert_deny_with_forge_reason "test_deny_write_when_active" "Write"

echo "=== test_deny_edit_when_active ==="
_assert_deny_with_forge_reason "test_deny_edit_when_active" "Edit"

echo "=== test_deny_notebook_edit_when_active ==="
_assert_deny_with_forge_reason "test_deny_notebook_edit_when_active" "NotebookEdit"

# -----------------------------------------------------------------------------
echo "=== test_rewrite_forge_p_injects_uuid_and_pipes ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"Refactor utils.py\""}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty')"
_cmd="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.updatedInput.command // empty')"
if [ "${_dec}" = "allow" ] \
    && echo "${_cmd}" | grep -Eq -- '--conversation-id [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
    && echo "${_cmd}" | grep -q -- '--verbose' \
    && echo "${_cmd}" | grep -q "sed 's/\^/\[FORGE\] /'" \
    && echo "${_cmd}" | grep -q "sed 's/\^/\[FORGE-LOG\] /'"; then
  assert_pass "test_rewrite_forge_p_injects_uuid_and_pipes"
else
  assert_fail "test_rewrite_forge_p_injects_uuid_and_pipes" "dec='${_dec}' cmd='${_cmd}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_rewrite_is_idempotent ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge --conversation-id aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee --verbose -p \"x\""}}')"
if [ -z "${_out}" ]; then
  assert_pass "test_rewrite_is_idempotent"
else
  assert_fail "test_rewrite_is_idempotent" "expected empty, got: '${_out}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_readonly_bash_passthrough ==="
_all_passed=1
for _c in 'git status' 'ls -la' 'grep foo bar.txt' 'cat README.md' 'find . -type f' 'forge conversation list'; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_hook "$_j")"
  if [ -n "${_out}" ]; then
    assert_fail "test_readonly_bash_passthrough[${_c}]" "expected empty, got: '${_out}'"
    _all_passed=0
  fi
done
[ "${_all_passed}" = "1" ] && assert_pass "test_readonly_bash_passthrough"

# -----------------------------------------------------------------------------
echo "=== test_mutating_bash_denied ==="
_all_passed=1
for _c in 'rm foo' 'git commit -m "x"' 'echo hi > /tmp/out'; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_hook "$_j")"
  _dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  if [ "${_dec}" != "deny" ]; then
    assert_fail "test_mutating_bash_denied[${_c}]" "dec='${_dec}' out='${_out}'"
    _all_passed=0
  fi
done
[ "${_all_passed}" = "1" ] && assert_pass "test_mutating_bash_denied"

# -----------------------------------------------------------------------------
echo "=== test_mutating_bash_level3_passthrough ==="
_all_passed=1
for _c in 'rm foo' 'git commit -m "x"' 'echo hi > /tmp/out'; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(FORGE_LEVEL_3=1 HOME="${HOME_SANDBOX}" bash "${HOOK_FILE}" <<< "${_j}" 2>/dev/null)"
  if [ -n "${_out}" ]; then
    assert_fail "test_mutating_bash_level3_passthrough[${_c}]" "expected empty, got: '${_out}'"
    _all_passed=0
  fi
done
[ "${_all_passed}" = "1" ] && assert_pass "test_mutating_bash_level3_passthrough"

# -----------------------------------------------------------------------------
# NOTE: Classifier matches first-token-prefix only; chained mutating tails pass
# through. This is a known, intentional Phase 6 classifier gap documented in
# 06-02-SUMMARY.md. A proper shell-parser fix is out of Phase 6 scope.
echo "=== test_chained_command_with_mutating_tail ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git status && rm foo"}}')"
if [ -z "${_out}" ]; then
  assert_pass "test_chained_command_with_mutating_tail"
else
  assert_fail "test_chained_command_with_mutating_tail" "expected empty passthrough, got: '${_out}'"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

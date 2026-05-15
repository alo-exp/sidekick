#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — hooks/forge-delegation-enforcer.sh Tests (Phase 6)
# =============================================================================
# Phase 6 foundation assertions. Plans 06-02 and 06-03 append further tests.
# All tests sandbox HOME so the real session marker is never read or written.

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

# Sandbox HOME and CLAUDE_PROJECT_DIR so neither the real marker file nor the
# real .forge/ are ever touched. Plan 06-03 added CLAUDE_PROJECT_DIR sandboxing
# so runtime-created .forge/conversations.idx lives inside the sandbox.
HOME_SANDBOX="$(mktemp -d)"
PROJECT_SANDBOX="$(mktemp -d)"
FORGE_STUB_DIR="${HOME_SANDBOX}/bin"
TEST_SESSION_ID="forge-test-$$"
MARKER_DIR="${HOME_SANDBOX}/.claude/sessions/${TEST_SESSION_ID}"
MARKER_FILE="${MARKER_DIR}/.forge-delegation-active"
trap 'rm -rf "${HOME_SANDBOX}" "${PROJECT_SANDBOX}"' EXIT
mkdir -p "${MARKER_DIR}" "${FORGE_STUB_DIR}"
MARKER_ACTIVATION_COUNTER=0

activate_marker() {
  MARKER_ACTIVATION_COUNTER=$((MARKER_ACTIVATION_COUNTER+1))
  printf 'activation-%s-%s\n' "${TEST_SESSION_ID}" "${MARKER_ACTIVATION_COUNTER}" > "${MARKER_FILE}"
}

# Forge stub: exits with the numeric code in $HOME/forge-stub-exit, default 0.
# Tests mutate that file to simulate DB-writable vs DB-locked states without
# depending on env inheritance into sanitized sidekick subprocesses.
cat > "${FORGE_STUB_DIR}/forge" <<'STUB'
#!/usr/bin/env bash
if [ -f "${HOME}/forge-stub-exit" ]; then
  exit "$(cat "${HOME}/forge-stub-exit")"
fi
if [ -f "${HOME}/forge-capture-enable" ]; then
  env > "${HOME}/forge-child-env.txt"
  printf 'STATUS: SUCCESS\napi_key=child-secret-token\nPATTERNS_DISCOVERED: []\n'
fi
exit 0
STUB
chmod +x "${FORGE_STUB_DIR}/forge"

# STUB_PATH prepends the stub dir so `forge conversation list` inside the hook
# calls our stub, not the real binary.
STUB_PATH="${FORGE_STUB_DIR}:${PATH}"

set_forge_stub_exit() {
  if [ "${1:-0}" = "0" ]; then
    rm -f "${HOME_SANDBOX}/forge-stub-exit"
  else
    printf '%s' "$1" > "${HOME_SANDBOX}/forge-stub-exit"
  fi
}

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
activate_marker

# Helper: pipe stdin JSON to the hook with sandboxed HOME + CLAUDE_PROJECT_DIR +
# stubbed forge on PATH, capture stdout + rc.
run_hook() {
  local json="$1"
  local extra_env="${2:-}"
  if [ -n "${extra_env}" ]; then
    HOME="${HOME_SANDBOX}" CLAUDE_PROJECT_DIR="${PROJECT_SANDBOX}" PATH="${STUB_PATH}" \
      env SIDEKICK_TEST_SESSION_ID="${TEST_SESSION_ID}" ${extra_env} bash "${HOOK_FILE}" <<< "${json}" 2>/dev/null
  else
    HOME="${HOME_SANDBOX}" CLAUDE_PROJECT_DIR="${PROJECT_SANDBOX}" PATH="${STUB_PATH}" \
      SIDEKICK_TEST_SESSION_ID="${TEST_SESSION_ID}" \
      bash "${HOOK_FILE}" <<< "${json}" 2>/dev/null
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
echo "=== test_level3_direct_edit_passthrough ==="
_all_passed=1
for _tool in Write Edit NotebookEdit; do
  case "$_tool" in
    Write)
      _j="$(jq -cn --arg p "${PROJECT_SANDBOX}/direct-write.txt" '{tool_name:"Write",tool_input:{file_path:$p,content:"y"}}')"
      ;;
    Edit)
      _j="$(jq -cn --arg p "${PROJECT_SANDBOX}/direct-edit.txt" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"a",new_string:"b"}}')"
      ;;
    NotebookEdit)
      _j="$(jq -cn --arg p "${PROJECT_SANDBOX}/direct-notebook.ipynb" '{tool_name:"NotebookEdit",tool_input:{file_path:$p,cell_type:"code",source:"x"}}')"
      ;;
  esac
  _out="$(FORGE_LEVEL_3=1 run_hook "$_j")"
  if [ -n "${_out}" ]; then
    assert_fail "test_level3_direct_edit_passthrough[${_tool}]" "expected empty, got: '${_out}'"
    _all_passed=0
  fi
done
[ "${_all_passed}" = "1" ] && assert_pass "test_level3_direct_edit_passthrough"

# -----------------------------------------------------------------------------
echo "=== test_level3_session_marker_flow ==="
_start_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"sidekick forge-level3 start"}}')"
_start_dec="$(printf '%s' "${_start_out}" | jq -r '.hookSpecificOutput.permissionDecision // empty')"
_start_cmd="$(printf '%s' "${_start_out}" | jq -r '.hookSpecificOutput.updatedInput.command // empty')"
if [ "${_start_dec}" = "allow" ] && [ -n "${_start_cmd}" ]; then
  HOME="${HOME_SANDBOX}" CLAUDE_PROJECT_DIR="${PROJECT_SANDBOX}" PATH="${STUB_PATH}" bash -c "${_start_cmd}" >/dev/null 2>&1
else
  assert_fail "test_level3_session_marker_flow[start]" "dec='${_start_dec}' cmd='${_start_cmd}' out='${_start_out}'"
  _start_cmd=""
fi

_inside_j="$(jq -cn --arg p "${PROJECT_SANDBOX}/marker-write.txt" '{tool_name:"Write",tool_input:{file_path:$p,content:"y"}}')"
_inside_out="$(run_hook "${_inside_j}")"
_inside_bash_j="$(jq -cn --arg c "touch ${PROJECT_SANDBOX}/marker-bash.txt" '{tool_name:"Bash",tool_input:{command:$c}}')"
_inside_bash_out="$(run_hook "${_inside_bash_j}")"
_outside_j="$(jq -cn --arg p "/tmp/sidekick-marker-outside.txt" '{tool_name:"Write",tool_input:{file_path:$p,content:"y"}}')"
_outside_out="$(run_hook "${_outside_j}")"
_outside_dec="$(printf '%s' "${_outside_out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
_outside_bash_j="$(jq -cn --arg c "touch /tmp/sidekick-marker-outside.txt" '{tool_name:"Bash",tool_input:{command:$c}}')"
_outside_bash_out="$(run_hook "${_outside_bash_j}")"
_outside_bash_dec="$(printf '%s' "${_outside_bash_out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
_stop_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"sidekick forge-level3 stop"}}')"
_stop_dec="$(printf '%s' "${_stop_out}" | jq -r '.hookSpecificOutput.permissionDecision // empty')"
_stop_cmd="$(printf '%s' "${_stop_out}" | jq -r '.hookSpecificOutput.updatedInput.command // empty')"
if [ "${_stop_dec}" = "allow" ] && [ -n "${_stop_cmd}" ]; then
  HOME="${HOME_SANDBOX}" CLAUDE_PROJECT_DIR="${PROJECT_SANDBOX}" PATH="${STUB_PATH}" bash -c "${_stop_cmd}" >/dev/null 2>&1
fi
_after_out="$(run_hook "${_inside_j}")"
_after_dec="$(printf '%s' "${_after_out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ -z "${_inside_out}" ] \
    && [ -z "${_inside_bash_out}" ] \
    && [ "${_outside_dec}" = "deny" ] \
    && [ "${_outside_bash_dec}" = "deny" ] \
    && [ "${_stop_dec}" = "allow" ] \
    && [ "${_after_dec}" = "deny" ]; then
  assert_pass "test_level3_session_marker_flow"
else
  assert_fail "test_level3_session_marker_flow" "inside='${_inside_out}' inside_bash='${_inside_bash_out}' outside_dec='${_outside_dec}' outside_bash_dec='${_outside_bash_dec}' stop_dec='${_stop_dec}' after_dec='${_after_dec}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_level3_marker_does_not_survive_forge_stop_reactivation ==="
_start_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"sidekick forge-level3 start"}}')"
_start_cmd="$(printf '%s' "${_start_out}" | jq -r '.hookSpecificOutput.updatedInput.command // empty')"
if [ -n "${_start_cmd}" ]; then
  HOME="${HOME_SANDBOX}" CLAUDE_PROJECT_DIR="${PROJECT_SANDBOX}" PATH="${STUB_PATH}" bash -c "${_start_cmd}" >/dev/null 2>&1
fi
_stale_level3_marker="${MARKER_DIR}/.forge-level3-active"
rm -f "${MARKER_FILE}"
activate_marker
_reactivated_j="$(jq -cn --arg p "${PROJECT_SANDBOX}/reactivated-write.txt" '{tool_name:"Write",tool_input:{file_path:$p,content:"y"}}')"
_reactivated_out="$(run_hook "${_reactivated_j}")"
_reactivated_dec="$(printf '%s' "${_reactivated_out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
rm -f "${_stale_level3_marker}"
if [ -f "${MARKER_FILE}" ] && [ "${_reactivated_dec}" = "deny" ]; then
  assert_pass "test_level3_marker_does_not_survive_forge_stop_reactivation"
else
  assert_fail "test_level3_marker_does_not_survive_forge_stop_reactivation" "dec='${_reactivated_dec}' out='${_reactivated_out}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_rewrite_forge_p_injects_uuid_and_safe_runner ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"Refactor utils.py\""}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty')"
_cmd="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.updatedInput.command // empty')"
if [ "${_dec}" = "allow" ] \
    && echo "${_cmd}" | grep -q -- 'sidekick-safe-runner.sh' \
    && echo "${_cmd}" | grep -q -- ' forge forge ' \
    && echo "${_cmd}" | grep -Eq -- '--conversation-id [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
    && echo "${_cmd}" | grep -q -- '--verbose'; then
  assert_pass "test_rewrite_forge_p_injects_uuid_and_safe_runner"
else
  assert_fail "test_rewrite_forge_p_injects_uuid_and_safe_runner" "dec='${_dec}' cmd='${_cmd}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_rewrite_forge_p_with_tee_tail_preserves_logging ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"Refactor utils.py\"|tee .planning/forge.log"}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty')"
_cmd="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.updatedInput.command // empty')"
if [ "${_dec}" = "allow" ] \
    && echo "${_cmd}" | grep -q -- 'sidekick-safe-runner.sh' \
    && echo "${_cmd}" | grep -Eq -- '--conversation-id [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
    && echo "${_cmd}" | grep -q -- '--verbose' \
    && echo "${_cmd}" | grep -q -- '| tee .planning/forge.log'; then
  assert_pass "test_rewrite_forge_p_with_tee_tail_preserves_logging"
else
  assert_fail "test_rewrite_forge_p_with_tee_tail_preserves_logging" "dec='${_dec}' cmd='${_cmd}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_safe_runner_sanitizes_child_env_and_redacts_output ==="
touch "${HOME_SANDBOX}/forge-capture-enable"
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"Capture env\""}}')"
_cmd="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.updatedInput.command // empty')"
_run_out="$(CLAUDE_API_KEY=claude-secret CODEX_TOKEN=codex-secret OPENAI_API_KEY=openai-secret bash -c "PATH='${STUB_PATH}' HOME='${HOME_SANDBOX}' ${_cmd}" 2>&1 || true)"
_child_env="$(cat "${HOME_SANDBOX}/forge-child-env.txt" 2>/dev/null || true)"
rm -f "${HOME_SANDBOX}/forge-capture-enable" "${HOME_SANDBOX}/forge-child-env.txt"
if [ -n "${_child_env}" ] \
    && ! printf '%s' "${_child_env}" | grep -Eq 'CLAUDE|CODEX|API_KEY|TOKEN|SECRET|OPENAI' \
    && ! printf '%s' "${_run_out}" | grep -q 'child-secret-token' \
    && printf '%s' "${_run_out}" | grep -q '\[REDACTED\]'; then
  assert_pass "test_safe_runner_sanitizes_child_env_and_redacts_output"
else
  assert_fail "test_safe_runner_sanitizes_child_env_and_redacts_output" "child_env='${_child_env}' run_out='${_run_out}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_rewrite_forge_p_quotes_prompt_metacharacters ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"Refactor utils.py; rm -rf /tmp/evil | cat --conversation-id bad-id-with\""}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty')"
_cmd="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.updatedInput.command // empty')"
if [ "${_dec}" = "allow" ] \
    && echo "${_cmd}" | grep -Eq -- '--conversation-id [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
    && echo "${_cmd}" | grep -q -- "'Refactor utils.py; rm -rf /tmp/evil | cat --conversation-id bad-id-with'"; then
  assert_pass "test_rewrite_forge_p_quotes_prompt_metacharacters"
else
  assert_fail "test_rewrite_forge_p_quotes_prompt_metacharacters" "dec='${_dec}' cmd='${_cmd}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_rewrite_forge_p_ignores_prompt_conversation_id ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"--conversation-id=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\""}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty')"
_cmd="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.updatedInput.command // empty')"
if [ "${_dec}" = "allow" ] \
    && echo "${_cmd}" | grep -Eq -- '--conversation-id [0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
    && echo "${_cmd}" | grep -q -- '--verbose' \
    && echo "${_cmd}" | grep -q -- '-p --conversation-id=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'; then
  assert_pass "test_rewrite_forge_p_ignores_prompt_conversation_id"
else
  assert_fail "test_rewrite_forge_p_ignores_prompt_conversation_id" "dec='${_dec}' cmd='${_cmd}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_rewrite_preserves_existing_conversation_id ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge --conversation-id aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee --verbose -p \"x\""}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
_cmd="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null)"
if [ "${_dec}" = "allow" ] \
    && echo "${_cmd}" | grep -q -- '--conversation-id aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' \
    && echo "${_cmd}" | grep -q -- '--verbose' \
    && echo "${_cmd}" | grep -q -- 'sidekick-safe-runner.sh'; then
  assert_pass "test_rewrite_preserves_existing_conversation_id"
else
  assert_fail "test_rewrite_preserves_existing_conversation_id" "dec='${_dec}' cmd='${_cmd}' out='${_out}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_existing_conversation_id_denies_when_idx_unsafe ==="
_resume_project="$(mktemp -d)"
_resume_outside="$(mktemp -d)"
ln -s "${_resume_outside}" "${_resume_project}/.forge"
_out="$(HOME="${HOME_SANDBOX}" CLAUDE_PROJECT_DIR="${_resume_project}" PATH="${STUB_PATH}" SIDEKICK_TEST_SESSION_ID="${TEST_SESSION_ID}" bash "${HOOK_FILE}" <<< '{"tool_name":"Bash","tool_input":{"command":"forge --conversation-id aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee --verbose -p \"resume x\""}}' 2>/dev/null)"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ "${_dec}" = "deny" ] && [ ! -e "${_resume_outside}/conversations.idx" ]; then
  assert_pass "test_existing_conversation_id_denies_when_idx_unsafe"
else
  assert_fail "test_existing_conversation_id_denies_when_idx_unsafe" "dec='${_dec}' outside_idx=$([ -e "${_resume_outside}/conversations.idx" ] && echo yes || echo no) out='${_out}'"
fi
rm -rf "${_resume_project}" "${_resume_outside}"

# -----------------------------------------------------------------------------
echo "=== test_readonly_bash_passthrough ==="
_all_passed=1
for _c in 'git status' 'ls -la' 'grep foo bar.txt' 'cat README.md' 'find . -type f' 'sed -n 1,3p README.md' "awk '{print}' README.md" 'forge conversation list'; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_hook "$_j")"
  if [ -n "${_out}" ]; then
    assert_fail "test_readonly_bash_passthrough[${_c}]" "expected empty, got: '${_out}'"
    _all_passed=0
  fi
done
[ "${_all_passed}" = "1" ] && assert_pass "test_readonly_bash_passthrough"

# -----------------------------------------------------------------------------
echo "=== test_git_readonly_allowlist_is_token_aware ==="
_all_passed=1
for _c in \
  'git branch' \
  'git branch --list' \
  'git remote -v' \
  'git remote show origin' \
  'git stash list'; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_hook "$_j")"
  if [ -n "${_out}" ]; then
    assert_fail "test_git_readonly_allowlist_is_token_aware[${_c}]" "expected empty, got: '${_out}'"
    _all_passed=0
  fi
done
[ "${_all_passed}" = "1" ] && assert_pass "test_git_readonly_allowlist_is_token_aware"

# -----------------------------------------------------------------------------
echo "=== test_git_mutating_nouns_denied ==="
_all_passed=1
for _c in \
  'git branch -D old' \
  'git branch new-feature' \
  'git remote add origin https://example.invalid/repo.git' \
  'git remote set-url origin https://example.invalid/repo.git' \
  'git stash push -m work' \
  'env git stash push -m work'; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_hook "$_j")"
  _dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  if [ "${_dec}" != "deny" ]; then
    assert_fail "test_git_mutating_nouns_denied[${_c}]" "dec='${_dec}' out='${_out}'"
    _all_passed=0
  fi
done
[ "${_all_passed}" = "1" ] && assert_pass "test_git_mutating_nouns_denied"

# -----------------------------------------------------------------------------
echo "=== test_mutating_bash_denied ==="
_all_passed=1
for _c in \
  'rm foo' \
  'git commit -m "x"' \
  'echo hi > /tmp/out' \
  "awk 'BEGIN { system(\"touch pwned\") }'" \
  "sed 'w pwned' README.md" \
  "sed '1e touch pwned' README.md" \
  'find . -okdir touch {} \;'; do
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
echo "=== test_tee_tail_preserves_safe_runner_failure ==="
set_forge_stub_exit 0
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"Fail with tee\" | tee .planning/forge-fail.log"}}')"
_cmd="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.updatedInput.command // empty')"
set_forge_stub_exit 7
set +e
bash -c "PATH='${STUB_PATH}' HOME='${HOME_SANDBOX}' ${_cmd}" >/tmp/sidekick-forge-tee-test.out 2>&1
_rc=$?
set -e
set_forge_stub_exit 0
if [ "${_rc}" -eq 7 ]; then
  assert_pass "test_tee_tail_preserves_safe_runner_failure"
else
  assert_fail "test_tee_tail_preserves_safe_runner_failure" "rc='${_rc}' cmd='${_cmd}' out='$(cat /tmp/sidekick-forge-tee-test.out 2>/dev/null || true)'"
fi
rm -f /tmp/sidekick-forge-tee-test.out

# -----------------------------------------------------------------------------
echo "=== test_mutating_bash_level3_project_bounded_passthrough ==="
_all_passed=1
for _c in \
  'rm foo' \
  'git commit -m "x"' \
  'python3 scripts/fix.py' \
  "echo hi > ${PROJECT_SANDBOX}/out.txt" \
  "mkdir -p ${PROJECT_SANDBOX}/nested"; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(FORGE_LEVEL_3=1 run_hook "${_j}")"
  if [ -n "${_out}" ]; then
    assert_fail "test_mutating_bash_level3_project_bounded_passthrough[${_c}]" "expected empty, got: '${_out}'"
    _all_passed=0
  fi
done
[ "${_all_passed}" = "1" ] && assert_pass "test_mutating_bash_level3_project_bounded_passthrough"

# -----------------------------------------------------------------------------
echo "=== test_mutating_bash_level3_outside_project_denied ==="
_all_passed=1
for _c in \
  'touch /tmp/sidekick-review-outside-project' \
  'echo hi > /tmp/out' \
  'touch $HOME/sidekick-review-outside-project' \
  'touch ${TMPDIR}/sidekick-review-outside-project' \
  'cat > $HOME/sidekick-review-outside-project' \
  'touch "$(printf /tmp/sidekick-review-outside-project)"' \
  'rm -rf ~' \
  'cd ~ && rm -rf *' \
  'cp README.md ~' \
  'git push origin main' \
  'curl https://example.com' \
  'brew install foo' \
  'gh release delete v0.1.0' \
  'bash -c "touch x"' \
  'cd /tmp && touch out' \
  'git -C /tmp commit -m "x"' \
  'cat README.md | tee -a /tmp/out'; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(FORGE_LEVEL_3=1 run_hook "${_j}")"
  _dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  _rsn="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
  if [ "${_dec}" != "deny" ] || ! echo "${_rsn}" | grep -q 'outside the current project tree'; then
    assert_fail "test_mutating_bash_level3_outside_project_denied[${_c}]" "dec='${_dec}' reason='${_rsn}' out='${_out}'"
    _all_passed=0
  fi
done
[ "${_all_passed}" = "1" ] && assert_pass "test_mutating_bash_level3_outside_project_denied"

# ENF-06 (v1.3): &&-chained command with a mutating tail is now DENIED.
# The Phase 6 "known gap" has been closed — all chain segments are scanned.
echo "=== test_chained_command_with_mutating_tail ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git status && rm foo"}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ "${_dec}" = "deny" ]; then
  assert_pass "test_chained_command_with_mutating_tail (ENF-06: chain with mutating segment denied)"
else
  assert_fail "test_chained_command_with_mutating_tail" "expected deny for chain with mutating tail, got: '${_out}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_non_readonly_chain_and_pipe_denied ==="
_all_passed=1
for _c in \
  "pwd && python3 -c 'open(\"pwned.txt\",\"w\").write(\"x\")'" \
  'pwd && forge -p "Refactor utils.py"' \
  "cat README.md | python3 -c 'open(\"pwned.txt\",\"w\").write(\"x\")'"; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_hook "$_j")"
  _dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  if [ "${_dec}" != "deny" ]; then
    assert_fail "test_non_readonly_chain_and_pipe_denied[${_c}]" "dec='${_dec}' out='${_out}'"
    _all_passed=0
  fi
done
[ "${_all_passed}" = "1" ] && assert_pass "test_non_readonly_chain_and_pipe_denied"

# -----------------------------------------------------------------------------
echo "=== test_readonly_chain_passes ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"cd /tmp && ls"}}')"
if [ -z "${_out}" ]; then
  assert_pass "test_readonly_chain_passes (ENF-06: read-only chain passes through)"
else
  assert_fail "test_readonly_chain_passes" "expected empty passthrough for read-only chain, got: '${_out}'"
fi

# -----------------------------------------------------------------------------
# Plan 06-03: audit index + activation-lifecycle assertions.
# -----------------------------------------------------------------------------

# Helper: reset the project sandbox between tests so state doesn't leak.
_reset_project_sandbox() {
  rm -rf "${PROJECT_SANDBOX}"
  PROJECT_SANDBOX="$(mktemp -d)"
}

# -----------------------------------------------------------------------------
echo "=== test_idx_created_on_first_rewrite ==="
_reset_project_sandbox
set_forge_stub_exit 0
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"first task\""}}')"
if [ -f "${PROJECT_SANDBOX}/.forge/conversations.idx" ]; then
  assert_pass "test_idx_created_on_first_rewrite"
else
  assert_fail "test_idx_created_on_first_rewrite" "idx not created; stdout='${_out}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_idx_row_format ==="
_rows="$(wc -l < "${PROJECT_SANDBOX}/.forge/conversations.idx" | tr -d ' ' || echo 0)"
_line="$(head -n 1 "${PROJECT_SANDBOX}/.forge/conversations.idx" 2>/dev/null || echo '')"
# Regex: ISO8601\tUUID\tsidekick-<ts>-<8hex>\thint
if [ "${_rows}" = "1" ] && echo "${_line}" | grep -Eq $'^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z\t[0-9a-f-]{36}\tsidekick-[0-9]+-[0-9a-f]{8}\t.+$'; then
  assert_pass "test_idx_row_format"
else
  assert_fail "test_idx_row_format" "rows=${_rows} line='${_line}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_idx_row_task_hint ==="
_reset_project_sandbox
set_forge_stub_exit 0
run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"Refactor utils.py to use early returns\""}}' >/dev/null
_hint="$(awk -F'\t' '{print $4}' "${PROJECT_SANDBOX}/.forge/conversations.idx" 2>/dev/null || echo '')"
if [ "${#_hint}" -le 80 ] && echo "${_hint}" | grep -q '^Refactor utils.py'; then
  assert_pass "test_idx_row_task_hint"
else
  assert_fail "test_idx_row_task_hint" "hint='${_hint}' (len=${#_hint})"
fi

# -----------------------------------------------------------------------------
echo "=== test_idx_row_redacts_secret_hint ==="
_reset_project_sandbox
set_forge_stub_exit 0
run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"Use token=supersecret123 and password=hunter2\""}}' >/dev/null
_hint="$(awk -F'\t' '{print $4}' "${PROJECT_SANDBOX}/.forge/conversations.idx" 2>/dev/null || echo '')"
if echo "${_hint}" | grep -q '\[REDACTED\]' \
    && ! echo "${_hint}" | grep -q 'supersecret123' \
    && ! echo "${_hint}" | grep -q 'hunter2' \
    && [ "${#_hint}" -le 80 ]; then
  assert_pass "test_idx_row_redacts_secret_hint"
else
  assert_fail "test_idx_row_redacts_secret_hint" "hint='${_hint}'"
fi

# -----------------------------------------------------------------------------
# test_idx_append_idempotent_by_uuid
# Uses SIDEKICK_TEST_UUID_OVERRIDE (test-only env var, contract defined in
# 06-01-hook-foundation.md <test_injection_contract>) to force two successive
# forge-p rewrite invocations to receive the SAME UUID. This is the only way
# to exercise the append_idx_row dedup grep branch — without the override,
# each gen_uuid call yields a fresh UUID and dedup is unreachable in finite
# test time.
echo "=== test_idx_append_idempotent_by_uuid ==="
_reset_project_sandbox
_FIXED_UUID="deadbeef-1111-2222-3333-444455556666"
export SIDEKICK_TEST_UUID_OVERRIDE="${_FIXED_UUID}"
# Both invocations go through the rewrite branch — neither input has
# --conversation-id, so idempotent-passthrough does NOT short-circuit.
set_forge_stub_exit 0
run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"first call\""}}' >/dev/null
run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"second call\""}}' >/dev/null
_count="$(grep -c "${_FIXED_UUID}" "${PROJECT_SANDBOX}/.forge/conversations.idx" 2>/dev/null || echo 0)"
unset SIDEKICK_TEST_UUID_OVERRIDE
if [ "${_count}" = "1" ]; then
  assert_pass "test_idx_append_idempotent_by_uuid"
else
  assert_fail "test_idx_append_idempotent_by_uuid" "expected exactly 1 row for UUID ${_FIXED_UUID}, got ${_count}"
fi

# -----------------------------------------------------------------------------
# test_db_precheck_denies_when_forge_fails
# When the forge stub exits non-zero on the FIRST rewrite attempt (no sentinel
# exists yet), the hook must emit deny with reason mentioning the precheck
# failure AND must NOT create .forge/conversations.idx. The strict execution
# order in <activation_lifecycle_design> guarantees: precheck runs BEFORE
# ensure_forge_dir_and_idx. If precheck fails, the idx file does not exist.
echo "=== test_db_precheck_denies_when_forge_fails ==="
_reset_project_sandbox
set_forge_stub_exit 3
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"blocked task\""}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
_rsn="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
if [ "${_dec}" = "deny" ] \
    && echo "${_rsn}" | grep -q "'forge conversation list' failed" \
    && [ ! -e "${PROJECT_SANDBOX}/.forge/conversations.idx" ]; then
  assert_pass "test_db_precheck_denies_when_forge_fails"
else
  assert_fail "test_db_precheck_denies_when_forge_fails" "dec='${_dec}' reason='${_rsn}' idx_exists=$([ -e "${PROJECT_SANDBOX}/.forge/conversations.idx" ] && echo yes || echo no)"
fi

# -----------------------------------------------------------------------------
echo "=== test_symlinked_forge_dir_denied ==="
_reset_project_sandbox
_outside_forge_dir="$(mktemp -d)"
ln -s "${_outside_forge_dir}" "${PROJECT_SANDBOX}/.forge"
set_forge_stub_exit 0
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"symlink task\""}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ "${_dec}" = "deny" ] && [ ! -e "${_outside_forge_dir}/conversations.idx" ]; then
  assert_pass "test_symlinked_forge_dir_denied"
else
  assert_fail "test_symlinked_forge_dir_denied" "dec='${_dec}' outside_idx=$([ -e "${_outside_forge_dir}/conversations.idx" ] && echo yes || echo no)"
fi
rm -rf "${_outside_forge_dir}"

# -----------------------------------------------------------------------------
# test_db_precheck_runs_once_via_sentinel
# Step 1: passing forge stub on first invocation → sentinel is created.
# Step 2: swap stub to always-fail, invoke again WITHOUT bumping marker mtime →
#         hook still succeeds because `marker -nt sentinel` is false (sentinel
#         was just touched, so it's at least as new as marker).
# Step 3: sleep 1, touch marker to bump mtime STRICTLY newer than sentinel,
#         keep failing stub → precheck re-runs and denies.
# Uses `sleep 1; touch` (portable bash 3.2+, no date -v/date -d branching).
echo "=== test_db_precheck_runs_once_via_sentinel ==="
_reset_project_sandbox
set_forge_stub_exit 0
run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"step1\""}}' >/dev/null
_step1_ok="no"
if [ -f "${PROJECT_SANDBOX}/.forge/.db_check_ok" ]; then _step1_ok="yes"; fi

# Step 2: failing stub but fresh sentinel → passthrough (sentinel short-circuits)
set_forge_stub_exit 3
_out2="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"step2\""}}')"
_dec2="$(printf '%s' "$_out2" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
_step2_ok="no"
if [ "${_dec2}" = "allow" ]; then _step2_ok="yes"; fi

# Step 3: bump marker mtime, keep failing stub → precheck re-runs and denies
sleep 1
activate_marker
_out3="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"step3\""}}')"
_dec3="$(printf '%s' "$_out3" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
_step3_ok="no"
if [ "${_dec3}" = "deny" ]; then _step3_ok="yes"; fi

if [ "${_step1_ok}" = "yes" ] && [ "${_step2_ok}" = "yes" ] && [ "${_step3_ok}" = "yes" ]; then
  assert_pass "test_db_precheck_runs_once_via_sentinel"
else
  assert_fail "test_db_precheck_runs_once_via_sentinel" "step1=${_step1_ok} step2=${_step2_ok} step3=${_step3_ok}"
fi

# -----------------------------------------------------------------------------
# test_idx_preserved_across_deactivate
# Phase 6 deactivation (owned by skills/forge.md, NOT modified here) removes
# only the marker file. Nothing in the enforcer hook deletes .forge/ or the
# idx. This test simulates deactivation by removing the marker and asserts
# idx persistence.
echo "=== test_idx_preserved_across_deactivate ==="
_reset_project_sandbox
# Refresh marker (test_db_precheck_runs_once_via_sentinel may have bumped it).
activate_marker
set_forge_stub_exit 0
run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"task before deactivate\""}}' >/dev/null
_rows_before="$(wc -l < "${PROJECT_SANDBOX}/.forge/conversations.idx" | tr -d ' ' || echo 0)"
rm -f "${MARKER_FILE}"
if [ -f "${PROJECT_SANDBOX}/.forge/conversations.idx" ]; then
  _rows_after="$(wc -l < "${PROJECT_SANDBOX}/.forge/conversations.idx" | tr -d ' ' || echo 0)"
  if [ "${_rows_after}" = "${_rows_before}" ] && [ "${_rows_after}" -ge 1 ]; then
    assert_pass "test_idx_preserved_across_deactivate"
  else
    assert_fail "test_idx_preserved_across_deactivate" "rows_before=${_rows_before} rows_after=${_rows_after}"
  fi
else
  assert_fail "test_idx_preserved_across_deactivate" "idx removed on deactivate (should be preserved)"
fi
# Restore marker for any subsequent tests.
activate_marker

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

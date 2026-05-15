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
if [ -f "${HOME}/kay-capture-enable" ]; then
  env > "${HOME}/kay-child-env.txt"
  printf 'STATUS: SUCCESS\naccess_token=child-secret-token\nPATTERNS_DISCOVERED: []\n'
fi
if [ "${1:-}" = "--version" ]; then
  printf 'kay 0.9.4\n'
  exit 0
fi
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

echo "=== test_deny_reordered_sed_inplace_when_active ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"sed -E -i '\''s/foo/bar/'\'' README.md"}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ "${_dec}" = "deny" ]; then
  assert_pass "test_deny_reordered_sed_inplace_when_active"
else
  assert_fail "test_deny_reordered_sed_inplace_when_active" "dec='${_dec}' out='${_out}'"
fi

echo "=== test_deny_reordered_awk_inplace_when_active ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"awk '\''{print}'\'' -i inplace file.txt"}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ "${_dec}" = "deny" ]; then
  assert_pass "test_deny_reordered_awk_inplace_when_active"
else
  assert_fail "test_deny_reordered_awk_inplace_when_active" "dec='${_dec}' out='${_out}'"
fi

echo "=== test_deny_sed_awk_execute_write_forms_when_active ==="
_all_passed=1
for _c in \
  "awk 'BEGIN { system(\"touch pwned\") }'" \
  "sed 'w pwned' README.md" \
  "sed '1e touch pwned' README.md" \
  'find . -okdir touch {} \;'; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_hook "$_j")"
  _dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  if [ "${_dec}" != "deny" ]; then
    assert_fail "test_deny_sed_awk_execute_write_forms_when_active[${_c}]" "dec='${_dec}' out='${_out}'"
    _all_passed=0
  fi
done
[ "${_all_passed}" = "1" ] && assert_pass "test_deny_sed_awk_execute_write_forms_when_active"

echo "=== test_deny_process_substitution_input_when_active ==="
_all_passed=1
for _c in 'cat <(rm foo)' "grep x <(sed -i 's/a/b/' file.txt)"; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_hook "$_j")"
  _dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  if [ "${_dec}" != "deny" ]; then
    assert_fail "test_deny_process_substitution_input_when_active[${_c}]" "dec='${_dec}' out='${_out}'"
    _all_passed=0
  fi
done
[ "${_all_passed}" = "1" ] && assert_pass "test_deny_process_substitution_input_when_active"

echo "=== test_rewrite_codex_exec_injects_full_auto_and_safe_runner ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"kay exec \"Refactor utils.py\""}}' 'SIDEKICK_TEST_UUID_OVERRIDE=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
_cmd="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null)"
if [ "${_dec}" = "allow" ] \
    && echo "${_cmd}" | grep -q -- 'sidekick-safe-runner.sh' \
    && echo "${_cmd}" | grep -Eq -- ' kay exec --full-auto'; then
  assert_pass "test_rewrite_codex_exec_injects_full_auto_and_safe_runner"
else
  assert_fail "test_rewrite_codex_exec_injects_full_auto_and_safe_runner" "dec='${_dec}' cmd='${_cmd}'"
fi

echo "=== test_incompatible_code_binary_is_not_treated_as_kay ==="
_fake_path="$(mktemp -d)"
cat > "${_fake_path}/code" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "exec" ]; then
  touch "${HOME}/code-exec-called"
  printf 'not Kay\n' >&2
  exit 64
fi
if [ "${1:-}" = "--version" ]; then
  printf 'code 1.2.3\n'
  exit 0
fi
if [ "${1:-}" = "update" ]; then
  printf 'update help still exists\n'
  exit 0
fi
exit 0
STUB
chmod +x "${_fake_path}/code"
_out="$(HOME="${HOME_SANDBOX}" SIDEKICK_PROJECT_DIR="${PROJECT_SANDBOX}" PATH="${_fake_path}:/usr/bin:/bin:/usr/sbin:/sbin" SIDEKICK_TEST_SESSION_ID="${TEST_SESSION_ID}" bash "${HOOK_FILE}" <<< '{"tool_name":"Bash","tool_input":{"command":"code exec \"Refactor utils.py\""}}' 2>/dev/null)"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
_rsn="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
rm -rf "${_fake_path}"
if [ "${_dec}" = "deny" ] \
  && echo "${_rsn}" | grep -q 'no Kay-compatible runtime' \
  && [ ! -e "${HOME_SANDBOX}/code-exec-called" ]; then
  assert_pass "test_incompatible_code_binary_is_not_treated_as_kay"
else
  assert_fail "test_incompatible_code_binary_is_not_treated_as_kay" "dec='${_dec}' reason='${_rsn}' out='${_out}'"
fi
rm -f "${HOME_SANDBOX}/code-exec-called"

echo "=== test_exec_capable_codex_binary_is_not_treated_as_kay ==="
_fake_path="$(mktemp -d)"
cat > "${_fake_path}/codex" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "exec" ]; then
  touch "${HOME}/codex-exec-called"
  exit 0
fi
if [ "${1:-}" = "--version" ]; then
  printf 'codex 1.2.3\n'
  exit 0
fi
exit 0
STUB
chmod +x "${_fake_path}/codex"
_out="$(HOME="${HOME_SANDBOX}" SIDEKICK_PROJECT_DIR="${PROJECT_SANDBOX}" PATH="${_fake_path}:/usr/bin:/bin:/usr/sbin:/sbin" SIDEKICK_TEST_SESSION_ID="${TEST_SESSION_ID}" bash "${HOOK_FILE}" <<< '{"tool_name":"Bash","tool_input":{"command":"codex exec \"Refactor utils.py\""}}' 2>/dev/null)"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
_rsn="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
rm -rf "${_fake_path}"
if [ "${_dec}" = "deny" ] \
  && echo "${_rsn}" | grep -q 'no Kay-compatible runtime' \
  && [ ! -e "${HOME_SANDBOX}/codex-exec-called" ]; then
  assert_pass "test_exec_capable_codex_binary_is_not_treated_as_kay"
else
  assert_fail "test_exec_capable_codex_binary_is_not_treated_as_kay" "dec='${_dec}' reason='${_rsn}' out='${_out}'"
fi
rm -f "${HOME_SANDBOX}/codex-exec-called"

echo "=== test_safe_runner_sanitizes_child_env_and_redacts_output ==="
touch "${HOME_SANDBOX}/kay-capture-enable"
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"kay exec \"Capture env\""}}' 'SIDEKICK_TEST_UUID_OVERRIDE=bbbbbbbb-cccc-dddd-eeee-ffffffffffff')"
_cmd="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null)"
_run_out="$(CLAUDE_API_KEY=claude-secret CODEX_TOKEN=codex-secret OPENAI_API_KEY=openai-secret bash -c "PATH='${STUB_PATH}' HOME='${HOME_SANDBOX}' ${_cmd}" 2>&1 || true)"
_child_env="$(cat "${HOME_SANDBOX}/kay-child-env.txt" 2>/dev/null || true)"
rm -f "${HOME_SANDBOX}/kay-capture-enable" "${HOME_SANDBOX}/kay-child-env.txt"
if [ -n "${_child_env}" ] \
    && ! printf '%s' "${_child_env}" | grep -Eq 'CLAUDE|CODEX|API_KEY|TOKEN|SECRET|OPENAI' \
    && ! printf '%s' "${_run_out}" | grep -q 'child-secret-token' \
    && printf '%s' "${_run_out}" | grep -q '\[REDACTED\]'; then
  assert_pass "test_safe_runner_sanitizes_child_env_and_redacts_output"
else
  assert_fail "test_safe_runner_sanitizes_child_env_and_redacts_output" "child_env='${_child_env}' run_out='${_run_out}'"
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

echo "=== test_denied_codex_exec_does_not_append_idx_row ==="
_idx="${PROJECT_SANDBOX}/.kay/conversations.idx"
_before="$(wc -l < "${_idx}" 2>/dev/null | tr -d ' ' || echo 0)"
_bad_json="$(jq -cn --arg c 'kay exec "Refactor utils.py" > /tmp/out' '{tool_name:"Bash", tool_input:{command:$c}}')"
_out="$(run_hook "${_bad_json}" 'SIDEKICK_TEST_UUID_OVERRIDE=dddddddd-eeee-ffff-1111-222222222222')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
_after="$(wc -l < "${_idx}" 2>/dev/null | tr -d ' ' || echo 0)"
if [ "${_dec}" = "deny" ] \
    && [ "${_before}" = "${_after}" ] \
    && ! grep -q 'dddddddd-eeee-ffff-1111-222222222222' "${_idx}" 2>/dev/null; then
  assert_pass "test_denied_codex_exec_does_not_append_idx_row"
else
  assert_fail "test_denied_codex_exec_does_not_append_idx_row" "dec='${_dec}' before=${_before} after=${_after} out='${_out}'"
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

echo "=== test_idx_row_redacts_secret_hint ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"kay exec \"Use OPENAI_API_KEY=secret123 and GITHUB_TOKEN=hidden456\""}}' 'SIDEKICK_TEST_UUID_OVERRIDE=cccccccc-dddd-eeee-ffff-111111111111')"
_line="$(tail -n 1 "${PROJECT_SANDBOX}/.kay/conversations.idx" 2>/dev/null || echo '')"
_hint="$(printf '%s' "${_line}" | awk -F'\t' '{print $4}')"
if echo "${_hint}" | grep -q '\[REDACTED\]' \
    && ! echo "${_hint}" | grep -q 'secret123' \
    && ! echo "${_hint}" | grep -q 'hidden456' \
    && [ "${#_hint}" -le 80 ]; then
  assert_pass "test_idx_row_redacts_secret_hint"
else
  assert_fail "test_idx_row_redacts_secret_hint" "hint='${_hint}' out='${_out}'"
fi

echo "=== test_symlinked_kay_dir_denied ==="
_symlink_project="$(mktemp -d)"
_outside_kay="$(mktemp -d)"
ln -s "${_outside_kay}" "${_symlink_project}/.kay"
_out="$(HOME="${HOME_SANDBOX}" SIDEKICK_PROJECT_DIR="${_symlink_project}" PATH="${STUB_PATH}" SIDEKICK_TEST_SESSION_ID="${TEST_SESSION_ID}" SIDEKICK_TEST_UUID_OVERRIDE=dddddddd-eeee-ffff-1111-222222222222 bash "${HOOK_FILE}" <<< '{"tool_name":"Bash","tool_input":{"command":"kay exec \"symlink task\""}}' 2>/dev/null)"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ "${_dec}" = "deny" ] && [ ! -e "${_outside_kay}/conversations.idx" ]; then
  assert_pass "test_symlinked_kay_dir_denied"
else
  assert_fail "test_symlinked_kay_dir_denied" "dec='${_dec}' outside_idx=$([ -e "${_outside_kay}/conversations.idx" ] && echo yes || echo no) out='${_out}'"
fi
rm -rf "${_symlink_project}" "${_outside_kay}"

echo "=== test_unwritable_kay_idx_denied ==="
_unwritable_project="$(mktemp -d)"
mkdir -p "${_unwritable_project}/.kay"
touch "${_unwritable_project}/.kay/conversations.idx"
chmod 500 "${_unwritable_project}/.kay"
chmod 400 "${_unwritable_project}/.kay/conversations.idx"
_out="$(HOME="${HOME_SANDBOX}" SIDEKICK_PROJECT_DIR="${_unwritable_project}" PATH="${STUB_PATH}" SIDEKICK_TEST_SESSION_ID="${TEST_SESSION_ID}" SIDEKICK_TEST_UUID_OVERRIDE=eeeeeeee-ffff-1111-2222-333333333333 bash "${HOOK_FILE}" <<< '{"tool_name":"Bash","tool_input":{"command":"kay exec \"unwritable idx\""}}' 2>/dev/null)"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
_idx_text="$(cat "${_unwritable_project}/.kay/conversations.idx" 2>/dev/null || true)"
chmod 700 "${_unwritable_project}/.kay" 2>/dev/null || true
chmod 600 "${_unwritable_project}/.kay/conversations.idx" 2>/dev/null || true
if [ "${_dec}" = "deny" ] && ! printf '%s' "${_idx_text}" | grep -q 'eeeeeeee-ffff-1111-2222-333333333333'; then
  assert_pass "test_unwritable_kay_idx_denied"
else
  assert_fail "test_unwritable_kay_idx_denied" "dec='${_dec}' idx='${_idx_text}' out='${_out}'"
fi
rm -rf "${_unwritable_project}"

echo "=== test_readonly_bash_passthrough ==="
_all_passed=1
for _c in 'git status' 'sed -n 1,3p README.md' "awk '{print}' README.md"; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_hook "${_j}")"
  if [ -n "${_out}" ]; then
    assert_fail "test_readonly_bash_passthrough[${_c}]" "expected empty, got: '${_out}'"
    _all_passed=0
  fi
done
if [ "${_all_passed}" = "1" ]; then
  assert_pass "test_readonly_bash_passthrough"
fi

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

echo "=== test_non_readonly_chain_and_pipe_denied ==="
_all_passed=1
for _c in \
  "pwd && python3 -c 'open(\"pwned.txt\",\"w\").write(\"x\")'" \
  'pwd && kay exec "Refactor utils.py"' \
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

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

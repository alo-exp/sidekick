#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — hooks/codex-delegation-enforcer.sh Tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
HOOK_FILE="${PLUGIN_DIR}/hooks/codex-delegation-enforcer.sh"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

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
STUB_DIR="${HOME_SANDBOX}/bin"
TEST_SESSION_ID="codex-test-$$"
KAY_MARKER_DIR="${HOME_SANDBOX}/.kay/sessions/${TEST_SESSION_ID}"
KAY_MARKER_FILE="${KAY_MARKER_DIR}/.kay-delegation-active"
CODEX_MARKER_DIR="${HOME_SANDBOX}/.codex/sessions/${TEST_SESSION_ID}"
CODEX_MARKER_FILE="${CODEX_MARKER_DIR}/.codex-delegation-active"
ACTIVE_MODE_DIR="${HOME_SANDBOX}/.sidekick/sessions/${TEST_SESSION_ID}"
ACTIVE_MODE_FILE="${ACTIVE_MODE_DIR}/active-sidekick"
KAY_PROVIDER_FILE="${ACTIVE_MODE_DIR}/kay-provider"
trap 'rm -rf "${HOME_SANDBOX}" "${PROJECT_SANDBOX}"' EXIT
mkdir -p "${KAY_MARKER_DIR}" "${CODEX_MARKER_DIR}" "${ACTIVE_MODE_DIR}" "${STUB_DIR}"

cat > "${STUB_DIR}/kay" <<'STUB'
#!/usr/bin/env bash
if [ -f "${HOME}/kay-capture-enable" ]; then
  env > "${HOME}/kay-child-env.txt"
  printf 'STATUS: SUCCESS\naccess_token=child-secret-token\nPATTERNS_DISCOVERED: []\n'
fi
if [ "${1:-}" = "--version" ]; then
  printf 'kay 0.9.17\n'
  exit 0
fi
if [ "${1:-}" = "exec" ] && [ "${2:-}" = "--help" ]; then
  printf 'kay exec help\n'
  exit 0
fi
exit 0
STUB
chmod +x "${STUB_DIR}/kay"
ln -sf kay "${STUB_DIR}/code"
ln -sf kay "${STUB_DIR}/coder"

cat > "${STUB_DIR}/codex" <<'STUB'
#!/usr/bin/env bash
if [ "${SIDEKICK_TEST_FAKE_CODEX_IS_KAY:-0}" = "1" ]; then
  if [ "${1:-}" = "--version" ]; then
    printf 'kay 0.9.17\n'
    exit 0
  fi
  if [ "${1:-}" = "exec" ] && [ "${2:-}" = "--help" ]; then
    printf 'kay exec help\n'
    exit 0
  fi
fi
if [ "${1:-}" = "--version" ]; then
  printf 'codex 0.1.0\n'
  exit 0
fi
if [ "${1:-}" = "exec" ] && [ "${2:-}" = "--help" ]; then
  printf 'Usage: codex exec [OPTIONS] [PROMPT]\n  --sandbox <MODE>\n  --ask-for-approval <POLICY>\n'
  exit 0
fi
if [ -f "${HOME}/codex-capture-enable" ]; then
  env > "${HOME}/codex-child-env.txt"
  printf 'STATUS: SUCCESS\naccess_token=codex-secret-token\nPATTERNS_DISCOVERED: []\n'
fi
exit 0
STUB
chmod +x "${STUB_DIR}/codex"

STUB_PATH="${STUB_DIR}:${PATH}"

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

activate_kay() {
  rm -f "${ACTIVE_MODE_FILE}" "${CODEX_MARKER_FILE}" "${KAY_PROVIDER_FILE}"
  touch "${KAY_MARKER_FILE}"
  printf '%s\n' "kay" > "${ACTIVE_MODE_FILE}"
}

activate_codex() {
  rm -f "${ACTIVE_MODE_FILE}" "${KAY_MARKER_FILE}" "${KAY_PROVIDER_FILE}"
  touch "${CODEX_MARKER_FILE}"
  printf '%s\n' "codex" > "${ACTIVE_MODE_FILE}"
}

extract_decision() {
  printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null
}

extract_reason() {
  printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null
}

extract_command() {
  printf '%s' "$1" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null
}

assert_deny_reason_contains() {
  local name="$1" tool_name="$2" fragment="$3"
  local out dec rsn
  out="$(run_hook "{\"tool_name\":\"${tool_name}\",\"tool_input\":{\"file_path\":\"/tmp/x\",\"content\":\"y\"}}")"
  dec="$(extract_decision "${out}")"
  rsn="$(extract_reason "${out}")"
  if [ "${dec}" = "deny" ] && echo "${rsn}" | grep -qi -- "${fragment}"; then
    assert_pass "${name}"
  else
    assert_fail "${name}" "dec='${dec}' reason='${rsn}'"
  fi
}

echo "=== test_noop_when_marker_absent ==="
out="$(run_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x","content":"y"}}')"
if [ -z "${out}" ]; then
  assert_pass "test_noop_when_marker_absent"
else
  assert_fail "test_noop_when_marker_absent" "expected empty, got: '${out}'"
fi

echo "=== test_noop_when_unknown_sidekick_is_active ==="
touch "${KAY_MARKER_FILE}"
printf '%s\n' "pilot" > "${ACTIVE_MODE_FILE}"
out="$(run_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x","content":"y"}}')"
if [ -z "${out}" ]; then
  assert_pass "test_noop_when_unknown_sidekick_is_active"
else
  assert_fail "test_noop_when_unknown_sidekick_is_active" "expected empty, got: '${out}'"
fi
rm -f "${ACTIVE_MODE_FILE}"

activate_kay

echo "=== test_kay_mode_denies_direct_write ==="
assert_deny_reason_contains "test_kay_mode_denies_direct_write" "Write" "kay"

echo "=== test_kay_mode_denies_direct_edit ==="
assert_deny_reason_contains "test_kay_mode_denies_direct_edit" "Edit" "kay"

echo "=== test_kay_mode_denies_notebook_edit ==="
assert_deny_reason_contains "test_kay_mode_denies_notebook_edit" "NotebookEdit" "kay"

echo "=== test_kay_mode_denies_mutating_bash ==="
out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"sed -E -i '\''s/foo/bar/'\'' README.md"}}')"
dec="$(extract_decision "${out}")"
rsn="$(extract_reason "${out}")"
if [ "${dec}" = "deny" ] && echo "${rsn}" | grep -qi 'kay'; then
  assert_pass "test_kay_mode_denies_mutating_bash"
else
  assert_fail "test_kay_mode_denies_mutating_bash" "dec='${dec}' reason='${rsn}' out='${out}'"
fi

echo "=== test_kay_mode_rewrites_exec_for_safe_runner ==="
out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"kay exec \"Refactor utils.py\""}}' 'SIDEKICK_TEST_UUID_OVERRIDE=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee')"
dec="$(extract_decision "${out}")"
cmd="$(extract_command "${out}")"
if [ "${dec}" = "allow" ] \
  && echo "${cmd}" | grep -q 'sidekick-safe-runner.sh' \
  && echo "${cmd}" | grep -Eq ' kay exec ' \
  && echo "${cmd}" | grep -q -- '-c model_provider=opencode-go' \
  && echo "${cmd}" | grep -q -- '-c model=' \
  && echo "${cmd}" | grep -Eq ' --full-auto( |$)'; then
  assert_pass "test_kay_mode_rewrites_exec_for_safe_runner"
else
  assert_fail "test_kay_mode_rewrites_exec_for_safe_runner" "dec='${dec}' cmd='${cmd}'"
fi

echo "=== test_kay_mode_routes_xiaomi_non_visual_work_to_pro ==="
out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"kay exec \"Refactor utils.py\""}}' 'SIDEKICK_KAY_PROVIDER=xiaomi')"
dec="$(extract_decision "${out}")"
cmd="$(extract_command "${out}")"
if [ "${dec}" = "allow" ] \
  && echo "${cmd}" | grep -q 'sidekick-safe-runner.sh' \
  && echo "${cmd}" | grep -q -- '-c model_provider=xiaomi' \
  && echo "${cmd}" | grep -Eq -- '(^|[[:space:]])-c model=xiaomi/mimo-v2\.5-pro([[:space:]]|$)' \
  && echo "${cmd}" | grep -Eq -- ' --full-auto( |$)'; then
  assert_pass "test_kay_mode_routes_xiaomi_non_visual_work_to_pro"
else
  assert_fail "test_kay_mode_routes_xiaomi_non_visual_work_to_pro" "dec='${dec}' cmd='${cmd}'"
fi

echo "=== test_kay_mode_routes_xiaomi_visual_work_to_mimo ==="
out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"kay exec \"Inspect this screenshot and explain what is shown\""}}' 'SIDEKICK_KAY_PROVIDER=xiaomi')"
dec="$(extract_decision "${out}")"
cmd="$(extract_command "${out}")"
if [ "${dec}" = "allow" ] \
  && echo "${cmd}" | grep -q 'sidekick-safe-runner.sh' \
  && echo "${cmd}" | grep -q -- '-c model_provider=xiaomi' \
  && echo "${cmd}" | grep -Eq -- '(^|[[:space:]])-c model=xiaomi/mimo-v2\.5([[:space:]]|$)' \
  && ! echo "${cmd}" | grep -q -- 'mimo-v2.5-pro' \
  && echo "${cmd}" | grep -Eq -- ' --full-auto( |$)'; then
  assert_pass "test_kay_mode_routes_xiaomi_visual_work_to_mimo"
else
  assert_fail "test_kay_mode_routes_xiaomi_visual_work_to_mimo" "dec='${dec}' cmd='${cmd}'"
fi

echo "=== test_kay_mode_uses_session_xiaomi_provider ==="
printf '%s\n' "xiaomi" > "${KAY_PROVIDER_FILE}"
out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"kay exec \"Refactor utils.py\""}}')"
dec="$(extract_decision "${out}")"
cmd="$(extract_command "${out}")"
if [ "${dec}" = "allow" ] \
  && echo "${cmd}" | grep -q 'sidekick-safe-runner.sh' \
  && echo "${cmd}" | grep -q -- '-c model_provider=xiaomi' \
  && echo "${cmd}" | grep -Eq -- '(^|[[:space:]])-c model=xiaomi/mimo-v2\.5-pro([[:space:]]|$)'; then
  assert_pass "test_kay_mode_uses_session_xiaomi_provider"
else
  assert_fail "test_kay_mode_uses_session_xiaomi_provider" "dec='${dec}' cmd='${cmd}'"
fi

echo "=== test_kay_mode_invalid_env_provider_fails_safe_over_session ==="
printf '%s\n' "xiaomi" > "${KAY_PROVIDER_FILE}"
out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"kay exec \"Refactor utils.py\""}}' 'SIDEKICK_KAY_PROVIDER=unknown')"
dec="$(extract_decision "${out}")"
cmd="$(extract_command "${out}")"
if [ "${dec}" = "allow" ] \
  && echo "${cmd}" | grep -q 'sidekick-safe-runner.sh' \
  && echo "${cmd}" | grep -q -- '-c model_provider=opencode-go' \
  && echo "${cmd}" | grep -Eq -- '(^|[[:space:]])-c model=opencode-go/mimo-v2\.5-pro([[:space:]]|$)'; then
  assert_pass "test_kay_mode_invalid_env_provider_fails_safe_over_session"
else
  assert_fail "test_kay_mode_invalid_env_provider_fails_safe_over_session" "dec='${dec}' cmd='${cmd}'"
fi

echo "=== test_kay_mode_uses_session_ocg_provider_alias ==="
printf '%s\n' "ocg" > "${KAY_PROVIDER_FILE}"
out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"kay exec \"Run tests\""}}')"
dec="$(extract_decision "${out}")"
cmd="$(extract_command "${out}")"
if [ "${dec}" = "allow" ] \
  && echo "${cmd}" | grep -q 'sidekick-safe-runner.sh' \
  && echo "${cmd}" | grep -q -- '-c model_provider=opencode-go' \
  && echo "${cmd}" | grep -Eq -- '(^|[[:space:]])-c model=opencode-go/deepseek-v4-flash([[:space:]]|$)'; then
  assert_pass "test_kay_mode_uses_session_ocg_provider_alias"
else
  assert_fail "test_kay_mode_uses_session_ocg_provider_alias" "dec='${dec}' cmd='${cmd}'"
fi
rm -f "${KAY_PROVIDER_FILE}"

echo "=== test_kay_mode_records_project_local_audit_index ==="
idx="${PROJECT_SANDBOX}/.kay/conversations.idx"
if [ -f "${idx}" ] \
  && grep -q 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' "${idx}" \
  && grep -q 'Refactor utils.py' "${idx}"; then
  assert_pass "test_kay_mode_records_project_local_audit_index"
else
  assert_fail "test_kay_mode_records_project_local_audit_index" "idx='${idx}' contents='$(cat "${idx}" 2>/dev/null || true)'"
fi

activate_codex

echo "=== test_codex_mode_denies_direct_write ==="
assert_deny_reason_contains "test_codex_mode_denies_direct_write" "Write" "gpt-5.4-mini"

echo "=== test_codex_mode_denies_direct_edit ==="
assert_deny_reason_contains "test_codex_mode_denies_direct_edit" "Edit" "gpt-5.4-mini"

echo "=== test_codex_mode_denies_mutating_bash ==="
out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"python3 -c '\''open(\"README.md\", \"w\").write(\"oops\")'\''"}}')"
dec="$(extract_decision "${out}")"
rsn="$(extract_reason "${out}")"
if [ "${dec}" = "deny" ] && echo "${rsn}" | grep -qi 'codex'; then
  assert_pass "test_codex_mode_denies_mutating_bash"
else
  assert_fail "test_codex_mode_denies_mutating_bash" "dec='${dec}' reason='${rsn}' out='${out}'"
fi

echo "=== test_codex_mode_rewrites_exec_for_gpt_5_4_mini_xhigh ==="
out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"codex exec \"Refactor utils.py\""}}' 'SIDEKICK_TEST_UUID_OVERRIDE=bbbbbbbb-cccc-dddd-eeee-ffffffffffff')"
dec="$(extract_decision "${out}")"
cmd="$(extract_command "${out}")"
if [ "${dec}" = "allow" ] \
  && echo "${cmd}" | grep -q 'sidekick-safe-runner.sh' \
  && echo "${cmd}" | grep -q 'codex exec' \
  && echo "${cmd}" | grep -q -- '-m gpt-5.4-mini' \
  && echo "${cmd}" | grep -q -- '-c model_reasoning_effort=xhigh' \
  && echo "${cmd}" | grep -q -- '--sandbox workspace-write' \
  && echo "${cmd}" | grep -q -- '--ask-for-approval never' \
  && ! echo "${cmd}" | grep -q -- '--full-auto'; then
  assert_pass "test_codex_mode_rewrites_exec_for_gpt_5_4_mini_xhigh"
else
  assert_fail "test_codex_mode_rewrites_exec_for_gpt_5_4_mini_xhigh" "dec='${dec}' cmd='${cmd}'"
fi

echo "=== test_codex_mode_rejects_kay_alias_masquerading_as_codex ==="
out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"codex exec \"Refactor utils.py\""}}' 'SIDEKICK_TEST_FAKE_CODEX_IS_KAY=1')"
dec="$(extract_decision "${out}")"
rsn="$(extract_reason "${out}")"
if [ "${dec}" = "deny" ] && echo "${rsn}" | grep -q 'OpenAI Codex CLI'; then
  assert_pass "test_codex_mode_rejects_kay_alias_masquerading_as_codex"
else
  assert_fail "test_codex_mode_rejects_kay_alias_masquerading_as_codex" "dec='${dec}' reason='${rsn}'"
fi

echo "=== test_codex_mode_records_project_local_audit_index ==="
idx="${PROJECT_SANDBOX}/.codex/conversations.idx"
if [ -f "${idx}" ] \
  && grep -q 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff' "${idx}" \
  && grep -q 'Refactor utils.py' "${idx}"; then
  assert_pass "test_codex_mode_records_project_local_audit_index"
else
  assert_fail "test_codex_mode_records_project_local_audit_index" "idx='${idx}' contents='$(cat "${idx}" 2>/dev/null || true)'"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

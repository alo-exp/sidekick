#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Cursor hook stdin/stdout contract tests
# Regression harness for delegation lockdown (#22 double-JSON, empty stdout, ERR trap)
# =============================================================================

set -euo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

green='\033[0;32m'
red='\033[0;31m'
reset='\033[0m'

cursor_contract_assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS + 1)); }
cursor_contract_assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not in PATH — skipping Cursor hook contract tests"
  exit 0
fi

# shellcheck source=tests/lib/cursor_hook_contract_helpers.bash
source "${SCRIPT_DIR}/lib/cursor_hook_contract_helpers.bash"
cursor_contract_helpers_init "${SCRIPT_DIR}"
trap cursor_contract_cleanup EXIT

if [ ! -f "${CURSOR_CONTRACT_HOOK_FILE}" ]; then
  echo "ERROR: ${CURSOR_CONTRACT_HOOK_FILE} not found"
  exit 1
fi

INACTIVE_CURSOR_TOOLS=(Shell Write Edit StrReplace Delete Task Read Grep)
KAY_CURSOR_SOFT_TOOLS=(Write Edit StrReplace NotebookEdit Delete)
KAY_CURSOR_READONLY_SHELL='git status'
KAY_CURSOR_MUTATING_SHELL="sed -E -i 's/foo/bar/' README.md"
CODEX_CURSOR_MUTATING_SHELL='python3 -c "open(\"README.md\", \"w\").write(\"oops\")"'

echo "=== inactive delegation: Cursor host tool matrix ==="
cursor_contract_clear_activation
for tool in "${INACTIVE_CURSOR_TOOLS[@]}"; do
  payload="$(cursor_contract_tool_payload "${tool}")"
  out="$(run_enforcer_cursor "${payload}")"
  assert_single_json_permission "inactive_cursor_${tool}_allow_single_json" "${out}" "allow" "cursor"
done

echo "=== active Kay on Cursor: soft file tools + readonly shell ==="
cursor_contract_activate_kay
for tool in "${KAY_CURSOR_SOFT_TOOLS[@]}"; do
  payload="$(cursor_contract_tool_payload "${tool}")"
  out="$(run_enforcer_cursor "${payload}")"
  assert_single_json_permission "kay_cursor_${tool}_soft_allow" "${out}" "allow" "cursor"
done

payload="$(cursor_contract_tool_payload Shell "${KAY_CURSOR_READONLY_SHELL}")"
out="$(run_enforcer_cursor "${payload}")"
assert_single_json_permission "kay_cursor_readonly_shell_allow" "${out}" "allow" "cursor"

payload="$(cursor_contract_tool_payload Task)"
out="$(run_enforcer_cursor "${payload}")"
assert_single_json_permission "kay_cursor_task_allow" "${out}" "allow" "cursor"

payload="$(cursor_contract_tool_payload Read)"
out="$(run_enforcer_cursor "${payload}")"
assert_single_json_permission "kay_cursor_read_allow" "${out}" "allow" "cursor"

payload="$(cursor_contract_tool_payload Grep)"
out="$(run_enforcer_cursor "${payload}")"
assert_single_json_permission "kay_cursor_grep_allow" "${out}" "allow" "cursor"

echo "=== active Kay on Cursor: mutating shell denied ==="
payload="$(cursor_contract_tool_payload Shell "${KAY_CURSOR_MUTATING_SHELL}")"
out="$(run_enforcer_cursor "${payload}")"
assert_single_json_permission "kay_cursor_mutating_shell_deny" "${out}" "deny" "cursor"

echo "=== active Codex on Cursor: same matrix ==="
cursor_contract_activate_codex
for tool in "${KAY_CURSOR_SOFT_TOOLS[@]}"; do
  payload="$(cursor_contract_tool_payload "${tool}")"
  out="$(run_enforcer_cursor "${payload}")"
  assert_single_json_permission "codex_cursor_${tool}_soft_allow" "${out}" "allow" "cursor"
done

payload="$(cursor_contract_tool_payload Shell "${KAY_CURSOR_READONLY_SHELL}")"
out="$(run_enforcer_cursor "${payload}")"
assert_single_json_permission "codex_cursor_readonly_shell_allow" "${out}" "allow" "cursor"

payload="$(cursor_contract_tool_payload Task)"
out="$(run_enforcer_cursor "${payload}")"
assert_single_json_permission "codex_cursor_task_allow" "${out}" "allow" "cursor"

payload="$(cursor_contract_tool_payload Read)"
out="$(run_enforcer_cursor "${payload}")"
assert_single_json_permission "codex_cursor_read_allow" "${out}" "allow" "cursor"

payload="$(cursor_contract_tool_payload Grep)"
out="$(run_enforcer_cursor "${payload}")"
assert_single_json_permission "codex_cursor_grep_allow" "${out}" "allow" "cursor"

payload="$(cursor_contract_tool_payload Shell "${CODEX_CURSOR_MUTATING_SHELL}")"
out="$(run_enforcer_cursor "${payload}")"
assert_single_json_permission "codex_cursor_mutating_shell_deny" "${out}" "deny" "cursor"

echo "=== multi-line regression (#22): passthrough paths emit exactly one line ==="
cursor_contract_clear_activation
PASSTHROUGH_CASES=(
  "inactive_write|$(cursor_contract_tool_payload Write)"
  "inactive_shell|$(cursor_contract_tool_payload Shell 'git status')"
  "inactive_unknown|$(jq -cn --arg cid "${CURSOR_CONTRACT_CONVERSATION_ID}" '{conversation_id:$cid,tool_name:"SwitchMode",tool_input:{target_mode_id:"plan"}}')"
  "kay_write|$(cursor_contract_tool_payload Write)"
  "kay_readonly_shell|$(cursor_contract_tool_payload Shell "${KAY_CURSOR_READONLY_SHELL}")"
  "kay_mcp_write|$(jq -cn --arg cid "${CURSOR_CONTRACT_CONVERSATION_ID}" '{conversation_id:$cid,tool_name:"MCP: filesystem write_file",tool_input:{path:"/tmp/x",content:"y"}}')"
  "codex_write|$(cursor_contract_tool_payload Write)"
  "codex_readonly_shell|$(cursor_contract_tool_payload Shell "${KAY_CURSOR_READONLY_SHELL}")"
)

cursor_contract_activate_kay
for entry in "${PASSTHROUGH_CASES[@]}"; do
  label="${entry%%|*}"
  payload="${entry#*|}"
  case "${label}" in
    inactive_*)
      cursor_contract_clear_activation
      ;;
    kay_*)
      cursor_contract_activate_kay
      ;;
    codex_*)
      cursor_contract_activate_codex
      ;;
  esac
  out="$(run_enforcer_cursor "${payload}")"
  lines="$(count_hook_output_lines "${out}")"
  if [ "${lines}" = "1" ] && printf '%s' "${out}" | jq -e . >/dev/null 2>&1; then
    cursor_contract_assert_pass "multiline_regression_${label}"
  else
    cursor_contract_assert_fail "multiline_regression_${label}" "lines='${lines}' out='${out}'"
  fi
done

echo "=== empty stdout regression: hook always emits JSON ==="
cursor_contract_clear_activation
EMPTY_STDOUT_CASES=(
  "inactive_empty_shell_command|$(jq -cn --arg cid "${CURSOR_CONTRACT_CONVERSATION_ID}" '{conversation_id:$cid,tool_name:"Shell",tool_input:{}}')"
  "inactive_missing_tool_input|$(jq -cn --arg cid "${CURSOR_CONTRACT_CONVERSATION_ID}" '{conversation_id:$cid,tool_name:"Read"}')"
  "kay_empty_shell_command|$(jq -cn --arg cid "${CURSOR_CONTRACT_CONVERSATION_ID}" '{conversation_id:$cid,tool_name:"Shell",tool_input:{}}')"
  "codex_empty_shell_command|$(jq -cn --arg cid "${CURSOR_CONTRACT_CONVERSATION_ID}" '{conversation_id:$cid,tool_name:"Shell",tool_input:{}}')"
)

for entry in "${EMPTY_STDOUT_CASES[@]}"; do
  label="${entry%%|*}"
  payload="${entry#*|}"
  case "${label}" in
    inactive_*)
      cursor_contract_clear_activation
      ;;
    kay_*)
      cursor_contract_activate_kay
      ;;
    codex_*)
      cursor_contract_activate_codex
      ;;
  esac
  out="$(run_enforcer_cursor "${payload}")"
  assert_nonempty_single_json "empty_stdout_${label}" "${out}"
done

echo "=== ERR trap: Cursor host fail-open emits allow JSON ==="
trap_out=""
trap_rc=0
trap_out="$(HOME="${CURSOR_CONTRACT_HOME_SANDBOX}" SIDEKICK_HOOK_HOST=cursor bash -euo pipefail -c "
  source '${CURSOR_CONTRACT_HOOK_FILE}'
  false
" 2>/dev/null)" || trap_rc=$?
if [ "${trap_rc}" -eq 0 ]; then
  assert_single_json_permission "cursor_err_trap_emits_allow" "${trap_out}" "allow" "cursor"
else
  cursor_contract_assert_fail "cursor_err_trap_emits_allow" "trap exit rc=${trap_rc} out='${trap_out}'"
fi

trap_out=""
trap_rc=0
trap_out="$(HOME="${CURSOR_CONTRACT_HOME_SANDBOX}" bash -euo pipefail -c "
  source '${CURSOR_CONTRACT_HOOK_FILE}'
  false
" 2>/dev/null)" || trap_rc=$?
if [ "${trap_rc}" -ne 0 ]; then
  cursor_contract_assert_pass "claude_err_trap_preserves_failure_exit"
else
  cursor_contract_assert_fail "claude_err_trap_preserves_failure_exit" "expected non-zero exit, got rc=${trap_rc} out='${trap_out}'"
fi

echo "=== Claude host format: inactive passthrough uses hookSpecificOutput ==="
cursor_contract_clear_activation
payload='{"tool_name":"Write","tool_input":{"file_path":"/tmp/x","content":"y"}}'
out="$(run_enforcer_claude "${payload}")"
assert_single_json_permission "claude_inactive_write_hookSpecificOutput_allow" "${out}" "allow" "claude"
if printf '%s' "${out}" | jq -e 'has("permission") | not' >/dev/null 2>&1; then
  cursor_contract_assert_pass "claude_inactive_write_not_flat_cursor_json"
else
  cursor_contract_assert_fail "claude_inactive_write_not_flat_cursor_json" "out='${out}'"
fi

echo "=== install contract: merge-cursor-hooks metadata and resolvable scripts ==="
INSTALL_TMP="$(mktemp -d)"
CURSOR_HOME_TMP="${INSTALL_TMP}/home/.cursor"
export HOME="${INSTALL_TMP}/home"
export CURSOR_HOME="${CURSOR_HOME_TMP}"
mkdir -p "${CURSOR_HOME_TMP}/plugins/cache/alo-labs/sidekick/current"
cp -R "${REPO_ROOT}/hooks" "${CURSOR_HOME_TMP}/plugins/cache/alo-labs/sidekick/current/"
cp "${REPO_ROOT}/scripts/merge-cursor-hooks.py" "${INSTALL_TMP}/merge-cursor-hooks.py"

printf '{"version":1,"hooks":{"preToolUse":[{"command":"existing-hook"}]}}\n' > "${CURSOR_HOME_TMP}/hooks.json"
install_path="${CURSOR_HOME_TMP}/plugins/cache/alo-labs/sidekick/current"
if python3 "${INSTALL_TMP}/merge-cursor-hooks.py" "${install_path}" >/dev/null 2>&1; then
  if python3 - "${CURSOR_HOME_TMP}/hooks.json" "${install_path}" <<'PY'
import json
import os
import sys

hooks_path, install_path = sys.argv[1:3]
data = json.load(open(hooks_path))
hooks = data.get("hooks", {})

expected_scripts = [
    "cursor-session-bootstrap.sh",
    "cursor-session-end.sh",
    "codex-delegation-enforcer.sh",
    "codex-progress-surface.sh",
]
found = {name: False for name in expected_scripts}

for event, entries in hooks.items():
    for entry in entries:
        command = entry.get("command", "")
        for script in expected_scripts:
            if script in command:
                found[script] = True
                if install_path not in command:
                    raise SystemExit(f"missing install path in {script}: {command}")
                script_path = os.path.join(install_path, "hooks", script)
                if not os.path.isfile(script_path):
                    raise SystemExit(f"script not resolvable: {script_path}")
        if "codex-delegation-enforcer.sh" in command:
            if entry.get("failClosed") is not False:
                raise SystemExit("enforcer failClosed must be false")

pre = hooks.get("preToolUse", [])
if not any(entry.get("command") == "existing-hook" for entry in pre):
    raise SystemExit("existing preToolUse hook was removed")

if not all(found.values()):
    missing = [name for name, ok in found.items() if not ok]
    raise SystemExit(f"missing hook entries: {missing}")
PY
  then
    cursor_contract_assert_pass "merge_cursor_hooks_install_contract"
  else
    cursor_contract_assert_fail "merge_cursor_hooks_install_contract" "hooks.json validation failed"
  fi
else
  cursor_contract_assert_fail "merge_cursor_hooks_install_contract" "merge script failed"
fi
rm -rf "${INSTALL_TMP}"

echo "=== session scoping: sessionEnd clears markers and restores inactive passthrough ==="
cursor_contract_activate_kay
if [ -f "${CURSOR_CONTRACT_KAY_MARKER_FILE}" ] && [ -f "${CURSOR_CONTRACT_ACTIVE_MODE_FILE}" ]; then
  cursor_contract_assert_pass "session_scope_precheck_kay_active"
else
  cursor_contract_assert_fail "session_scope_precheck_kay_active" "markers missing before sessionEnd"
fi

session_end_payload="$(jq -cn --arg cid "${CURSOR_CONTRACT_CONVERSATION_ID}" '{conversation_id:$cid}')"
run_cursor_session_end "${session_end_payload}" >/dev/null

if [ ! -f "${CURSOR_CONTRACT_KAY_MARKER_FILE}" ] \
  && [ ! -f "${CURSOR_CONTRACT_ACTIVE_MODE_FILE}" ] \
  && [ ! -f "${CURSOR_CONTRACT_CODEX_MARKER_FILE}" ]; then
  cursor_contract_assert_pass "session_end_clears_delegation_markers"
else
  cursor_contract_assert_fail "session_end_clears_delegation_markers" \
    "kay=$(test -f "${CURSOR_CONTRACT_KAY_MARKER_FILE}" && echo yes || echo no) active=$(test -f "${CURSOR_CONTRACT_ACTIVE_MODE_FILE}" && echo yes || echo no)"
fi

payload="$(cursor_contract_tool_payload Write)"
out="$(run_enforcer_cursor "${payload}")"
assert_single_json_permission "session_end_restores_inactive_write_allow" "${out}" "allow" "cursor"

payload="$(cursor_contract_tool_payload Shell "${KAY_CURSOR_MUTATING_SHELL}")"
out="$(run_enforcer_cursor "${payload}")"
assert_single_json_permission "session_end_restores_inactive_mutating_shell_allow" "${out}" "allow" "cursor"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

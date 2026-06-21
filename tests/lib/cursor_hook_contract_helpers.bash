#!/usr/bin/env bash
# Shared helpers for Cursor hook stdin/stdout contract tests.

set -euo pipefail

cursor_contract_helpers_init() {
  local script_dir="$1"
  CURSOR_CONTRACT_PLUGIN_DIR="$(cd "${script_dir}/.." && pwd)"
  CURSOR_CONTRACT_HOOK_FILE="${CURSOR_CONTRACT_PLUGIN_DIR}/hooks/codex-delegation-enforcer.sh"
  CURSOR_CONTRACT_SESSION_END="${CURSOR_CONTRACT_PLUGIN_DIR}/hooks/cursor-session-end.sh"
  CURSOR_CONTRACT_MERGE_PY="${CURSOR_CONTRACT_PLUGIN_DIR}/scripts/merge-cursor-hooks.py"
  CURSOR_CONTRACT_INSTALL_SCRIPT="${CURSOR_CONTRACT_PLUGIN_DIR}/scripts/install-cursor.sh"

  CURSOR_CONTRACT_HOME_SANDBOX="$(mktemp -d)"
  CURSOR_CONTRACT_PROJECT_SANDBOX="$(mktemp -d)"
  CURSOR_CONTRACT_STUB_DIR="${CURSOR_CONTRACT_HOME_SANDBOX}/bin"
  CURSOR_CONTRACT_TEST_SESSION_ID="cursor-contract-$$"
  CURSOR_CONTRACT_CONVERSATION_ID="${CURSOR_CONTRACT_TEST_SESSION_ID}"

  CURSOR_CONTRACT_KAY_MARKER_DIR="${CURSOR_CONTRACT_HOME_SANDBOX}/.kay/sessions/${CURSOR_CONTRACT_TEST_SESSION_ID}"
  CURSOR_CONTRACT_KAY_MARKER_FILE="${CURSOR_CONTRACT_KAY_MARKER_DIR}/.kay-delegation-active"
  CURSOR_CONTRACT_CODEX_MARKER_DIR="${CURSOR_CONTRACT_HOME_SANDBOX}/.codex/sessions/${CURSOR_CONTRACT_TEST_SESSION_ID}"
  CURSOR_CONTRACT_CODEX_MARKER_FILE="${CURSOR_CONTRACT_CODEX_MARKER_DIR}/.codex-delegation-active"
  CURSOR_CONTRACT_ACTIVE_MODE_DIR="${CURSOR_CONTRACT_HOME_SANDBOX}/.sidekick/sessions/${CURSOR_CONTRACT_TEST_SESSION_ID}"
  CURSOR_CONTRACT_ACTIVE_MODE_FILE="${CURSOR_CONTRACT_ACTIVE_MODE_DIR}/active-sidekick"

  mkdir -p \
    "${CURSOR_CONTRACT_KAY_MARKER_DIR}" \
    "${CURSOR_CONTRACT_CODEX_MARKER_DIR}" \
    "${CURSOR_CONTRACT_ACTIVE_MODE_DIR}" \
    "${CURSOR_CONTRACT_STUB_DIR}"

  cursor_contract_write_runtime_stubs
  CURSOR_CONTRACT_STUB_PATH="${CURSOR_CONTRACT_STUB_DIR}:${PATH}"
}

cursor_contract_cleanup() {
  rm -rf "${CURSOR_CONTRACT_HOME_SANDBOX:-}" "${CURSOR_CONTRACT_PROJECT_SANDBOX:-}"
}

cursor_contract_write_runtime_stubs() {
  cat > "${CURSOR_CONTRACT_STUB_DIR}/kay" <<'STUB'
#!/usr/bin/env bash
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
  chmod +x "${CURSOR_CONTRACT_STUB_DIR}/kay"
  ln -sf kay "${CURSOR_CONTRACT_STUB_DIR}/code"
  ln -sf kay "${CURSOR_CONTRACT_STUB_DIR}/coder"

  cat > "${CURSOR_CONTRACT_STUB_DIR}/codex" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
  printf 'codex 0.1.0\n'
  exit 0
fi
if [ "${1:-}" = "exec" ] && [ "${2:-}" = "--help" ]; then
  printf 'Usage: codex exec [OPTIONS] [PROMPT]\n  --sandbox <MODE>\n  --ask-for-approval <POLICY>\n'
  exit 0
fi
exit 0
STUB
  chmod +x "${CURSOR_CONTRACT_STUB_DIR}/codex"
}

cursor_contract_clear_activation() {
  rm -f \
    "${CURSOR_CONTRACT_ACTIVE_MODE_FILE}" \
    "${CURSOR_CONTRACT_KAY_MARKER_FILE}" \
    "${CURSOR_CONTRACT_CODEX_MARKER_FILE}" \
    "${CURSOR_CONTRACT_ACTIVE_MODE_DIR}/kay-provider"
}

cursor_contract_activate_kay() {
  cursor_contract_clear_activation
  touch "${CURSOR_CONTRACT_KAY_MARKER_FILE}"
  printf '%s\n' "kay" > "${CURSOR_CONTRACT_ACTIVE_MODE_FILE}"
}

cursor_contract_activate_codex() {
  cursor_contract_clear_activation
  touch "${CURSOR_CONTRACT_CODEX_MARKER_FILE}"
  printf '%s\n' "codex" > "${CURSOR_CONTRACT_ACTIVE_MODE_FILE}"
}

cursor_contract_tool_payload() {
  local tool_name="$1"
  case "$tool_name" in
    Shell)
      jq -cn \
        --arg cid "${CURSOR_CONTRACT_CONVERSATION_ID}" \
        --arg cmd "${2:-git status}" \
        '{conversation_id:$cid,tool_name:"Shell",tool_input:{command:$cmd}}'
      ;;
    Write)
      jq -cn \
        --arg cid "${CURSOR_CONTRACT_CONVERSATION_ID}" \
        '{conversation_id:$cid,tool_name:"Write",tool_input:{file_path:"/tmp/x",content:"y"}}'
      ;;
    Edit)
      jq -cn \
        --arg cid "${CURSOR_CONTRACT_CONVERSATION_ID}" \
        '{conversation_id:$cid,tool_name:"Edit",tool_input:{file_path:"/tmp/x",old_string:"a",new_string:"b"}}'
      ;;
    StrReplace)
      jq -cn \
        --arg cid "${CURSOR_CONTRACT_CONVERSATION_ID}" \
        '{conversation_id:$cid,tool_name:"StrReplace",tool_input:{path:"/tmp/x",old_string:"a",new_string:"b"}}'
      ;;
    Delete)
      jq -cn \
        --arg cid "${CURSOR_CONTRACT_CONVERSATION_ID}" \
        '{conversation_id:$cid,tool_name:"Delete",tool_input:{path:"/tmp/x"}}'
      ;;
    NotebookEdit)
      jq -cn \
        --arg cid "${CURSOR_CONTRACT_CONVERSATION_ID}" \
        '{conversation_id:$cid,tool_name:"NotebookEdit",tool_input:{target_notebook:"/tmp/n.ipynb",cell_idx:0,is_new_cell:true,cell_language:"python",old_string:"",new_string:"print(1)"}}'
      ;;
    Task)
      jq -cn \
        --arg cid "${CURSOR_CONTRACT_CONVERSATION_ID}" \
        '{conversation_id:$cid,tool_name:"Task",tool_input:{description:"do work",subagent_type:"explore"}}'
      ;;
    Read)
      jq -cn \
        --arg cid "${CURSOR_CONTRACT_CONVERSATION_ID}" \
        '{conversation_id:$cid,tool_name:"Read",tool_input:{path:"/tmp/x"}}'
      ;;
    Grep)
      jq -cn \
        --arg cid "${CURSOR_CONTRACT_CONVERSATION_ID}" \
        '{conversation_id:$cid,tool_name:"Grep",tool_input:{pattern:"foo",path:"."}}'
      ;;
    *)
      return 1
      ;;
  esac
}

count_hook_output_lines() {
  local out="$1"
  printf '%s\n' "${out}" | sed '/^$/d' | wc -l | tr -d ' '
}

extract_hook_permission() {
  local out="$1"
  local host="${2:-cursor}"
  case "$host" in
    cursor)
      printf '%s' "${out}" | jq -r '.permission // empty' 2>/dev/null
      ;;
    claude)
      printf '%s' "${out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null
      ;;
    *)
      return 1
      ;;
  esac
}

run_enforcer_cursor() {
  local json="$1"
  local extra_env="${2:-}"
  if [ -n "${extra_env}" ]; then
    HOME="${CURSOR_CONTRACT_HOME_SANDBOX}" \
      SIDEKICK_PROJECT_DIR="${CURSOR_CONTRACT_PROJECT_SANDBOX}" \
      PATH="${CURSOR_CONTRACT_STUB_PATH}" \
      SIDEKICK_HOOK_HOST=cursor \
      SIDEKICK_TEST_SESSION_ID="${CURSOR_CONTRACT_TEST_SESSION_ID}" \
      env ${extra_env} bash "${CURSOR_CONTRACT_HOOK_FILE}" <<< "${json}" 2>/dev/null
  else
    HOME="${CURSOR_CONTRACT_HOME_SANDBOX}" \
      SIDEKICK_PROJECT_DIR="${CURSOR_CONTRACT_PROJECT_SANDBOX}" \
      PATH="${CURSOR_CONTRACT_STUB_PATH}" \
      SIDEKICK_HOOK_HOST=cursor \
      SIDEKICK_TEST_SESSION_ID="${CURSOR_CONTRACT_TEST_SESSION_ID}" \
      bash "${CURSOR_CONTRACT_HOOK_FILE}" <<< "${json}" 2>/dev/null
  fi
}

run_enforcer_claude() {
  local json="$1"
  local extra_env="${2:-}"
  if [ -n "${extra_env}" ]; then
    HOME="${CURSOR_CONTRACT_HOME_SANDBOX}" \
      SIDEKICK_PROJECT_DIR="${CURSOR_CONTRACT_PROJECT_SANDBOX}" \
      PATH="${CURSOR_CONTRACT_STUB_PATH}" \
      SIDEKICK_TEST_SESSION_ID="${CURSOR_CONTRACT_TEST_SESSION_ID}" \
      env ${extra_env} bash "${CURSOR_CONTRACT_HOOK_FILE}" <<< "${json}" 2>/dev/null
  else
    HOME="${CURSOR_CONTRACT_HOME_SANDBOX}" \
      SIDEKICK_PROJECT_DIR="${CURSOR_CONTRACT_PROJECT_SANDBOX}" \
      PATH="${CURSOR_CONTRACT_STUB_PATH}" \
      SIDEKICK_TEST_SESSION_ID="${CURSOR_CONTRACT_TEST_SESSION_ID}" \
      bash "${CURSOR_CONTRACT_HOOK_FILE}" <<< "${json}" 2>/dev/null
  fi
}

assert_single_json_permission() {
  local name="$1"
  local out="$2"
  local expected="$3"
  local host="${4:-cursor}"

  local lines permission
  lines="$(count_hook_output_lines "${out}")"

  if [ -z "${out}" ]; then
    cursor_contract_assert_fail "${name}" "stdout is empty"
    return 0
  fi

  if [ "${lines}" != "1" ]; then
    cursor_contract_assert_fail "${name}" "expected 1 stdout line, got ${lines}: ${out}"
    return 0
  fi

  if ! printf '%s' "${out}" | jq -e . >/dev/null 2>&1; then
    cursor_contract_assert_fail "${name}" "invalid JSON: ${out}"
    return 0
  fi

  permission="$(extract_hook_permission "${out}" "${host}")"
  if [ "${permission}" = "${expected}" ]; then
    case "$host" in
      cursor)
        if printf '%s' "${out}" | jq -e 'has("permission") and (.hookSpecificOutput // null | type) == "null"' >/dev/null 2>&1; then
          cursor_contract_assert_pass "${name}"
        else
          cursor_contract_assert_fail "${name}" "cursor output must be flat JSON, got: ${out}"
        fi
        ;;
      claude)
        if printf '%s' "${out}" | jq -e '.hookSpecificOutput.permissionDecision == "'"${expected}"'"' >/dev/null 2>&1; then
          cursor_contract_assert_pass "${name}"
        else
          cursor_contract_assert_fail "${name}" "claude hookSpecificOutput missing: ${out}"
        fi
        ;;
    esac
  else
    cursor_contract_assert_fail "${name}" "permission='${permission}' expected='${expected}' out='${out}'"
  fi
}

assert_nonempty_single_json() {
  local name="$1"
  local out="$2"
  local lines
  lines="$(count_hook_output_lines "${out}")"
  if [ -z "${out}" ]; then
    cursor_contract_assert_fail "${name}" "stdout is empty"
    return 0
  fi
  if [ "${lines}" != "1" ]; then
    cursor_contract_assert_fail "${name}" "expected 1 stdout line, got ${lines}: ${out}"
    return 0
  fi
  if printf '%s' "${out}" | jq -e . >/dev/null 2>&1; then
    cursor_contract_assert_pass "${name}"
  else
    cursor_contract_assert_fail "${name}" "invalid JSON: ${out}"
  fi
}

run_cursor_session_end() {
  local json="$1"
  HOME="${CURSOR_CONTRACT_HOME_SANDBOX}" \
    SIDEKICK_TEST_SESSION_ID="${CURSOR_CONTRACT_TEST_SESSION_ID}" \
    SIDEKICK_SESSION_ID="${CURSOR_CONTRACT_TEST_SESSION_ID}" \
    bash "${CURSOR_CONTRACT_SESSION_END}" <<< "${json}" 2>/dev/null
}

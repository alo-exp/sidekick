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

# Sandbox HOME and CLAUDE_PROJECT_DIR so neither the real marker file nor the
# real .forge/ are ever touched. Plan 06-03 added CLAUDE_PROJECT_DIR sandboxing
# so runtime-created .forge/conversations.idx lives inside the sandbox.
HOME_SANDBOX="$(mktemp -d)"
PROJECT_SANDBOX="$(mktemp -d)"
FORGE_STUB_DIR="${HOME_SANDBOX}/bin"
trap 'rm -rf "${HOME_SANDBOX}" "${PROJECT_SANDBOX}"' EXIT
mkdir -p "${HOME_SANDBOX}/.claude" "${FORGE_STUB_DIR}"

# Forge stub: a one-line script that exits with $FORGE_STUB_EXIT (default 0).
# Tests mutate FORGE_STUB_EXIT between invocations to simulate DB-writable vs
# DB-locked states without touching the real forge binary.
cat > "${FORGE_STUB_DIR}/forge" <<'STUB'
#!/usr/bin/env bash
exit "${FORGE_STUB_EXIT:-0}"
STUB
chmod +x "${FORGE_STUB_DIR}/forge"

# STUB_PATH prepends the stub dir so `forge conversation list` inside the hook
# calls our stub, not the real binary.
STUB_PATH="${FORGE_STUB_DIR}:${PATH}"

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

# Helper: pipe stdin JSON to the hook with sandboxed HOME + CLAUDE_PROJECT_DIR +
# stubbed forge on PATH, capture stdout + rc.
run_hook() {
  local json="$1"
  local extra_env="${2:-}"
  if [ -n "${extra_env}" ]; then
    HOME="${HOME_SANDBOX}" CLAUDE_PROJECT_DIR="${PROJECT_SANDBOX}" PATH="${STUB_PATH}" \
      env "${extra_env}" bash "${HOOK_FILE}" <<< "${json}" 2>/dev/null
  else
    HOME="${HOME_SANDBOX}" CLAUDE_PROJECT_DIR="${PROJECT_SANDBOX}" PATH="${STUB_PATH}" \
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
  _out="$(FORGE_LEVEL_3=1 HOME="${HOME_SANDBOX}" CLAUDE_PROJECT_DIR="${PROJECT_SANDBOX}" PATH="${STUB_PATH}" bash "${HOOK_FILE}" <<< "${_j}" 2>/dev/null)"
  if [ -n "${_out}" ]; then
    assert_fail "test_mutating_bash_level3_passthrough[${_c}]" "expected empty, got: '${_out}'"
    _all_passed=0
  fi
done
[ "${_all_passed}" = "1" ] && assert_pass "test_mutating_bash_level3_passthrough"

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
FORGE_STUB_EXIT=0
_out="$(FORGE_STUB_EXIT=0 run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"first task\""}}')"
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
FORGE_STUB_EXIT=0 run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"Refactor utils.py to use early returns\""}}' >/dev/null
_hint="$(awk -F'\t' '{print $4}' "${PROJECT_SANDBOX}/.forge/conversations.idx" 2>/dev/null || echo '')"
if [ "${#_hint}" -le 80 ] && echo "${_hint}" | grep -q '^Refactor utils.py'; then
  assert_pass "test_idx_row_task_hint"
else
  assert_fail "test_idx_row_task_hint" "hint='${_hint}' (len=${#_hint})"
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
FORGE_STUB_EXIT=0 run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"first call\""}}' >/dev/null
FORGE_STUB_EXIT=0 run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"second call\""}}' >/dev/null
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
_out="$(FORGE_STUB_EXIT=3 run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"blocked task\""}}')"
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
FORGE_STUB_EXIT=0 run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"step1\""}}' >/dev/null
_step1_ok="no"
if [ -f "${PROJECT_SANDBOX}/.forge/.db_check_ok" ]; then _step1_ok="yes"; fi

# Step 2: failing stub but fresh sentinel → passthrough (sentinel short-circuits)
_out2="$(FORGE_STUB_EXIT=3 run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"step2\""}}')"
_dec2="$(printf '%s' "$_out2" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
_step2_ok="no"
if [ "${_dec2}" = "allow" ]; then _step2_ok="yes"; fi

# Step 3: bump marker mtime, keep failing stub → precheck re-runs and denies
sleep 1
touch "${HOME_SANDBOX}/.claude/.forge-delegation-active"
_out3="$(FORGE_STUB_EXIT=3 run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"step3\""}}')"
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
# Re-touch marker (test_db_precheck_runs_once_via_sentinel may have bumped it).
touch "${HOME_SANDBOX}/.claude/.forge-delegation-active"
FORGE_STUB_EXIT=0 run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"task before deactivate\""}}' >/dev/null
_rows_before="$(wc -l < "${PROJECT_SANDBOX}/.forge/conversations.idx" | tr -d ' ' || echo 0)"
rm -f "${HOME_SANDBOX}/.claude/.forge-delegation-active"
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
touch "${HOME_SANDBOX}/.claude/.forge-delegation-active"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

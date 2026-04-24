#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — v1.2 End-to-End Integration Test (Phase 9)
# =============================================================================
# Drives the full v1.2 flow in a sandboxed HOME / CLAUDE_PROJECT_DIR:
#
#   1. Activate marker (simulating `/forge`).
#   2. Feed PreToolUse enforcer a `forge -p …` Bash invocation.
#      -> expect permissionDecision=allow + rewritten command with UUID,
#         --verbose, output pipe, AND a row appended to .forge/conversations.idx.
#   3. Feed PostToolUse progress-surface hook a STATUS block output from that
#      same rewritten command.
#      -> expect additionalContext with [FORGE-SUMMARY] + /forge:replay <UUID>.
#   4. Confirm the UUID that flowed through PreToolUse is the same UUID cited
#      by PostToolUse (end-to-end round-trip).
#   5. Deactivate: marker removed, idx preserved.
#
# This exercises Phases 6, 7, and 8 together and is the "proof" that v1.2
# artifacts compose correctly.
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
PRE_HOOK="${PLUGIN_DIR}/hooks/forge-delegation-enforcer.sh"
POST_HOOK="${PLUGIN_DIR}/hooks/forge-progress-surface.sh"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

[ -f "${PRE_HOOK}" ]  || { echo "ERROR: ${PRE_HOOK} missing";  exit 1; }
[ -f "${POST_HOOK}" ] || { echo "ERROR: ${POST_HOOK} missing"; exit 1; }

# Sandbox HOME and CLAUDE_PROJECT_DIR so no real files are touched.
HOME_SANDBOX="$(mktemp -d)"
PROJECT_SANDBOX="$(mktemp -d)"
trap 'rm -rf "${HOME_SANDBOX}" "${PROJECT_SANDBOX}"' EXIT
mkdir -p "${HOME_SANDBOX}/.claude"
mkdir -p "${HOME_SANDBOX}/bin"

# Stub forge binary so db_precheck inside the enforcer succeeds without a
# real Forge install. Exit 0 on every invocation.
cat > "${HOME_SANDBOX}/bin/forge" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "${HOME_SANDBOX}/bin/forge"
STUB_PATH="${HOME_SANDBOX}/bin:${PATH}"

# Helper: run pre-hook
run_pre() {
  local json="$1"
  HOME="${HOME_SANDBOX}" \
  CLAUDE_PROJECT_DIR="${PROJECT_SANDBOX}" \
  PATH="${STUB_PATH}" \
    bash "${PRE_HOOK}" <<< "${json}" 2>/dev/null
}

# Helper: run post-hook
run_post() {
  local json="$1"
  HOME="${HOME_SANDBOX}" \
    bash "${POST_HOOK}" <<< "${json}" 2>/dev/null
}

# -----------------------------------------------------------------------------
echo "=== E2E step 1: activate marker (simulating /forge) ==="
touch "${HOME_SANDBOX}/.claude/.forge-delegation-active"
if [ -f "${HOME_SANDBOX}/.claude/.forge-delegation-active" ]; then
  assert_pass "e2e_step1_marker_activated"
else
  assert_fail "e2e_step1_marker_activated" "marker not created"
fi

# -----------------------------------------------------------------------------
echo "=== E2E step 2: PreToolUse rewrites forge -p and appends idx row ==="
# Use SIDEKICK_TEST_UUID_OVERRIDE to get a deterministic UUID for the
# round-trip assertion in step 4.
EXPECTED_UUID="11111111-2222-3333-4444-555566667777"
PRE_INPUT='{"tool_name":"Bash","tool_input":{"command":"forge -p \"Refactor utils.py to use early returns\""}}'
PRE_OUT="$(SIDEKICK_TEST_UUID_OVERRIDE="${EXPECTED_UUID}" \
  HOME="${HOME_SANDBOX}" \
  CLAUDE_PROJECT_DIR="${PROJECT_SANDBOX}" \
  PATH="${STUB_PATH}" \
  bash "${PRE_HOOK}" <<< "${PRE_INPUT}" 2>/dev/null)"

PRE_DECISION="$(printf '%s' "${PRE_OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
PRE_CMD="$(printf '%s' "${PRE_OUT}" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null)"

if [ "${PRE_DECISION}" = "allow" ] \
  && echo "${PRE_CMD}" | grep -q -- "--conversation-id ${EXPECTED_UUID}" \
  && echo "${PRE_CMD}" | grep -q -- "--verbose" \
  && echo "${PRE_CMD}" | grep -q '\[FORGE\]' \
  && echo "${PRE_CMD}" | grep -q '\[FORGE-LOG\]'; then
  assert_pass "e2e_step2_pretooluse_rewrites_command"
else
  assert_fail "e2e_step2_pretooluse_rewrites_command" "decision=${PRE_DECISION} cmd=${PRE_CMD}"
fi

IDX_FILE="${PROJECT_SANDBOX}/.forge/conversations.idx"
if [ -f "${IDX_FILE}" ] && grep -q -- "${EXPECTED_UUID}" "${IDX_FILE}"; then
  assert_pass "e2e_step2_idx_row_appended"
else
  assert_fail "e2e_step2_idx_row_appended" "idx missing or row absent: $(cat "${IDX_FILE}" 2>/dev/null)"
fi

# -----------------------------------------------------------------------------
echo "=== E2E step 3: PostToolUse surfaces STATUS block ==="
# Simulate Forge's stdout stream for the rewritten command. The enforcer's
# rewritten command prefixes lines with [FORGE], and the STATUS block below
# mirrors what Forge emits in practice.
TOOL_OUT=$'[FORGE] Reading utils.py...\n[FORGE] Refactoring with early returns...\n[FORGE] Running tests... 12/12 passed\n[FORGE] STATUS: SUCCESS\n[FORGE] FILES_CHANGED: [utils.py]\n[FORGE] ASSUMPTIONS: []\n[FORGE] PATTERNS_DISCOVERED: []'
POST_INPUT="$(jq -cn --arg cmd "${PRE_CMD}" --arg out "${TOOL_OUT}" \
  '{tool_name:"Bash", tool_input:{command:$cmd}, tool_response:{output:$out}}')"

POST_OUT="$(run_post "${POST_INPUT}")"
POST_CTX="$(printf '%s' "${POST_OUT}" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"

if echo "${POST_CTX}" | grep -q '\[FORGE-SUMMARY\]' \
  && echo "${POST_CTX}" | grep -q 'STATUS: SUCCESS' \
  && echo "${POST_CTX}" | grep -q 'FILES_CHANGED: \[utils.py\]'; then
  assert_pass "e2e_step3_posttooluse_emits_summary"
else
  assert_fail "e2e_step3_posttooluse_emits_summary" "ctx=${POST_CTX}"
fi

# -----------------------------------------------------------------------------
echo "=== E2E step 4: Post-hook surfaces history hint ==="
# Hook emits a /forge-history footer after each task (forge:replay removed in v1.4).
if echo "${POST_CTX}" | grep -q '/forge-history'; then
  assert_pass "e2e_step4_history_hint_in_summary"
else
  assert_fail "e2e_step4_history_hint_in_summary" "history hint missing: ${POST_CTX}"
fi

# -----------------------------------------------------------------------------
echo "=== E2E step 5: deactivate preserves idx, hooks become no-op ==="
rm -f "${HOME_SANDBOX}/.claude/.forge-delegation-active"

# Idx file should still exist with the row from step 2.
if [ -f "${IDX_FILE}" ] && grep -q -- "${EXPECTED_UUID}" "${IDX_FILE}"; then
  assert_pass "e2e_step5_idx_preserved_after_deactivate"
else
  assert_fail "e2e_step5_idx_preserved_after_deactivate" "idx lost after deactivate"
fi

# PreToolUse should now be a no-op.
PRE_POST_DEACT="$(run_pre '{"tool_name":"Bash","tool_input":{"command":"forge -p \"another task\""}}')"
if [ -z "${PRE_POST_DEACT}" ]; then
  assert_pass "e2e_step5_pretooluse_noop_after_deactivate"
else
  assert_fail "e2e_step5_pretooluse_noop_after_deactivate" "got: ${PRE_POST_DEACT}"
fi

# PostToolUse should also be a no-op.
POST_POST_DEACT="$(run_post "${POST_INPUT}")"
if [ -z "${POST_POST_DEACT}" ]; then
  assert_pass "e2e_step5_posttooluse_noop_after_deactivate"
else
  assert_fail "e2e_step5_posttooluse_noop_after_deactivate" "got: ${POST_POST_DEACT}"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

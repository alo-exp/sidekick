#!/usr/bin/env bash
# Unit tests for hooks/validate-release-gate.sh
#
# The hook blocks `gh release create` commands via Claude Code's PreToolUse
# permissionDecision=deny mechanism unless all quality-gate stage markers
# are present in ~/.sidekick/quality-gate-state.
#
# We override HOME to a temp directory for each scenario so we can
# write marker files deterministically without touching the real state.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/validate-release-gate.sh"

PASS=0; FAIL=0
assert_pass() { echo "  [PASS] $1"; PASS=$((PASS+1)); }
assert_fail() { echo "  [FAIL] $1 — $2"; FAIL=$((FAIL+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not in PATH — skipping validate-release-gate tests"
  exit 0
fi

if [ ! -x "${HOOK}" ] && [ ! -r "${HOOK}" ]; then
  echo "Hook script not found at ${HOOK}"
  exit 1
fi

run_hook() {
  # $1 = temp HOME, $2 = JSON payload
  HOME="$1" bash "${HOOK}" <<<"$2"
}

setup_home() {
  local h
  h="$(mktemp -d)"
  mkdir -p "${h}/.sidekick"
  echo "${h}"
}

write_markers() {
  local h="$1"; shift
  : > "${h}/.sidekick/quality-gate-state"
  for s in "$@"; do
    echo "quality-gate-stage-${s}" >> "${h}/.sidekick/quality-gate-state"
  done
}

# ---------------------------------------------------------------------------
# Scenario 1: non-Bash tool → exit 0, no output
# ---------------------------------------------------------------------------
echo "Scenario 1: non-Bash tool passes through"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Read","tool_input":{"file_path":"/etc/hosts"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
if [ "${RC}" -eq 0 ] && [ -z "${OUT}" ]; then
  assert_pass "non-Bash tool: exit 0, no JSON decision"
else
  assert_fail "non-Bash tool" "rc=${RC} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 2: Bash with non-target command → exit 0, no output
# ---------------------------------------------------------------------------
echo "Scenario 2: Bash with non-release command passes through"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
if [ "${RC}" -eq 0 ] && [ -z "${OUT}" ]; then
  assert_pass "Bash non-target: exit 0, no JSON decision"
else
  assert_fail "Bash non-target" "rc=${RC} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 3: gh release create with NO markers → deny
# ---------------------------------------------------------------------------
echo "Scenario 3: release command with no markers is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "no markers: permissionDecision=deny"
else
  assert_fail "no markers deny" "rc=${RC} decision=${DECISION}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 4: gh release create with ALL 4 markers → pass-through
# ---------------------------------------------------------------------------
echo "Scenario 4: release command with all markers passes"
H="$(setup_home)"
write_markers "${H}" 1 2 3 4
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh release create v1.2.1 --generate-notes"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
if [ "${RC}" -eq 0 ] && [ -z "${OUT}" ]; then
  assert_pass "all 4 markers: exit 0, no deny"
else
  assert_fail "all markers pass" "rc=${RC} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 5: stage-10 marker must NOT satisfy stage-1 (anchored match)
# ---------------------------------------------------------------------------
echo "Scenario 5: stage-10 does not satisfy stage-1 (anchored grep)"
H="$(setup_home)"
: > "${H}/.sidekick/quality-gate-state"
# Only a spurious stage-10 marker — stages 1-4 should all still be missing.
echo "quality-gate-stage-10" >> "${H}/.sidekick/quality-gate-state"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
REASON=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ] && [[ "${REASON}" == *"1"* ]] && [[ "${REASON}" == *"2"* ]]; then
  assert_pass "stage-10 does not satisfy stage-1: denied with missing 1,2,3,4"
else
  assert_fail "stage-10 anchored" "rc=${RC} decision=${DECISION} reason=${REASON}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 6: partial markers (1,2 only) → deny listing missing 3,4
# ---------------------------------------------------------------------------
echo "Scenario 6: partial markers deny with correct missing list"
H="$(setup_home)"
write_markers "${H}" 1 2
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
REASON=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ] && [[ "${REASON}" == *"3"* ]] && [[ "${REASON}" == *"4"* ]]; then
  assert_pass "partial markers: denied with 3,4 missing"
else
  assert_fail "partial markers" "rc=${RC} decision=${DECISION} reason=${REASON}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 7: hookEventName is 'PreToolUse' in the output JSON
# ---------------------------------------------------------------------------
echo "Scenario 7: deny JSON has hookEventName=PreToolUse"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
EVENT=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)
if [ "${EVENT}" = "PreToolUse" ]; then
  assert_pass "hookEventName=PreToolUse"
else
  assert_fail "hookEventName" "got=${EVENT}"
fi
rm -rf "${H}"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
exit "${FAIL}"

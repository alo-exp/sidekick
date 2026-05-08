#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Codex skill surface tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
DELEGATE_FILE="${PLUGIN_DIR}/skills/codex-delegate/SKILL.md"
DELEGATE_LEGACY_FILE="${PLUGIN_DIR}/skills/codex-delegate.md"
STOP_FILE="${PLUGIN_DIR}/skills/codex-stop/SKILL.md"
REMOVED_CODEX_FILE="${PLUGIN_DIR}/skills/codex/SKILL.md"
REMOVED_CODEX_LEGACY="${PLUGIN_DIR}/skills/codex.md"
REMOVED_HISTORY_FILE="${PLUGIN_DIR}/skills/codex-history/SKILL.md"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

[ -f "${DELEGATE_FILE}" ] || { echo "ERROR: ${DELEGATE_FILE} missing"; exit 1; }
[ -f "${DELEGATE_LEGACY_FILE}" ] || { echo "ERROR: ${DELEGATE_LEGACY_FILE} missing"; exit 1; }
[ -f "${STOP_FILE}" ] || { echo "ERROR: ${STOP_FILE} missing"; exit 1; }

echo "=== T1: canonical codex-delegate frontmatter ==="
if grep -q '^name: codex-delegate' "${DELEGATE_FILE}"; then
  assert_pass "name: codex-delegate present"
else
  assert_fail "frontmatter" "name: codex-delegate not found"
fi

echo "=== T2: codex-delegate contains runtime delegation guidance ==="
if grep -q 'code exec --full-auto' "${DELEGATE_FILE}" \
  && grep -q 'codex exec --full-auto' "${DELEGATE_FILE}" \
  && grep -q 'coder exec --full-auto' "${DELEGATE_FILE}"; then
  assert_pass "delegate commands for code/codex/coder present"
else
  assert_fail "delegation guidance" "missing one or more runtime command variants"
fi

echo "=== T3: codex-delegate workflow sections present ==="
if grep -q 'STEP 0' "${DELEGATE_FILE}" \
  && grep -q 'Delegation Protocol' "${DELEGATE_FILE}" \
  && grep -q 'Native Workflow' "${DELEGATE_FILE}"; then
  assert_pass "step structure present"
else
  assert_fail "workflow structure" "missing expected sections"
fi

echo "=== T4: codex-stop frontmatter and marker handling ==="
if grep -q '^name: codex-stop' "${STOP_FILE}" \
  && grep -q '\.codex-delegation-active' "${STOP_FILE}"; then
  assert_pass "codex-stop marker workflow present"
else
  assert_fail "codex-stop" "missing name or marker handling"
fi

echo "=== T5: legacy alias points to canonical codex-delegate skill ==="
if grep -q 'skills/codex-delegate/SKILL.md' "${DELEGATE_LEGACY_FILE}" \
  && grep -qi 'deprecated' "${DELEGATE_LEGACY_FILE}" \
  && grep -q '^name: codex-delegate' "${DELEGATE_LEGACY_FILE}"; then
  assert_pass "legacy alias points to canonical delegate skill"
else
  assert_fail "legacy alias" "missing canonical reference, deprecation note, or alias name"
fi

echo "=== T6: removed codex canonical/history skills are absent ==="
if [ ! -f "${REMOVED_CODEX_FILE}" ] \
  && [ ! -f "${REMOVED_CODEX_LEGACY}" ] \
  && [ ! -f "${REMOVED_HISTORY_FILE}" ]; then
  assert_pass "codex, codex legacy, and codex-history files removed"
else
  assert_fail "removed skills" "one or more removed codex skill files still present"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

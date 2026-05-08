#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — skills/codex/SKILL.md Tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
SKILL_FILE="${PLUGIN_DIR}/skills/codex/SKILL.md"
LEGACY_FILE="${PLUGIN_DIR}/skills/codex.md"
DELEGATE_FILE="${PLUGIN_DIR}/skills/codex-delegate/SKILL.md"
DELEGATE_LEGACY_FILE="${PLUGIN_DIR}/skills/codex-delegate.md"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

[ -f "${SKILL_FILE}" ] || { echo "ERROR: ${SKILL_FILE} missing"; exit 1; }
[ -f "${LEGACY_FILE}" ] || { echo "ERROR: ${LEGACY_FILE} missing"; exit 1; }
[ -f "${DELEGATE_FILE}" ] || { echo "ERROR: ${DELEGATE_FILE} missing"; exit 1; }
[ -f "${DELEGATE_LEGACY_FILE}" ] || { echo "ERROR: ${DELEGATE_LEGACY_FILE} missing"; exit 1; }

echo "=== T1: YAML frontmatter contains name: codex ==="
grep -q '^name: codex' "${SKILL_FILE}" && assert_pass "name: codex present" || assert_fail "YAML frontmatter" "name: codex not found"

echo "=== T2: Health Check section present ==="
grep -q 'Health Check' "${SKILL_FILE}" && assert_pass "Health Check section present" || assert_fail "Health Check" "not found"

echo "=== T3: Delegation Protocol section present ==="
grep -q 'Delegation Protocol' "${SKILL_FILE}" && assert_pass "Delegation Protocol section present" || assert_fail "Delegation Protocol" "not found"

echo "=== T4: Native Workflow section present ==="
grep -q 'Native Workflow' "${SKILL_FILE}" && assert_pass "Native Workflow section present" || assert_fail "Native Workflow" "not found"

echo "=== T5: Host Routing section present ==="
if grep -q 'Host Routing' "${SKILL_FILE}" \
  && grep -q 'Claude Code' "${SKILL_FILE}" \
  && grep -q 'Codex' "${SKILL_FILE}"; then
  assert_pass "Host Routing section present"
else
  assert_fail "Host Routing" "not found"
fi

echo "=== T6: codex exec guidance present ==="
if grep -q 'codex exec --full-auto' "${SKILL_FILE}" \
  && grep -q 'code exec --full-auto' "${SKILL_FILE}" \
  && grep -q 'coder exec --full-auto' "${SKILL_FILE}"; then
  assert_pass "codex/code/coder exec guidance present"
else
  assert_fail "delegation command guidance" "missing one of codex/code/coder exec references"
fi

echo "=== T7: MiniMax config guidance present ==="
if grep -q 'MiniMax-M2.7' "${SKILL_FILE}" \
  && grep -q '~/.code/config.toml' "${SKILL_FILE}" \
  && grep -q '~/.codex/config.toml' "${SKILL_FILE}"; then
  assert_pass "MiniMax config guidance present"
else
  assert_fail "MiniMax config" "missing runtime config references"
fi

echo "=== T8: AGENTS.md and subagent guidance present ==="
if grep -q 'AGENTS.md' "${SKILL_FILE}" && grep -q 'subagent' "${SKILL_FILE}"; then
  assert_pass "AGENTS.md and subagent guidance present"
else
  assert_fail "workflow guidance" "missing AGENTS.md or subagent mention"
fi

echo "=== T9: Skill-first wrapper note present ==="
if grep -q 'skills/forge-stop/SKILL.md' "${SKILL_FILE}" \
  && grep -q 'skills/codex-stop/SKILL.md' "${SKILL_FILE}" \
  && grep -q 'commands/' "${SKILL_FILE}" \
  && grep -qiE 'thin wrappers|source of truth' "${SKILL_FILE}"; then
  assert_pass "skill-first wrapper note present"
else
  assert_fail "skill-first wrapper note" "missing skill-first packaging note"
fi

echo "=== T10: Legacy wrapper points to canonical skill ==="
if grep -q 'skills/codex/SKILL.md' "${LEGACY_FILE}" && grep -qi 'deprecated' "${LEGACY_FILE}"; then
  assert_pass "legacy wrapper points to canonical skill"
else
  assert_fail "legacy wrapper" "missing canonical skill reference or deprecation note"
fi

echo "=== T11: codex-delegate bridge points to canonical skill ==="
if grep -q 'skills/codex/SKILL.md' "${DELEGATE_FILE}" \
  && grep -qi 'bridge' "${DELEGATE_FILE}" \
  && grep -q '^name: codex-delegate' "${DELEGATE_FILE}"; then
  assert_pass "codex-delegate bridge points to canonical skill"
else
  assert_fail "codex-delegate bridge" "missing canonical skill reference, bridge note, or alias name"
fi

echo "=== T12: codex-delegate legacy flat alias remains available ==="
if grep -q 'skills/codex-delegate/SKILL.md' "${DELEGATE_LEGACY_FILE}" \
  && grep -qi 'deprecated' "${DELEGATE_LEGACY_FILE}" \
  && grep -q '^name: codex-delegate' "${DELEGATE_LEGACY_FILE}"; then
  assert_pass "codex-delegate legacy flat alias remains available"
else
  assert_fail "codex-delegate legacy alias" "missing canonical bridge reference, deprecation note, or alias name"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

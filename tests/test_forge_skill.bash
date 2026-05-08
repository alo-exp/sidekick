#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — skills/forge/SKILL.md Tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0; SKIP=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
SKILL_FILE="${PLUGIN_DIR}/skills/forge/SKILL.md"

green='\033[0;32m'; red='\033[0;31m'; yellow='\033[0;33m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }
skip()        { echo -e "${yellow}SKIP${reset} $1: $2"; SKIP=$((SKIP+1)); }

if [ ! -f "${SKILL_FILE}" ]; then
  echo "ERROR: ${SKILL_FILE} not found"
  exit 1
fi

echo "=== T1: YAML frontmatter contains name: forge-delegate ==="
grep -q 'name: forge-delegate' "${SKILL_FILE}" && assert_pass "name: forge-delegate present" || assert_fail "YAML frontmatter" "name: forge-delegate not found"

echo "=== T2: Activation section present ==="
grep -q '## Activation' "${SKILL_FILE}" && assert_pass "Activation section present" || assert_fail "Activation section" "not found"

echo "=== T3: Health Check subsection present ==="
grep -q 'Health Check' "${SKILL_FILE}" && assert_pass "Health Check subsection present" || assert_fail "Health Check" "not found"

echo "=== T4: Deactivation section present ==="
grep -q 'Deactivat' "${SKILL_FILE}" && assert_pass "Deactivation section present" || assert_fail "Deactivation" "not found"

echo "=== T5: Level 1 fallback section present ==="
grep -q 'Level 1' "${SKILL_FILE}" && assert_pass "Level 1 fallback present" || assert_fail "Level 1 fallback" "not found"

echo "=== T6: Level 2 fallback section present ==="
grep -q 'Level 2' "${SKILL_FILE}" && assert_pass "Level 2 fallback present" || assert_fail "Level 2 fallback" "not found"

echo "=== T7: Level 3 fallback section present ==="
grep -q 'Level 3' "${SKILL_FILE}" && assert_pass "Level 3 fallback present" || assert_fail "Level 3 fallback" "not found"

echo "=== T8: AGENTS.md Mentoring section present ==="
grep -q 'AGENTS.md' "${SKILL_FILE}" && grep -q 'Mentoring' "${SKILL_FILE}" && assert_pass "AGENTS.md Mentoring section present" || assert_fail "AGENTS.md Mentoring" "not found"

echo "=== T9: Token Optimization section present ==="
grep -q 'Token' "${SKILL_FILE}" && grep -q 'Optim' "${SKILL_FILE}" && assert_pass "Token Optimization section present" || assert_fail "Token Optimization" "not found"

echo "=== T10: Skill Injection section present ==="
grep -q 'Skill Injection' "${SKILL_FILE}" && assert_pass "Skill Injection section present" || assert_fail "Skill Injection" "not found"

echo "=== T11: Canonical stop skill note present ==="
if grep -q 'skills/forge-stop/SKILL.md' "${SKILL_FILE}" \
  && grep -qiE 'canonical|source of truth' "${SKILL_FILE}" \
  && ! grep -q 'skills/forge-history/SKILL.md' "${SKILL_FILE}"; then
  assert_pass "Canonical stop skill note present"
else
  assert_fail "Canonical stop note" "missing canonical stop-skill note or stale forge-history reference present"
fi

echo "=== T12: forge-history skill file removed ==="
if [ ! -f "${PLUGIN_DIR}/skills/forge-history/SKILL.md" ]; then
  assert_pass "forge-history skill file removed"
else
  assert_fail "forge-history removal" "skills/forge-history/SKILL.md still present"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

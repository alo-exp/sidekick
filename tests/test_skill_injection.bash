#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Skill Injection Infrastructure Tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0; SKIP=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
FORGE_SKILLS="${PLUGIN_DIR}/.forge/skills"

green='\033[0;32m'; red='\033[0;31m'; yellow='\033[0;33m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }
skip()        { echo -e "${yellow}SKIP${reset} $1: $2"; SKIP=$((SKIP+1)); }

echo "=== T1: quality-gates SKILL.md exists ==="
[ -f "${FORGE_SKILLS}/quality-gates/SKILL.md" ] && assert_pass "quality-gates/SKILL.md exists" || assert_fail "quality-gates/SKILL.md" "not found"

echo "=== T2: code-review SKILL.md exists ==="
[ -f "${FORGE_SKILLS}/code-review/SKILL.md" ] && assert_pass "code-review/SKILL.md exists" || assert_fail "code-review/SKILL.md" "not found"

echo "=== T3: security SKILL.md exists ==="
[ -f "${FORGE_SKILLS}/security/SKILL.md" ] && assert_pass "security/SKILL.md exists" || assert_fail "security/SKILL.md" "not found"

echo "=== T4: testing-strategy SKILL.md exists ==="
[ -f "${FORGE_SKILLS}/testing-strategy/SKILL.md" ] && assert_pass "testing-strategy/SKILL.md exists" || assert_fail "testing-strategy/SKILL.md" "not found"

echo "=== T5: Each bootstrap skill has trigger field ==="
ALL_HAVE_TRIGGER=true
for skill in quality-gates code-review security testing-strategy; do
  if ! grep -q 'trigger:' "${FORGE_SKILLS}/${skill}/SKILL.md"; then
    ALL_HAVE_TRIGGER=false
    assert_fail "trigger field" "missing in ${skill}/SKILL.md"
    break
  fi
done
[ "${ALL_HAVE_TRIGGER}" = "true" ] && assert_pass "All bootstrap skills have trigger field"

echo "=== T6: No Claude-specific tool invocations in bootstrap skills ==="
TOOL_HITS=$(grep -rlE 'Use the (Read|Write|Edit|Bash|AskUserQuestion|TodoWrite) tool' "${FORGE_SKILLS}/" 2>/dev/null || true)
TOOL_HITS=$(echo "${TOOL_HITS}" | grep -c . || true)
if [ "${TOOL_HITS}" -eq 0 ]; then
  assert_pass "No Claude-specific tool invocations in bootstrap skills"
else
  assert_fail "Claude tool references" "found in ${TOOL_HITS} file(s)"
fi

echo "=== T7: SKILL.md contains skill mapping/injection reference ==="
grep -qiE 'mapping|inject' "${PLUGIN_DIR}/skills/forge/SKILL.md" && assert_pass "Skill mapping/injection referenced in SKILL.md" || assert_fail "Skill mapping" "not found in SKILL.md"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

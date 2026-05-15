#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Fallback Ladder Structure Tests (skills/forge/SKILL.md)
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

# Extract sections for targeted grep
LEVEL1=$(sed -n '/^### Level 1/,/^### Level 2/p' "${SKILL_FILE}")
LEVEL2=$(sed -n '/^### Level 2/,/^### Level 3/p' "${SKILL_FILE}")
LEVEL3=$(sed -n '/^### Level 3/,/^---$/p' "${SKILL_FILE}")
FAILURE_DETECT=$(sed -n '/^## Failure Detection/,/^---$/p' "${SKILL_FILE}")

echo "=== T1: Level 1 contains Guide ==="
if echo "${LEVEL1}" | grep -qi "guide"; then
  assert_pass "Level 1 section contains 'Guide'"
else
  assert_fail "Level 1 Guide" "not found"
fi

echo "=== T2: Level 2 contains Handhold and subtask decomposition ==="
if echo "${LEVEL2}" | grep -qi "handhold" && echo "${LEVEL2}" | grep -qiE "decompos|subtask"; then
  assert_pass "Level 2 contains Handhold and subtask/decomposition reference"
else
  assert_fail "Level 2 Handhold+subtask" "missing one or both keywords"
fi

echo "=== T3: Level 2 mentions 3-attempt limit ==="
if echo "${LEVEL2}" | grep -qE "3|three" && echo "${LEVEL2}" | grep -qiE "attempt|fail|retry"; then
  assert_pass "Level 2 mentions 3-attempt limit"
else
  assert_fail "Level 2 3-attempt" "not found"
fi

echo "=== T4: Level 3 contains Take over ==="
if echo "${LEVEL3}" | grep -qi "take over"; then
  assert_pass "Level 3 section contains 'Take over'"
else
  assert_fail "Level 3 Take over" "not found"
fi

echo "=== T5: Level 3 contains DEBRIEF template ==="
if echo "${LEVEL3}" | grep -qiE "DEBRIEF|debrief"; then
  assert_pass "Level 3 contains DEBRIEF reference"
else
  assert_fail "Level 3 DEBRIEF" "not found"
fi

echo "=== T6: Level 3 contains session marker controls ==="
if echo "${LEVEL3}" | grep -q 'sidekick forge-level3 start' \
  && echo "${LEVEL3}" | grep -q 'sidekick forge-level3 stop'; then
  assert_pass "Level 3 contains start/stop marker controls"
else
  assert_fail "Level 3 marker controls" "start/stop commands not found"
fi

echo "=== T7: Failure Detection covers signal types ==="
if echo "${FAILURE_DETECT}" | grep -qiE "error|stall|wrong.output|exit.code"; then
  assert_pass "Failure Detection section covers signal types"
else
  assert_fail "Failure Detection signals" "not found"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

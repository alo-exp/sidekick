#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — AGENTS.md Deduplication & Session Log Tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0; SKIP=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"

green='\033[0;32m'; red='\033[0;31m'; yellow='\033[0;33m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }
skip()        { echo -e "${yellow}SKIP${reset} $1: $2"; SKIP=$((SKIP+1)); }

echo "=== T1: AGENTS.md exists at project root ==="
[ -f "${PLUGIN_DIR}/AGENTS.md" ] && assert_pass "AGENTS.md exists" || assert_fail "AGENTS.md" "not found at project root"

echo "=== T2: AGENTS.md contains Project Conventions section ==="
grep -q '## Project Conventions' "${PLUGIN_DIR}/AGENTS.md" && assert_pass "Project Conventions section present" || assert_fail "Project Conventions" "not found"

echo "=== T3: SKILL.md mentions deduplication ==="
grep -qiE 'dedup|duplicate|semantically equivalent' "${PLUGIN_DIR}/skills/forge/SKILL.md" && assert_pass "Deduplication logic referenced in SKILL.md" || assert_fail "Deduplication" "not mentioned in SKILL.md"

echo "=== T4: docs/sessions/ directory exists ==="
[ -d "${PLUGIN_DIR}/docs/sessions" ] && assert_pass "docs/sessions/ directory exists" || assert_fail "docs/sessions/" "directory not found"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

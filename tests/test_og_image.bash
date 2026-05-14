#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — social preview image tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

expect_contains() {
  local path="$1" needle="$2" label="$3"
  if grep -Fq -- "${needle}" "${ROOT}/${path}"; then
    pass "${label}"
  else
    fail "${label}" "missing '${needle}' in ${path}"
  fi
}

echo "=== T1: Social preview highlights current shared-agent support ==="
expect_contains "docs/og-image.html" "Reduce Claude Code and Codex costs by up to" "og image keeps the cost-focused headline"
expect_contains "docs/og-image.html" "Claude Code and Codex can both route work to Forge or Kay" "og image describes Forge and Kay as shared agents"
expect_contains "docs/og-image.html" "MiniMax.io and OpenCode Go" "og image highlights MiniMax.io and OpenCode Go"
expect_contains "docs/og-image.html" "Available · Kay Agent" "og image badge names Kay as an agent"
expect_contains "docs/og-image.html" "<div class=\"card-name\">Kay</div>" "og image card names Kay"
expect_contains "docs/og-image.html" "Every Code Agent" "og image role describes Kay"
expect_contains "docs/og-image.html" "Code exec path" "og image describes Kay execution path"

echo "=== T2: Kay is surfaced before Forge in the preview pills ==="
kay_line="$(grep -n '<span class="pill">🧠 Kay</span>' "${ROOT}/docs/og-image.html" | head -n1 | cut -d: -f1 || true)"
forge_line="$(grep -n '<span class="pill">🦀 ForgeCode</span>' "${ROOT}/docs/og-image.html" | head -n1 | cut -d: -f1 || true)"
if [ -n "${kay_line}" ] && [ -n "${forge_line}" ] && [ "${kay_line}" -lt "${forge_line}" ]; then
  pass "preview pills order is Kay → ForgeCode"
else
  fail "preview pills order is Kay → ForgeCode" "lines: Kay='${kay_line}', ForgeCode='${forge_line}'"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

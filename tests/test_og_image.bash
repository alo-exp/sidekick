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

echo "=== T1: Social preview highlights Kay support ==="
expect_contains "docs/og-image.html" "Now supporting Kay, the multi-AI fork of OSS Codex" "og image highlights Kay support"
expect_contains "docs/og-image.html" "Available · Kay" "og image badge names Kay"
expect_contains "docs/og-image.html" "<div class=\"card-name\">Kay</div>" "og image card names Kay"
expect_contains "docs/og-image.html" "Multi-AI Fork of OSS Codex" "og image role describes Kay"

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

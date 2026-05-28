#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin -- help-site navigation tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

expect_file() {
  local rel="$1"
  if [ -f "${ROOT}/${rel}" ]; then pass "file present: ${rel}"; else fail "file present: ${rel}" "missing"; fi
}

expect_contains() {
  local rel="$1" needle="$2" label="$3"
  if grep -Fq -- "${needle}" "${ROOT}/${rel}"; then pass "${label}"; else fail "${label}" "missing ${needle} in ${rel}"; fi
}

expect_absent() {
  local rel="$1" needle="$2" label="$3"
  if grep -Fqi -- "${needle}" "${ROOT}/${rel}"; then fail "${label}" "unexpected ${needle} in ${rel}"; else pass "${label}"; fi
}

pages=(
  site/help/index.html
  site/help/getting-started/index.html
  site/help/concepts/index.html
  site/help/workflows/index.html
  site/help/reference/index.html
  site/help/troubleshooting/index.html
)

echo "=== T1: help pages exist and share navigation ==="
for page in "${pages[@]}"; do
  expect_file "${page}"
  expect_contains "${page}" "Sidekick Help" "${page} includes help shell"
  expect_contains "${page}" "Getting Started" "${page} links getting started"
  expect_contains "${page}" "Concepts" "${page} links concepts"
  expect_contains "${page}" "Workflows" "${page} links workflows"
  expect_contains "${page}" "Reference" "${page} links reference"
  expect_contains "${page}" "Troubleshooting" "${page} links troubleshooting"
done

echo "=== T2: help content covers Kay, Codex, and verification ==="
expect_contains "site/help/index.html" "/sidekick:kay-delegate" "help home includes Kay activation"
expect_contains "site/help/index.html" "/sidekick:codex-delegate" "help home includes Codex activation"
expect_contains "site/help/concepts/index.html" "active-sidekick" "concepts explain active selector"
expect_contains "site/help/workflows/index.html" "kay exec" "workflows explain Kay runtime"
expect_contains "site/help/workflows/index.html" "codex exec" "workflows explain Codex runtime"
expect_contains "site/help/reference/index.html" "bash tests/run_unit.bash" "reference includes strict tests"
expect_contains "site/help/troubleshooting/index.html" "Verification Fails" "troubleshooting covers verification recovery"
expect_contains "site/help/search.js" "Kay exec and Codex exec" "search index includes supported runtimes"

echo "=== T3: help site has no removed sidekick copy ==="
for page in "${pages[@]}" site/help/search.js; do
  expect_absent "${page}" "forge" "${page} is free of removed sidekick text"
  expect_absent "${page}" "forgecode" "${page} is free of removed runtime text"
done

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

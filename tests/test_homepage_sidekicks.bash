#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — homepage sidekick card tests
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

expect_not_contains() {
  local path="$1" needle="$2" label="$3"
  if grep -Fq -- "${needle}" "${ROOT}/${path}"; then
    fail "${label}" "unexpected '${needle}' in ${path}"
  else
    pass "${label}"
  fi
}

extract_sidekick_section() {
  awk '
    /<!-- ───── SIDEKICKS ───── -->/ { in_section=1; next }
    /<!-- ───── BENCHMARK ───── -->/ { if (in_section) exit }
    in_section { print }
  ' "${ROOT}/docs/index.html"
}

echo "=== T1: Homepage copy highlights current Sidekick support ==="
expect_contains "docs/index.html" "Delegate implementation work to" "homepage hero headline describes delegation"
expect_contains "docs/index.html" "<p class=\"subtitle\"><strong>Give Claude Code and Codex execution sidekicks.</strong>" "homepage subtitle leads with the sidekick claim"
if grep -F '<h1>' "${ROOT}/docs/index.html" | grep -Fq "Give Claude Code and Codex execution sidekicks"; then
  fail "homepage hero headline excludes the sidekick claim" "subtitle text still appears in the h1"
else
  pass "homepage hero headline excludes the sidekick claim"
fi
expect_contains "docs/index.html" "Sidekick installs and orchestrates Forge for Claude Code and Kay for Code/Codex workflows" "homepage describes current shipped runtimes"
expect_contains "docs/index.html" "Claude Code delegates to Forge. Code and Codex workflows route to Kay" "homepage describes host-specific delegation"
expect_contains "docs/index.html" "Every Code extension line" "homepage describes Kay as the Every Code runtime"
expect_contains "docs/index.html" "code exec --full-auto" "homepage documents Kay primary exec path"
expect_contains "docs/index.html" "MiniMax M2.7" "homepage highlights Kay MiniMax default"
expect_not_contains "docs/index.html" "OpenCode Go" "homepage removes stale OpenCode Go copy"
expect_not_contains "docs/index.html" "<div class=\"sk-name\">OpenCode</div>" "homepage removes OpenCode sidekick card"

echo "=== T2: Sidekick cards appear in the requested order ==="
section="$(extract_sidekick_section)"
kay_line="$(printf '%s\n' "${section}" | grep -n '<div class="sk-name">Kay</div>' | head -n1 | cut -d: -f1 || true)"
forge_line="$(printf '%s\n' "${section}" | grep -n '<div class="sk-name">Forge</div>' | head -n1 | cut -d: -f1 || true)"

if [ -n "${kay_line}" ] && [ -n "${forge_line}" ] && [ "${kay_line}" -lt "${forge_line}" ]; then
  pass "homepage card order is Kay → Forge"
else
  fail "homepage card order is Kay → Forge" "lines: Kay='${kay_line}', Forge='${forge_line}'"
fi
expect_not_contains "docs/index.html" "<div class=\"sk-name\">Pilot</div>" "homepage sidekick cards exclude unshipped Pilot card"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

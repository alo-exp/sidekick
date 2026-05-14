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

extract_sidekick_section() {
  awk '
    /<!-- ───── SIDEKICKS ───── -->/ { in_section=1; next }
    /<!-- ───── BENCHMARK ───── -->/ { if (in_section) exit }
    in_section { print }
  ' "${ROOT}/docs/index.html"
}

echo "=== T1: Homepage copy highlights Claude and Codex support ==="
expect_contains "docs/index.html" "Reduce Claude Code and Codex Costs" "homepage hero headline mentions both hosts"
expect_contains "docs/index.html" "<p class=\"subtitle\"><strong>Give Both Hosts the Sidekick They're Missing.</strong>" "homepage subtitle leads with the sidekick claim"
if grep -F '<h1>' "${ROOT}/docs/index.html" | grep -Fq "Give Both Hosts the Sidekick They're Missing"; then
  fail "homepage hero headline excludes the sidekick claim" "subtitle text still appears in the h1"
else
  pass "homepage hero headline excludes the sidekick claim"
fi
expect_contains "docs/index.html" "Sidekick now supports both Claude and Codex" "homepage highlights Claude and Codex support"
expect_contains "docs/index.html" "Claude delegates to Forge, Codex delegates to Kay" "homepage describes host-specific delegation"
expect_contains "docs/index.html" "Forge and Kay both support MiniMax.io" "homepage highlights MiniMax.io support"
expect_contains "docs/index.html" "Kay also supports OpenCode Go" "homepage highlights OpenCode Go support"
expect_contains "docs/index.html" "multi-AI fork of OSS Codex" "homepage describes Kay as a multi-AI Codex fork"

echo "=== T2: Sidekick cards appear in the requested order ==="
section="$(extract_sidekick_section)"
kay_line="$(printf '%s\n' "${section}" | grep -n '<div class="sk-name">Kay</div>' | head -n1 | cut -d: -f1 || true)"
forge_line="$(printf '%s\n' "${section}" | grep -n '<div class="sk-name">Forge</div>' | head -n1 | cut -d: -f1 || true)"
pilot_line="$(printf '%s\n' "${section}" | grep -n '<div class="sk-name">Pilot</div>' | head -n1 | cut -d: -f1 || true)"

if [ -n "${kay_line}" ] && [ -n "${forge_line}" ] && [ -n "${pilot_line}" ] &&
  [ "${kay_line}" -lt "${forge_line}" ] && [ "${forge_line}" -lt "${pilot_line}" ]; then
  pass "homepage card order is Kay → Forge → Pilot"
else
  fail "homepage card order is Kay → Forge → Pilot" "lines: Kay='${kay_line}', Forge='${forge_line}', Pilot='${pilot_line}'"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

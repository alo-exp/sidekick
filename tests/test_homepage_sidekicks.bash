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
expect_contains "docs/index.html" "Reduce Claude Code and Codex Costs by up to" "homepage keeps the cost-focused hero headline"
expect_contains "docs/index.html" "<p class=\"subtitle\"><strong>Give Both Hosts the Sidekick They're Missing.</strong>" "homepage subtitle leads with the shared-host claim"
if grep -F '<h1>' "${ROOT}/docs/index.html" | grep -Fq "Give Claude Code and Codex execution sidekicks"; then
  fail "homepage hero headline excludes the sidekick claim" "subtitle text still appears in the h1"
else
  pass "homepage hero headline excludes the sidekick claim"
fi
expect_contains "docs/index.html" "Sidekick gives Claude Code and Codex the same two implementation agents: Forge and Kay" "homepage describes Forge and Kay as shared agents"
expect_contains "docs/index.html" "Claude Code and Codex can both work with Forge and Kay" "homepage avoids host-specific agent mapping"
expect_contains "docs/index.html" "Every Code Agent · MiniMax.io + OpenCode Go" "homepage describes Kay as the Every Code agent"
expect_contains "docs/index.html" "code exec --full-auto" "homepage documents Kay primary exec path"
expect_contains "docs/index.html" "MiniMax M2.7" "homepage highlights Kay MiniMax default"
expect_contains "docs/index.html" "OpenCode Go" "homepage highlights OpenCode Go compatibility"
expect_not_contains "docs/index.html" "OpenRouter" "homepage does not highlight OpenRouter"
expect_not_contains "docs/index.html" "Forge for Claude Code. Kay for Code/Codex" "homepage removes stale host-specific mapping"
expect_not_contains "docs/index.html" "Sidekick installs and orchestrates Forge for Claude Code and Kay for Code/Codex workflows" "homepage removes stale runtime-specific copy"
expect_not_contains "docs/index.html" "<div class=\"sk-name\">OpenCode</div>" "homepage removes OpenCode sidekick card"

echo "=== T2: Sidekick cards appear in the requested order ==="
section="$(extract_sidekick_section)"
kay_line="$(printf '%s\n' "${section}" | grep -n '<div class="sk-name">Kay</div>' | head -n1 | cut -d: -f1 || true)"
forge_line="$(printf '%s\n' "${section}" | grep -n '<div class="sk-name">Forge</div>' | head -n1 | cut -d: -f1 || true)"
pilot_line="$(printf '%s\n' "${section}" | grep -n '<div class="sk-name">Pilot</div>' | head -n1 | cut -d: -f1 || true)"

if [ -n "${kay_line}" ] && [ -n "${forge_line}" ] && [ -n "${pilot_line}" ] && [ "${kay_line}" -lt "${forge_line}" ] && [ "${forge_line}" -lt "${pilot_line}" ]; then
  pass "homepage card order is Kay → Forge → Pilot"
else
  fail "homepage card order is Kay → Forge → Pilot" "lines: Kay='${kay_line}', Forge='${forge_line}', Pilot='${pilot_line}'"
fi
expect_contains "docs/index.html" "<div class=\"sk-name\">Pilot</div>" "homepage restores the Pilot card"

echo "=== T3: Terminal-Bench 2.0 rows are current ==="
expect_contains "docs/index.html" "ForgeCode currently holds #2, #4, and #6" "homepage benchmark summary uses current Forge ranks"
expect_contains "docs/index.html" "GPT-5.5" "homepage benchmark includes current Codex CLI leader"
expect_contains "docs/index.html" "TongAgents" "homepage benchmark includes current #3 entry"
expect_contains "docs/index.html" "<span class=\"rank-badge\">#4</span>" "homepage benchmark marks ForgeCode at #4"
expect_contains "docs/index.html" "<span style=\"color:var(--text-dim);font-family:var(--font-mono)\">#53</span>" "homepage benchmark updates OpenCode rank"
expect_not_contains "docs/index.html" "82.9%" "homepage removes stale Pilot benchmark score"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

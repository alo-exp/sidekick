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

expect_not_contains() {
  local path="$1" needle="$2" label="$3"
  if grep -Fq -- "${needle}" "${ROOT}/${path}"; then
    fail "${label}" "unexpected '${needle}' in ${path}"
  else
    pass "${label}"
  fi
}

echo "=== T1: Social preview highlights current host and agent support ==="
expect_contains "docs/og-image.html" "Claude Code + Codex" "og image names both supported hosts"
expect_contains "docs/og-image.html" "Terminal-Bench 2.0" "og image anchors benchmark claim"
expect_contains "docs/og-image.html" "Kay (OSS Codex)" "og image names Kay with OSS Codex identity"
expect_contains "docs/og-image.html" "Forge" "og image names Forge"
expect_contains "docs/og-image.html" "coding agents," "og image uses concise coding agents headline"
expect_contains "docs/og-image.html" "as</span> Sidekicks" "og image uses capital-S Sidekicks headline"
expect_not_contains "docs/og-image.html" "coding agents as your sidekicks" "og image avoids lowercase sidekicks headline"
expect_contains "docs/og-image.html" "#1 Codex CLI lineage" "og image highlights Kay upstream #1 result"
expect_contains "docs/og-image.html" "#2 ForgeCode" "og image highlights ForgeCode #2 result"
expect_contains "docs/og-image.html" "82.0%" "og image includes Codex CLI score"
expect_contains "docs/og-image.html" "81.8%" "og image includes ForgeCode score"
expect_contains "docs/og-image.html" "Claude Code and Codex can delegate to Kay (OSS Codex) or Forge" "og image states shared host-to-agent support concisely"
expect_not_contains "docs/og-image.html" "Both hosts can delegate to both execution agents" "og image removes verbose host-to-agent sentence"
expect_not_contains "docs/og-image.html" "2026-04-23" "og image omits rank dates to reduce clutter"
expect_not_contains "docs/og-image.html" "2026-03-12" "og image omits rank dates to reduce clutter"
expect_not_contains "docs/og-image.html" "Kay follows the Codex agent line" "og image removes paragraph copy inside Kay card"
expect_not_contains "docs/og-image.html" "Reduce Claude Code and Codex costs by up to" "og image removes old cost-first headline"
expect_not_contains "docs/og-image.html" "Available · Kay Agent" "og image removes old single-agent Kay badge"

echo "=== T2: Kay and Forge benchmark cards are ordered #1 then #2 ==="
kay_line="$(grep -n '<div class="rank">#1</div>' "${ROOT}/docs/og-image.html" | head -n1 | cut -d: -f1 || true)"
forge_line="$(grep -n '<div class="rank">#2</div>' "${ROOT}/docs/og-image.html" | head -n1 | cut -d: -f1 || true)"
if [ -n "${kay_line}" ] && [ -n "${forge_line}" ] && [ "${kay_line}" -lt "${forge_line}" ]; then
  pass "preview cards order is Kay/Codex #1 before Forge #2"
else
  fail "preview cards order is Kay/Codex #1 before Forge #2" "lines: #1='${kay_line}', #2='${forge_line}'"
fi

echo "=== T3: Generated PNG keeps OpenGraph dimensions ==="
if file "${ROOT}/docs/og-image.png" | grep -Fq "1200 x 630"; then
  pass "og image PNG is 1200x630"
else
  fail "og image PNG is 1200x630" "$(file "${ROOT}/docs/og-image.png" 2>/dev/null || echo missing)"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

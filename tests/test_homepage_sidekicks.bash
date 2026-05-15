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
expect_contains "docs/index.html" "Forge and Kay route implementation through multiple lower-cost AI API backends" "homepage explains low-cost API routing"
expect_contains "docs/index.html" "Claude Code or Codex stays focused on planning, review, and agent mentoring" "homepage explains host AI mentoring"
if grep -F '<h1>' "${ROOT}/docs/index.html" | grep -Fq "Give Claude Code and Codex execution sidekicks"; then
  fail "homepage hero headline excludes the sidekick claim" "subtitle text still appears in the h1"
else
  pass "homepage hero headline excludes the sidekick claim"
fi
expect_contains "docs/index.html" "Advisor Pattern and Continuous Mentoring for Execution Agents" "homepage highlights the advisor pattern and mentoring with title case"
expect_contains "docs/index.html" "execution AI agents such as Forge and Kay" "homepage describes Forge and Kay as execution AIs"
expect_contains "docs/index.html" "<span>Host AI Agents Advise and Mentor</span><span>Execution AI Agents Execute</span>" "homepage splits the host/execution agent heading"
expect_contains "docs/index.html" "Claude Code and Codex can both route work to Forge or Kay" "homepage avoids host-specific agent mapping"
expect_contains "docs/index.html" "Every Code Agent · MiniMax.io + OpenCode Go" "homepage describes Kay as the Every Code agent"
expect_contains "docs/index.html" "Codex CLI lineage: #6 on" "homepage highlights Kay's Codex lineage"
expect_contains "docs/index.html" "Activation surface: kay-delegate" "homepage documents Kay activation surface"
expect_not_contains "docs/index.html" "code exec" "homepage removes deprecated code exec copy"
expect_contains "docs/index.html" "MiniMax M2.7" "homepage highlights Kay MiniMax default"
expect_contains "docs/index.html" "OpenCode Go" "homepage highlights OpenCode Go compatibility"
expect_contains "docs/index.html" "<span class=\"hero-pill\"><i data-lucide=\"key\"></i> OpenCode Go</span>" "homepage uses key icon for OpenCode Go API access"
expect_not_contains "docs/index.html" "<span class=\"hero-pill\"><i data-lucide=\"code-2\"></i> OpenCode Go</span>" "homepage removes code icon from OpenCode Go pill"
expect_not_contains "docs/index.html" "OpenRouter" "homepage does not highlight OpenRouter"
expect_not_contains "docs/index.html" "Start with the right doc" "homepage removes the documentation landing section"
expect_not_contains "docs/index.html" "id=\"docs-map\"" "homepage removes the docs-map section"
expect_not_contains "docs/index.html" "extraKnownMarketplaces" "homepage removes settings.json installation instructions"
expect_not_contains "docs/index.html" "enabledPlugins" "homepage removes settings.json enablement instructions"
expect_not_contains "docs/index.html" "Auto-Install" "homepage removes the Auto-Install hero pill"
expect_not_contains "docs/index.html" "Config path" "homepage backend table removes config path column"
expect_not_contains "docs/index.html" "Forge for Claude Code. Kay for Code/Codex" "homepage removes stale host-specific mapping"
expect_not_contains "docs/index.html" "Sidekick installs and orchestrates Forge for Claude Code and Kay for Code/Codex workflows" "homepage removes stale runtime-specific copy"
expect_not_contains "docs/index.html" "SessionStart hooks install missing agent assets" "homepage removes session-start runtime sync copy"
expect_contains "docs/index.html" "Session-Gated Hooks" "homepage describes per-session hook activation"
expect_not_contains "docs/index.html" "<div class=\"sk-name\">OpenCode</div>" "homepage removes OpenCode sidekick card"
expect_contains "docs/index.html" "sidekick-theme-v2" "homepage uses versioned theme storage"
expect_not_contains "docs/index.html" "localStorage.getItem('sidekick-theme')" "homepage ignores legacy light theme preference on first load"
expect_contains "docs/index.html" "localStorage.removeItem('sidekick-theme')" "homepage clears legacy theme storage after a new choice"

echo "=== T2: Sidekick cards appear in the requested order ==="
section="$(extract_sidekick_section)"
kay_line="$(printf '%s\n' "${section}" | grep -n '<div class="sk-name">Kay</div>' | head -n1 | cut -d: -f1 || true)"
forge_line="$(printf '%s\n' "${section}" | grep -n '<div class="sk-name">Forge</div>' | head -n1 | cut -d: -f1 || true)"
pilot_line="$(printf '%s\n' "${section}" | grep -n '<div class="sk-name">Pilot</div>' | head -n1 | cut -d: -f1 || true)"

if [ -n "${kay_line}" ] && [ -n "${forge_line}" ] && [ -n "${pilot_line}" ] && [ "${kay_line}" -lt "${forge_line}" ] && [ "${forge_line}" -lt "${pilot_line}" ]; then
  pass "homepage card order is Kay -> Forge -> Pilot"
else
  fail "homepage card order is Kay -> Forge -> Pilot" "lines: Kay='${kay_line}', Forge='${forge_line}', Pilot='${pilot_line}'"
fi
expect_contains "docs/index.html" "<div class=\"sk-name\">Pilot</div>" "homepage restores the Pilot card"

echo "=== T3: Terminal-Bench 2.0 rows are current ==="
expect_contains "docs/index.html" "Kay (Codex) and Forge on" "homepage benchmark heading includes Kay and Forge"
expect_contains "docs/index.html" "Verified May 15, 2026: Codex CLI ranks #6, ForgeCode holds #7, #11, and #13, Claude Code ranks #53, and OpenCode ranks #67" "homepage benchmark summary uses current Kay/Codex and Forge ranks"
expect_contains "docs/index.html" "GPT-5.5" "homepage benchmark includes current Codex row"
expect_contains "docs/index.html" "Codex CLI → Kay upstream" "homepage highlights Codex CLI as Kay upstream"
expect_contains "docs/index.html" "NexAU-AHE" "homepage benchmark includes current #2 entry"
expect_contains "docs/index.html" "<span class=\"rank-badge\">#6</span>" "homepage benchmark marks Codex CLI at #6"
expect_contains "docs/index.html" "<span class=\"rank-badge\">#7</span>" "homepage benchmark marks ForgeCode at #7"
expect_contains "docs/index.html" "<span class=\"rank-badge\">#11</span>" "homepage benchmark marks ForgeCode at #11"
expect_contains "docs/index.html" "<span class=\"rank-badge\">#13</span>" "homepage benchmark marks ForgeCode at #13"
expect_not_contains "docs/index.html" "<span class=\"rank-badge\">#29</span>" "homepage does not highlight weak #29 Codex row"
expect_contains "docs/index.html" "<span style=\"color:var(--text-dim);font-family:var(--font-mono)\">#67</span>" "homepage benchmark updates OpenCode rank"
expect_not_contains "docs/index.html" "82.9%" "homepage removes stale Pilot benchmark score"

echo "=== T4: Installation and delegation examples are plugin-first ==="
expect_contains "docs/index.html" "/plugin install" "homepage gives Claude Code plugin install instruction"
expect_contains "docs/index.html" "alo-labs/sidekick" "homepage names Claude Sidekick plugin"
expect_contains "docs/index.html" "codex plugin marketplace add" "homepage gives Codex plugin marketplace instruction"
expect_contains "docs/index.html" "codex plugin marketplace add</span> <span class=\"val\">alo-exp/sidekick" "homepage uses the working Codex marketplace source"
expect_not_contains "docs/index.html" "codex plugin marketplace add</span> <span class=\"val\">alo-labs/sidekick" "homepage does not use the broken Codex owner/repo pair"
expect_contains "docs/index.html" "Install Once, Delegate Per Session" "homepage removes sync-every-session install framing"
expect_not_contains "docs/index.html" "Install Once, Sync Every Session" "homepage removes sync-every-session heading"
expect_contains "docs/index.html" "Get API Access" "homepage first setup step is API access"
expect_contains "docs/index.html" "href=\"https://platform.minimax.io/subscribe/token-plan\"" "homepage hyperlinks current MiniMax token-plan URL"
expect_contains "docs/index.html" "href=\"https://opencode.ai/go\"" "homepage hyperlinks current OpenCode Go URL"
expect_contains "docs/index.html" ".step-code a.cmd" "homepage styles setup URLs as wrapping links"
expect_contains "docs/index.html" "overflow-wrap:anywhere" "homepage prevents setup URLs from overflowing boxes"
expect_contains "docs/index.html" "font-family:var(--font-mono);margin:0 auto 16px;" "homepage centers setup card numbers"
expect_not_contains "docs/index.html" "https://opencode.ai/docs/go/" "homepage removes old OpenCode Go docs URL"
expect_not_contains "docs/index.html" "platform.minimaxi.com" "homepage removes misspelled MiniMax URL"
expect_not_contains "docs/index.html" "Kay login:" "homepage first card removes Kay login"
expect_contains "docs/index.html" "Install Sidekick" "homepage second setup step is plugin install"
expect_contains "docs/index.html" "Delegate Per Session" "homepage third setup step is per-session delegation"
expect_not_contains "docs/index.html" "SessionStart Syncs Agents" "homepage setup steps do not expose internal SessionStart sync"
expect_contains "docs/index.html" "Forge:</span> <span class=\"cmd\">/forge:delegate</span>" "homepage shows Forge delegate command"
expect_not_contains "docs/index.html" "/forge implement X" "homepage does not treat /forge as a task command"
expect_contains "docs/index.html" "Kay:</span> <span class=\"cmd\">/kay:delegate</span>" "homepage shows Kay delegate command"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

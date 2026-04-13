#!/usr/bin/env bash
# Run all test suites and print a combined summary.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
green='\033[0;32m'; red='\033[0;31m'; bold='\033[1m'; reset='\033[0m'

TOTAL_PASS=0; TOTAL_FAIL=0; SUITE_FAIL=0

run_suite() {
  local name="$1" script="$2"
  echo ""
  echo -e "${bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"
  echo -e "${bold}Suite: ${name}${reset}"
  echo -e "${bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"
  if bash "${SCRIPT_DIR}/${script}"; then
    echo -e "${green}Suite PASSED: ${name}${reset}"
  else
    echo -e "${red}Suite FAILED: ${name}${reset}"
    SUITE_FAIL=$((SUITE_FAIL+1))
  fi
}

run_suite "install.sh unit tests"         "test_install_sh.bash"
run_suite "Plugin integrity verification" "test_plugin_integrity.bash"
run_suite "Fresh install simulation"      "test_fresh_install_sim.bash"
run_suite "End-to-end forge smoke tests"  "test_forge_e2e.bash"
run_suite "Forge skill structure tests"      "test_forge_skill.bash"
run_suite "AGENTS.md deduplication tests"    "test_agents_md_dedup.bash"
run_suite "Skill injection tests"            "test_skill_injection.bash"
run_suite "Fallback ladder tests"            "test_fallback_ladder.bash"

echo ""
echo -e "${bold}══════════════════════════════════════════${reset}"
if [ "${SUITE_FAIL}" -eq 0 ]; then
  echo -e "${green}${bold}ALL SUITES PASSED${reset}"
else
  echo -e "${red}${bold}${SUITE_FAIL} SUITE(S) FAILED${reset}"
fi
echo -e "${bold}══════════════════════════════════════════${reset}"
exit "${SUITE_FAIL}"

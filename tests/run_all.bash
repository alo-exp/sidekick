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
run_suite "Forge delegation enforcer hook tests" "test_forge_enforcer_hook.bash"
run_suite "Forge progress surface hook tests"    "test_forge_progress_surface.bash"
run_suite "Forge v1.2 E2E integration tests"     "test_forge_v12_integration.bash"
run_suite "Forge v1.2 coverage gap tests"        "test_v12_coverage.bash"
run_suite "Forge v1.3 coverage gap tests"        "test_v13_coverage.bash"
run_suite "Codex skill structure tests"          "test_codex_skill.bash"
run_suite "Codex packaging manifest tests"       "test_codex_plugin_manifest.bash"
run_suite "Codex marketplace manifest tests"     "test_codex_marketplace_manifest.bash"
run_suite "Codex plugin/read skill exposure tests" "run_live_codex_plugin_read.bash"
run_suite "Codex delegation enforcer hook tests" "test_codex_enforcer_hook.bash"
run_suite "Codex progress surface hook tests"    "test_codex_progress_surface.bash"
run_suite "Docs contract tests"                  "test_docs_contract.bash"
run_suite "Help-site navigation tests"           "test_help_site_navigation.bash"
run_suite "Release gate hook tests"              "test_validate_release_gate_hook.bash"
run_suite "Post-release cleanup script tests"    "test_post_release_cleanup.bash"
run_suite "Repository layout tests"              "test_repo_layout.bash"

echo ""
echo -e "${bold}══════════════════════════════════════════${reset}"
if [ "${SUITE_FAIL}" -eq 0 ]; then
  echo -e "${green}${bold}ALL SUITES PASSED${reset}"
else
  echo -e "${red}${bold}${SUITE_FAIL} SUITE(S) FAILED${reset}"
fi
echo -e "${bold}══════════════════════════════════════════${reset}"
exit "${SUITE_FAIL}"

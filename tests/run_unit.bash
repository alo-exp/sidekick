#!/usr/bin/env bash
# Run strict non-live unit and integration suites.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
green='\033[0;32m'; red='\033[0;31m'; bold='\033[1m'; reset='\033[0m'

SUITE_FAIL=0

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
run_suite "Generated host skill surface tests" "test_agent_surface_render.bash"
run_suite "Host surface rewrite tests"    "test_host_surface_rewrite.bash"
run_suite "Plugin integrity verification" "test_plugin_integrity.bash"
run_suite "Fresh install simulation"      "test_fresh_install_sim.bash"
run_suite "Clean reinstall bootstrap"     "test_clean_reinstall.bash"
run_suite "Hook trust seeding"            "test_hook_trust_state.bash"
run_suite "Removed sidekick absence contract tests" "test_removed_sidekick_absent.bash"
run_suite "Kay and Codex skill structure tests" "test_codex_skill.bash"
run_suite "Kay packaging manifest tests"         "test_codex_plugin_manifest.bash"
run_suite "Codex marketplace manifest tests"     "test_codex_marketplace_manifest.bash"
run_suite "Codex marketplace release-gate tests" "test_codex_marketplace_release_gate.bash"
run_suite "Cursor plugin manifest tests"         "test_cursor_plugin_manifest.bash"
run_suite "Cursor marketplace manifest tests"    "test_cursor_marketplace_manifest.bash"
run_suite "Cursor marketplace release-gate tests" "test_cursor_marketplace_release_gate.bash"
run_suite "Cursor install script tests"            "test_cursor_install.bash"
run_suite "Cursor session bootstrap tests"       "test_cursor_session_bootstrap.bash"
run_suite "Kay wrapper behavioral tests"       "test_run_in_kay_wrapper.bash"
run_suite "Kay delegation enforcer hook tests"   "test_codex_enforcer_hook.bash"
run_suite "Cursor hook contract tests"           "test_cursor_hook_contract.bash"
run_suite "Kay progress surface hook tests"      "test_codex_progress_surface.bash"
run_suite "Docs contract tests"                  "test_docs_contract.bash"
run_suite "Homepage sidekick card tests"         "test_homepage_sidekicks.bash"
run_suite "Social preview image tests"           "test_og_image.bash"
run_suite "Help-site navigation tests"           "test_help_site_navigation.bash"
run_suite "Sidekick hook activation gate tests"  "test_sidekick_hook_activation_gate.bash"
run_suite "Legacy hook scrub tests"              "test_legacy_hook_scrub.bash"
run_suite "Post-release cleanup script tests"    "test_post_release_cleanup.bash"
run_suite "Repository layout tests"              "test_repo_layout.bash"
run_suite "Runner contract tests"                "test_runner_contract.bash"

echo ""
echo -e "${bold}══════════════════════════════════════════${reset}"
if [ "${SUITE_FAIL}" -eq 0 ]; then
  echo -e "${green}${bold}ALL STRICT NON-LIVE SUITES PASSED${reset}"
else
  echo -e "${red}${bold}${SUITE_FAIL} SUITE(S) FAILED${reset}"
fi
echo -e "${bold}══════════════════════════════════════════${reset}"
exit "${SUITE_FAIL}"

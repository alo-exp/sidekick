#!/usr/bin/env bash
# Run the skip-safe full local sweep and print a combined summary.
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

run_suite "Strict non-live unit + integration suites" "run_unit.bash"
run_suite "Skip-safe Forge E2E probe"                 "test_forge_e2e.bash"
run_suite "Skip-safe Forge smoke harness"             "smoke/run_smoke.bash"
run_suite "Skip-safe Forge live E2E"                  "run_live_e2e.bash"
run_suite "Skip-safe Kay plugin/read probe"           "run_live_codex_plugin_read.bash"
run_suite "Skip-safe Kay marketplace install"         "run_live_codex_marketplace_install.bash"
run_suite "Skip-safe Kay smoke harness"               "smoke/run_codex_smoke.bash"
run_suite "Skip-safe Kay live E2E"                    "run_live_codex_e2e.bash"

echo ""
echo -e "${bold}══════════════════════════════════════════${reset}"
if [ "${SUITE_FAIL}" -eq 0 ]; then
  echo -e "${green}${bold}ALL SKIP-SAFE SUITES PASSED${reset}"
else
  echo -e "${red}${bold}${SUITE_FAIL} SUITE(S) FAILED${reset}"
fi
echo -e "${bold}══════════════════════════════════════════${reset}"
exit "${SUITE_FAIL}"

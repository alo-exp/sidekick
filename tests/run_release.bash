#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Pre-release gate
# =============================================================================
# Runs the full pre-release test pyramid in order and aborts on the first
# failure. Intended to be run by the maintainer before tagging a new version.
#
#   1. run_all.bash      — unit + integration suites (always runs)
#   2. smoke/run_smoke   — live `forge --version` + trivial forge -p
#                          (requires SIDEKICK_LIVE_FORGE=1)
#   3. run_live_e2e.bash — full Claude→Forge delegation on seeded testapp
#                          (requires SIDEKICK_LIVE_FORGE=1)
#
# Both live-Forge stages skip cleanly (exit 0) when the env var is unset,
# so this script is still useful in CI — it will run stage 1 and cleanly
# skip stages 2+3. Before tagging a release, a maintainer should run it
# locally with SIDEKICK_LIVE_FORGE=1 to exercise the live path.
#
# Usage
#   bash tests/run_release.bash                    # unit + smoke-skipped + e2e-skipped
#   SIDEKICK_LIVE_FORGE=1 bash tests/run_release.bash  # full pyramid (recommended pre-tag)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

green='\033[0;32m'; red='\033[0;31m'; yellow='\033[0;33m'; bold='\033[1m'; reset='\033[0m'

STAGE_FAIL=0
run_stage() {
  local name="$1" script="$2"
  echo ""
  echo -e "${bold}▼ Stage: ${name}${reset}"
  if bash "$script"; then
    echo -e "${green}  → stage passed${reset}"
  else
    echo -e "${red}  → stage FAILED${reset}"
    STAGE_FAIL=$((STAGE_FAIL + 1))
    echo ""
    echo -e "${red}${bold}Release gate aborted at: ${name}${reset}"
    exit 1
  fi
}

echo -e "${bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"
echo -e "${bold}Sidekick pre-release gate${reset}"
if [[ "${SIDEKICK_LIVE_FORGE:-}" == "1" ]]; then
  echo -e "  live Forge: ${green}enabled${reset} (smoke + e2e will run)"
else
  echo -e "  live Forge: ${yellow}disabled${reset} (smoke + e2e will skip)"
  echo -e "  ${yellow}Tip:${reset} set SIDEKICK_LIVE_FORGE=1 before tagging to exercise the live path."
fi
echo -e "${bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"

run_stage "Unit + integration suites"  "${SCRIPT_DIR}/run_all.bash"
run_stage "Live-Forge smoke harness"   "${SCRIPT_DIR}/smoke/run_smoke.bash"
run_stage "Live-Forge E2E testapp"     "${SCRIPT_DIR}/run_live_e2e.bash"

echo ""
echo -e "${bold}═══════════════════════════════════════════${reset}"
echo -e "${green}${bold}RELEASE GATE PASSED${reset} — safe to tag."
echo -e "${bold}═══════════════════════════════════════════${reset}"
exit 0

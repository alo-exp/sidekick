#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Pre-release gate
# =============================================================================
# Runs the full pre-release test pyramid in order and aborts on the first
# failure. Intended to be run by the maintainer before tagging a new version.
#
#   1. run_all.bash          — unit + integration suites (always runs)
#   2. smoke/run_smoke.bash   — live `forge --version` + trivial forge -p
#                              (requires SIDEKICK_LIVE_FORGE=1)
#   3. run_live_e2e.bash      — full host→Forge delegation on seeded testapp
#                              (requires SIDEKICK_LIVE_FORGE=1)
#   4. run_live_codex_marketplace_install.bash
#                             — install Sidekick through the Codex marketplace
#                              and prove it materializes in the Codex cache
#                              (requires SIDEKICK_LIVE_CODEX=1)
#   5. smoke/run_codex_smoke.bash
#                             — live `kay --version` + trivial kay exec
#                              (requires SIDEKICK_LIVE_CODEX=1)
#   6. run_live_codex_e2e.bash
#                             — full host→Kay delegation on seeded testapp
#                              (requires SIDEKICK_LIVE_CODEX=1)
#
# The live stages skip cleanly (exit 0) when the env vars are unset, so this
# script is still useful in CI — it will run stage 1 and cleanly skip stages
# 2-6. Before tagging a release, a maintainer should complete the quality gate
# first, then run this locally twice with SIDEKICK_LIVE_FORGE=1
# SIDEKICK_LIVE_CODEX=1 to exercise the live path.
#
# Usage
#   bash tests/run_release.bash
#   SIDEKICK_LIVE_FORGE=1 SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
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
export SIDEKICK_RELEASE_GATE=1
echo -e "${bold}Sidekick pre-release gate${reset}"
if [[ "${SIDEKICK_LIVE_FORGE:-}" == "1" ]]; then
  echo -e "  live Forge: ${green}enabled${reset} (smoke + e2e will run)"
  export SIDEKICK_VERIFY_REMOTE_INSTALLERS="${SIDEKICK_VERIFY_REMOTE_INSTALLERS:-1}"
else
  echo -e "  live Forge: ${yellow}disabled${reset} (smoke + e2e will skip)"
  echo -e "  ${yellow}Tip:${reset} set SIDEKICK_LIVE_FORGE=1 before tagging to exercise the live path."
fi
if [[ "${SIDEKICK_LIVE_CODEX:-}" == "1" ]]; then
  echo -e "  live Kay: ${green}enabled${reset} (marketplace + smoke + e2e will run)"
else
  echo -e "  live Kay: ${yellow}disabled${reset} (marketplace + smoke + e2e will skip)"
  echo -e "  ${yellow}Tip:${reset} set SIDEKICK_LIVE_CODEX=1 before tagging to exercise the live path."
fi
echo -e "${bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"

run_stage "Unit + integration suites"  "${SCRIPT_DIR}/run_all.bash"
run_stage "Live-Forge smoke harness"   "${SCRIPT_DIR}/smoke/run_smoke.bash"
run_stage "Live-Forge E2E testapp"     "${SCRIPT_DIR}/run_live_e2e.bash"
run_stage "Live-Codex marketplace install" "${SCRIPT_DIR}/run_live_codex_marketplace_install.bash"
run_stage "Live-Kay smoke harness"       "${SCRIPT_DIR}/smoke/run_codex_smoke.bash"
run_stage "Live-Kay E2E testapp"         "${SCRIPT_DIR}/run_live_codex_e2e.bash"

echo ""
echo -e "${bold}═══════════════════════════════════════════${reset}"
echo -e "${green}${bold}RELEASE GATE PASSED${reset} — safe to tag."
echo -e "${yellow}Next:${reset} run ${bold}bash tests/post_release_cleanup.bash${reset} after the release is published."
echo -e "${bold}═══════════════════════════════════════════${reset}"
exit 0

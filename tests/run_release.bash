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
# script is still useful in CI. A no-live run is not release-authorizing: only a
# run with both SIDEKICK_LIVE_FORGE=1 and SIDEKICK_LIVE_CODEX=1 records a
# current-session live-pyramid marker. The release hook requires two such
# markers before it allows a GitHub release command.
#
# Usage
#   bash tests/run_release.bash
#   SIDEKICK_LIVE_FORGE=1 SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE_PYRAMID_MARKER="quality-gate-live-pyramid"

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

live_pyramid_enabled() {
  [[ "${SIDEKICK_LIVE_FORGE:-}" == "1" && "${SIDEKICK_LIVE_CODEX:-}" == "1" ]]
}

quality_gate_state_file() {
  local qg_dir="${HOME}/.claude/.sidekick"
  if [[ -n "${CODEX_PLUGIN_ROOT:-}" || -n "${CODEX_HOME:-}" || -n "${CODEX_THREAD_ID:-}" ]]; then
    qg_dir="${HOME}/.codex/.sidekick"
  fi
  printf '%s\n' "${SIDEKICK_QG_STATE:-${qg_dir}/quality-gate-state}"
}

quality_gate_session_id() {
  printf '%s\n' "${SIDEKICK_SESSION_ID:-${CODEX_THREAD_ID:-${CLAUDE_SESSION_ID:-${SESSION_ID:-}}}}"
}

record_live_pyramid_marker() {
  local state_file session_id git_sha timestamp
  state_file="$(quality_gate_state_file)"
  session_id="$(quality_gate_session_id)"
  if [[ -z "${session_id}" ]]; then
    echo -e "${red}${bold}Cannot record live-pyramid marker: no host session id found.${reset}"
    echo "Set SIDEKICK_SESSION_ID, CODEX_THREAD_ID, CLAUDE_SESSION_ID, or SESSION_ID and rerun the live release gate."
    exit 1
  fi

  mkdir -p "$(dirname "${state_file}")"
  git_sha="$(git -C "${SCRIPT_DIR}/.." rev-parse --short=12 HEAD 2>/dev/null || printf 'unknown')"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  printf '%s session=%s sha=%s at=%s\n' "${LIVE_PYRAMID_MARKER}" "${session_id}" "${git_sha}" "${timestamp}" >> "${state_file}"
  echo -e "${green}  → recorded ${LIVE_PYRAMID_MARKER} for this host session${reset}"
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
if live_pyramid_enabled; then
  record_live_pyramid_marker
  echo -e "${green}${bold}RELEASE GATE PASSED${reset} — one live-pyramid run recorded."
  echo -e "${yellow}Release hook requirement:${reset} complete two current-session live-pyramid runs before tagging."
else
  echo -e "${yellow}${bold}NON-LIVE RELEASE CHECKS PASSED${reset} — live stages skipped; not safe to tag."
  echo -e "${yellow}Next:${reset} rerun twice with ${bold}SIDEKICK_LIVE_FORGE=1 SIDEKICK_LIVE_CODEX=1${reset} before releasing."
fi
echo -e "${yellow}Next:${reset} run ${bold}bash tests/post_release_cleanup.bash${reset} after the release is published."
echo -e "${bold}═══════════════════════════════════════════${reset}"
exit 0

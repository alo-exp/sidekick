#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Pre-release gate
# =============================================================================
# Runs the full pre-release test pyramid in order and aborts on the first
# failure. Intended to be run by the maintainer before tagging a new version.
#
#   1. run_unit.bash         — strict non-live unit + integration suites
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
# CI should run tests/run_unit.bash. This runner is for release operators: the
# live stages skip cleanly when env vars are unset, and Codex live runs are
# release-authorizing. Kay/Codex live tests force OpenCode Go with
# deepseek-v4-flash and low reasoning so release evidence uses the verifier
# profile, not the general implementation profile. A run with
# SIDEKICK_LIVE_CODEX=1 records a current-session, current-commit live-pyramid
# marker. Forge live stages may also be run when available, but they are not
# required when Forge testing is intentionally skipped. The release hook requires
# two such markers before it allows release tag publication or a GitHub release
# command.
#
# Usage
#   bash tests/run_in_kay.bash SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
#   bash tests/run_in_kay.bash SIDEKICK_LIVE_FORGE=1 SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash   # when Forge live is available
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIVE_PYRAMID_MARKER="quality-gate-live-pyramid"
LIVE_PYRAMID_CANDIDATE_MARKER="quality-gate-live-pyramid-candidate"

green='\033[0;32m'; red='\033[0;31m'; yellow='\033[0;33m'; bold='\033[1m'; reset='\033[0m'

validate_kay_wrapper_context() {
  if [[ "${SIDEKICK_KAY_WRAPPER_ACTIVE:-}" != "1" ]]; then
    return 1
  fi
  if [[ -z "${SIDEKICK_KAY_ISOLATED_HOME:-}" || "${HOME}" != "${SIDEKICK_KAY_ISOLATED_HOME}" ]]; then
    return 1
  fi
  if [[ -z "${SIDEKICK_KAY_PROOF_FILE:-}" || -z "${SIDEKICK_KAY_PROOF_TOKEN:-}" || -z "${SIDEKICK_KAY_PROOF_SHA256:-}" ]]; then
    return 1
  fi
  if [[ -z "${SIDEKICK_KAY_RUN_ID:-}" ]]; then
    return 1
  fi
  case "${SIDEKICK_KAY_PROOF_FILE}" in
    "${SIDEKICK_KAY_ISOLATED_HOME}"/*) ;;
    *) return 1 ;;
  esac
  [[ -f "${SIDEKICK_KAY_PROOF_FILE}" ]] || return 1
  [[ "$(tr -d '[:space:]' < "${SIDEKICK_KAY_PROOF_FILE}")" == "${SIDEKICK_KAY_PROOF_TOKEN}" ]] || return 1
  [[ "$(printf '%s' "${SIDEKICK_KAY_PROOF_TOKEN}" | shasum -a 256 | awk '{print $1}')" == "${SIDEKICK_KAY_PROOF_SHA256}" ]]
}

if ! validate_kay_wrapper_context; then
  echo -e "${red}${bold}Release tests must run inside Kay.${reset}"
  echo "Use: bash tests/run_in_kay.bash SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash"
  exit 1
fi

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
  [[ "${SIDEKICK_LIVE_CODEX:-}" == "1" ]]
}

quality_gate_state_file() {
  printf '%s\n' "${HOME}/.codex/.sidekick/quality-gate-state"
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

  if ! mkdir -p "$(dirname "${state_file}")"; then
    echo -e "${red}${bold}Cannot record live-pyramid marker: failed to create state directory.${reset}"
    exit 1
  fi
  printf '%s\n' "${session_id}" > "$(dirname "${state_file}")/current-session"

  git_sha="$(git -C "${SCRIPT_DIR}/.." rev-parse --short=12 HEAD 2>/dev/null || true)"
  if [[ -z "${git_sha}" ]]; then
    echo -e "${red}${bold}Cannot record live-pyramid marker: no current git SHA found.${reset}"
    echo "Run the live release gate from a Sidekick git checkout."
    exit 1
  fi

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  if ! printf '%s session=%s sha=%s at=%s run_id=%s token=%s proof_sha256=%s\n' "${LIVE_PYRAMID_CANDIDATE_MARKER}" "${session_id}" "${git_sha}" "${timestamp}" "${SIDEKICK_KAY_RUN_ID}" "${SIDEKICK_KAY_PROOF_TOKEN}" "${SIDEKICK_KAY_PROOF_SHA256}" >> "${state_file}"; then
    echo -e "${red}${bold}Cannot record live-pyramid marker: failed to write state file.${reset}"
    exit 1
  fi
  echo -e "${green}  → recorded ${LIVE_PYRAMID_CANDIDATE_MARKER} inside isolated Kay state${reset}"
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

run_stage "Strict non-live unit + integration suites" "${SCRIPT_DIR}/run_unit.bash"
run_stage "Live-Forge smoke harness"   "${SCRIPT_DIR}/smoke/run_smoke.bash"
run_stage "Live-Forge E2E testapp"     "${SCRIPT_DIR}/run_live_e2e.bash"
run_stage "Live-Codex marketplace install" "${SCRIPT_DIR}/run_live_codex_marketplace_install.bash"
run_stage "Live-Kay smoke harness"       "${SCRIPT_DIR}/smoke/run_codex_smoke.bash"
run_stage "Live-Kay E2E testapp"         "${SCRIPT_DIR}/run_live_codex_e2e.bash"

echo ""
echo -e "${bold}═══════════════════════════════════════════${reset}"
if live_pyramid_enabled; then
  record_live_pyramid_marker
  echo -e "${green}${bold}RELEASE GATE PASSED${reset} — one live-pyramid candidate recorded for wrapper promotion."
  echo -e "${yellow}Release hook requirement:${reset} complete two current-session live-pyramid runs before tagging."
else
  echo -e "${yellow}${bold}NON-LIVE RELEASE CHECKS PASSED${reset} — live Kay stages skipped; not safe to tag."
  echo -e "${yellow}Next:${reset} rerun twice with ${bold}SIDEKICK_LIVE_CODEX=1${reset} before releasing."
fi
echo -e "${yellow}Next:${reset} run ${bold}bash tests/post_release_cleanup.bash${reset} after the release is published."
echo -e "${bold}═══════════════════════════════════════════${reset}"
exit 0

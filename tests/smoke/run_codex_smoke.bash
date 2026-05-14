#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Live Kay Smoke Harness
# =============================================================================
# Hits the real Kay binary on PATH. Gated behind SIDEKICK_LIVE_CODEX=1 so CI
# never runs it. Intended to run pre-release on the maintainer's machine,
# where Codex is already installed and configured.
#
# What this DOES test
#   - `kay --version` (or legacy aliases) is reachable
#   - a trivial non-interactive Kay prompt round-trip emits the expected
#     STATUS / FILES_CHANGED lines
#
# What this does NOT test
#   - Delegation enforcement (that's covered by the unit suite)
#   - Multi-file editing quality (that's covered by the live E2E driver in
#     tests/run_live_codex_e2e.bash)
#
# Exit codes
#   0 — smoke passed, OR env var absent (skipped cleanly)
#   1 — smoke failed (Kay unreachable or STATUS missing)
# =============================================================================

set -uo pipefail

green='\033[0;32m'; red='\033[0;31m'; yellow='\033[0;33m'; bold='\033[1m'; reset='\033[0m'

if [[ "${SIDEKICK_LIVE_CODEX:-}" != "1" ]]; then
  echo -e "${yellow}Smoke harness skipped${reset} (set SIDEKICK_LIVE_CODEX=1 to run against the real Kay binary)."
  exit 0
fi

echo -e "${bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"
echo -e "${bold}Sidekick live-Kay smoke harness${reset}"
echo -e "${bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"

PASS=0; FAIL=0
pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

resolve_codex_binary() {
  for candidate in kay code codex coder; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

prepare_codex_runner() {
  local bin="$1"
  local help_file
  help_file="$(mktemp)"
  CODEX_RUNNER=()

  if "${bin}" exec --help >"${help_file}" 2>&1; then
    if grep -q -- '--full-auto' "${help_file}"; then
      if grep -q -- '--skip-git-repo-check' "${help_file}"; then
        CODEX_RUNNER=( "${bin}" exec --skip-git-repo-check --full-auto )
      else
        CODEX_RUNNER=( "${bin}" exec --full-auto )
      fi
    elif grep -q -- '--dangerously-bypass-approvals-and-sandbox' "${help_file}"; then
      CODEX_RUNNER=( "${bin}" exec --skip-git-repo-check --ephemeral --dangerously-bypass-approvals-and-sandbox )
    else
      if grep -q -- '--skip-git-repo-check' "${help_file}"; then
        CODEX_RUNNER=( "${bin}" exec --skip-git-repo-check )
      else
        CODEX_RUNNER=( "${bin}" exec )
      fi
    fi
  elif "${bin}" --help 2>&1 | grep -q -- '--no-approval'; then
    CODEX_RUNNER=( "${bin}" --no-approval )
  else
    CODEX_RUNNER=( "${bin}" )
  fi

  rm -f "${help_file}"
}

run_with_timeout() {
  local secs="$1"; shift
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${secs}" "$@"
  elif command -v timeout >/dev/null 2>&1; then
    timeout "${secs}" "$@"
  else
    "$@"
  fi
}

echo "=== smoke_codex_on_path ==="
if CODEX_BIN="$(resolve_codex_binary)"; then
  pass "Kay binary exists at $(command -v "${CODEX_BIN}")"
else
  fail "smoke_codex_on_path" "kay/code/codex/coder not found on PATH"
  echo "Aborting smoke — Kay binary required."
  exit 1
fi

prepare_codex_runner "${CODEX_BIN}"

echo "=== smoke_codex_version ==="
_ver_out="$("${CODEX_BIN}" --version 2>&1 || true)"
if [[ "${_ver_out}" == *"kay"* ]] || [[ "${_ver_out}" =~ [0-9]+\.[0-9]+ ]]; then
  pass "kay --version identifies the runtime (${_ver_out})"
else
  fail "smoke_codex_version" "unexpected: ${_ver_out}"
fi

echo "=== smoke_codex_prompt_round_trip ==="
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT
PROMPT=$'Respond with exactly two lines and nothing else:\nSTATUS: SUCCESS\nFILES_CHANGED: []'

set +e
_out="$(cd "${WORKDIR}" && run_with_timeout 120 "${CODEX_RUNNER[@]}" "${PROMPT}" 2>&1)"
_rc=$?
set -e

_clean="$(printf '%s' "${_out}" | sed $'s/\x1b\\[[0-9;]*m//g')"
if [ "${_rc}" -eq 0 ] \
    && printf '%s' "${_clean}" | grep -q '^STATUS: SUCCESS' \
    && printf '%s' "${_clean}" | grep -q '^FILES_CHANGED: \[\]'; then
  pass "Kay prompt round-trip returned STATUS and FILES_CHANGED"
else
  fail "smoke_codex_prompt_round_trip" "rc=${_rc}"
  echo "--- Kay output (first 40 lines) ---"
  printf '%s\n' "${_clean}" | head -n 40
  echo "--- end ---"
fi

echo ""
echo -e "${bold}═══════════════════════════════════════════${reset}"
if [[ "${FAIL}" -eq 0 ]]; then
  echo -e "${green}${bold}SMOKE PASSED${reset} ($PASS checks)"
else
  echo -e "${red}${bold}SMOKE FAILED${reset} ($FAIL of $((PASS+FAIL)) failed)"
fi
echo -e "${bold}═══════════════════════════════════════════${reset}"

exit "${FAIL}"

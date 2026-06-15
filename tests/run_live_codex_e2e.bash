#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Live Kay End-to-End Driver
# =============================================================================
# Pre-release check that exercises a FULL host→Kay delegation round-trip
# against the real Kay binary and the real model on the seeded Test Notes App.
# Gated behind SIDEKICK_LIVE_CODEX=1. Never runs in CI.
#
# Flow
#   1. Copy tests/test-notes-app/ to $TMPDIR so the canonical source never mutates.
#   2. npm install in the sandbox (host network; Kay sandbox blocks registry.npmjs.org).
#   3. Run scripts/e2e-smoke.sh — baseline MUST fail (health bug is live).
#   4. Send Kay a structured task prompt asking it to fix /api/health.
#   5. Re-run scripts/e2e-smoke.sh — MUST pass.
#   6. Assert src/server.js returns status ok.
#   7. Print the path to the sandbox so the maintainer can inspect.
#
# Exit codes
#   0 — E2E passed, OR env var absent (skipped cleanly)
#   1 — any assertion failed, or Kay returned non-zero, or timeout tripped
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../.env.local" ]; then
  # shellcheck source=/dev/null
  set -a
  source "${SCRIPT_DIR}/../.env.local"
  set +a
fi

green='\033[0;32m'; red='\033[0;31m'; yellow='\033[0;33m'; bold='\033[1m'; reset='\033[0m'

if [[ "${SIDEKICK_LIVE_CODEX:-}" != "1" ]]; then
  echo -e "${yellow}Live E2E skipped${reset} (set SIDEKICK_LIVE_CODEX=1 to run the full Kay round-trip)."
  exit 0
fi

echo -e "${bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"
echo -e "${bold}Sidekick live-Kay E2E driver (Test Notes App)${reset}"
echo -e "${bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"

for tool in node npm curl; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo -e "${red}FAIL${reset}: ${tool} not on PATH"
    exit 1
  fi
done

LIVE_KAY_MODEL_PROVIDER="${KAY_LIVE_MODEL_PROVIDER:-${SIDEKICK_KAY_MODEL_PROVIDER:-opencode-go}}"
LIVE_KAY_MODEL="${KAY_LIVE_MODEL:-${SIDEKICK_KAY_MODEL:-opencode-go/deepseek-v4-flash}}"

resolve_codex_binary() {
  if [ -n "${SIDEKICK_KAY_BIN:-}" ]; then
    if [ -x "${SIDEKICK_KAY_BIN}" ] \
      && "${SIDEKICK_KAY_BIN}" --version 2>/dev/null | grep -qiE '^kay([[:space:]]|$)' \
      && "${SIDEKICK_KAY_BIN}" exec --help >/dev/null 2>&1; then
      printf '%s' "${SIDEKICK_KAY_BIN}"
      return 0
    fi
    return 1
  fi

  for candidate in kay code coder; do
    if command -v "${candidate}" >/dev/null 2>&1 \
      && "${candidate}" --version 2>/dev/null | grep -qiE '^kay([[:space:]]|$)' \
      && "${candidate}" exec --help >/dev/null 2>&1; then
      printf '%s' "${candidate}"
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
    if grep -q -- '--dangerously-bypass-approvals-and-sandbox' "${help_file}"; then
      CODEX_RUNNER=( "${bin}" exec )
      if grep -q -- '--skip-git-repo-check' "${help_file}"; then
        CODEX_RUNNER+=(--skip-git-repo-check)
      fi
      if grep -q -- '--ephemeral' "${help_file}"; then
        CODEX_RUNNER+=(--ephemeral)
      fi
      CODEX_RUNNER+=(--dangerously-bypass-approvals-and-sandbox)
    elif grep -q -- '--full-auto' "${help_file}"; then
      if grep -q -- '--skip-git-repo-check' "${help_file}"; then
        CODEX_RUNNER=( "${bin}" exec --skip-git-repo-check --full-auto )
      else
        CODEX_RUNNER=( "${bin}" exec --full-auto )
      fi
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
    perl -e '
      use POSIX ":sys_wait_h";
      my $secs = shift @ARGV;
      my $pid = fork();
      die "fork failed: $!" unless defined $pid;
      if ($pid == 0) {
        setpgrp(0, 0);
        exec @ARGV or die "exec failed: $!";
      }
      my $deadline = time + $secs;
      while (time < $deadline) {
        my $res = waitpid($pid, WNOHANG);
        exit($? >> 8) if $res == $pid;
        sleep 1;
      }
      if (kill 0, $pid) {
        kill "TERM", -$pid;
        sleep 2;
        kill "KILL", -$pid if kill 0, $pid;
        waitpid($pid, 0);
        exit 124;
      }
      waitpid($pid, 0);
      exit($? >> 8);
    ' "${secs}" "$@"
  fi
}

CODEX_BIN="$(resolve_codex_binary)"
if [ -z "${CODEX_BIN}" ]; then
  echo -e "${red}FAIL${reset}: Kay-compatible kay/code/coder not on PATH"
  exit 1
fi
prepare_codex_runner "${CODEX_BIN}"

KAY_AUTH_PATH="${KAY_AUTH_PATH:-${HOME}/.kay/auth.json}"
OPENCODE_GO_API_KEY_VALUE="${OPENCODE_GO_API_KEY:-${CUSTOM_OPENCODE_GO_API_KEY:-}}"
MINIMAX_API_KEY_VALUE="${MINIMAX_API_KEY:-}"
OPENCODE_GO_KEY_FROM_ENV=0
MINIMAX_KEY_FROM_ENV=0
if [ -n "${OPENCODE_GO_API_KEY:-${CUSTOM_OPENCODE_GO_API_KEY:-}}" ]; then
  OPENCODE_GO_KEY_FROM_ENV=1
fi
if [ -n "${MINIMAX_API_KEY:-}" ]; then
  MINIMAX_KEY_FROM_ENV=1
fi

if [ "${LIVE_KAY_MODEL_PROVIDER}" = "minimax" ]; then
  if [ -z "${MINIMAX_API_KEY_VALUE}" ] && [ -f "${KAY_AUTH_PATH}" ]; then
    MINIMAX_API_KEY_VALUE="$(python3 -c 'import json, sys, pathlib
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
api_key = data.get("provider_credentials", {}).get("minimax", {}).get("api_key")
if api_key:
    print(api_key)
    raise SystemExit(0)
raise SystemExit(1)' "${KAY_AUTH_PATH}" 2>/dev/null)" || true
  fi
  if [ -z "${MINIMAX_API_KEY_VALUE}" ]; then
    echo -e "${red}FAIL${reset}: MINIMAX_API_KEY was not set and no MiniMax key was found in ${KAY_AUTH_PATH}"
    exit 1
  fi
else
  if [ -z "${OPENCODE_GO_API_KEY_VALUE}" ] && [ -f "${KAY_AUTH_PATH}" ]; then
    OPENCODE_GO_API_KEY_VALUE="$(python3 -c 'import json, sys, pathlib
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
creds = data.get("provider_credentials", {})
api_key = creds.get("opencode-go", {}).get("api_key")
if api_key:
    print(api_key)
    raise SystemExit(0)
raise SystemExit(1)' "${KAY_AUTH_PATH}")"
  fi
  if [ -z "${OPENCODE_GO_API_KEY_VALUE}" ]; then
    echo -e "${red}FAIL${reset}: OPENCODE_GO_API_KEY was not set and no OpenCode Go key was found in ${KAY_AUTH_PATH}"
    exit 1
  fi
fi

# Kay prefers ~/.kay/auth.json over env API keys when provider credentials exist (alo-labs/kay#43).
if [[ -z "${SIDEKICK_KAY_ISOLATED_HOME:-}" ]]; then
  NEED_ISOLATED=0
  if [ "${LIVE_KAY_MODEL_PROVIDER}" = "minimax" ] && [[ "${MINIMAX_KEY_FROM_ENV}" -eq 1 ]]; then
    NEED_ISOLATED=1
  fi
  if [ "${LIVE_KAY_MODEL_PROVIDER}" != "minimax" ] && [[ "${OPENCODE_GO_KEY_FROM_ENV}" -eq 1 ]]; then
    NEED_ISOLATED=1
  fi
  if [[ "${NEED_ISOLATED}" -eq 1 ]]; then
    SIDEKICK_KAY_ISOLATED_HOME="$(mktemp -d -t sidekick-kay-home.XXXXXX)"
    mkdir -p "${SIDEKICK_KAY_ISOLATED_HOME}/.kay"
    printf '%s\n' '{"auth_mode":"chatgpt","provider_credentials":{}}' > "${SIDEKICK_KAY_ISOLATED_HOME}/.kay/auth.json"
    export HOME="${SIDEKICK_KAY_ISOLATED_HOME}"
    KAY_AUTH_PATH="${SIDEKICK_KAY_ISOLATED_HOME}/.kay/auth.json"
    echo "Using isolated Kay HOME for provider API key override: ${HOME}"
  fi
fi

NOTES_APP_SRC="${SCRIPT_DIR}/test-notes-app"
SMOKE_SCRIPT="${NOTES_APP_SRC}/scripts/e2e-smoke.sh"
[[ -f "${NOTES_APP_SRC}/package.json" && -f "${NOTES_APP_SRC}/src/server.js" && -f "${SMOKE_SCRIPT}" ]] || {
  echo -e "${red}FAIL${reset}: test-notes-app source not found at ${NOTES_APP_SRC}"
  exit 1
}

SANDBOX="$(mktemp -d -t sidekick-notes-e2e.XXXXXX)"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --exclude='node_modules' --exclude='data' --exclude='.git' "${NOTES_APP_SRC}/" "${SANDBOX}/"
else
  cp -R "${NOTES_APP_SRC}/." "${SANDBOX}/"
  rm -rf "${SANDBOX}/node_modules" "${SANDBOX}/data" "${SANDBOX}/.git"
fi
chmod +x "${SANDBOX}/scripts/e2e-smoke.sh"
echo "Sandbox: ${SANDBOX}"

PASS=0; FAIL=0
pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

pick_free_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("", 0)); print(s.getsockname()[1]); s.close()'
}

E2E_PORT="$(pick_free_port)"
export NOTES_APP_DB_PATH="${SANDBOX}/data/notes.db"

echo "=== e2e_npm_install ==="
if ( cd "${SANDBOX}" && npm install --silent ); then
  pass "e2e_npm_install"
else
  fail "e2e_npm_install" "npm install failed in sandbox"
  exit 1
fi

run_smoke() {
  PORT="${E2E_PORT}" NOTES_APP_DB_PATH="${NOTES_APP_DB_PATH}" bash "${SANDBOX}/scripts/e2e-smoke.sh" 2>&1
}

echo "=== e2e_baseline_fails ==="
_base="$(run_smoke || true)"
if printf '%s' "${_base}" | grep -q 'health check failed'; then
  pass "e2e_baseline_fails (seeded health bug is live)"
else
  fail "e2e_baseline_fails" "expected baseline health failure, got:
${_base}"
  echo "Aborting E2E."
  exit 1
fi

read -r -d '' TASK_PROMPT <<EOF || true
OBJECTIVE: Fix the /api/health bug in src/server.js so the live E2E smoke script passes.

CONTEXT:
- This is the Test Notes App (Node.js + Express + better-sqlite3).
- node_modules is already installed; do NOT run npm install.
- scripts/e2e-smoke.sh starts the server on PORT=${E2E_PORT} and checks:
  - GET /api/health returns JSON with "status":"ok"
  - POST /api/notes creates a note and GET /api/notes lists it
- src/server.js currently returns status "broken" from /api/health.

DESIRED STATE:
- /api/health returns { status: "ok", timestamp: <iso> }.
- No other routes or files change unless required for the health fix.

SUCCESS CRITERIA:
- PORT=${E2E_PORT} NOTES_APP_DB_PATH=<sandbox>/data/notes.db bash scripts/e2e-smoke.sh exits 0.
- src/server.js contains status: 'ok' in the health handler.

INJECTED SKILLS: quality-gates, testing-strategy

IMPLEMENTATION:
- Edit src/server.js directly.
- Run bash scripts/e2e-smoke.sh with PORT=${E2E_PORT} after the fix and confirm it passes.
EOF

echo "=== e2e_kay_delegation ==="
echo "Sending task prompt to Kay (timeout 300s)..."
set +e
if [ "${LIVE_KAY_MODEL_PROVIDER}" = "minimax" ]; then
  KAY_ENV=( HOME="${HOME}" MINIMAX_API_KEY="${MINIMAX_API_KEY_VALUE}" )
else
  KAY_ENV=( HOME="${HOME}" OPENCODE_GO_API_KEY="${OPENCODE_GO_API_KEY_VALUE}" CUSTOM_OPENCODE_GO_API_KEY="${OPENCODE_GO_API_KEY_VALUE}" )
fi
KAY_LOG="$(mktemp -t sidekick-kay-e2e-out.XXXXXX)"
run_with_timeout 300 env "${KAY_ENV[@]}" \
  "${CODEX_RUNNER[@]}" \
    -C "${SANDBOX}" \
    -c model_provider="${LIVE_KAY_MODEL_PROVIDER}" \
    -c model="${LIVE_KAY_MODEL}" \
    -c model_reasoning_effort=low \
    -c preferred_model_reasoning_effort=low \
    "${TASK_PROMPT}" >"${KAY_LOG}" 2>&1
KAY_RC=$?
KAY_OUT="$(cat "${KAY_LOG}")"
rm -f "${KAY_LOG}"
set -e
echo "kay rc=${KAY_RC}"
echo "--- Kay output (tail 40 lines) ---"
printf '%s\n' "${KAY_OUT}" | tail -n 40
echo "--- end kay output ---"

if [[ "${KAY_RC}" -eq 0 ]]; then
  pass "e2e_kay_delegation (rc=0)"
else
  fail "e2e_kay_delegation" "Kay exited non-zero (rc=${KAY_RC})"
fi

echo "=== e2e_health_handler_patched ==="
if grep -qE "status:[[:space:]]*['\"]ok['\"]" "${SANDBOX}/src/server.js"; then
  pass "e2e_health_handler_patched (health returns ok)"
else
  fail "e2e_health_handler_patched" "src/server.js still broken:
$(grep -n 'api/health' -A3 "${SANDBOX}/src/server.js" || cat "${SANDBOX}/src/server.js")"
fi

echo "=== e2e_smoke_passes_after_fix ==="
_post="$(run_smoke || true)"
if printf '%s' "${_post}" | grep -q 'e2e-smoke passed'; then
  pass "e2e_smoke_passes_after_fix"
else
  fail "e2e_smoke_passes_after_fix" "smoke output:
${_post}"
fi

echo ""
echo -e "${bold}═══════════════════════════════════════════${reset}"
if [[ "${FAIL}" -eq 0 ]]; then
  echo -e "${green}${bold}LIVE E2E PASSED${reset} ($PASS checks)"
  echo "Sandbox preserved for inspection: ${SANDBOX}"
else
  echo -e "${red}${bold}LIVE E2E FAILED${reset} ($FAIL of $((PASS+FAIL)) failed)"
  echo "Sandbox preserved for inspection: ${SANDBOX}"
fi
echo -e "${bold}═══════════════════════════════════════════${reset}"

exit "${FAIL}"

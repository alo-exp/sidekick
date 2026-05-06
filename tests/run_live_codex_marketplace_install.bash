#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Live Codex marketplace install test
# =============================================================================

set -uo pipefail

green='\033[0;32m'; red='\033[0;31m'; yellow='\033[0;33m'; bold='\033[1m'; reset='\033[0m'

if [[ "${SIDEKICK_LIVE_CODEX:-}" != "1" ]]; then
  echo -e "${yellow}Marketplace install skipped${reset} (set SIDEKICK_LIVE_CODEX=1 to exercise the real Codex install path)."
  exit 0
fi

echo -e "${bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"
echo -e "${bold}Sidekick live-Codex marketplace install${reset}"
echo -e "${bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"

PASS=0; FAIL=0
pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

CODEX_REPO="/Users/shafqat/projects/codex-cli/kay"
MARKETPLACE_REPO="/Users/shafqat/projects/codex-plugins"
SIDEKICK_DIR="/Users/shafqat/projects/sidekick/repo"
PLUGIN_VERSION="$(python3 -c "import json; print(json.load(open('${SIDEKICK_DIR}/.codex-plugin/plugin.json'))['version'])")"
MARKETPLACE_NAME="alo-labs-codex"
INSTALL_ROOT_REL="plugins/cache/${MARKETPLACE_NAME}/sidekick/${PLUGIN_VERSION}"

resolve_codex_binary() {
  if command -v node >/dev/null 2>&1 && [[ -f "${CODEX_REPO}/codex-cli/bin/codex.js" ]]; then
    printf 'node %s\n' "${CODEX_REPO}/codex-cli/bin/codex.js"
    return 0
  fi
  for candidate in codex code coder; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

prepare_codex_runner() {
  local -a bin=( "$@" )
  local help_file
  help_file="$(mktemp)"
  CODEX_RUNNER=()

  if "${bin[@]}" exec --help >"${help_file}" 2>&1; then
    if grep -q -- '--full-auto' "${help_file}"; then
      CODEX_RUNNER=( "${bin[@]}" exec --full-auto )
    elif grep -q -- '--dangerously-bypass-approvals-and-sandbox' "${help_file}"; then
      CODEX_RUNNER=( "${bin[@]}" exec --skip-git-repo-check --ephemeral --dangerously-bypass-approvals-and-sandbox )
    else
      CODEX_RUNNER=( "${bin[@]}" exec )
    fi
  elif "${bin[@]}" --help 2>&1 | grep -q -- '--no-approval'; then
      CODEX_RUNNER=( "${bin[@]}" --no-approval )
  else
    CODEX_RUNNER=( "${bin[@]}" )
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

if ! CODEX_BIN_STRING="$(resolve_codex_binary)"; then
  fail "codex binary" "codex/code/coder not found on PATH and local Codex launcher missing at ${CODEX_REPO}/codex-cli/bin/codex.js"
  exit 1
fi

read -r -a CODEX_BIN <<< "${CODEX_BIN_STRING}"
prepare_codex_runner "${CODEX_BIN[@]}"

if ! command -v python3 >/dev/null 2>&1; then
  fail "python3" "python3 not found on PATH"
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  fail "git" "git not found on PATH"
  exit 1
fi

WORKSPACE="$(mktemp -d -t sidekick-codex-marketplace.XXXXXX)"
CODEX_HOME="$(mktemp -d -t sidekick-codex-home.XXXXXX)"
trap 'rm -rf "${WORKSPACE}" "${CODEX_HOME}"' EXIT
mkdir -p "${WORKSPACE}/workspace"
printf 'sidekick marketplace install smoke\n' > "${WORKSPACE}/workspace/README.txt"

echo "=== marketplace_add ==="
set +e
(cd "${WORKSPACE}/workspace" && CODEX_HOME="${CODEX_HOME}" "${CODEX_BIN[@]}" plugin marketplace add "${MARKETPLACE_REPO}" >/tmp/sidekick-codex-marketplace-add.log 2>&1)
ADD_RC=$?
set -e
if [ "${ADD_RC}" -eq 0 ]; then
  pass "marketplace was added to Codex configuration"
else
  fail "marketplace_add" "Codex exited ${ADD_RC}; output:
$(cat /tmp/sidekick-codex-marketplace-add.log)"
  exit 1
fi

CACHE_ROOT="${CODEX_HOME}/${INSTALL_ROOT_REL}"
if [ -e "${CACHE_ROOT}" ]; then
  fail "precondition" "plugin cache root already exists before the live exec run: ${CACHE_ROOT}"
  exit 1
fi

read -r -d '' TASK_PROMPT <<'EOF' || true
Respond with exactly one line:
STATUS: OK
Do not edit any files.
EOF

echo "=== live_codex_exec ==="
set +e
EXEC_OUT="$(cd "${WORKSPACE}/workspace" && CODEX_HOME="${CODEX_HOME}" run_with_timeout 180 "${CODEX_RUNNER[@]}" "${TASK_PROMPT}" 2>&1)"
EXEC_RC=$?
set -e
echo "codex rc=${EXEC_RC}"
echo "--- codex output (tail 40 lines) ---"
printf '%s\n' "${EXEC_OUT}" | tail -n 40
echo "--- end codex output ---"

if [ "${EXEC_RC}" -eq 0 ]; then
  pass "Codex exec completed with the marketplace installed"
else
  fail "live_codex_exec" "Codex exited non-zero (rc=${EXEC_RC})"
fi

echo "=== installed_plugin_cache ==="
if [ -f "${CACHE_ROOT}/.codex-plugin/plugin.json" ]; then
  pass "Sidekick installed into Codex plugin cache at ${CACHE_ROOT}"
else
  fail "installed_plugin_cache" "missing ${CACHE_ROOT}/.codex-plugin/plugin.json"
fi

echo "=== installed_plugin_manifest ==="
if python3 - "${CACHE_ROOT}/.codex-plugin/plugin.json" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
assert data["name"] == "sidekick"
assert data["version"] == "1.5.0"
assert data["skills"] == "./skills/"
assert data["hooks"] == "./hooks/hooks.json"
PY
then
  pass "installed Codex plugin manifest is the Sidekick package"
else
  fail "installed_plugin_manifest" "installed plugin manifest was missing expected Sidekick metadata"
fi

echo ""
echo -e "${bold}═══════════════════════════════════════════${reset}"
if [ "${FAIL}" -eq 0 ]; then
  echo -e "${green}${bold}LIVE MARKETPLACE INSTALL PASSED${reset} ($PASS checks)"
  echo "Workspace preserved for inspection: ${WORKSPACE}"
else
  echo -e "${red}${bold}LIVE MARKETPLACE INSTALL FAILED${reset} ($FAIL of $((PASS+FAIL)) failed)"
  echo "Workspace preserved for inspection: ${WORKSPACE}"
fi
echo -e "${bold}═══════════════════════════════════════════${reset}"

exit "${FAIL}"

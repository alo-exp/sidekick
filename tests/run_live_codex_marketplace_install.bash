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

MARKETPLACE_REPO="/Users/shafqat/projects/codex-plugins"
SIDEKICK_DIR="/Users/shafqat/projects/sidekick/repo"
CODEX_REPO="/Users/shafqat/projects/codex-cli/kay"
CODEX_RUST_REPO="${CODEX_REPO}/codex-rs"
CODE_RUST_REPO="${CODEX_REPO}/code-rs"
PLUGIN_VERSION="$(python3 -c "import json; print(json.load(open('${SIDEKICK_DIR}/.codex-plugin/plugin.json'))['version'])")"
MARKETPLACE_NAME="alo-labs-codex"

resolve_codex_runner() {
  local built_codex="${CODEX_RUST_REPO}/target/debug/codex"
  if [[ -x "${built_codex}" ]]; then
    CODEX_BIN=( "${built_codex}" )
    return 0
  fi

  if ! command -v cargo >/dev/null 2>&1; then
    return 1
  fi

  CODEX_BIN=( cargo run --manifest-path "${CODEX_RUST_REPO}/Cargo.toml" -q -p codex-cli -- )
  return 0
}

resolve_code_runner() {
  local built_code="${CODE_RUST_REPO}/target/debug/code"
  if [[ -x "${built_code}" ]]; then
    CODE_BIN=( "${built_code}" )
    return 0
  fi

  if ! command -v cargo >/dev/null 2>&1; then
    return 1
  fi

  CODE_BIN=( cargo run --manifest-path "${CODE_RUST_REPO}/Cargo.toml" -q -p code-cli -- )
  return 0
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

if ! resolve_codex_runner; then
  fail "codex runner" "could not find a built codex binary or cargo on PATH"
  exit 1
fi

if ! resolve_code_runner; then
  fail "code runner" "could not find a built code binary or cargo on PATH"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  fail "python3" "python3 not found on PATH"
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  fail "git" "git not found on PATH"
  exit 1
fi

WORKSPACE="$(mktemp -d -t sidekick-codex-marketplace.XXXXXX)"
CODE_HOME="$(mktemp -d -t sidekick-codex-home.XXXXXX)"
trap 'rm -rf "${WORKSPACE}" "${CODE_HOME}"' EXIT
mkdir -p "${WORKSPACE}/workspace"
printf 'sidekick marketplace install smoke\n' > "${WORKSPACE}/workspace/README.txt"

echo "=== marketplace_add ==="
set +e
(cd "${WORKSPACE}/workspace" && CODEX_HOME="${CODE_HOME}" CODE_HOME="${CODE_HOME}" "${CODEX_BIN[@]}" plugin marketplace add "${MARKETPLACE_REPO}" >/tmp/sidekick-codex-marketplace-add.log 2>&1)
ADD_RC=$?
set -e
if [ "${ADD_RC}" -eq 0 ]; then
  pass "marketplace was added to Codex configuration"
else
  fail "marketplace_add" "Codex exited ${ADD_RC}; output:
$(cat /tmp/sidekick-codex-marketplace-add.log)"
  exit 1
fi

EXPECTED_MARKETPLACE_SOURCE="$(python3 -c "from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve())" "${MARKETPLACE_REPO}")"

echo "=== marketplace_config_entry ==="
if grep -Fq "[marketplaces.${MARKETPLACE_NAME}]" "${CODE_HOME}/config.toml" \
  && grep -Fq 'source_type = "local"' "${CODE_HOME}/config.toml" \
  && grep -Fq "source = \"${EXPECTED_MARKETPLACE_SOURCE}\"" "${CODE_HOME}/config.toml"
then
  pass "Codex recorded the Sidekick marketplace as a local source"
else
  fail "marketplace_config_entry" "missing local marketplace entry in ${CODE_HOME}/config.toml"
fi

echo "=== codex_command_surface ==="
if [ -f "${SIDEKICK_DIR}/commands/codex-stop.md" ] \
  && [ -f "${SIDEKICK_DIR}/commands/codex-history.md" ] \
  && [ -f "${SIDEKICK_DIR}/skills/codex-delegate.md" ] \
  && [ -L "${SIDEKICK_DIR}/skills/codex-stop/SKILL.md" ] \
  && [ -L "${SIDEKICK_DIR}/skills/codex-history/SKILL.md" ] \
  && [ "$(readlink "${SIDEKICK_DIR}/skills/codex-stop/SKILL.md")" = "../../commands/codex-stop.md" ] \
  && [ "$(readlink "${SIDEKICK_DIR}/skills/codex-history/SKILL.md")" = "../../commands/codex-history.md" ]
then
  pass "Codex marketplace source exposes the stop/history command docs plus the codex-delegate alias"
else
  fail "codex_command_surface" "command docs or bridge symlinks missing or mis-targeted"
fi

read -r -d '' TASK_PROMPT <<'EOF' || true
Respond with exactly one line:
STATUS: OK
Do not edit any files.
EOF

echo "=== live_codex_exec ==="
MINIMAX_API_KEY_VALUE="${MINIMAX_API_KEY:-}"
if [ -z "${MINIMAX_API_KEY_VALUE}" ] && [ -f /Users/shafqat/forge/.credentials.json ]; then
  MINIMAX_API_KEY_VALUE="$(python3 -c 'import json, sys, pathlib
path = pathlib.Path(sys.argv[1])
for entry in json.loads(path.read_text()):
    if entry.get("id") == "minimax":
        api_key = entry.get("auth_details", {}).get("api_key")
        if api_key:
            print(api_key)
            raise SystemExit(0)
raise SystemExit(1)' /Users/shafqat/forge/.credentials.json)"
fi
if [ -z "${MINIMAX_API_KEY_VALUE}" ]; then
  fail "minimax_key" "MINIMAX_API_KEY was not set and no minimax key was found in /Users/shafqat/forge/.credentials.json"
  exit 1
fi
set +e
EXEC_OUT="$(cd "${WORKSPACE}/workspace" && CODEX_HOME="${CODE_HOME}" CODE_HOME="${CODE_HOME}" MINIMAX_API_KEY="${MINIMAX_API_KEY_VALUE}" run_with_timeout 180 "${CODE_BIN[@]}" exec --skip-git-repo-check -c model_provider=minimax -c model=MiniMax-M2.7 "${TASK_PROMPT}" 2>&1)"
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

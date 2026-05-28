#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Live Codex marketplace install test with Kay runtime
# =============================================================================

set -uo pipefail

green='\033[0;32m'; red='\033[0;31m'; yellow='\033[0;33m'; bold='\033[1m'; reset='\033[0m'

if [[ "${SIDEKICK_LIVE_CODEX:-}" != "1" ]]; then
  echo -e "${yellow}Marketplace install skipped${reset} (set SIDEKICK_LIVE_CODEX=1 to exercise the real Codex marketplace/plugin install path with Kay runtime)."
  exit 0
fi

echo -e "${bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"
echo -e "${bold}Sidekick live-Codex marketplace install with Kay runtime${reset}"
echo -e "${bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"

PASS=0; FAIL=0
pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIDEKICK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOST_HOME_FOR_TOOLS="${SIDEKICK_HOST_HOME:-${HOME}}"
CODEX_REPO="${SIDEKICK_CODEX_REPO:-${HOST_HOME_FOR_TOOLS}/projects/codex-cli/kay}"
CODEX_RUST_REPO="${CODEX_REPO}/codex-rs"
if [ -d "${CODEX_REPO}/kay-rs" ]; then
  CODE_RUST_REPO="${CODEX_REPO}/kay-rs"
else
  CODE_RUST_REPO="${CODEX_REPO}/code-rs"
fi
PLUGIN_VERSION="$(python3 -c "import json; print(json.load(open('${SIDEKICK_DIR}/.codex-plugin/plugin.json'))['version'])")"
MARKETPLACE_SOURCE="${CODEX_MARKETPLACE_SOURCE:-alo-labs/codex-plugins}"
MARKETPLACE_NAME="${CODEX_MARKETPLACE_NAME:-alo-labs-codex}"
EXPECTED_MARKETPLACE_SOURCE="${CODEX_MARKETPLACE_EXPECTED_SOURCE:-https://github.com/alo-labs/codex-plugins.git}"
EXPECTED_MARKETPLACE_SOURCE_TYPE="${CODEX_MARKETPLACE_EXPECTED_SOURCE_TYPE:-git}"

resolve_codex_runner() {
  if [ -n "${SIDEKICK_CODEX_BIN:-}" ]; then
    CODEX_BIN=( "${SIDEKICK_CODEX_BIN}" )
    return 0
  fi

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
  if [ -n "${SIDEKICK_KAY_BIN:-}" ]; then
    CODE_BIN=( "${SIDEKICK_KAY_BIN}" )
    return 0
  fi

  local built_code="${CODE_RUST_REPO}/target/debug/kay"
  if [[ -x "${built_code}" ]]; then
    CODE_BIN=( "${built_code}" )
    return 0
  fi

  if ! command -v cargo >/dev/null 2>&1; then
    return 1
  fi

  CODE_BIN=( cargo run --manifest-path "${CODE_RUST_REPO}/Cargo.toml" -q -p code-cli --bin kay -- )
  return 0
}

prepare_code_exec_runner() {
  local help_file
  help_file="$(mktemp)"
  CODE_RUNNER=( "${CODE_BIN[@]}" exec )

  if "${CODE_BIN[@]}" exec --help >"${help_file}" 2>&1; then
    CODE_RUNNER=( "${CODE_BIN[@]}" exec )
    if grep -q -- '--skip-git-repo-check' "${help_file}"; then
      CODE_RUNNER+=(--skip-git-repo-check)
    fi
    if grep -q -- '--dangerously-bypass-approvals-and-sandbox' "${help_file}"; then
      CODE_RUNNER+=(--dangerously-bypass-approvals-and-sandbox)
    elif grep -q -- '--full-auto' "${help_file}"; then
      CODE_RUNNER+=(--full-auto)
    fi
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

if ! resolve_codex_runner; then
  fail "codex runner" "could not find a built codex binary or cargo on PATH"
  exit 1
fi

if ! resolve_code_runner; then
  fail "kay runner" "could not find a built Kay binary or cargo on PATH"
  exit 1
fi
prepare_code_exec_runner

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
(cd "${WORKSPACE}/workspace" && CODEX_HOME="${CODE_HOME}" CODE_HOME="${CODE_HOME}" "${CODEX_BIN[@]}" plugin marketplace add "${MARKETPLACE_SOURCE}" >/tmp/sidekick-codex-marketplace-add.log 2>&1)
ADD_RC=$?
set -e
if [ "${ADD_RC}" -eq 0 ]; then
  pass "marketplace was added to Codex configuration"
else
  fail "marketplace_add" "Codex exited ${ADD_RC}; output:
$(cat /tmp/sidekick-codex-marketplace-add.log)"
  exit 1
fi

MARKETPLACE_ROOT="${CODE_HOME}/.tmp/marketplaces/${MARKETPLACE_NAME}"
INSTALLED_ROOT="${CODE_HOME}/plugins/cache/${MARKETPLACE_NAME}/sidekick/${PLUGIN_VERSION}"

echo "=== marketplace_config_entry ==="
if grep -Fq "[marketplaces.${MARKETPLACE_NAME}]" "${CODE_HOME}/config.toml" \
  && grep -Fq "source_type = \"${EXPECTED_MARKETPLACE_SOURCE_TYPE}\"" "${CODE_HOME}/config.toml" \
  && grep -Fq "source = \"${EXPECTED_MARKETPLACE_SOURCE}\"" "${CODE_HOME}/config.toml"
then
  pass "Codex recorded the Sidekick marketplace source in the isolated CODEX_HOME"
else
  fail "marketplace_config_entry" "missing marketplace entry in ${CODE_HOME}/config.toml"
fi

echo "=== plugin_add ==="
set +e
(cd "${WORKSPACE}/workspace" && CODEX_HOME="${CODE_HOME}" CODE_HOME="${CODE_HOME}" "${CODEX_BIN[@]}" plugin add "sidekick@${MARKETPLACE_NAME}" >/tmp/sidekick-codex-plugin-add.log 2>&1)
PLUGIN_ADD_RC=$?
set -e
if [ "${PLUGIN_ADD_RC}" -eq 0 ]; then
  pass "Sidekick plugin was added from the configured Codex marketplace"
else
  fail "plugin_add" "Codex exited ${PLUGIN_ADD_RC}; output:
$(cat /tmp/sidekick-codex-plugin-add.log)"
  exit 1
fi

echo "=== marketplace_checkout_root ==="
if [ -d "${MARKETPLACE_ROOT}" ] \
  && [ -f "${MARKETPLACE_ROOT}/.agents/plugins/marketplace.json" ]; then
  pass "Codex materialized the Sidekick marketplace checkout in isolated CODEX_HOME"
else
  fail "marketplace_checkout_root" "missing ${MARKETPLACE_ROOT} or marketplace manifest"
fi

echo "=== plugin_install_root ==="
if [ -d "${INSTALLED_ROOT}" ] \
  && [ -f "${INSTALLED_ROOT}/.codex-plugin/plugin.json" ] \
  && [ "$(python3 -c "import json; print(json.load(open('${INSTALLED_ROOT}/.codex-plugin/plugin.json'))['version'])")" = "${PLUGIN_VERSION}" ]; then
  pass "Codex materialized the Sidekick plugin cache in isolated CODEX_HOME at the expected version"
else
  fail "plugin_install_root" "missing ${INSTALLED_ROOT} or installed plugin version does not match ${PLUGIN_VERSION}"
fi

SKILL_ROOT="$(python3 - "${INSTALLED_ROOT}" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).resolve()
manifest = json.loads((root / ".codex-plugin" / "plugin.json").read_text())
skills = manifest["skills"]
skill_root = (root / skills).resolve()
try:
    skill_root.relative_to(root)
except ValueError:
    raise SystemExit(f"manifest skills path escapes installed root: {skills}")
print(skill_root)
PY
)"

echo "=== marketplace_skill_surface ==="
if [ -f "${SKILL_ROOT}/codex-delegate/SKILL.md" ] \
  && [ -f "${SKILL_ROOT}/codex-delegate.md" ] \
  && [ -f "${SKILL_ROOT}/codex-stop/SKILL.md" ] \
  && [ -f "${SKILL_ROOT}/kay-delegate/SKILL.md" ] \
  && [ -f "${SKILL_ROOT}/kay-stop/SKILL.md" ] \
  && [ ! -f "${SKILL_ROOT}/codex/SKILL.md" ] \
  && [ ! -f "${SKILL_ROOT}/codex-history/SKILL.md" ] \
  && [ ! -f "${SKILL_ROOT}/forge/SKILL.md" ] \
  && [ ! -f "${SKILL_ROOT}/forge-stop/SKILL.md" ] \
  && grep -q '^name: codex-delegate' "${SKILL_ROOT}/codex-delegate/SKILL.md" \
  && grep -q '\.codex-delegation-active' "${SKILL_ROOT}/codex-stop/SKILL.md" \
  && grep -q '^name: kay-delegate' "${SKILL_ROOT}/kay-delegate/SKILL.md" \
  && grep -q '\.kay-delegation-active' "${SKILL_ROOT}/kay-stop/SKILL.md" \
  && grep -q '^user-invocable: false' "${SKILL_ROOT}/codex-delegate.md"
then
  pass "installed marketplace exposes the canonical Sidekick skill surface"
else
  fail "marketplace_skill_surface" "Codex manifest skill surface is missing or mis-targeted in ${SKILL_ROOT}"
fi

echo "=== marketplace_skills_list_surface ==="
if python3 - "${CODE_HOME}" "${WORKSPACE}/workspace" "${CODEX_BIN[@]}" <<'PY'
import json
import os
import pathlib
import queue
import subprocess
import sys
import threading
import time

code_home = pathlib.Path(sys.argv[1])
workspace = pathlib.Path(sys.argv[2])
codex_cmd = sys.argv[3:]

env = os.environ.copy()
env["CODEX_HOME"] = str(code_home)
env["CODE_HOME"] = str(code_home)

proc = subprocess.Popen(
    [*codex_cmd, "app-server", "--listen", "stdio://"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    env=env,
    cwd=workspace,
)

q = queue.Queue()

def pump(pipe, label):
    for line in iter(pipe.readline, ""):
        q.put((label, line))
    q.put((label, None))

threading.Thread(target=pump, args=(proc.stdout, "stdout"), daemon=True).start()
threading.Thread(target=pump, args=(proc.stderr, "stderr"), daemon=True).start()

def send(obj):
    proc.stdin.write(json.dumps(obj) + "\n")
    proc.stdin.flush()

def recv_id(target_id, timeout=30):
    end = time.time() + timeout
    while time.time() < end:
        try:
            _label, line = q.get(timeout=0.2)
        except queue.Empty:
            continue
        if line is None:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if obj.get("id") == target_id:
            return obj
    raise TimeoutError(f"timed out waiting for JSON-RPC response {target_id}")

try:
    send(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "clientInfo": {
                    "name": "sidekick-marketplace-probe",
                    "title": "Sidekick Marketplace Probe",
                    "version": "0.1.0",
                },
                "capabilities": {"experimentalApi": True},
            },
        }
    )
    recv_id(1)
    send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    send({"jsonrpc": "2.0", "id": 2, "method": "skills/list", "params": {}})
    resp = recv_id(2)
    names = []
    for entry in resp["result"]["data"]:
        for skill in entry.get("skills", []):
            if skill["name"].startswith("sidekick:"):
                names.append(skill["name"])
    print("skill_names:", ", ".join(names))
    expected = [
        "sidekick:codex-delegate",
        "sidekick:codex-stop",
        "sidekick:kay-delegate",
        "sidekick:kay-stop",
        "sidekick:kay:delegate",
    ]
    if names != expected:
        raise SystemExit(
            "skills/list did not return the unique expected Sidekick surface: "
            + ", ".join(names)
        )
finally:
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
PY
then
  pass "installed marketplace exposes a unique Sidekick skills/list picker surface"
else
  fail "marketplace_skills_list_surface" "Codex skills/list did not match the expected unique Sidekick surface"
fi

read -r -d '' TASK_PROMPT <<'EOF' || true
Respond with exactly one line:
STATUS: OK
Do not edit any files.
EOF

echo "=== live_kay_exec ==="
OPENCODE_GO_API_KEY_VALUE="${OPENCODE_GO_API_KEY:-${CUSTOM_OPENCODE_GO_API_KEY:-}}"
KAY_AUTH_PATH="${KAY_AUTH_PATH:-${HOME}/.kay/auth.json}"
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
  fail "opencode_go_key" "OPENCODE_GO_API_KEY was not set and no OpenCode Go key was found in ${KAY_AUTH_PATH}"
  exit 1
fi
set +e
EXEC_OUT="$(cd "${WORKSPACE}/workspace" && CODEX_HOME="${CODE_HOME}" CODE_HOME="${CODE_HOME}" OPENCODE_GO_API_KEY="${OPENCODE_GO_API_KEY_VALUE}" CUSTOM_OPENCODE_GO_API_KEY="${OPENCODE_GO_API_KEY_VALUE}" run_with_timeout 180 "${CODE_RUNNER[@]}" -c model_provider=opencode-go -c model=opencode-go/deepseek-v4-flash -c model_reasoning_effort=low -c preferred_model_reasoning_effort=low "${TASK_PROMPT}" 2>&1)"
EXEC_RC=$?
set -e
echo "kay rc=${EXEC_RC}"
echo "--- Kay output (tail 40 lines) ---"
printf '%s\n' "${EXEC_OUT}" | tail -n 40
echo "--- end codex output ---"

if [ "${EXEC_RC}" -eq 0 ]; then
  pass "Kay exec completed with the marketplace installed"
else
  fail "live_kay_exec" "Kay exited non-zero (rc=${EXEC_RC})"
fi

echo "=== installed_plugin_cache ==="
if [ -d "${INSTALLED_ROOT}" ]; then
  if ! HOME="${CODE_HOME}" CODEX_HOME="${CODE_HOME}" CODE_HOME="${CODE_HOME}" CODEX_PLUGIN_ROOT="${INSTALLED_ROOT}" SIDEKICK_INSTALL_KAY=0 bash "${INSTALLED_ROOT}/install.sh" >/dev/null 2>&1; then
    fail "installed cache rewrite" "reinstalling the installed tree at ${INSTALLED_ROOT} failed"
  fi
  if grep -Fq 'CODEX_PLUGIN_ROOT' "${INSTALLED_ROOT}/hooks/hooks.json" \
    && ! grep -Fq 'CLAUDE_PLUGIN_ROOT' "${INSTALLED_ROOT}/hooks/hooks.json" \
    && grep -Fq 'CODEX_PROJECT_DIR' "${INSTALLED_ROOT}/hooks/lib/sidekick-registry.sh" \
    && ! grep -Fq 'CLAUDE_PROJECT_DIR' "${INSTALLED_ROOT}/hooks/lib/sidekick-registry.sh" \
    && grep -Fq '.codex/' "${INSTALLED_ROOT}/sidekicks/registry.json" \
    && ! grep -Fq '.claude/' "${INSTALLED_ROOT}/sidekicks/registry.json" \
    && grep -Fq 'SIDEKICK_HOST_SESSION_ID' "${SKILL_ROOT}/kay-delegate/SKILL.md" \
    && grep -Fq 'CLAUDE_SESSION_ID' "${SKILL_ROOT}/kay-delegate/SKILL.md" \
    && grep -Fq 'CODEX_THREAD_ID' "${SKILL_ROOT}/kay-delegate/SKILL.md" \
    && ! grep -Fq '${HOME}/.codex/sessions/${SIDEKICK_SESSION}' "${SKILL_ROOT}/kay-delegate/SKILL.md" \
    && grep -Fq 'SIDEKICK_HOST_HOME' "${SKILL_ROOT}/codex-stop/SKILL.md" \
    && grep -Fq 'CLAUDE_SESSION_ID' "${SKILL_ROOT}/codex-stop/SKILL.md" \
    && grep -Fq 'CODEX_THREAD_ID' "${SKILL_ROOT}/codex-stop/SKILL.md" \
    && grep -Fq '.codex-delegation-active' "${SKILL_ROOT}/codex-stop/SKILL.md" \
    && python3 - "${CODE_HOME}/.Codex" "${CODE_HOME}/.codex" <<'PY' >/dev/null
import os
from pathlib import Path
import sys
legacy = Path(sys.argv[1])
lower = Path(sys.argv[2])
try:
    if not legacy.exists():
        raise SystemExit(0)
    if not os.path.samefile(legacy, lower):
        raise SystemExit(1)
except FileNotFoundError:
    raise SystemExit(0)
PY
    then
    pass "installed marketplace cache rewrote runtime surfaces while preserving canonical host-neutral skills"
  else
    fail "installed marketplace surface" "installed cache contents do not match the expected Codex runtime rewrite and canonical skill surface"
  fi
else
  fail "installed marketplace surface" "could not locate the installed Sidekick marketplace tree"
fi

echo ""
echo -e "${bold}═══════════════════════════════════════════${reset}"
if [ "${FAIL}" -eq 0 ]; then
  echo -e "${green}${bold}LIVE MARKETPLACE INSTALL PASSED${reset} ($PASS checks)"
  echo "Temporary workspace was: ${WORKSPACE} (removed on exit)"
else
  echo -e "${red}${bold}LIVE MARKETPLACE INSTALL FAILED${reset} ($FAIL of $((PASS+FAIL)) failed)"
  echo "Temporary workspace was: ${WORKSPACE} (removed on exit)"
fi
echo -e "${bold}═══════════════════════════════════════════${reset}"

exit "${FAIL}"

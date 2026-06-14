#!/usr/bin/env bash
# Run one live Kay delegation task in an isolated test-notes-app sandbox.
# Usage: run_kay_live_task.bash <task_id> <prompt_file> [max_seconds]
#
# Env:
#   SIDEKICK_KAY_REQUIRE_STATUS=1  — fail when kay rc=0 but last message lacks STATUS: SUCCESS
#   SIDEKICK_KAY_HOST_VERIFY=1     — run scripts/verify-*.sh on host after Kay
#   SIDEKICK_KAY_SEED_DIR=<path>   — copy seed tree instead of canonical test-notes-app
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../.env.local" ]; then
  set -a
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/../.env.local"
  set +a
fi

TASK_ID="${1:-}"
PROMPT_FILE="${2:-}"
MAX_SECONDS="${3:-600}"
MODEL_PROVIDER="${KAY_LIVE_MODEL_PROVIDER:-opencode-go}"
MODEL="${KAY_LIVE_MODEL:-mimo-v2.5-pro}"

SIDEKICK_KAY_REQUIRE_STATUS="${SIDEKICK_KAY_REQUIRE_STATUS:-1}"
SIDEKICK_KAY_HOST_VERIFY="${SIDEKICK_KAY_HOST_VERIFY:-1}"

if [ -z "${TASK_ID}" ] || [ -z "${PROMPT_FILE}" ] || [ ! -f "${PROMPT_FILE}" ]; then
  echo "usage: $0 <task_id> <prompt_file> [max_seconds]" >&2
  exit 2
fi

for tool in node npm curl kay; do
  command -v "${tool}" >/dev/null 2>&1 || { echo "missing tool: ${tool}" >&2; exit 1; }
done

REAL_KAY_AUTH="${KAY_AUTH_PATH:-${HOME}/.kay/auth.json}"
OPENCODE_GO_API_KEY_VALUE="${OPENCODE_GO_API_KEY:-${CUSTOM_OPENCODE_GO_API_KEY:-}}"
MINIMAX_API_KEY_VALUE="${MINIMAX_API_KEY:-}"
MINIMAX_KEY_FROM_ENV=0
if [ -n "${MINIMAX_API_KEY:-}" ]; then
  MINIMAX_KEY_FROM_ENV=1
fi

if [ "${MODEL_PROVIDER}" = "minimax" ]; then
  if [ -z "${MINIMAX_API_KEY_VALUE}" ] && [ -f "${REAL_KAY_AUTH}" ]; then
    MINIMAX_API_KEY_VALUE="$(python3 -c 'import json, sys, pathlib
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
api_key = data.get("provider_credentials", {}).get("minimax", {}).get("api_key")
if api_key:
    print(api_key)
    raise SystemExit(0)
raise SystemExit(1)' "${REAL_KAY_AUTH}" 2>/dev/null)" || true
  fi
  if [ -z "${MINIMAX_API_KEY_VALUE}" ]; then
    echo "MINIMAX_API_KEY not set and no minimax key in ${REAL_KAY_AUTH}" >&2
    exit 1
  fi
elif [ "${MODEL_PROVIDER}" = "opencode-go" ]; then
  if [ -z "${OPENCODE_GO_API_KEY_VALUE}" ]; then
    echo "OPENCODE_GO_API_KEY not set (use .env.local)" >&2
    exit 1
  fi
fi

ISOLATED_HOME="$(mktemp -d -t sidekick-kay-home.XXXXXX)"
mkdir -p "${ISOLATED_HOME}/.kay"
# Kay prefers ~/.kay/auth.json over env when provider credentials exist (alo-labs/kay#43).
if [ "${MODEL_PROVIDER}" = "minimax" ]; then
  if [ "${MINIMAX_KEY_FROM_ENV}" -eq 1 ]; then
    printf '%s\n' '{"auth_mode":"chatgpt","provider_credentials":{}}' > "${ISOLATED_HOME}/.kay/auth.json"
  else
    python3 -c 'import json, pathlib, sys
api_key = sys.argv[1]
path = pathlib.Path(sys.argv[2])
path.write_text(json.dumps({
    "auth_mode": "chatgpt",
    "provider_credentials": {"minimax": {"api_key": api_key}},
}, indent=2) + "\n")' "${MINIMAX_API_KEY_VALUE}" "${ISOLATED_HOME}/.kay/auth.json"
  fi
else
  printf '%s\n' '{"auth_mode":"chatgpt","provider_credentials":{}}' > "${ISOLATED_HOME}/.kay/auth.json"
fi

NOTES_APP_SRC="${SIDEKICK_KAY_SEED_DIR:-${SCRIPT_DIR}/test-notes-app}"
if [ ! -d "${NOTES_APP_SRC}" ]; then
  echo "source not found: ${NOTES_APP_SRC}" >&2
  exit 1
fi
SANDBOX="$(mktemp -d -t sidekick-kay-task.XXXXXX)"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --exclude='node_modules' --exclude='data' --exclude='.git' "${NOTES_APP_SRC}/" "${SANDBOX}/"
else
  cp -R "${NOTES_APP_SRC}/." "${SANDBOX}/"
  rm -rf "${SANDBOX}/node_modules" "${SANDBOX}/data" "${SANDBOX}/.git"
fi

# Canonical app keeps seeded health bug; seeds and complex tasks use ok health.
if [ "${NOTES_APP_SRC}" = "${SCRIPT_DIR}/test-notes-app" ]; then
  python3 - <<'PY' "${SANDBOX}/src/server.js"
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
text = re.sub(r"status:\s*'broken'", "status: 'ok'", text)
path.write_text(text)
PY
fi

( cd "${SANDBOX}" && npm install --silent )

# Pre-seed verify script templates for bulk-archive / sort tasks on canonical app.
VERIFY_SEED="${SCRIPT_DIR}/test-notes-app-seeds/export-import/scripts"
if [[ "${NOTES_APP_SRC}" == "${SCRIPT_DIR}/test-notes-app" && -d "${VERIFY_SEED}" ]]; then
  mkdir -p "${SANDBOX}/scripts"
  case "$(basename "${PROMPT_FILE}")" in
    task8-bulk-archive*.txt)
      for vs in verify-bulk-archive-api.sh verify-bulk-archive-ui.sh; do
        if [ -f "${VERIFY_SEED}/${vs}" ]; then
          cp "${VERIFY_SEED}/${vs}" "${SANDBOX}/scripts/${vs}"
        fi
      done
      ;;
    task9-sort-ui*.txt)
      for vs in verify-sort-api.sh verify-sort-ui.sh; do
        if [ -f "${VERIFY_SEED}/${vs}" ]; then
          cp "${VERIFY_SEED}/${vs}" "${SANDBOX}/scripts/${vs}"
        fi
      done
      ;;
  esac
fi

LOG_DIR="${SCRIPT_DIR}/.kay-live-logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/${TASK_ID}-$(date +%Y%m%dT%H%M%S).log"
META_FILE="${LOG_FILE%.log}.meta"
OUT_FILE="${LOG_DIR}/${TASK_ID}-last-message.txt"
printf 'task=%s\nsandbox=%s\n' "${TASK_ID}" "${SANDBOX}" >"${META_FILE}"

run_with_timeout() {
  local secs="$1"; shift
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "${secs}" "$@"
  elif command -v timeout >/dev/null 2>&1; then timeout "${secs}" "$@"
  else perl -e 'use POSIX ":sys_wait_h"; my $s=shift; my $p=fork(); die unless defined $p; if(!$p){exec @ARGV or die}; my $d=time+$s; while(time<$d){my $r=waitpid($p,WNOHANG); exit($?>>8) if $r==$p; sleep 1} kill 0,$p and kill "TERM",-$p; waitpid($p,0); exit 124' "${secs}" "$@"; fi
}

prepare_kay_runner() {
  local bin="$1"
  local help_file
  help_file="$(mktemp)"
  KAY_RUNNER=()

  if "${bin}" exec --help >"${help_file}" 2>&1; then
    if grep -q -- '--dangerously-bypass-approvals-and-sandbox' "${help_file}"; then
      KAY_RUNNER=( "${bin}" exec )
      if grep -q -- '--skip-git-repo-check' "${help_file}"; then
        KAY_RUNNER+=(--skip-git-repo-check)
      fi
      if grep -q -- '--ephemeral' "${help_file}"; then
        KAY_RUNNER+=(--ephemeral)
      fi
      KAY_RUNNER+=(--dangerously-bypass-approvals-and-sandbox)
    elif grep -q -- '--full-auto' "${help_file}"; then
      if grep -q -- '--skip-git-repo-check' "${help_file}"; then
        KAY_RUNNER=( "${bin}" exec --skip-git-repo-check --full-auto )
      else
        KAY_RUNNER=( "${bin}" exec --full-auto )
      fi
    else
      KAY_RUNNER=( "${bin}" exec )
    fi
  else
    KAY_RUNNER=( "${bin}" exec --full-auto )
  fi
  rm -f "${help_file}"
}

prepare_kay_runner kay

PROMPT="$(cat "${PROMPT_FILE}")"
echo "task=${TASK_ID} sandbox=${SANDBOX} log=${LOG_FILE}"

# Kay --max-seconds triggers graceful STATUS: BLOCKED before the outer wrapper SIGTERM.
KAY_MAX_SECONDS="${MAX_SECONDS}"
OUTER_TIMEOUT=$((MAX_SECONDS + 120))

set +e
if [ "${MODEL_PROVIDER}" = "minimax" ]; then
  KAY_ENV=( HOME="${ISOLATED_HOME}" MINIMAX_API_KEY="${MINIMAX_API_KEY_VALUE}" )
else
  KAY_ENV=( HOME="${ISOLATED_HOME}" OPENCODE_GO_API_KEY="${OPENCODE_GO_API_KEY_VALUE}" CUSTOM_OPENCODE_GO_API_KEY="${OPENCODE_GO_API_KEY_VALUE}" )
fi
run_with_timeout "${OUTER_TIMEOUT}" env "${KAY_ENV[@]}" \
  "${KAY_RUNNER[@]}" \
    -C "${SANDBOX}" \
    -c "model_provider=${MODEL_PROVIDER}" \
    -c "model=${MODEL}" \
    -c model_reasoning_effort=low \
    -c preferred_model_reasoning_effort=low \
    --max-seconds "${KAY_MAX_SECONDS}" \
    --output-last-message "${OUT_FILE}" \
    "${PROMPT}" >"${LOG_FILE}" 2>&1
RC=$?
set -e

echo "kay_rc=${RC}"

FAIL=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1: $2"; FAIL=$((FAIL + 1)); }

if [[ "${RC}" -eq 0 && "${SIDEKICK_KAY_REQUIRE_STATUS}" -eq 1 ]]; then
  if [ -f "${OUT_FILE}" ] && grep -q 'STATUS: SUCCESS' "${OUT_FILE}"; then
    pass "status_contract"
  else
    fail "status_contract" "kay rc=0 but STATUS: SUCCESS missing in ${OUT_FILE}"
    RC=1
  fi
fi

if [[ "${SIDEKICK_KAY_HOST_VERIFY}" -eq 1 ]]; then
  shopt -s nullglob
  verify_scripts=( "${SANDBOX}"/scripts/verify-*.sh )
  shopt -u nullglob
  if [ "${#verify_scripts[@]}" -eq 0 ]; then
    fail "host_verify" "no scripts/verify-*.sh in sandbox"
    RC=1
  else
    export PORT="${PORT:-3458}"
    for vs in "${verify_scripts[@]}"; do
      base="$(basename "${vs}")"
      case "${base}" in
        e2e-smoke.sh) continue ;;
      esac
      if ( cd "${SANDBOX}" && export PORT && bash "${vs}" ); then
        pass "host_verify $(basename "${vs}")"
      else
        fail "host_verify $(basename "${vs}")" "script exited non-zero"
        RC=1
      fi
    done
  fi
fi

echo "sandbox=${SANDBOX}"
echo "log=${LOG_FILE}"
echo "meta=${META_FILE}"
echo "last_message=${OUT_FILE}"
tail -n 40 "${LOG_FILE}" || true
if [ -f "${OUT_FILE}" ]; then
  echo "--- last message ---"
  tail -n 30 "${OUT_FILE}"
fi

if [[ "${FAIL}" -gt 0 ]]; then
  echo "gate_failures=${FAIL}"
fi
exit "${RC}"

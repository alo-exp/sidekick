#!/usr/bin/env bash
# Run a test command through Kay so local/pre-release evidence is produced by
# the Kay runtime rather than the host agent shell.

set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "Usage: bash tests/run_in_kay.bash <test-command> [args...]" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_KAY_PREEXISTED=0
if [ -e "${REPO_ROOT}/.kay" ]; then
  REPO_KAY_PREEXISTED=1
fi
HOST_HOME="${HOME}"
ISOLATED_HOME="$(mktemp -d "${TMPDIR:-/tmp}/sidekick-kay-home.XXXXXX")"
RESULT_DIR="${ISOLATED_HOME}/.sidekick-kay-test-results"
RESULT_ID="$(date -u +%Y%m%dT%H%M%SZ).$$"
RESULT_FILE="${RESULT_DIR}/${RESULT_ID}.rc"
SCRIPT_FILE="${RESULT_DIR}/${RESULT_ID}.bash"
KAY_OUTPUT_FILE="${RESULT_DIR}/${RESULT_ID}.out"
ISOLATED_QG_STATE="${ISOLATED_HOME}/.codex/.sidekick/quality-gate-state"
if [ -n "${SIDEKICK_HOST_QG_STATE:-}" ]; then
  HOST_QG_STATE="${SIDEKICK_HOST_QG_STATE}"
  HOST_QG_DIR="$(dirname "${HOST_QG_STATE}")"
elif [ -n "${SIDEKICK_HOST_QG_DIR:-}" ]; then
  HOST_QG_DIR="${SIDEKICK_HOST_QG_DIR}"
  HOST_QG_STATE="${HOST_QG_DIR}/quality-gate-state"
elif [ -n "${SIDEKICK_QG_STATE:-}" ]; then
  HOST_QG_STATE="${SIDEKICK_QG_STATE}"
  HOST_QG_DIR="$(dirname "${HOST_QG_STATE}")"
elif [ -n "${SIDEKICK_QG_DIR:-}" ]; then
  HOST_QG_DIR="${SIDEKICK_QG_DIR}"
  HOST_QG_STATE="${HOST_QG_DIR}/quality-gate-state"
else
  HOST_QG_DIR="${HOST_HOME}/.codex/.sidekick"
  HOST_QG_STATE="${HOST_QG_DIR}/quality-gate-state"
fi
HOST_PROOF_DIR="${HOST_QG_DIR}/kay-wrapper-proofs"
PROOF_DIR="${ISOLATED_HOME}/.sidekick-kay-proof"
PROOF_FILE="${PROOF_DIR}/${RESULT_ID}.proof"
PROOF_TOKEN="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
PROOF_SHA256="$(printf '%s' "${PROOF_TOKEN}" | shasum -a 256 | awk '{print $1}')"
RUN_NONCE="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
RUN_ID="${RESULT_ID}.${RUN_NONCE}"

cleanup() {
  if [ "${SIDEKICK_KEEP_KAY_TEST_ARTIFACTS:-0}" != "1" ]; then
    rm -rf "${ISOLATED_HOME}"
    rm -f "${SCRIPT_FILE}" "${RESULT_FILE}" "${KAY_OUTPUT_FILE}"
    if [ "${REPO_KAY_PREEXISTED}" = "0" ]; then
      rm -rf "${REPO_ROOT}/.kay"
    fi
  fi
}
trap cleanup EXIT

resolve_kay_binary() {
  local candidate
  for candidate in kay code codex coder "${HOME}/.local/bin/kay"; do
    if command -v "${candidate}" >/dev/null 2>&1 \
      && "${candidate}" --version 2>/dev/null | grep -qiE '^kay([[:space:]]|$)' \
      && "${candidate}" exec --help >/dev/null 2>&1; then
      command -v "${candidate}"
      return 0
    fi
    if [ -x "${candidate}" ] \
      && "${candidate}" --version 2>/dev/null | grep -qiE '^kay([[:space:]]|$)' \
      && "${candidate}" exec --help >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

quote_command() {
  local arg
  for arg in "$@"; do
    printf '%q ' "${arg}"
  done
}

quote_value() {
  printf '%q' "$1"
}

copy_if_present() {
  local src="$1" dst="$2"
  if [ -f "${src}" ]; then
    mkdir -p "$(dirname "${dst}")"
    cp "${src}" "${dst}"
  fi
}

run_with_timeout() {
  local secs="$1"
  shift
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

prepare_kay_runner() {
  local help
  help="$("${KAY_BIN}" exec --help 2>&1 || true)"

  KAY_RUNNER=("${KAY_BIN}" exec)
  if grep -Fq -- "--skip-git-repo-check" <<<"${help}"; then
    KAY_RUNNER+=(--skip-git-repo-check)
  fi
  if grep -Fq -- "--dangerously-bypass-approvals-and-sandbox" <<<"${help}"; then
    KAY_RUNNER+=(--dangerously-bypass-approvals-and-sandbox)
  elif grep -Fq -- "--full-auto" <<<"${help}"; then
    KAY_RUNNER+=(--full-auto)
  else
    echo "FAIL: Kay exec does not support --full-auto or the legacy bypass sandbox flag." >&2
    exit 1
  fi
}

KAY_BIN="$(resolve_kay_binary)" || {
  echo "FAIL: Kay binary not found. Expected kay/code/codex/coder on PATH or ~/.local/bin/kay." >&2
  exit 1
}
prepare_kay_runner
HOST_SESSION_ID="${SIDEKICK_SESSION_ID:-${CODEX_THREAD_ID:-${CLAUDE_SESSION_ID:-${SESSION_ID:-}}}}"

mkdir -p "${RESULT_DIR}" "${PROOF_DIR}" "${ISOLATED_HOME}/.kay" "${ISOLATED_HOME}/.codex" "${ISOLATED_HOME}/.config" "${ISOLATED_HOME}/.cache" "${ISOLATED_HOME}/.local/share"
rm -f "${RESULT_FILE}" "${SCRIPT_FILE}"
printf '%s\n' "${PROOF_TOKEN}" > "${PROOF_FILE}"
chmod 600 "${PROOF_FILE}"

copy_if_present "${HOST_HOME}/.kay/auth.json" "${ISOLATED_HOME}/.kay/auth.json"
copy_if_present "${HOST_HOME}/.kay/auth_accounts.json" "${ISOLATED_HOME}/.kay/auth_accounts.json"
copy_if_present "${HOST_HOME}/.kay/config.toml" "${ISOLATED_HOME}/.kay/config.toml"
copy_if_present "${HOST_HOME}/.kay/kay.toml" "${ISOLATED_HOME}/.kay/kay.toml"
copy_if_present "${HOST_HOME}/.kay/models_cache.openai.json" "${ISOLATED_HOME}/.kay/models_cache.openai.json"
OPENCODE_GO_API_KEY_VALUE="${OPENCODE_GO_API_KEY:-${CUSTOM_OPENCODE_GO_API_KEY:-}}"
if [ -z "${OPENCODE_GO_API_KEY_VALUE}" ] && [ -f "${HOST_HOME}/.kay/auth.json" ] && command -v python3 >/dev/null 2>&1; then
  OPENCODE_GO_API_KEY_VALUE="$(python3 -c 'import json, sys, pathlib
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
api_key = data.get("provider_credentials", {}).get("opencode-go", {}).get("api_key")
if api_key:
    print(api_key)
    raise SystemExit(0)
raise SystemExit(1)' "${HOST_HOME}/.kay/auth.json" 2>/dev/null || true)"
fi
if [ -d "${HOST_HOME}/.config/opencode" ]; then
  mkdir -p "${ISOLATED_HOME}/.config"
  cp -R "${HOST_HOME}/.config/opencode" "${ISOLATED_HOME}/.config/opencode"
fi

TEST_COMMAND="$(quote_command "$@")"
PROMOTE_RELEASE_MARKERS=0
if [ "$#" -eq 3 ] \
  && [ "$1" = "SIDEKICK_LIVE_CODEX=1" ] \
  && [ "$2" = "bash" ] \
  && [ "$3" = "tests/run_release.bash" ]; then
  PROMOTE_RELEASE_MARKERS=1
elif [ "$#" -eq 4 ] \
  && [ "$1" = "SIDEKICK_LIVE_FORGE=1" ] \
  && [ "$2" = "SIDEKICK_LIVE_CODEX=1" ] \
  && [ "$3" = "bash" ] \
  && [ "$4" = "tests/run_release.bash" ]; then
  PROMOTE_RELEASE_MARKERS=1
fi
REPO_ROOT_Q="$(quote_value "${REPO_ROOT}")"
RESULT_DIR_Q="$(quote_value "${RESULT_DIR}")"
RESULT_FILE_Q="$(quote_value "${RESULT_FILE}")"
ISOLATED_HOME_Q="$(quote_value "${ISOLATED_HOME}")"
ISOLATED_QG_STATE_Q="$(quote_value "${ISOLATED_QG_STATE}")"
PROOF_FILE_Q="$(quote_value "${PROOF_FILE}")"
PROOF_TOKEN_Q="$(quote_value "${PROOF_TOKEN}")"
PROOF_SHA256_Q="$(quote_value "${PROOF_SHA256}")"
RUN_ID_Q="$(quote_value "${RUN_ID}")"
HOST_SESSION_ID_Q="$(quote_value "${HOST_SESSION_ID}")"
cat >"${SCRIPT_FILE}" <<EOF
#!/usr/bin/env bash
export HOME=${ISOLATED_HOME_Q}
export KAY_HOME="\${HOME}/.kay"
export CODEX_HOME="\${HOME}/.codex"
export XDG_CONFIG_HOME="\${HOME}/.config"
export XDG_CACHE_HOME="\${HOME}/.cache"
export XDG_DATA_HOME="\${HOME}/.local/share"
export SIDEKICK_KAY_WRAPPER_ACTIVE=1
export SIDEKICK_KAY_ISOLATED_HOME=${ISOLATED_HOME_Q}
export SIDEKICK_KAY_PROOF_FILE=${PROOF_FILE_Q}
export SIDEKICK_KAY_PROOF_TOKEN=${PROOF_TOKEN_Q}
export SIDEKICK_KAY_PROOF_SHA256=${PROOF_SHA256_Q}
export SIDEKICK_KAY_RUN_ID=${RUN_ID_Q}
unset SIDEKICK_QG_STATE SIDEKICK_QG_DIR SIDEKICK_HOST_QG_DIR SIDEKICK_HOST_QG_STATE
cd ${REPO_ROOT_Q}
if [ -n ${HOST_SESSION_ID_Q} ]; then
  export SIDEKICK_SESSION_ID=${HOST_SESSION_ID_Q}
  mkdir -p "\${HOME}/.codex/.sidekick"
  printf '%s\n' ${HOST_SESSION_ID_Q} > "\${HOME}/.codex/.sidekick/current-session"
fi
set +e
${TEST_COMMAND}
rc=\$?
mkdir -p ${RESULT_DIR_Q}
printf '%s\n' "\$rc" > ${RESULT_FILE_Q}
exit "\$rc"
EOF
chmod +x "${SCRIPT_FILE}"

PROMPT=$(cat <<EOF
OBJECTIVE: Run the Sidekick test command exactly as provided and report the real exit code.

CONTEXT:
- Repository root: ${REPO_ROOT}
- This is a test-only Kay execution using isolated temporary HOME: ${ISOLATED_HOME}
- Do not edit source files unless the test command itself does so.
- Use OpenCode Go with deepseek-v4-flash and low reasoning, as already configured by this invocation.

DESIRED STATE:
- Execute this command from the repository root:
  bash ${SCRIPT_FILE}
- After the command exits, write its numeric exit code to:
  ${RESULT_FILE}

SUCCESS CRITERIA:
- The command actually ran inside Kay.
- ${RESULT_FILE} exists and contains the command exit code.
- Your final response includes STATUS and TEST_EXIT_CODE.

IMPLEMENTATION:
Run this exact command immediately as your next action. Do not inspect files first,
do not summarize the script first, and do not wait for more instructions:

bash ${SCRIPT_FILE}
EOF
)

set +e
printf '%s\n' "${PROMPT}" | run_with_timeout "${SIDEKICK_KAY_EXEC_TIMEOUT_SECONDS:-900}" \
  env \
  -u SIDEKICK_QG_STATE \
  -u SIDEKICK_QG_DIR \
  -u SIDEKICK_HOST_QG_DIR \
  -u SIDEKICK_HOST_QG_STATE \
  HOME="${ISOLATED_HOME}" \
  KAY_HOME="${ISOLATED_HOME}/.kay" \
  CODEX_HOME="${ISOLATED_HOME}/.codex" \
  XDG_CONFIG_HOME="${ISOLATED_HOME}/.config" \
  XDG_CACHE_HOME="${ISOLATED_HOME}/.cache" \
  XDG_DATA_HOME="${ISOLATED_HOME}/.local/share" \
  OPENCODE_GO_API_KEY="${OPENCODE_GO_API_KEY_VALUE}" \
  CUSTOM_OPENCODE_GO_API_KEY="${OPENCODE_GO_API_KEY_VALUE}" \
  "${KAY_RUNNER[@]}" \
  -C "${REPO_ROOT}" \
  -c model_provider=opencode-go \
  -c model=opencode-go/deepseek-v4-flash \
  -c model_reasoning_effort=low \
  -c preferred_model_reasoning_effort=low \
  - >"${KAY_OUTPUT_FILE}" 2>&1
KAY_RC=$?
set -e

cat "${KAY_OUTPUT_FILE}"

if [ ! -f "${RESULT_FILE}" ]; then
  echo "FAIL: Kay did not write ${RESULT_FILE}" >&2
  exit 1
fi

TEST_RC="$(tr -d '[:space:]' < "${RESULT_FILE}")"
case "${TEST_RC}" in
  ''|*[!0-9]*)
    echo "FAIL: invalid Kay test exit code: ${TEST_RC}" >&2
    exit 1
    ;;
esac

if [ "${TEST_RC}" -ne 0 ]; then
  exit "${TEST_RC}"
fi

if [ "${KAY_RC}" -ne 0 ]; then
  exit "${KAY_RC}"
fi

if [ "${PROMOTE_RELEASE_MARKERS}" = "1" ]; then
  if [ ! -f "${ISOLATED_QG_STATE}" ]; then
    echo "FAIL: Kay release run produced no isolated live-pyramid candidate state" >&2
    exit 1
  fi
  matching_candidate="$(
    awk -v run_id="${RUN_ID}" -v token="${PROOF_TOKEN}" '
      $1 == "quality-gate-live-pyramid-candidate" {
        has_run = 0
        has_token = 0
        for (i = 2; i <= NF; i++) {
          if ($i == "run_id=" run_id) has_run = 1
          if ($i == "token=" token) has_token = 1
        }
        if (has_run && has_token) print
      }
    ' "${ISOLATED_QG_STATE}"
  )"
  candidate_count="$(
    printf '%s\n' "${matching_candidate}" | awk 'NF { count++ } END { print count + 0 }'
  )"
  if [ "${candidate_count}" -ne 1 ]; then
    echo "FAIL: Kay release run produced ${candidate_count} matching live-pyramid candidates; expected exactly 1" >&2
    exit 1
  fi
  candidate_sha256="$(printf '%s\n' "${matching_candidate}" | shasum -a 256 | awk '{print $1}')"
  command_sha256="$(printf '%s' "${TEST_COMMAND}" | shasum -a 256 | awk '{print $1}')"
  final_marker="quality-gate-live-pyramid"
  for marker_field in ${matching_candidate}; do
    case "${marker_field}" in
      quality-gate-live-pyramid-candidate|token=*|proof_sha256=*) ;;
      *) final_marker="${final_marker} ${marker_field}" ;;
    esac
  done
  final_marker="${final_marker} source=kay-wrapper proof_sha256=${PROOF_SHA256} candidate_sha256=${candidate_sha256} command_sha256=${command_sha256}"
  mkdir -p "${HOST_QG_DIR}" "${HOST_PROOF_DIR}"
  chmod 700 "${HOST_PROOF_DIR}" 2>/dev/null || true
  printf 'sidekick-kay-wrapper-proof run_id=%s proof_sha256=%s candidate_sha256=%s command_sha256=%s\n' "${RUN_ID}" "${PROOF_SHA256}" "${candidate_sha256}" "${command_sha256}" > "${HOST_PROOF_DIR}/${RUN_ID}.proof"
  chmod 600 "${HOST_PROOF_DIR}/${RUN_ID}.proof" 2>/dev/null || true
  printf '%s\n' "${final_marker}" >> "${HOST_QG_STATE}"
  if [ -f "${ISOLATED_HOME}/.codex/.sidekick/current-session" ]; then
    cp "${ISOLATED_HOME}/.codex/.sidekick/current-session" "${HOST_QG_DIR}/current-session"
  fi
fi

exit 0

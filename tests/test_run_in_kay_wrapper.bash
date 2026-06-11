#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Kay wrapper behavioral tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT
FAKE_BIN="${TMP_ROOT}/bin"
mkdir -p "${FAKE_BIN}"

cat > "${FAKE_BIN}/kay" <<'FAKEKAY'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "--version" ]; then
  echo "kay 0.0.0-test"
  exit 0
fi

if [ "${1:-}" = "exec" ] && [ "${2:-}" = "--help" ]; then
  echo "Usage: kay exec [--full-auto] [--skip-git-repo-check]"
  exit 0
fi

if [ "${1:-}" != "exec" ]; then
  echo "unexpected fake kay args: $*" >&2
  exit 2
fi

prompt="$(cat)"
script="$(printf '%s\n' "${prompt}" | awk '/^bash .*\.bash$/ {print $2; exit}')"
if [ -z "${script}" ] || [ ! -f "${script}" ]; then
  echo "fake kay could not find generated wrapper script" >&2
  exit 2
fi

if [ "${FAKE_KAY_RUN_SCRIPT:-0}" = "1" ]; then
  bash "${script}"
  exit $?
fi

home_dir="$(awk -F= '/^export HOME=/{print $2; exit}' "${script}")"
run_id="$(awk -F= '/^export SIDEKICK_KAY_RUN_ID=/{print $2; exit}' "${script}")"
token="$(awk -F= '/^export SIDEKICK_KAY_PROOF_TOKEN=/{print $2; exit}' "${script}")"
proof_sha="$(awk -F= '/^export SIDEKICK_KAY_PROOF_SHA256=/{print $2; exit}' "${script}")"
result_file="$(awk '/^printf.*> / {print $NF; exit}' "${script}")"
if [ -n "${FAKE_KAY_TOKEN_LOG:-}" ]; then
  printf '%s\n' "${token}" > "${FAKE_KAY_TOKEN_LOG}"
fi

mkdir -p "$(dirname "${result_file}")"
printf '%s\n' "${FAKE_KAY_TEST_RC:-0}" > "${result_file}"

candidate_count="${FAKE_KAY_CANDIDATE_COUNT:-0}"
if [ "${FAKE_KAY_WRITE_CANDIDATE:-0}" = "1" ] && [ "${candidate_count}" -eq 0 ]; then
  candidate_count=1
fi

if [ "${candidate_count}" -gt 0 ]; then
  mkdir -p "${home_dir}/.codex/.sidekick"
  i=1
  while [ "${i}" -le "${candidate_count}" ]; do
    printf 'quality-gate-live-pyramid-candidate session=fake-session sha=fake-sha-%s at=20260524T00000%sZ run_id=%s token=%s proof_sha256=%s\n' "${i}" "${i}" "${run_id}" "${token}" "${proof_sha}" >> "${home_dir}/.codex/.sidekick/quality-gate-state"
    i=$((i + 1))
  done
fi

if [ "${FAKE_KAY_WRITE_HOST_LEAK:-0}" = "1" ] && [ -n "${SIDEKICK_QG_STATE:-}" ]; then
  printf 'host leak\n' >> "${SIDEKICK_QG_STATE}"
fi

exit "${FAKE_KAY_RC:-0}"
FAKEKAY
chmod +x "${FAKE_BIN}/kay"

run_wrapper() {
  env \
    PATH="${FAKE_BIN}:$PATH" \
    HOME="${TMP_ROOT}/host-home" \
    SIDEKICK_SESSION_ID="fake-session" \
    SIDEKICK_HOST_QG_DIR="${TMP_ROOT}/host-qg" \
    FAKE_KAY_WRITE_CANDIDATE="${FAKE_KAY_WRITE_CANDIDATE:-0}" \
    FAKE_KAY_WRITE_HOST_LEAK="${FAKE_KAY_WRITE_HOST_LEAK:-0}" \
    FAKE_KAY_TEST_RC="${FAKE_KAY_TEST_RC:-0}" \
    FAKE_KAY_RC="${FAKE_KAY_RC:-0}" \
    FAKE_KAY_RUN_SCRIPT="${FAKE_KAY_RUN_SCRIPT:-0}" \
    FAKE_KAY_TOKEN_LOG="${TMP_ROOT}/fake-kay-token" \
    "$@"
}

run_wrapper_no_host_qg_override() {
  env \
    PATH="${FAKE_BIN}:$PATH" \
    HOME="${TMP_ROOT}/host-home" \
    SIDEKICK_SESSION_ID="fake-session" \
    FAKE_KAY_WRITE_CANDIDATE="${FAKE_KAY_WRITE_CANDIDATE:-0}" \
    FAKE_KAY_WRITE_HOST_LEAK="${FAKE_KAY_WRITE_HOST_LEAK:-0}" \
    FAKE_KAY_TEST_RC="${FAKE_KAY_TEST_RC:-0}" \
    FAKE_KAY_RC="${FAKE_KAY_RC:-0}" \
    FAKE_KAY_RUN_SCRIPT="${FAKE_KAY_RUN_SCRIPT:-0}" \
    FAKE_KAY_TOKEN_LOG="${TMP_ROOT}/fake-kay-token" \
    "$@"
}

echo "=== T1: noncanonical commands do not promote candidates ==="
rm -rf "${TMP_ROOT}/host-home" "${TMP_ROOT}/host-qg"
if FAKE_KAY_WRITE_CANDIDATE=1 run_wrapper bash "${ROOT}/tests/run_in_kay.bash" bash -c true >/tmp/sidekick-fake-kay-noncanonical.out 2>&1; then
  if [ ! -f "${TMP_ROOT}/host-qg/quality-gate-state" ]; then
    assert_pass "noncanonical command does not promote candidate marker"
  else
    assert_fail "noncanonical command does not promote candidate marker" "$(cat "${TMP_ROOT}/host-qg/quality-gate-state")"
  fi
else
  assert_fail "noncanonical wrapper command" "$(cat /tmp/sidekick-fake-kay-noncanonical.out)"
fi

echo "=== T2: canonical release command fails without any candidate ==="
rm -rf "${TMP_ROOT}/host-home" "${TMP_ROOT}/host-qg"
if run_wrapper bash "${ROOT}/tests/run_in_kay.bash" SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash >/tmp/sidekick-fake-kay-zero.out 2>&1; then
  assert_fail "canonical zero-candidate release run fails" "wrapper unexpectedly passed"
elif grep -Fq "produced no matching live-pyramid candidates" /tmp/sidekick-fake-kay-zero.out \
  || grep -Fq "produced no isolated live-pyramid candidate state" /tmp/sidekick-fake-kay-zero.out; then
  assert_pass "canonical zero-candidate release run fails"
else
  assert_fail "canonical zero-candidate release run fails" "$(cat /tmp/sidekick-fake-kay-zero.out)"
fi

echo "=== T3: canonical release command promotes one proof-bound candidate ==="
rm -rf "${TMP_ROOT}/host-home" "${TMP_ROOT}/host-qg"
rm -f "${TMP_ROOT}/fake-kay-token"
if FAKE_KAY_WRITE_CANDIDATE=1 run_wrapper bash "${ROOT}/tests/run_in_kay.bash" SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash >/tmp/sidekick-fake-kay-canonical.out 2>&1; then
  state="${TMP_ROOT}/host-qg/quality-gate-state"
  leaked_token="$(cat "${TMP_ROOT}/fake-kay-token" 2>/dev/null || true)"
  if [ -f "${state}" ] \
    && grep -Fq "quality-gate-live-pyramid " "${state}" \
    && grep -Fq "source=kay-wrapper" "${state}" \
    && ! grep -Fq "token=" "${state}" \
    && [ -n "${leaked_token}" ] \
    && ! grep -Fq "${leaked_token}" "${state}" \
    && grep -Eq 'proof_sha256=[0-9a-f]{64}' "${state}" \
    && grep -Eq 'candidate_sha256=[0-9a-f]{64}' "${state}" \
    && grep -Eq 'command_sha256=[0-9a-f]{64}' "${state}"; then
    proof_field_count="$(grep -Eo 'proof_sha256=[0-9a-f]{64}' "${state}" | wc -l | tr -d ' ')"
    run_id="$(awk '{for(i=1;i<=NF;i++) if($i ~ /^run_id=/){print substr($i,8); exit}}' "${state}")"
    proof_path="${TMP_ROOT}/host-qg/kay-wrapper-proofs/${run_id}.proof"
    if [ "${proof_field_count}" != "1" ]; then
      assert_fail "canonical proof field count" "expected one proof_sha256 field, got ${proof_field_count}: $(cat "${state}")"
    elif printf '%s\n' "${proof_path}" | grep -Fq "${leaked_token}"; then
      assert_fail "canonical proof filename token redaction" "${proof_path}"
    elif [ ! -f "${proof_path}" ]; then
      assert_fail "canonical proof record" "missing proof record for ${run_id}"
    elif grep -Fq "${leaked_token}" "${proof_path}"; then
      assert_fail "canonical proof record token redaction" "$(cat "${proof_path}")"
    else
      assert_pass "canonical release command promotes one proof-bound candidate"
    fi
  else
    assert_fail "canonical promotion marker" "$(find "${TMP_ROOT}" -path '*quality-gate-state' -type f -maxdepth 5 -print -exec cat {} \; 2>/dev/null)"
  fi
else
  assert_fail "canonical wrapper command" "$(cat /tmp/sidekick-fake-kay-canonical.out)"
fi

echo "=== T4: duplicate canonical candidates promote the newest entry ==="
rm -rf "${TMP_ROOT}/host-home" "${TMP_ROOT}/host-qg"
rm -f "${TMP_ROOT}/fake-kay-token"
if FAKE_KAY_CANDIDATE_COUNT=2 run_wrapper bash "${ROOT}/tests/run_in_kay.bash" SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash >/tmp/sidekick-fake-kay-duplicate.out 2>&1; then
  state="${TMP_ROOT}/host-qg/quality-gate-state"
  final_count="$(grep -c '^quality-gate-live-pyramid ' "${state}" 2>/dev/null || true)"
  if [ "${final_count}" = "1" ] \
    && grep -Fq 'sha=fake-sha-2' "${state}" \
    && grep -Fq 'at=20260524T000002Z' "${state}" \
    && grep -Fq 'promoting the newest entry' /tmp/sidekick-fake-kay-duplicate.out; then
    assert_pass "duplicate canonical candidates promote the newest entry"
  else
    assert_fail "duplicate canonical candidates promote the newest entry" "$(cat "${state}" 2>/dev/null || cat /tmp/sidekick-fake-kay-duplicate.out)"
  fi
else
  assert_fail "duplicate canonical candidates promote the newest entry" "$(cat /tmp/sidekick-fake-kay-duplicate.out)"
fi

echo "=== T5: inherited host quality-gate state is cleared inside Kay command ==="
rm -rf "${TMP_ROOT}/host-home" "${TMP_ROOT}/host-qg"
mkdir -p "${TMP_ROOT}/host-qg"
host_state="${TMP_ROOT}/host-qg/quality-gate-state"
if SIDEKICK_QG_STATE="${host_state}" FAKE_KAY_WRITE_HOST_LEAK=1 run_wrapper bash "${ROOT}/tests/run_in_kay.bash" bash -c true >/tmp/sidekick-fake-kay-env.out 2>&1; then
  if [ ! -f "${host_state}" ]; then
    assert_pass "inherited host quality-gate state is cleared inside Kay command"
  else
    assert_fail "inherited host quality-gate state is cleared" "$(cat "${host_state}")"
  fi
else
  assert_fail "env isolation wrapper command" "$(cat /tmp/sidekick-fake-kay-env.out)"
fi

echo "=== T6: live model override env does not leak into nested Kay command ==="
rm -rf "${TMP_ROOT}/host-home" "${TMP_ROOT}/host-qg"
env_probe="${TMP_ROOT}/kay-model-env"
if SIDEKICK_KAY_MODEL_PROVIDER=minimax SIDEKICK_KAY_MODEL=minimax/MiniMax-M3 FAKE_KAY_RUN_SCRIPT=1 \
  run_wrapper bash "${ROOT}/tests/run_in_kay.bash" bash -c "printf '%s|%s' \"\${SIDEKICK_KAY_MODEL_PROVIDER-}\" \"\${SIDEKICK_KAY_MODEL-}\" > '${env_probe}'" >/tmp/sidekick-fake-kay-model-env.out 2>&1; then
  if [ "$(cat "${env_probe}" 2>/dev/null || true)" = "|" ]; then
    assert_pass "live model override env does not leak into nested Kay command"
  else
    assert_fail "live model override env does not leak" "$(cat "${env_probe}" 2>/dev/null || true)"
  fi
else
  assert_fail "live model override env does not leak" "$(cat /tmp/sidekick-fake-kay-model-env.out)"
fi

echo "=== T7: failed Kay/test exits suppress promotion ==="
rm -rf "${TMP_ROOT}/host-home" "${TMP_ROOT}/host-qg"
if FAKE_KAY_WRITE_CANDIDATE=1 FAKE_KAY_TEST_RC=7 run_wrapper bash "${ROOT}/tests/run_in_kay.bash" SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash >/tmp/sidekick-fake-kay-fail.out 2>&1; then
  assert_fail "failed test exit suppresses promotion" "wrapper unexpectedly passed"
elif [ ! -f "${TMP_ROOT}/host-qg/quality-gate-state" ]; then
  assert_pass "failed test exit suppresses promotion"
else
  assert_fail "failed test exit suppresses promotion" "$(cat "${TMP_ROOT}/host-qg/quality-gate-state")"
fi

echo "=== T8: wrapper honors pre-resolved host quality-gate state ==="
rm -rf "${TMP_ROOT}/host-home" "${TMP_ROOT}/host-qg" "${TMP_ROOT}/claude-qg"
mkdir -p "${TMP_ROOT}/claude-qg"
if FAKE_KAY_WRITE_CANDIDATE=1 SIDEKICK_QG_STATE="${TMP_ROOT}/claude-qg/quality-gate-state" run_wrapper_no_host_qg_override bash "${ROOT}/tests/run_in_kay.bash" SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash >/tmp/sidekick-fake-kay-claude-state.out 2>&1; then
  if [ -f "${TMP_ROOT}/claude-qg/quality-gate-state" ] && [ ! -f "${TMP_ROOT}/host-qg/quality-gate-state" ]; then
    assert_pass "wrapper honors pre-resolved host quality-gate state"
  else
    assert_fail "wrapper honors pre-resolved host quality-gate state" "claude=$(cat "${TMP_ROOT}/claude-qg/quality-gate-state" 2>/dev/null || true) codex=$(cat "${TMP_ROOT}/host-qg/quality-gate-state" 2>/dev/null || true)"
  fi
else
  assert_fail "wrapper honors pre-resolved host quality-gate state" "$(cat /tmp/sidekick-fake-kay-claude-state.out)"
fi

echo "=== T9: fake Kay executes generated script path ==="
rm -rf "${TMP_ROOT}/host-home" "${TMP_ROOT}/host-qg"
side_effect="${TMP_ROOT}/script-executed"
if FAKE_KAY_RUN_SCRIPT=1 run_wrapper bash "${ROOT}/tests/run_in_kay.bash" bash -c "printf ok > '${side_effect}'" >/tmp/sidekick-fake-kay-script.out 2>&1; then
  if [ "$(cat "${side_effect}" 2>/dev/null || true)" = "ok" ]; then
    assert_pass "fake Kay executes generated script path"
  else
    assert_fail "fake Kay executes generated script path" "missing side effect"
  fi
else
  assert_fail "fake Kay executes generated script path" "$(cat /tmp/sidekick-fake-kay-script.out)"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

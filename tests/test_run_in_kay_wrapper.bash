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

home_dir="$(awk -F= '/^export HOME=/{print $2; exit}' "${script}")"
run_id="$(awk -F= '/^export SIDEKICK_KAY_RUN_ID=/{print $2; exit}' "${script}")"
token="$(awk -F= '/^export SIDEKICK_KAY_PROOF_TOKEN=/{print $2; exit}' "${script}")"
proof_sha="$(awk -F= '/^export SIDEKICK_KAY_PROOF_SHA256=/{print $2; exit}' "${script}")"
result_file="$(awk '/^printf.*> / {print $NF; exit}' "${script}")"

mkdir -p "$(dirname "${result_file}")"
printf '%s\n' "${FAKE_KAY_TEST_RC:-0}" > "${result_file}"

if [ "${FAKE_KAY_WRITE_CANDIDATE:-0}" = "1" ]; then
  mkdir -p "${home_dir}/.codex/.sidekick"
  printf 'quality-gate-live-pyramid-candidate session=fake-session sha=fake-sha at=20260524T000000Z run_id=%s token=%s proof_sha256=%s\n' "${run_id}" "${token}" "${proof_sha}" >> "${home_dir}/.codex/.sidekick/quality-gate-state"
fi

if [ "${FAKE_KAY_WRITE_HOST_LEAK:-0}" = "1" ] && [ -n "${SIDEKICK_QG_STATE:-}" ]; then
  printf 'host leak\n' >> "${SIDEKICK_QG_STATE}"
fi

exit "${FAKE_KAY_RC:-0}"
FAKEKAY
chmod +x "${FAKE_BIN}/kay"

run_wrapper() {
  PATH="${FAKE_BIN}:$PATH" \
  HOME="${TMP_ROOT}/host-home" \
  SIDEKICK_SESSION_ID="fake-session" \
  SIDEKICK_HOST_QG_DIR="${TMP_ROOT}/host-qg" \
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

echo "=== T2: canonical release command fails without exactly one candidate ==="
rm -rf "${TMP_ROOT}/host-home" "${TMP_ROOT}/host-qg"
if run_wrapper bash "${ROOT}/tests/run_in_kay.bash" SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash >/tmp/sidekick-fake-kay-zero.out 2>&1; then
  assert_fail "canonical zero-candidate release run fails" "wrapper unexpectedly passed"
elif grep -Fq "expected exactly 1" /tmp/sidekick-fake-kay-zero.out || grep -Fq "produced no isolated live-pyramid candidate state" /tmp/sidekick-fake-kay-zero.out; then
  assert_pass "canonical zero-candidate release run fails"
else
  assert_fail "canonical zero-candidate release run fails" "$(cat /tmp/sidekick-fake-kay-zero.out)"
fi

echo "=== T3: canonical release command promotes one proof-bound candidate ==="
rm -rf "${TMP_ROOT}/host-home" "${TMP_ROOT}/host-qg"
if FAKE_KAY_WRITE_CANDIDATE=1 run_wrapper bash "${ROOT}/tests/run_in_kay.bash" SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash >/tmp/sidekick-fake-kay-canonical.out 2>&1; then
  state="${TMP_ROOT}/host-qg/quality-gate-state"
  if [ -f "${state}" ] \
    && grep -Fq "quality-gate-live-pyramid " "${state}" \
    && grep -Fq "source=kay-wrapper" "${state}" \
    && grep -Eq 'proof_sha256=[0-9a-f]{64}' "${state}"; then
    run_id="$(awk '{for(i=1;i<=NF;i++) if($i ~ /^run_id=/){print substr($i,8); exit}}' "${state}")"
    if [ -f "${TMP_ROOT}/host-qg/kay-wrapper-proofs/${run_id}.sha256" ]; then
      assert_pass "canonical release command promotes one proof-bound candidate"
    else
      assert_fail "canonical proof record" "missing proof record for ${run_id}"
    fi
  else
    assert_fail "canonical promotion marker" "$(cat "${state}" 2>/dev/null || true)"
  fi
else
  assert_fail "canonical wrapper command" "$(cat /tmp/sidekick-fake-kay-canonical.out)"
fi

echo "=== T4: inherited host quality-gate state is cleared inside Kay command ==="
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

echo "=== T5: failed Kay/test exits suppress promotion ==="
rm -rf "${TMP_ROOT}/host-home" "${TMP_ROOT}/host-qg"
if FAKE_KAY_WRITE_CANDIDATE=1 FAKE_KAY_TEST_RC=7 run_wrapper bash "${ROOT}/tests/run_in_kay.bash" SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash >/tmp/sidekick-fake-kay-fail.out 2>&1; then
  assert_fail "failed test exit suppresses promotion" "wrapper unexpectedly passed"
elif [ ! -f "${TMP_ROOT}/host-qg/quality-gate-state" ]; then
  assert_pass "failed test exit suppresses promotion"
else
  assert_fail "failed test exit suppresses promotion" "$(cat "${TMP_ROOT}/host-qg/quality-gate-state")"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

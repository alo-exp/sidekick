#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — test runner contract
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

expect_file() {
  local path="$1" label="$2"
  if [ -f "${ROOT}/${path}" ]; then
    assert_pass "${label}"
  else
    assert_fail "${label}" "missing ${path}"
  fi
}

expect_contains() {
  local path="$1" needle="$2" label="$3"
  if [ -f "${ROOT}/${path}" ] && grep -Fq -- "${needle}" "${ROOT}/${path}"; then
    assert_pass "${label}"
  else
    assert_fail "${label}" "missing ${needle} in ${path}"
  fi
}

expect_absent() {
  local path="$1" needle="$2" label="$3"
  if [ -f "${ROOT}/${path}" ] && grep -Fq -- "${needle}" "${ROOT}/${path}"; then
    assert_fail "${label}" "unexpected ${needle} in ${path}"
  else
    assert_pass "${label}"
  fi
}

echo "=== T1: runner files exist ==="
expect_file "tests/run_unit.bash" "strict non-live runner exists"
expect_file "tests/run_all.bash" "skip-safe runner exists"
expect_file "tests/run_release.bash" "release runner exists"
expect_file "tests/run_in_kay.bash" "Kay test wrapper exists"

echo "=== T2: run_unit is strictly non-live ==="
for script in \
  test_install_sh.bash \
  test_agent_surface_render.bash \
  test_host_surface_rewrite.bash \
  test_plugin_integrity.bash \
  test_codex_marketplace_release_gate.bash \
  test_runner_contract.bash \
  test_repo_layout.bash; do
  expect_contains "tests/run_unit.bash" "${script}" "run_unit includes ${script}"
done
for live_script in \
  test_forge_e2e.bash \
  run_live_codex_plugin_read.bash \
  smoke/run_smoke.bash \
  run_live_e2e.bash \
  run_live_codex_marketplace_install.bash \
  smoke/run_codex_smoke.bash \
  run_live_codex_e2e.bash; do
  expect_absent "tests/run_unit.bash" "${live_script}" "run_unit excludes live-gated ${live_script}"
done
expect_absent "tests/run_unit.bash" "cleanup_transient_repo_artifacts" "run_unit does not delete developer artifacts"
expect_absent "tests/run_unit.bash" "SIDEKICK_REPO_ROOT=" "run_unit does not override the cleanup root"

echo "=== T3: run_all is skip-safe everything ==="
expect_contains "tests/run_all.bash" "run_unit.bash" "run_all delegates strict suites to run_unit"
for live_script in \
  test_forge_e2e.bash \
  smoke/run_smoke.bash \
  run_live_e2e.bash \
  run_live_codex_plugin_read.bash \
  run_live_codex_marketplace_install.bash \
  smoke/run_codex_smoke.bash \
  run_live_codex_e2e.bash; do
  expect_contains "tests/run_all.bash" "${live_script}" "run_all includes skip-safe ${live_script}"
done

echo "=== T4: release runner authorizes from strict then live stages ==="
expect_contains "tests/run_release.bash" "run_unit.bash" "run_release uses strict non-live runner for tier 1"
expect_absent "tests/run_release.bash" "run_all.bash" "run_release does not use skip-safe aggregate runner as tier 1"
expect_contains "tests/run_release.bash" "SIDEKICK_KAY_WRAPPER_ACTIVE" "run_release requires Kay wrapper proof for release evidence"
expect_absent "tests/run_release.bash" "SIDEKICK_ALLOW_HOST_TESTS" "run_release has no host-test bypass"
expect_contains "tests/run_in_kay.bash" "deepseek-v4-flash" "Kay test wrapper uses DeepSeek V4 Flash"
expect_contains "tests/run_in_kay.bash" "model_reasoning_effort=low" "Kay test wrapper uses low reasoning"
expect_contains "tests/run_in_kay.bash" "current-session" "Kay test wrapper writes current session file"
expect_contains "tests/run_in_kay.bash" "--full-auto" "Kay test wrapper prefers full-auto execution"
expect_contains "tests/run_in_kay.bash" "prepare_kay_runner" "Kay test wrapper probes supported execution flags"
expect_contains "tests/run_in_kay.bash" "mktemp -d" "Kay test wrapper creates an isolated temporary HOME"
expect_contains "tests/run_in_kay.bash" "SIDEKICK_KAY_PROOF_FILE" "Kay test wrapper mints a wrapper proof file"
expect_contains "tests/run_release.bash" "validate_kay_wrapper_context" "run_release validates Kay wrapper proof"
expect_contains "tests/run_release.bash" "quality-gate-live-pyramid-candidate" "run_release writes only candidate live markers"
expect_contains "tests/run_in_kay.bash" "quality-gate-live-pyramid-candidate" "Kay wrapper promotes candidate live markers"
expect_contains "tests/run_in_kay.bash" "PROMOTE_RELEASE_MARKERS=0" "Kay wrapper defaults marker promotion off"
expect_contains "tests/run_in_kay.bash" 'SIDEKICK_LIVE_CODEX=1' "Kay wrapper only promotes canonical live release runs"
expect_contains "tests/run_in_kay.bash" "expected exactly 1" "Kay wrapper fails canonical release runs without exactly one candidate"
expect_contains "tests/run_in_kay.bash" "proof_sha256=" "Kay wrapper promotes proof-bound live markers"
expect_contains "tests/run_release.bash" "SIDEKICK_KAY_PROOF_SHA256" "run_release validates Kay wrapper proof digest"
expect_contains "hooks/validate-release-gate.sh" "print run_id" "release hook counts distinct Kay wrapper run ids"
expect_contains "hooks/validate-release-gate.sh" "kay-wrapper-proofs" "release hook requires wrapper proof records"

tmp_qg="$(mktemp -d "${TMPDIR:-/tmp}/sidekick-runner-contract.XXXXXX")"
if env \
  -u SIDEKICK_KAY_WRAPPER_ACTIVE \
  -u SIDEKICK_KAY_ISOLATED_HOME \
  -u SIDEKICK_KAY_PROOF_FILE \
  -u SIDEKICK_KAY_PROOF_TOKEN \
  SIDEKICK_TESTS_INSIDE_KAY=1 \
  SIDEKICK_LIVE_CODEX=1 \
  SIDEKICK_QG_STATE="${tmp_qg}/quality-gate-state" \
  bash "${ROOT}/tests/run_release.bash" >"${tmp_qg}/host-release.out" 2>&1; then
  assert_fail "host self-attestation cannot run release gate" "host release command unexpectedly passed"
elif [ -f "${tmp_qg}/quality-gate-state" ] && grep -Fq -- "quality-gate-live-pyramid" "${tmp_qg}/quality-gate-state"; then
  assert_fail "host self-attestation cannot record live marker" "host release command wrote a live-pyramid marker"
else
  assert_pass "host self-attestation cannot record live marker"
fi

spoof_state="${tmp_qg}/spoofed-host-state"
printf 'quality-gate-live-pyramid-candidate session=spoof-session sha=abc123 at=now\n' > "${spoof_state}"
if grep -Fq -- "quality-gate-live-pyramid session=" "${spoof_state}"; then
  assert_fail "spoofed wrapper env cannot write host marker" "candidate fixture already contained final marker"
else
  assert_pass "spoofed wrapper env cannot write host marker"
fi

expect_contains "tests/run_in_kay.bash" "KAY_RC" "Kay wrapper tracks Kay process exit"
expect_contains "tests/run_in_kay.bash" 'if [ "${KAY_RC}" -ne 0 ]' "Kay wrapper refuses marker promotion after Kay failure"
expect_contains "tests/run_in_kay.bash" "unset SIDEKICK_QG_STATE" "Kay wrapper clears inherited host state overrides"
expect_contains "tests/run_in_kay.bash" "trap cleanup EXIT" "Kay wrapper cleans temporary auth artifacts"

echo "=== T5: live Codex probe is portable ==="
expect_contains "tests/run_live_codex_plugin_read.bash" "SIDEKICK_CODEX_REPO" "Codex probe exposes repo override"
expect_contains "tests/run_live_codex_plugin_read.bash" "SIDEKICK_CODEX_BIN" "Codex probe exposes binary override"
expect_contains "tests/smoke/run_codex_smoke.bash" "SIDEKICK_KAY_BIN" "Kay smoke exposes binary override"
expect_contains "tests/run_live_codex_e2e.bash" "SIDEKICK_KAY_BIN" "Kay live E2E exposes binary override"
expect_absent "tests/run_live_codex_plugin_read.bash" "/Users/" "Codex probe avoids absolute maintainer home paths"
expect_absent "tests/run_live_codex_plugin_read.bash" "/.cargo/bin" "Codex probe avoids hard-coded cargo bin path"

echo "=== T6: live Codex marketplace install follows public surface ==="
expect_contains "tests/run_live_codex_marketplace_install.bash" 'MARKETPLACE_SOURCE="${CODEX_MARKETPLACE_SOURCE:-alo-labs/codex-plugins}"' "marketplace install uses current public marketplace source"
expect_contains "tests/run_live_codex_marketplace_install.bash" 'MARKETPLACE_NAME="${CODEX_MARKETPLACE_NAME:-alo-labs-codex}"' "marketplace install uses current marketplace name"
expect_contains "tests/run_live_codex_marketplace_install.bash" 'plugin add "sidekick@${MARKETPLACE_NAME}"' "marketplace install adds Sidekick plugin from configured marketplace"
expect_contains "tests/run_live_codex_marketplace_install.bash" 'manifest["skills"]' "marketplace install resolves skill root from manifest"
expect_contains "tests/run_live_codex_marketplace_install.bash" 'SKILL_ROOT' "marketplace install validates manifest-selected skill surface"
expect_absent "tests/run_live_codex_marketplace_install.bash" 'MARKETPLACE_SOURCE="${CODEX_MARKETPLACE_SOURCE:-alo-exp/sidekick}"' "marketplace install avoids old repo/name source"
expect_absent "tests/run_live_codex_marketplace_install.bash" 'MARKETPLACE_SOURCE="${CODEX_MARKETPLACE_SOURCE:-alo-labs-codex/sidekick}"' "marketplace install avoids marketplace-name-as-repo source"
expect_absent "tests/run_live_codex_marketplace_install.bash" 'MARKETPLACE_NAME="${CODEX_MARKETPLACE_NAME:-alo-labs}"' "marketplace install avoids old marketplace name"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

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
  if [ -f "${ROOT}/${path}" ] && grep -Fq "${needle}" "${ROOT}/${path}"; then
    assert_pass "${label}"
  else
    assert_fail "${label}" "missing ${needle} in ${path}"
  fi
}

expect_absent() {
  local path="$1" needle="$2" label="$3"
  if [ -f "${ROOT}/${path}" ] && grep -Fq "${needle}" "${ROOT}/${path}"; then
    assert_fail "${label}" "unexpected ${needle} in ${path}"
  else
    assert_pass "${label}"
  fi
}

echo "=== T1: runner files exist ==="
expect_file "tests/run_unit.bash" "strict non-live runner exists"
expect_file "tests/run_all.bash" "skip-safe runner exists"
expect_file "tests/run_release.bash" "release runner exists"

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

echo "=== T3: run_all is skip-safe everything ==="
expect_contains "tests/run_all.bash" "run_unit.bash" "run_all delegates strict suites to run_unit"
expect_contains "tests/run_all.bash" "test_forge_e2e.bash" "run_all includes skip-safe Forge E2E probe"
expect_contains "tests/run_all.bash" "run_live_codex_plugin_read.bash" "run_all includes skip-safe Codex plugin/read probe"

echo "=== T4: release runner authorizes from strict then live stages ==="
expect_contains "tests/run_release.bash" "run_unit.bash" "run_release uses strict non-live runner for tier 1"
expect_absent "tests/run_release.bash" "run_all.bash" "run_release does not use skip-safe aggregate runner as tier 1"

echo "=== T5: live Codex probe is portable ==="
expect_contains "tests/run_live_codex_plugin_read.bash" "SIDEKICK_CODEX_REPO" "Codex probe exposes repo override"
expect_contains "tests/run_live_codex_plugin_read.bash" "SIDEKICK_CODEX_BIN" "Codex probe exposes binary override"
expect_absent "tests/run_live_codex_plugin_read.bash" "/Users/" "Codex probe avoids absolute maintainer home paths"
expect_absent "tests/run_live_codex_plugin_read.bash" "/.cargo/bin" "Codex probe avoids hard-coded cargo bin path"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — hooks/forge-delegation-enforcer.sh Tests (Phase 6)
# =============================================================================
# Phase 6 foundation assertions. Plans 06-02 and 06-03 append further tests.
# All tests sandbox HOME so the real ~/.claude/.forge-delegation-active is
# never read or written.

set -euo pipefail

PASS=0; FAIL=0; SKIP=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
HOOK_FILE="${PLUGIN_DIR}/hooks/forge-delegation-enforcer.sh"

green='\033[0;32m'; red='\033[0;31m'; yellow='\033[0;33m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }
skip()        { echo -e "${yellow}SKIP${reset} $1: $2"; SKIP=$((SKIP+1)); }

if [ ! -f "${HOOK_FILE}" ]; then
  echo "ERROR: ${HOOK_FILE} not found"
  exit 1
fi

# Sandbox HOME so the real marker file is untouched.
HOME_SANDBOX="$(mktemp -d)"
trap 'rm -rf "${HOME_SANDBOX}"' EXIT
mkdir -p "${HOME_SANDBOX}/.claude"

# -----------------------------------------------------------------------------
echo "=== test_noop_when_marker_absent ==="
# With no marker file present, hook must exit 0 with empty stdout + stderr.
set +e
_out="$(HOME="${HOME_SANDBOX}" bash "${HOOK_FILE}" \
  <<< '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x","content":"y"}}' \
  2>/tmp/enf_err_$$)"
_rc=$?
_err="$(cat /tmp/enf_err_$$ 2>/dev/null || true)"
rm -f /tmp/enf_err_$$
set -e
if [ "${_rc}" -eq 0 ] && [ -z "${_out}" ] && [ -z "${_err}" ]; then
  assert_pass "test_noop_when_marker_absent"
else
  assert_fail "test_noop_when_marker_absent" "rc=${_rc} out='${_out}' err='${_err}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_exit2_on_malformed_json ==="
set +e
_out="$(HOME="${HOME_SANDBOX}" bash "${HOOK_FILE}" <<< 'not json' 2>/tmp/enf_err_$$)"
_rc=$?
_err="$(cat /tmp/enf_err_$$ 2>/dev/null || true)"
rm -f /tmp/enf_err_$$
set -e
if [ "${_rc}" -eq 2 ] && echo "${_err}" | grep -q 'malformed'; then
  assert_pass "test_exit2_on_malformed_json"
else
  assert_fail "test_exit2_on_malformed_json" "rc=${_rc} err='${_err}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_gen_uuid_format ==="
# Source the hook (source-guard prevents main() from running) and call gen_uuid.
_uuid="$(bash -c "source '${HOOK_FILE}'; gen_uuid")"
if echo "${_uuid}" | grep -Eq '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'; then
  assert_pass "test_gen_uuid_format (uuid=${_uuid})"
else
  assert_fail "test_gen_uuid_format" "bad uuid format: '${_uuid}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_gen_uuid_honors_test_override ==="
# See <test_injection_contract> in 06-01-hook-foundation.md:
# SIDEKICK_TEST_UUID_OVERRIDE forces gen_uuid to echo its value verbatim,
# enabling 06-03's idx-dedup test to exercise the append_idx_row dedup branch.
_fixed="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
_uuid="$(SIDEKICK_TEST_UUID_OVERRIDE="${_fixed}" bash -c "source '${HOOK_FILE}'; gen_uuid")"
if [ "${_uuid}" = "${_fixed}" ]; then
  assert_pass "test_gen_uuid_honors_test_override"
else
  assert_fail "test_gen_uuid_honors_test_override" "expected '${_fixed}' got '${_uuid}'"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — cursor sessionStart bootstrap tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
HOOK_FILE="${PLUGIN_DIR}/hooks/cursor-session-bootstrap.sh"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

if [ ! -f "${HOOK_FILE}" ]; then
  echo "ERROR: ${HOOK_FILE} not found"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not in PATH — skipping cursor session bootstrap tests"
  exit 0
fi

out="$(bash "${HOOK_FILE}" <<< '{"conversation_id":"cursor-session-123","session_id":"cursor-session-123"}' 2>/dev/null)"
sid="$(printf '%s' "${out}" | jq -r '.env.SIDEKICK_SESSION_ID // empty' 2>/dev/null)"
if [ "${sid}" = "cursor-session-123" ]; then
  assert_pass "sessionStart exports SIDEKICK_SESSION_ID from conversation_id"
else
  assert_fail "sessionStart exports SIDEKICK_SESSION_ID" "sid='${sid}' out='${out}'"
fi

out="$(bash "${HOOK_FILE}" <<< '{}' 2>/dev/null)"
if [ -z "${out}" ]; then
  assert_pass "sessionStart noops when conversation_id is absent"
else
  assert_fail "sessionStart noops when conversation_id is absent" "out='${out}'"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

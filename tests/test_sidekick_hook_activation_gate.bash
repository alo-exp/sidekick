#!/usr/bin/env bash
# Regression tests for the Sidekick session activation contract.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
KAY_ENFORCER="${REPO_ROOT}/hooks/codex-delegation-enforcer.sh"
FORGE_ENFORCER="${REPO_ROOT}/hooks/forge-delegation-enforcer.sh"
SESSION_ID="${SIDEKICK_TEST_SESSION:-test-session}"

PASS=0
FAIL=0
assert_pass() { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
assert_fail() { echo "  [FAIL] $1 - $2"; FAIL=$((FAIL + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not in PATH - skipping Sidekick hook activation tests"
  exit 0
fi

setup_home() {
  local h
  h="$(mktemp -d)"
  mkdir -p "${h}/.claude/.sidekick" "${h}/.codex/.sidekick"
  printf '%s\n' "${h}"
}

activate_kay() {
  local h="$1"
  mkdir -p "${h}/.sidekick/sessions/${SESSION_ID}" "${h}/.kay/sessions/${SESSION_ID}"
  printf '%s\n' "kay" > "${h}/.sidekick/sessions/${SESSION_ID}/active-sidekick"
  : > "${h}/.kay/sessions/${SESSION_ID}/.kay-delegation-active"
}

create_kay_marker_only() {
  local h="$1"
  mkdir -p "${h}/.kay/sessions/${SESSION_ID}"
  : > "${h}/.kay/sessions/${SESSION_ID}/.kay-delegation-active"
}

activate_forge() {
  local h="$1"
  mkdir -p "${h}/.sidekick/sessions/${SESSION_ID}" "${h}/.claude/sessions/${SESSION_ID}"
  printf '%s\n' "forge" > "${h}/.sidekick/sessions/${SESSION_ID}/active-sidekick"
  : > "${h}/.claude/sessions/${SESSION_ID}/.forge-delegation-active"
}

create_forge_marker_only() {
  local h="$1"
  mkdir -p "${h}/.claude/sessions/${SESSION_ID}"
  : > "${h}/.claude/sessions/${SESSION_ID}/.forge-delegation-active"
}

run_enforcer() {
  local h="$1" hook="$2" payload="$3"
  HOME="${h}" \
    SIDEKICK_SESSION_ID="${SESSION_ID}" \
    SESSION_ID="${SESSION_ID}" \
    CODEX_THREAD_ID= \
    CODEX_HOME= \
    CODEX_PLUGIN_ROOT= \
    bash "${hook}" <<<"${payload}"
}

expect_enforcer_passthrough() {
  local label="$1" h="$2" hook="$3" out rc decision payload
  payload="$(jq -cn '{tool_name:"Write",tool_input:{file_path:"hooks/generated-test-fixture.sh",content:"changed"}}')"
  out="$(run_enforcer "${h}" "${hook}" "${payload}")"; rc=$?
  decision="$(printf '%s' "${out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  if [ "${rc}" -eq 0 ] && [ -z "${out}" ] && [ -z "${decision}" ]; then
    assert_pass "${label}"
  else
    assert_fail "${label}" "rc=${rc} decision=${decision} out=${out}"
  fi
}

expect_enforcer_denied() {
  local label="$1" h="$2" hook="$3" out rc decision payload
  payload="$(jq -cn '{tool_name:"Write",tool_input:{file_path:"hooks/generated-test-fixture.sh",content:"changed"}}')"
  out="$(run_enforcer "${h}" "${hook}" "${payload}")"; rc=$?
  decision="$(printf '%s' "${out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  if [ "${rc}" -eq 0 ] && [ "${decision}" = "deny" ]; then
    assert_pass "${label}"
  else
    assert_fail "${label}" "rc=${rc} decision=${decision} out=${out}"
  fi
}

echo "Scenario 1: stale Kay marker alone does not activate enforcer hook"
H="$(setup_home)"
create_kay_marker_only "${H}"
expect_enforcer_passthrough "Kay marker without active-sidekick passes through" "${H}" "${KAY_ENFORCER}"
rm -rf "${H}"

echo "Scenario 2: explicit Kay activation enables enforcer hook"
H="$(setup_home)"
activate_kay "${H}"
expect_enforcer_denied "Kay active session denies direct Write" "${H}" "${KAY_ENFORCER}"
rm -rf "${H}"

echo "Scenario 3: stale Forge marker alone does not activate enforcer hook"
H="$(setup_home)"
create_forge_marker_only "${H}"
expect_enforcer_passthrough "Forge marker without active-sidekick passes through" "${H}" "${FORGE_ENFORCER}"
rm -rf "${H}"

echo "Scenario 4: explicit Forge activation enables enforcer hook"
H="$(setup_home)"
activate_forge "${H}"
expect_enforcer_denied "Forge active session denies direct Write" "${H}" "${FORGE_ENFORCER}"
rm -rf "${H}"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
exit "${FAIL}"

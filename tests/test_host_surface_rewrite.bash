#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — host-specific install surface rewrite tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
INSTALL_SH="${PLUGIN_DIR}/install.sh"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

prepare_surface_sandbox() {
  local root="$1"
  cp "${INSTALL_SH}" "${root}/install.sh"
  mkdir -p "${root}/hooks/lib" "${root}/skills/kay-delegate" "${root}/skills/kay-stop" "${root}/skills/codex-delegate" "${root}/skills/codex-stop" "${root}/sidekicks"
  cp -R "${PLUGIN_DIR}/agents" "${root}/agents"
  cp "${PLUGIN_DIR}/hooks/lib/sidekick-registry.sh" "${root}/hooks/lib/sidekick-registry.sh"
  cp "${PLUGIN_DIR}/hooks/hooks.json" "${root}/hooks/hooks.json"
  cp "${PLUGIN_DIR}/skills/kay-delegate/SKILL.md" "${root}/skills/kay-delegate/SKILL.md"
  cp "${PLUGIN_DIR}/skills/kay-stop/SKILL.md" "${root}/skills/kay-stop/SKILL.md"
  cp "${PLUGIN_DIR}/skills/codex-delegate/SKILL.md" "${root}/skills/codex-delegate/SKILL.md"
  cp "${PLUGIN_DIR}/skills/codex-stop/SKILL.md" "${root}/skills/codex-stop/SKILL.md"
  cp "${PLUGIN_DIR}/sidekicks/registry.json" "${root}/sidekicks/registry.json"
}

assert_contains() {
  local path="$1" needle="$2" label="$3"
  if grep -Fq "$needle" "$path"; then
    assert_pass "$label"
  else
    assert_fail "$label" "missing: $needle"
  fi
}

assert_absent() {
  local path="$1" needle="$2" label="$3"
  if grep -Fq "$needle" "$path"; then
    assert_fail "$label" "unexpected: $needle"
  else
    assert_pass "$label"
  fi
}

assert_order() {
  local path="$1" first="$2" second="$3" label="$4" first_line second_line
  first_line="$(grep -nF "$first" "$path" | head -1 | cut -d: -f1 || true)"
  second_line="$(grep -nF "$second" "$path" | head -1 | cut -d: -f1 || true)"
  if [ -n "${first_line}" ] && [ -n "${second_line}" ] && [ "${first_line}" -lt "${second_line}" ]; then
    assert_pass "$label"
  else
    assert_fail "$label" "order not found: ${first} before ${second}"
  fi
}

assert_count() {
  local path="$1" needle="$2" expected="$3" label="$4" actual
  actual="$( { grep -F "$needle" "$path" || true; } | wc -l | tr -d ' ')"
  if [ "${actual}" = "${expected}" ]; then
    assert_pass "$label"
  else
    assert_fail "$label" "expected ${expected}, found ${actual}: ${needle}"
  fi
}

run_case() {
  local host="$1"
  local host_env_var="$2"
  local host_session_var="$3"
  local other_env_var="$4"
  local other_session_var="$5"
  local marker_prefix="$6"
  local skill_prefix="$7"
  local root

  root="$(mktemp -d)"
  trap 'rm -rf "${root}" 2>/dev/null || true' RETURN
  prepare_surface_sandbox "${root}"
  mkdir -p "${root}/home"

  if [ "${host}" = "codex" ]; then
    env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_SESSION_ID -u CLAUDE_PROJECT_DIR -u CLAUDE_THREAD_ID \
      HOME="${root}/home" \
      SIDEKICK_INSTALL_CODE=0 \
      CODEX_PLUGIN_ROOT="${root}" \
      bash "${root}/install.sh" >/dev/null 2>&1
  else
    env -u CODEX_PLUGIN_ROOT -u CODEX_HOME -u CODEX_THREAD_ID -u CODEX_PROJECT_DIR \
      HOME="${root}/home" \
      SIDEKICK_INSTALL_CODE=0 \
      CLAUDE_PLUGIN_ROOT="${root}" \
      bash "${root}/install.sh" >/dev/null 2>&1
  fi

  local hooks="${root}/hooks/hooks.json"
  local registry="${root}/sidekicks/registry.json"
  local registry_helper="${root}/hooks/lib/sidekick-registry.sh"
  local canonical_kay_skill="${root}/skills/kay-delegate/SKILL.md"
  local generated_kay_skill="${root}/agents/${host}/kay-delegate/SKILL.md"
  local generated_kay_stop_skill="${root}/agents/${host}/kay-stop/SKILL.md"
  local generated_codex_stop_skill="${root}/agents/${host}/codex-stop/SKILL.md"
  assert_contains "${hooks}" "${host_env_var}" "${host}: hooks.json uses the host plugin root"
  assert_absent "${hooks}" "${other_env_var}" "${host}: hooks.json excludes the other host root"
  assert_contains "${hooks}" "\${${host_env_var}:-\${SIDEKICK_PLUGIN_ROOT:-}}" "${host}: hooks.json prefers the active host plugin root"
  assert_absent "${hooks}" "\${SIDEKICK_PLUGIN_ROOT:-\${${host_env_var}" "${host}: hooks.json does not let stale SIDEKICK_PLUGIN_ROOT override host root"

  assert_contains "${registry_helper}" "${host_env_var}" "${host}: registry helper uses the host plugin root"
  assert_contains "${registry_helper}" "${host_session_var}" "${host}: registry helper uses the host session var"
  assert_absent "${registry_helper}" "${other_env_var}" "${host}: registry helper excludes the other host root"
  assert_absent "${registry_helper}" "${other_session_var}" "${host}: registry helper excludes the other host session var"
  assert_order "${registry_helper}" "if [[ -n \"\${${host_env_var}:-}\" ]]; then" "if [[ -n \"\${SIDEKICK_PLUGIN_ROOT:-}\" ]]; then" "${host}: registry helper prefers the active host plugin root"
  assert_count "${registry_helper}" "if [[ -n \"\${${host_env_var}:-}\" ]]; then" "1" "${host}: registry helper has one active host root branch"

  assert_contains "${registry}" "${marker_prefix}/sessions/\${${host_session_var}}" "${host}: registry marker rewrites to the host session path"
  assert_absent "${registry}" "${other_env_var}" "${host}: registry excludes the other host root"
  assert_absent "${registry}" "${other_session_var}" "${host}: registry excludes the other host session var"

  assert_contains "${canonical_kay_skill}" "SIDEKICK_HOST_SESSION_ID" "${host}: canonical Kay skill remains host-placeholder based"
  assert_contains "${canonical_kay_skill}" "CLAUDE_SESSION_ID" "${host}: canonical Kay skill keeps Claude fallback in source"
  assert_contains "${canonical_kay_skill}" "CODEX_THREAD_ID" "${host}: canonical Kay skill keeps Codex fallback in source"
  assert_absent "${canonical_kay_skill}" "${marker_prefix}/sessions/\${${host_session_var}}" "${host}: install does not rewrite canonical Kay skill to a host session path"

  assert_contains "${generated_kay_skill}" "\${HOME}/${marker_prefix}/sessions/\${SIDEKICK_SESSION}" "${host}: generated Kay skill uses the host session path"
  assert_contains "${generated_kay_skill}" "${host_session_var}" "${host}: generated Kay skill resolver uses the host session var"
  assert_absent "${generated_kay_skill}" "${other_env_var}" "${host}: generated Kay skill excludes the other host root"
  assert_absent "${generated_kay_skill}" "${other_session_var}" "${host}: generated Kay skill excludes the other host session var"

  assert_contains "${generated_kay_stop_skill}" "${host_session_var}" "${host}: generated Kay stop skill uses the host session var"
  assert_absent "${generated_kay_stop_skill}" "${other_session_var}" "${host}: generated Kay stop skill excludes the other host session var"
  assert_contains "${generated_codex_stop_skill}" "${host_session_var}" "${host}: generated Codex stop skill uses the host session var"
  assert_absent "${generated_codex_stop_skill}" "${other_session_var}" "${host}: generated Codex stop skill excludes the other host session var"
}

run_mixed_detection_case() {
  local host="$1"
  local root hooks

  root="$(mktemp -d)"
  trap 'rm -rf "${root}" 2>/dev/null || true' RETURN
  prepare_surface_sandbox "${root}"
  mkdir -p "${root}/home"

  if [ "${host}" = "codex" ]; then
    env -u SIDEKICK_INSTALL_HOST \
      HOME="${root}/home" \
      SIDEKICK_INSTALL_CODE=0 \
      CODEX_PLUGIN_ROOT="${root}" \
      CLAUDE_SESSION_ID="claude-session-from-parent" \
      bash "${root}/install.sh" >/dev/null 2>&1
  else
    env -u SIDEKICK_INSTALL_HOST \
      HOME="${root}/home" \
      SIDEKICK_INSTALL_CODE=0 \
      CLAUDE_PLUGIN_ROOT="${root}" \
      CODEX_HOME="${root}/home/.codex" \
      bash "${root}/install.sh" >/dev/null 2>&1
  fi

  hooks="${root}/hooks/hooks.json"
  case "${host}" in
    codex)
      assert_contains "${hooks}" "\${CODEX_PLUGIN_ROOT:-\${SIDEKICK_PLUGIN_ROOT:-}}" "mixed env: CODEX_PLUGIN_ROOT beats generic Claude session env"
      assert_absent "${hooks}" "CLAUDE_PLUGIN_ROOT" "mixed env: Codex explicit root does not render Claude hooks"
      ;;
    claude)
      assert_contains "${hooks}" "\${CLAUDE_PLUGIN_ROOT:-\${SIDEKICK_PLUGIN_ROOT:-}}" "mixed env: CLAUDE_PLUGIN_ROOT beats generic Codex env"
      assert_absent "${hooks}" "CODEX_PLUGIN_ROOT" "mixed env: Claude explicit root does not render Codex hooks"
      ;;
  esac
}

echo "=== T1: Codex install rewrites host-specific paths ==="
run_case "codex" "CODEX_PLUGIN_ROOT" "CODEX_THREAD_ID" "CLAUDE_PLUGIN_ROOT" "CLAUDE_SESSION_ID" ".codex" "~/.codex"

echo "=== T2: Claude install rewrites host-specific paths ==="
run_case "claude" "CLAUDE_PLUGIN_ROOT" "CLAUDE_SESSION_ID" "CODEX_PLUGIN_ROOT" "CODEX_THREAD_ID" ".claude" "~/.claude"

echo "=== T3: Explicit plugin roots win mixed host detection ==="
run_mixed_detection_case "claude"
run_mixed_detection_case "codex"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

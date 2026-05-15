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
  mkdir -p "${root}/hooks/lib" "${root}/skills/forge" "${root}/skills/forge-stop" "${root}/skills/codex-stop" "${root}/sidekicks"
  cp "${PLUGIN_DIR}/hooks/lib/sidekick-registry.sh" "${root}/hooks/lib/sidekick-registry.sh"
  cp "${PLUGIN_DIR}/hooks/hooks.json" "${root}/hooks/hooks.json"
  cp "${PLUGIN_DIR}/hooks/validate-release-gate.sh" "${root}/hooks/validate-release-gate.sh"
  cp "${PLUGIN_DIR}/skills/forge/SKILL.md" "${root}/skills/forge/SKILL.md"
  cp "${PLUGIN_DIR}/skills/forge-stop/SKILL.md" "${root}/skills/forge-stop/SKILL.md"
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
      SIDEKICK_INSTALL_FORGE=0 \
      SIDEKICK_INSTALL_CODE=0 \
      CODEX_PLUGIN_ROOT="${root}" \
      bash "${root}/install.sh" >/dev/null 2>&1
  else
    env -u CODEX_PLUGIN_ROOT -u CODEX_HOME -u CODEX_THREAD_ID -u CODEX_PROJECT_DIR \
      HOME="${root}/home" \
      SIDEKICK_INSTALL_FORGE=0 \
      SIDEKICK_INSTALL_CODE=0 \
      CLAUDE_PLUGIN_ROOT="${root}" \
      bash "${root}/install.sh" >/dev/null 2>&1
  fi

  local hooks="${root}/hooks/hooks.json"
  local registry="${root}/sidekicks/registry.json"
  local registry_helper="${root}/hooks/lib/sidekick-registry.sh"
  local release_gate="${root}/hooks/validate-release-gate.sh"
  local forge_skill="${root}/skills/forge/SKILL.md"
  local forge_stop_skill="${root}/skills/forge-stop/SKILL.md"
  local kay_stop_skill="${root}/skills/codex-stop/SKILL.md"
  local host_project_var
  local other_project_var

  if [ "${host}" = "codex" ]; then
    host_project_var="CODEX_PROJECT_DIR"
    other_project_var="CLAUDE_PROJECT_DIR"
  else
    host_project_var="CLAUDE_PROJECT_DIR"
    other_project_var="CODEX_PROJECT_DIR"
  fi

  assert_contains "${hooks}" "${host_env_var}" "${host}: hooks.json uses the host plugin root"
  assert_absent "${hooks}" "${other_env_var}" "${host}: hooks.json excludes the other host root"

  assert_contains "${registry_helper}" "${host_env_var}" "${host}: registry helper uses the host plugin root"
  assert_contains "${registry_helper}" "${host_session_var}" "${host}: registry helper uses the host session var"
  assert_absent "${registry_helper}" "${other_env_var}" "${host}: registry helper excludes the other host root"
  assert_absent "${registry_helper}" "${other_session_var}" "${host}: registry helper excludes the other host session var"

  assert_contains "${release_gate}" "SIDEKICK_QG_DIR=\"\$HOME/${marker_prefix}/.sidekick\"" "${host}: release gate defaults to the host quality-gate state path"
  assert_contains "${release_gate}" 'STATE_FILE="${SIDEKICK_QG_STATE:-${SIDEKICK_QG_DIR}/quality-gate-state}"' "${host}: release gate resolves quality-gate state from the host dir"
  assert_absent "${release_gate}" "${host_session_var}, ${host_session_var}" "${host}: release gate message does not duplicate the host session var"
  case "${marker_prefix}" in
    .codex) assert_absent "${release_gate}" "\$HOME/.claude/.sidekick/quality-gate-state" "${host}: release gate excludes Claude quality-gate state path" ;;
    .claude) assert_absent "${release_gate}" "\$HOME/.codex/.sidekick/quality-gate-state" "${host}: release gate excludes Codex quality-gate state path" ;;
  esac

  assert_contains "${registry}" "${marker_prefix}/sessions/\${${host_session_var}}" "${host}: registry marker rewrites to the host session path"
  assert_absent "${registry}" "${other_env_var}" "${host}: registry excludes the other host root"
  assert_absent "${registry}" "${other_session_var}" "${host}: registry excludes the other host session var"

  assert_contains "${forge_skill}" "\${HOME}/${marker_prefix}/sessions/\${SIDEKICK_SESSION}" "${host}: forge skill rewrites to the host session path"
  assert_contains "${forge_skill}" "${host_session_var}" "${host}: forge skill resolver uses the host session var"
  assert_contains "${forge_skill}" "${host_project_var}" "${host}: forge skill uses the host project var"
  assert_absent "${forge_skill}" "${other_env_var}" "${host}: forge skill excludes the other host root"
  assert_absent "${forge_skill}" "${other_session_var}" "${host}: forge skill excludes the other host session var"
  assert_absent "${forge_skill}" "${other_project_var}" "${host}: forge skill excludes the other host project var"

  assert_contains "${forge_stop_skill}" "${host_session_var}" "${host}: forge stop skill uses the host session var"
  assert_contains "${forge_stop_skill}" "\${HOME}/${marker_prefix}/sessions/\${SIDEKICK_SESSION}" "${host}: forge stop skill rewrites to the host session path"
  assert_absent "${forge_stop_skill}" "${other_session_var}" "${host}: forge stop skill excludes the other host session var"
  assert_contains "${kay_stop_skill}" "${host_session_var}" "${host}: Kay stop skill uses the host session var"
  assert_absent "${kay_stop_skill}" "${other_session_var}" "${host}: Kay stop skill excludes the other host session var"
}

echo "=== T1: Codex install rewrites host-specific paths ==="
run_case "codex" "CODEX_PLUGIN_ROOT" "CODEX_THREAD_ID" "CLAUDE_PLUGIN_ROOT" "CLAUDE_SESSION_ID" ".codex" "~/.codex"

echo "=== T2: Claude install rewrites host-specific paths ==="
run_case "claude" "CLAUDE_PLUGIN_ROOT" "CLAUDE_SESSION_ID" "CODEX_PLUGIN_ROOT" "CODEX_THREAD_ID" ".claude" "~/.claude"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

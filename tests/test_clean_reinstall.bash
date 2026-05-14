#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — clean reinstall bootstrap tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
INSTALL_SH="${PLUGIN_DIR}/install.sh"
TARGET_VERSION="$(python3 -c "import json; print(json.load(open('${PLUGIN_DIR}/sidekicks/registry.json'))['kay']['install']['version'])")"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

copy_snapshot() {
  local dest="$1"
  mkdir -p "${dest}/hooks/lib" "${dest}/hooks" "${dest}/skills/forge" "${dest}/skills/codex-stop" "${dest}/sidekicks" "${dest}/output-styles" "${dest}/.claude-plugin" "${dest}/.codex-plugin"

  cp "${INSTALL_SH}" "${dest}/install.sh"
  cp "${PLUGIN_DIR}/hooks/hooks.json" "${dest}/hooks/hooks.json"
  cp "${PLUGIN_DIR}/hooks/lib/sidekick-registry.sh" "${dest}/hooks/lib/sidekick-registry.sh"
  cp "${PLUGIN_DIR}/hooks/forge-delegation-enforcer.sh" "${dest}/hooks/forge-delegation-enforcer.sh"
  cp "${PLUGIN_DIR}/hooks/codex-delegation-enforcer.sh" "${dest}/hooks/codex-delegation-enforcer.sh"
  cp "${PLUGIN_DIR}/hooks/scrub-legacy-user-hooks.py" "${dest}/hooks/scrub-legacy-user-hooks.py"
  cp "${PLUGIN_DIR}/hooks/validate-release-gate.sh" "${dest}/hooks/validate-release-gate.sh"
  cp "${PLUGIN_DIR}/skills/forge/SKILL.md" "${dest}/skills/forge/SKILL.md"
  cp "${PLUGIN_DIR}/skills/codex-stop/SKILL.md" "${dest}/skills/codex-stop/SKILL.md"
  cp "${PLUGIN_DIR}/sidekicks/registry.json" "${dest}/sidekicks/registry.json"
  cp "${PLUGIN_DIR}/output-styles/forge.md" "${dest}/output-styles/forge.md"
  cp "${PLUGIN_DIR}/output-styles/codex.md" "${dest}/output-styles/codex.md"
  cp "${PLUGIN_DIR}/.claude-plugin/plugin.json" "${dest}/.claude-plugin/plugin.json"
  cp "${PLUGIN_DIR}/.codex-plugin/plugin.json" "${dest}/.codex-plugin/plugin.json"
}

seed_host_state() {
  local home="$1"

  mkdir -p "${home}/.Codex/plugins" "${home}/.codex/plugins" "${home}/.claude"
  cat > "${home}/.Codex/config.toml" <<'EOF'
[plugins."sidekick@alo-labs-codex-local"]
enabled = true

[plugins."topgun@alo-labs-codex"]
enabled = true

[hooks.state."sidekick@alo-labs-codex-local:hooks/hooks.json:session_start:0:0"]
status = "stale"

[hooks.state."sidekick@alo-labs-codex-local:hooks/hooks.json:pre_tool_use:0:0"]
status = "stale"

[hooks.state."topgun@alo-labs-codex:hooks/hooks.json:pre_tool_use:0:0"]
status = "keep"
EOF
  cat > "${home}/.codex/config.toml" <<'EOF'
[plugins."sidekick@alo-labs-codex-local"]
enabled = true

[plugins."topgun@alo-labs-codex"]
enabled = true

[hooks.state."sidekick@alo-labs-codex-local:hooks/hooks.json:session_start:0:0"]
status = "stale"

[hooks.state."sidekick@alo-labs-codex-local:hooks/hooks.json:pre_tool_use:0:0"]
status = "stale"

[hooks.state."topgun@alo-labs-codex:hooks/hooks.json:pre_tool_use:0:0"]
status = "keep"
EOF
  cat > "${home}/.Codex/plugins/installed_plugins.json" <<EOF
{
  "version": 2,
  "plugins": {
    "sidekick@alo-labs-codex-local": [
      {
        "scope": "project",
        "projectPath": "${home}",
        "installPath": "${home}/.Codex/plugins/cache/alo-labs-codex-local/sidekick/current",
        "version": "${TARGET_VERSION}",
        "installedAt": "2026-05-12T00:00:00Z",
        "lastUpdated": "2026-05-12T00:00:00Z"
      }
    ],
    "topgun@alo-labs-codex": [
      {
        "scope": "project",
        "projectPath": "${home}",
        "installPath": "${home}/.Codex/plugins/cache/alo-labs-codex/topgun/current",
        "version": "0.7.6",
        "installedAt": "2026-05-12T00:00:00Z",
        "lastUpdated": "2026-05-12T00:00:00Z"
      }
    ]
  }
}
EOF
  cat > "${home}/.codex/plugins/installed_plugins.json" <<EOF
{
  "version": 2,
  "plugins": {
    "sidekick@alo-labs-codex-local": [
      {
        "scope": "project",
        "projectPath": "${home}",
        "installPath": "${home}/.codex/plugins/cache/alo-labs-codex/sidekick/current",
        "version": "${TARGET_VERSION}",
        "installedAt": "2026-05-12T00:00:00Z",
        "lastUpdated": "2026-05-12T00:00:00Z"
      }
    ],
    "topgun@alo-labs-codex": [
      {
        "scope": "project",
        "projectPath": "${home}",
        "installPath": "${home}/.codex/plugins/cache/alo-labs-codex/topgun/current",
        "version": "0.7.6",
        "installedAt": "2026-05-12T00:00:00Z",
        "lastUpdated": "2026-05-12T00:00:00Z"
      }
    ]
  }
}
EOF
  cat > "${home}/.claude/config.toml" <<'EOF'
[plugins."keep@other-marketplace"]
enabled = true
EOF
}

assert_clean_state() {
  local home="$1"
  local target_root="$2"
  local plugin_root="$3"
  local legacy_backup_root="$4"
  local resolved_current resolved_target legacy_samefile

  resolved_current="$(python3 - "${plugin_root}/current" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).resolve())
PY
)"
  resolved_target="$(python3 - "${target_root}" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).resolve())
PY
)"
  legacy_samefile="$(python3 - "${home}/.Codex" "${home}/.codex" <<'PY'
from pathlib import Path
import os
import sys

legacy = Path(sys.argv[1])
lower = Path(sys.argv[2])
try:
    print("yes" if os.path.samefile(legacy, lower) else "no")
except FileNotFoundError:
    print("no")
PY
)"

  if [ -d "${target_root}" ] \
    && [ -L "${plugin_root}/current" ] \
    && [ "${resolved_current}" = "${resolved_target}" ] \
    && [ ! -e "${plugin_root}/0.5.3" ] \
    && [ ! -e "${plugin_root}/stale-marker.txt" ] \
    && grep -Fq 'CODEX_PLUGIN_ROOT' "${target_root}/hooks/hooks.json" \
    && ! grep -Fq 'CLAUDE_PLUGIN_ROOT' "${target_root}/hooks/hooks.json" \
    && grep -Fq 'CODEX_PROJECT_DIR' "${target_root}/hooks/lib/sidekick-registry.sh" \
    && ! grep -Fq 'CLAUDE_PROJECT_DIR' "${target_root}/hooks/lib/sidekick-registry.sh" \
    && grep -Fq '.codex/' "${target_root}/sidekicks/registry.json" \
    && ! grep -Fq '.claude/' "${target_root}/sidekicks/registry.json" \
    && grep -Fq '~/.kay' "${target_root}/skills/codex-stop/SKILL.md" \
    && ! grep -Fq '~/.claude' "${target_root}/skills/codex-stop/SKILL.md" \
    && ! grep -Fq 'sidekick@alo-labs-codex-local' "${home}/.codex/config.toml" \
    && ! grep -Fq 'sidekick@alo-labs-codex-local' "${home}/.codex/plugins/installed_plugins.json" \
    && grep -Fq 'topgun@alo-labs-codex' "${home}/.codex/config.toml" \
    && grep -Fq 'topgun@alo-labs-codex' "${home}/.codex/plugins/installed_plugins.json" \
    && { [ ! -e "${home}/.Codex" ] || [ "${legacy_samefile}" = "yes" ]; } \
    && [ -d "${legacy_backup_root}" ] \
    && [ -n "$(find "${legacy_backup_root}" -mindepth 1 -maxdepth 2 -type f -print -quit 2>/dev/null)" ] \
    && grep -Fq 'keep@other-marketplace' "${home}/.claude/config.toml"
  then
    return 0
  fi

  return 1
}

WORKDIR="$(mktemp -d "${HOME}/.sidekick-clean-reinstall.XXXXXX")"
trap 'rm -rf "${WORKDIR}" 2>/dev/null || true' EXIT

SOURCE_SNAPSHOT="${WORKDIR}/source-snapshot"
HOME_DIR="${WORKDIR}/home"
TARGET_ROOT="${HOME_DIR}/.codex/plugins/cache/alo-labs-codex/sidekick/${TARGET_VERSION}"
PLUGIN_ROOT="$(dirname "${TARGET_ROOT}")"
LEGACY_BACKUP_ROOT="${HOME_DIR}/.codex/legacy-uppercase-backups"

copy_snapshot "${SOURCE_SNAPSHOT}"
seed_host_state "${HOME_DIR}"

mkdir -p "${PLUGIN_ROOT}/0.5.3"
printf 'stale\n' > "${PLUGIN_ROOT}/0.5.3/stale.txt"
printf 'stale\n' > "${PLUGIN_ROOT}/stale-marker.txt"
ln -sfn "${PLUGIN_ROOT}/0.5.3" "${PLUGIN_ROOT}/current"

echo "=== T1: clean reinstall bootstraps missing versioned tree ==="
if env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_SESSION_ID -u CLAUDE_PROJECT_DIR -u CLAUDE_THREAD_ID \
  HOME="${HOME_DIR}" \
  SIDEKICK_PLUGIN_ROOT="${SOURCE_SNAPSHOT}" \
  CODEX_PLUGIN_ROOT="${TARGET_ROOT}" \
  SIDEKICK_CLEAN_REINSTALL=1 \
  SIDEKICK_INSTALL_FORGE=0 \
  SIDEKICK_INSTALL_CODE=0 \
  bash "${SOURCE_SNAPSHOT}/install.sh" >/tmp/sidekick-clean-reinstall-1.out 2>/tmp/sidekick-clean-reinstall-1.err
then
  assert_pass "clean reinstall exits successfully"
else
  assert_fail "clean reinstall bootstrap" "installer failed on the bootstrap pass"
  cat /tmp/sidekick-clean-reinstall-1.out 2>/dev/null || true
  cat /tmp/sidekick-clean-reinstall-1.err 2>/dev/null || true
  exit 1
fi

if assert_clean_state "${HOME_DIR}" "${TARGET_ROOT}" "${PLUGIN_ROOT}" "${LEGACY_BACKUP_ROOT}"; then
  assert_pass "clean reinstall removes stale registry, config, hook-state, cache roots, and rewrites the live tree"
else
  assert_fail "clean reinstall state" "one or more stale entries or rewrite checks failed"
fi

echo "=== T2: reinstall remains stable after the cache tree is removed again ==="
rm -rf "${PLUGIN_ROOT}"
if env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_SESSION_ID -u CLAUDE_PROJECT_DIR -u CLAUDE_THREAD_ID \
  HOME="${HOME_DIR}" \
  SIDEKICK_PLUGIN_ROOT="${SOURCE_SNAPSHOT}" \
  CODEX_PLUGIN_ROOT="${TARGET_ROOT}" \
  SIDEKICK_CLEAN_REINSTALL=1 \
  SIDEKICK_INSTALL_FORGE=0 \
  SIDEKICK_INSTALL_CODE=0 \
  bash "${SOURCE_SNAPSHOT}/install.sh" >/tmp/sidekick-clean-reinstall-2.out 2>/tmp/sidekick-clean-reinstall-2.err
then
  assert_pass "reinstall after cache-root removal exits successfully"
else
  assert_fail "reinstall after cache-root removal" "installer failed on the second pass"
  cat /tmp/sidekick-clean-reinstall-2.out 2>/dev/null || true
  cat /tmp/sidekick-clean-reinstall-2.err 2>/dev/null || true
  exit 1
fi

if assert_clean_state "${HOME_DIR}" "${TARGET_ROOT}" "${PLUGIN_ROOT}" "${LEGACY_BACKUP_ROOT}"; then
  assert_pass "reinstall after cleanup keeps the current alias stable and leaves unrelated host state intact"
else
  assert_fail "stable reinstall state" "one or more checks failed after the second pass"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

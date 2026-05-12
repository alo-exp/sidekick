#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Integrity & Manifest Tests
# Verifies plugin.json _integrity hashes match actual files on disk.
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
MANIFEST="${PLUGIN_DIR}/.claude-plugin/plugin.json"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

sha256() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }
claim() { python3 -c "import json; d=json.load(open('${MANIFEST}')); print(d['_integrity'].get('${1}',''))"; }

echo "=== Manifest integrity verification ==="

check_hash() {
  local key="$1" rel_path="$2"
  local claimed actual
  claimed="$(claim "$key")"
  actual="$(sha256 "${PLUGIN_DIR}/${rel_path}")"

  if [ -z "${claimed}" ]; then
    assert_fail "integrity key ${key}" "missing from manifest"
    return
  fi
  if [ -z "${actual}" ]; then
    assert_fail "integrity file ${rel_path}" "missing from repo"
    return
  fi
  if [ "${claimed}" = "${actual}" ]; then
    assert_pass "${rel_path} hash matches manifest (${key})"
  else
    assert_fail "${rel_path} hash" "claimed=${claimed} actual=${actual}"
  fi
}

check_hash "install_sh_sha256" "install.sh"
check_hash "forge_md_sha256" "skills/forge.md"
check_hash "forge_skill_md_sha256" "skills/forge/SKILL.md"
check_hash "codex_delegate_skill_md_sha256" "skills/codex-delegate/SKILL.md"
check_hash "codex_delegate_md_sha256" "skills/codex-delegate.md"
check_hash "hooks_json_sha256" "hooks/hooks.json"
check_hash "forge_delegation_enforcer_sha256" "hooks/forge-delegation-enforcer.sh"
check_hash "codex_delegation_enforcer_sha256" "hooks/codex-delegation-enforcer.sh"
check_hash "enforcer_utils_sha256" "hooks/lib/enforcer-utils.sh"
check_hash "sidekick_registry_sha256" "sidekicks/registry.json"
check_hash "legacy_hooks_scrub_sha256" "hooks/scrub-legacy-user-hooks.py"
check_hash "runtime_sync_sha256" "hooks/runtime-sync.sh"
check_hash "forge_progress_surface_sha256" "hooks/forge-progress-surface.sh"
check_hash "codex_progress_surface_sha256" "hooks/codex-progress-surface.sh"
check_hash "validate_release_gate_sha256" "hooks/validate-release-gate.sh"
check_hash "output_style_forge_sha256" "output-styles/forge.md"
check_hash "output_style_codex_sha256" "output-styles/codex.md"
check_hash "forge_stop_skill_md_sha256" "skills/forge-stop/SKILL.md"
check_hash "codex_stop_skill_md_sha256" "skills/codex-stop/SKILL.md"

# Removed-skill surface must stay removed.
echo "=== Removed skill surface ==="
if [ ! -f "${PLUGIN_DIR}/skills/codex/SKILL.md" ] \
  && [ ! -f "${PLUGIN_DIR}/skills/codex.md" ] \
  && [ ! -f "${PLUGIN_DIR}/skills/codex-history/SKILL.md" ] \
  && [ ! -f "${PLUGIN_DIR}/skills/forge-history/SKILL.md" ]; then
  assert_pass "removed Codex/Forge history skill files are absent"
else
  assert_fail "removed skill surface" "one or more removed skill files still present"
fi

# Cross-check Codex installer source between manifest and registry.
echo "=== Registry cross-checks ==="
CLAIMED_CODEX_INSTALL="$(claim codex_installer_sha256)"
REGISTRY_KAY_URL="$(python3 -c "import json; d=json.load(open('${PLUGIN_DIR}/sidekicks/registry.json')); print(d['kay']['install']['url'])")"
REGISTRY_KAY_VERSION="$(python3 -c "import json; d=json.load(open('${PLUGIN_DIR}/sidekicks/registry.json')); print(d['kay']['install']['version'])")"
REGISTRY_KAY_SHA="$(python3 -c "import json; d=json.load(open('${PLUGIN_DIR}/sidekicks/registry.json')); print(d['kay']['install']['sha256'])")"
if [ "${REGISTRY_KAY_URL}" = "https://raw.githubusercontent.com/alo-labs/kay/v0.7.2/scripts/install/install.sh" ] \
  && [ "${REGISTRY_KAY_VERSION}" = "v0.7.2" ] \
  && [ "${REGISTRY_KAY_SHA}" = "a08e754c5a532f7786340af9f0b21a72ff9cccb6d5c5ffa03c19553c0e7a31cc" ] \
  && [ "${CLAIMED_CODEX_INSTALL}" = "a08e754c5a532f7786340af9f0b21a72ff9cccb6d5c5ffa03c19553c0e7a31cc" ]; then
  assert_pass "kay installer points at the pinned Kay v0.7.2 release and checksum"
else
  assert_fail "kay installer source" "url=${REGISTRY_KAY_URL} version=${REGISTRY_KAY_VERSION} registry_sha=${REGISTRY_KAY_SHA} manifest_sha=${CLAIMED_CODEX_INSTALL}"
fi

# install.sh pinned forge installer hash must match manifest.
INSTALL_PINNED="$(grep 'EXPECTED_FORGE_SHA=' "${PLUGIN_DIR}/install.sh" | grep -v '^#' | sed 's/.*="\(.*\)"/\1/' | head -n 1)"
CLAIMED_FORGECODE="$(claim forgecode_installer_sha256)"
if [ "${INSTALL_PINNED}" = "${CLAIMED_FORGECODE}" ]; then
  assert_pass "install.sh EXPECTED_FORGE_SHA matches manifest forgecode_installer_sha256"
else
  assert_fail "forge installer hash pin" "install.sh=${INSTALL_PINNED} manifest=${CLAIMED_FORGECODE}"
fi

# Verify plugin version major/minor expectation.
PLUGIN_VERSION="$(python3 -c "import json; d=json.load(open('${MANIFEST}')); print(d.get('version',''))")"
case "${PLUGIN_VERSION}" in
  0.5.*) assert_pass "plugin.json version is 0.5.x (${PLUGIN_VERSION})" ;;
  *)     assert_fail "plugin.json version" "expected 0.5.x, got ${PLUGIN_VERSION}" ;;
esac

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

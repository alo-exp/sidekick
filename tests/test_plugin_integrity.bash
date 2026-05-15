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
  if git -C "${PLUGIN_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git -C "${PLUGIN_DIR}" ls-files --error-unmatch "${rel_path}" >/dev/null 2>&1; then
      assert_pass "${rel_path} is tracked by git"
    else
      assert_fail "integrity file ${rel_path}" "exists on disk but is not tracked by git"
    fi
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
check_hash "sidekick_registry_lib_sha256" "hooks/lib/sidekick-registry.sh"
check_hash "safe_runner_sha256" "hooks/lib/sidekick-safe-runner.sh"
check_hash "sidekick_registry_sha256" "sidekicks/registry.json"
check_hash "legacy_hooks_scrub_sha256" "hooks/scrub-legacy-user-hooks.py"
check_hash "forge_progress_surface_sha256" "hooks/forge-progress-surface.sh"
check_hash "codex_progress_surface_sha256" "hooks/codex-progress-surface.sh"
check_hash "validate_release_gate_sha256" "hooks/validate-release-gate.sh"
check_hash "output_style_forge_sha256" "output-styles/forge.md"
check_hash "output_style_codex_sha256" "output-styles/codex.md"
check_hash "forge_delegate_alias_skill_md_sha256" "skills/forge:delegate/SKILL.md"
check_hash "kay_delegate_alias_skill_md_sha256" "skills/kay:delegate/SKILL.md"
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
if [ "${REGISTRY_KAY_URL}" = "https://raw.githubusercontent.com/alo-labs/kay/v0.9.4/scripts/install/install.sh" ] \
  && [ "${REGISTRY_KAY_VERSION}" = "v0.9.4" ] \
  && [ "${REGISTRY_KAY_SHA}" = "a2b6cba30bb41eec0d920f051796fad5841de6612e0be34eefeeab64efd94555" ] \
  && [ "${CLAIMED_CODEX_INSTALL}" = "a2b6cba30bb41eec0d920f051796fad5841de6612e0be34eefeeab64efd94555" ]; then
  assert_pass "kay installer points at the pinned Kay installer with kay primary binary support"
else
  assert_fail "kay installer source" "url=${REGISTRY_KAY_URL} version=${REGISTRY_KAY_VERSION} registry_sha=${REGISTRY_KAY_SHA} manifest_sha=${CLAIMED_CODEX_INSTALL}"
fi

if grep -q '^user-invocable: false' "${PLUGIN_DIR}/skills/forge.md"; then
  assert_pass "legacy flat Forge skill is hidden from public invocation"
else
  assert_fail "legacy flat Forge skill visibility" "skills/forge.md must remain user-invocable: false"
fi

# install.sh pinned forge installer hash must match manifest.
INSTALL_PINNED="$(grep 'EXPECTED_FORGE_SHA=' "${PLUGIN_DIR}/install.sh" | grep -v '^#' | sed 's/.*="\(.*\)"/\1/' | head -n 1)"
CLAIMED_FORGECODE="$(claim forgecode_installer_sha256)"
if [ "${INSTALL_PINNED}" = "${CLAIMED_FORGECODE}" ]; then
  assert_pass "install.sh EXPECTED_FORGE_SHA matches manifest forgecode_installer_sha256"
else
  assert_fail "forge installer hash pin" "install.sh=${INSTALL_PINNED} manifest=${CLAIMED_FORGECODE}"
fi

if [ "${SIDEKICK_VERIFY_REMOTE_INSTALLERS:-0}" = "1" ]; then
  REGISTRY_FORGE_URL="$(python3 -c "import json; d=json.load(open('${PLUGIN_DIR}/sidekicks/registry.json')); print(d['forge']['install']['url'])")"
  REGISTRY_FORGE_SHA="$(python3 -c "import json; d=json.load(open('${PLUGIN_DIR}/sidekicks/registry.json')); print(d['forge']['install']['sha256'])")"
  REMOTE_FORGE_TMP="$(mktemp "${TMPDIR:-/tmp}/sidekick-forge-installer.XXXXXX")"
  if curl -fsSL --max-time 60 --connect-timeout 15 "${REGISTRY_FORGE_URL}" -o "${REMOTE_FORGE_TMP}"; then
    if command -v shasum >/dev/null 2>&1; then
      REMOTE_FORGE_SHA="$(shasum -a 256 "${REMOTE_FORGE_TMP}" | awk '{print $1}')"
    else
      REMOTE_FORGE_SHA="$(sha256sum "${REMOTE_FORGE_TMP}" | awk '{print $1}')"
    fi
    if [ "${REMOTE_FORGE_SHA}" = "${REGISTRY_FORGE_SHA}" ] && [ "${REMOTE_FORGE_SHA}" = "${CLAIMED_FORGECODE}" ]; then
      assert_pass "remote Forge installer hash matches registry and manifest"
    else
      assert_fail "remote Forge installer hash" "remote=${REMOTE_FORGE_SHA} registry=${REGISTRY_FORGE_SHA} manifest=${CLAIMED_FORGECODE}"
    fi
  else
    assert_fail "remote Forge installer fetch" "could not fetch ${REGISTRY_FORGE_URL}"
  fi
  rm -f "${REMOTE_FORGE_TMP}"
else
  echo "SKIP remote Forge installer hash check (set SIDEKICK_VERIFY_REMOTE_INSTALLERS=1)"
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

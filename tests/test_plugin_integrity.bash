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
check_hash "kay_delegate_skill_md_sha256" "skills/kay-delegate/SKILL.md"
check_hash "kay_stop_skill_md_sha256" "skills/kay-stop/SKILL.md"
check_hash "codex_delegate_skill_md_sha256" "skills/codex-delegate/SKILL.md"
check_hash "codex_delegate_md_sha256" "skills/codex-delegate.md"
check_hash "claude_kay_delegate_skill_md_sha256" "agents/claude/kay-delegate/SKILL.md"
check_hash "claude_kay_stop_skill_md_sha256" "agents/claude/kay-stop/SKILL.md"
check_hash "claude_codex_delegate_skill_md_sha256" "agents/claude/codex-delegate/SKILL.md"
check_hash "claude_codex_delegate_md_sha256" "agents/claude/codex-delegate.md"
check_hash "claude_codex_stop_skill_md_sha256" "agents/claude/codex-stop/SKILL.md"
check_hash "codex_kay_delegate_skill_md_sha256" "agents/codex/kay-delegate/SKILL.md"
check_hash "codex_kay_stop_skill_md_sha256" "agents/codex/kay-stop/SKILL.md"
check_hash "codex_codex_delegate_skill_md_sha256" "agents/codex/codex-delegate/SKILL.md"
check_hash "codex_codex_delegate_md_sha256" "agents/codex/codex-delegate.md"
check_hash "codex_codex_stop_skill_md_sha256" "agents/codex/codex-stop/SKILL.md"
check_hash "render_agent_bundle_sha256" "scripts/render-agent-bundle.py"
check_hash "sync_host_surfaces_sha256" "scripts/sync-host-surfaces.sh"
check_hash "hooks_json_sha256" "hooks/hooks.json"
check_hash "codex_delegation_enforcer_sha256" "hooks/codex-delegation-enforcer.sh"
check_hash "enforcer_utils_sha256" "hooks/lib/enforcer-utils.sh"
check_hash "sidekick_registry_lib_sha256" "hooks/lib/sidekick-registry.sh"
check_hash "safe_runner_sha256" "hooks/lib/sidekick-safe-runner.sh"
check_hash "sidekick_registry_sha256" "sidekicks/registry.json"
check_hash "legacy_hooks_scrub_sha256" "hooks/scrub-legacy-user-hooks.py"
check_hash "codex_progress_surface_sha256" "hooks/codex-progress-surface.sh"
check_hash "output_style_kay_sha256" "output-styles/kay.md"
check_hash "output_style_codex_sha256" "output-styles/codex.md"
check_hash "codex_stop_skill_md_sha256" "skills/codex-stop/SKILL.md"

# Removed-skill surface must stay removed.
echo "=== Removed skill surface ==="
if [ ! -f "${PLUGIN_DIR}/skills/codex/SKILL.md" ] \
  && [ ! -f "${PLUGIN_DIR}/skills/codex.md" ] \
  && [ ! -f "${PLUGIN_DIR}/skills/codex-history/SKILL.md" ] \
  && [ ! -f "${PLUGIN_DIR}/skills/kay:delegate/SKILL.md" ] \
  && [ ! -f "${PLUGIN_DIR}/agents/claude/kay:delegate/SKILL.md" ] \
  && [ ! -f "${PLUGIN_DIR}/agents/codex/kay:delegate/SKILL.md" ]; then
  assert_pass "removed Codex history and redundant Kay alias skill files are absent"
else
  assert_fail "removed skill surface" "one or more removed skill files still present"
fi

# Cross-check Codex installer source between manifest and registry.
echo "=== Registry cross-checks ==="
CLAIMED_CODEX_INSTALL="$(claim codex_installer_sha256)"
REGISTRY_KAY_URL="$(python3 -c "import json; d=json.load(open('${PLUGIN_DIR}/sidekicks/registry.json')); print(d['kay']['install']['url'])")"
REGISTRY_KAY_VERSION="$(python3 -c "import json; d=json.load(open('${PLUGIN_DIR}/sidekicks/registry.json')); print(d['kay']['install']['version'])")"
REGISTRY_KAY_SHA="$(python3 -c "import json; d=json.load(open('${PLUGIN_DIR}/sidekicks/registry.json')); print(d['kay']['install']['sha256'])")"
if [ "${REGISTRY_KAY_URL}" = "https://raw.githubusercontent.com/alo-labs/kay/v0.9.17/scripts/install/install.sh" ] \
  && [ "${REGISTRY_KAY_VERSION}" = "v0.9.17" ] \
  && [ "${REGISTRY_KAY_SHA}" = "a2b6cba30bb41eec0d920f051796fad5841de6612e0be34eefeeab64efd94555" ] \
  && [ "${CLAIMED_CODEX_INSTALL}" = "a2b6cba30bb41eec0d920f051796fad5841de6612e0be34eefeeab64efd94555" ]; then
  assert_pass "kay installer points at the pinned Kay installer with kay primary binary support"
else
  assert_fail "kay installer source" "url=${REGISTRY_KAY_URL} version=${REGISTRY_KAY_VERSION} registry_sha=${REGISTRY_KAY_SHA} manifest_sha=${CLAIMED_CODEX_INSTALL}"
fi

if ! python3 -c "import json, pathlib; d=json.load(open('${MANIFEST}')); blob=json.dumps(d).lower(); assert 'forge' not in blob and 'forgecode' not in blob"; then
  assert_fail "manifest removal check" "Forge metadata remains in plugin manifest"
else
  assert_pass "plugin manifest has no removed sidekick metadata"
fi

# Verify plugin version remains on the pre-1.0 release line.
PLUGIN_VERSION="$(python3 -c "import json; d=json.load(open('${MANIFEST}')); print(d.get('version',''))")"
case "${PLUGIN_VERSION}" in
  0.[0-9]*.[0-9]*) assert_pass "plugin.json version is pre-1.0 semver (${PLUGIN_VERSION})" ;;
  *)                assert_fail "plugin.json version" "expected 0.x.y, got ${PLUGIN_VERSION}" ;;
esac

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

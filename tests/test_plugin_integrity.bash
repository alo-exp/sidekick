#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Integrity & Manifest Tests
# Verifies plugin.json _integrity hashes match actual files on disk.
# Usage: bash tests/test_plugin_integrity.bash
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

sha256() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

MANIFEST="${PLUGIN_DIR}/.claude-plugin/plugin.json"

echo "=== Manifest integrity verification ==="

# Load claimed hashes from plugin.json
CLAIMED_INSTALL=$(python3 -c "import json; d=json.load(open('${MANIFEST}')); print(d['_integrity']['install_sh_sha256'])")
CLAIMED_FORGE=$(python3 -c "import json; d=json.load(open('${MANIFEST}')); print(d['_integrity']['forge_md_sha256'])")
CLAIMED_HOOKS=$(python3 -c "import json; d=json.load(open('${MANIFEST}')); print(d['_integrity']['hooks_json_sha256'])")
CLAIMED_FORGECODE=$(python3 -c "import json; d=json.load(open('${MANIFEST}')); print(d['_integrity']['forgecode_installer_sha256'])")

echo "Claimed install.sh SHA:  ${CLAIMED_INSTALL}"
echo "Claimed forge.md SHA:    ${CLAIMED_FORGE}"
echo "Claimed hooks.json SHA:  ${CLAIMED_HOOKS}"
echo "Claimed forgecode SHA:   ${CLAIMED_FORGECODE}"
echo ""

# Compute actual hashes
ACTUAL_INSTALL=$(sha256 "${PLUGIN_DIR}/install.sh")
ACTUAL_FORGE=$(sha256 "${PLUGIN_DIR}/skills/forge.md")
ACTUAL_HOOKS=$(sha256 "${PLUGIN_DIR}/hooks/hooks.json")

echo "Actual install.sh SHA:   ${ACTUAL_INSTALL}"
echo "Actual forge.md SHA:     ${ACTUAL_FORGE}"
echo "Actual hooks.json SHA:   ${ACTUAL_HOOKS}"
echo ""

# Compare
[ "${CLAIMED_INSTALL}" = "${ACTUAL_INSTALL}" ] && \
  assert_pass "install.sh hash matches manifest" || \
  assert_fail "install.sh hash" "claimed=${CLAIMED_INSTALL} actual=${ACTUAL_INSTALL}"

[ "${CLAIMED_FORGE}" = "${ACTUAL_FORGE}" ] && \
  assert_pass "forge.md hash matches manifest" || \
  assert_fail "forge.md hash" "claimed=${CLAIMED_FORGE} actual=${ACTUAL_FORGE}"

[ "${CLAIMED_HOOKS}" = "${ACTUAL_HOOKS}" ] && \
  assert_pass "hooks.json hash matches manifest" || \
  assert_fail "hooks.json hash" "claimed=${CLAIMED_HOOKS} actual=${ACTUAL_HOOKS}"

# Verify install.sh EXPECTED_FORGE_SHA matches manifest
INSTALL_PINNED=$(grep 'EXPECTED_FORGE_SHA=' "${PLUGIN_DIR}/install.sh" | grep -v '^#' | sed 's/.*="\(.*\)"/\1/')
[ "${INSTALL_PINNED}" = "${CLAIMED_FORGECODE}" ] && \
  assert_pass "install.sh EXPECTED_FORGE_SHA matches manifest forgecode_installer_sha256" || \
  assert_fail "SHA cross-reference" "install.sh=${INSTALL_PINNED} manifest=${CLAIMED_FORGECODE}"

# Verify all three forge.md install blocks agree on the pinned hash
FORGE_HASHES=$(grep 'EXPECTED_FORGE_SHA=' "${PLUGIN_DIR}/skills/forge.md" | grep -v '^#' | sed 's/.*="\(.*\)"/\1/' | sort -u)
COUNT=$(echo "${FORGE_HASHES}" | wc -l | tr -d ' ')
UNIQUE_HASH=$(echo "${FORGE_HASHES}" | head -1)
if [ "${COUNT}" -eq 1 ] && [ "${UNIQUE_HASH}" = "${CLAIMED_FORGECODE}" ]; then
  assert_pass "All forge.md install blocks agree on pinned hash (${COUNT} occurrences, all ${UNIQUE_HASH:0:16}…)"
else
  assert_fail "forge.md hash consistency" "found ${COUNT} distinct hashes or mismatch with manifest: ${FORGE_HASHES}"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

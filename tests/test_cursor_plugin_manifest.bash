#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — .cursor-plugin/plugin.json packaging tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
CLAUDE_MANIFEST="${PLUGIN_DIR}/.claude-plugin/plugin.json"
CURSOR_MANIFEST="${PLUGIN_DIR}/.cursor-plugin/plugin.json"
CURSOR_MARKETPLACE="${PLUGIN_DIR}/.cursor-plugin/marketplace.json"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

[ -f "${CURSOR_MANIFEST}" ] || { echo "ERROR: ${CURSOR_MANIFEST} missing"; exit 1; }
[ -f "${CLAUDE_MANIFEST}" ] || { echo "ERROR: ${CLAUDE_MANIFEST} missing"; exit 1; }

echo "=== manifest_version_matches_claude ==="
CLAUDE_VERSION="$(python3 -c "import json; print(json.load(open('${CLAUDE_MANIFEST}'))['version'])")"
CURSOR_VERSION="$(python3 -c "import json; print(json.load(open('${CURSOR_MANIFEST}'))['version'])")"
if [ "${CLAUDE_VERSION}" = "${CURSOR_VERSION}" ]; then
  assert_pass "Cursor manifest version matches Claude manifest (${CURSOR_VERSION})"
else
  assert_fail "manifest version" "claude=${CLAUDE_VERSION} cursor=${CURSOR_VERSION}"
fi

echo "=== marketplace_version_matches_manifest ==="
CURSOR_MARKETPLACE_VERSION="$(python3 -c "import json; data=json.load(open('${CURSOR_MARKETPLACE}')); print(next(plugin['version'] for plugin in data['plugins'] if plugin['name'] == 'sidekick'))")"
if [ "${CURSOR_MARKETPLACE_VERSION}" = "${CURSOR_VERSION}" ]; then
  assert_pass "Cursor marketplace version matches plugin manifest (${CURSOR_MARKETPLACE_VERSION})"
else
  assert_fail "marketplace version" "marketplace=${CURSOR_MARKETPLACE_VERSION} manifest=${CURSOR_VERSION}"
fi

echo "=== manifest_core_fields ==="
if python3 - "${CURSOR_MANIFEST}" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
assert data["name"] == "sidekick"
assert data["skills"] == "agents/cursor/"
assert data["hooks"] == "hooks/cursor-hooks.json"
assert "outputStyles" not in data
assert "_integrity" not in data
assert "cursor" in data["description"].lower()
PY
then
  assert_pass "Cursor manifest points at generated skills and cursor-hooks.json"
else
  assert_fail "manifest core fields" "missing expected Cursor manifest data"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

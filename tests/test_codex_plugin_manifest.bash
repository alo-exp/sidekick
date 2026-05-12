#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — .codex-plugin/plugin.json packaging tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
CLAUDE_MANIFEST="${PLUGIN_DIR}/.claude-plugin/plugin.json"
CLAUDE_MARKETPLACE="${PLUGIN_DIR}/.claude-plugin/marketplace.json"
CODEX_MANIFEST="${PLUGIN_DIR}/.codex-plugin/plugin.json"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

[ -f "${CODEX_MANIFEST}" ] || { echo "ERROR: ${CODEX_MANIFEST} missing"; exit 1; }
[ -f "${CLAUDE_MANIFEST}" ] || { echo "ERROR: ${CLAUDE_MANIFEST} missing"; exit 1; }

echo "=== manifest_version_matches_claude ==="
CLAUDE_VERSION="$(python3 -c "import json; print(json.load(open('${CLAUDE_MANIFEST}'))['version'])")"
CODEX_VERSION="$(python3 -c "import json; print(json.load(open('${CODEX_MANIFEST}'))['version'])")"
if [ "${CLAUDE_VERSION}" = "${CODEX_VERSION}" ]; then
  assert_pass "Codex manifest version matches Claude manifest (${CODEX_VERSION})"
else
  assert_fail "manifest version" "claude=${CLAUDE_VERSION} codex=${CODEX_VERSION}"
fi

echo "=== marketplace_version_matches_manifest ==="
CLAUDE_MARKETPLACE_VERSION="$(python3 -c "import json; data=json.load(open('${CLAUDE_MARKETPLACE}')); print(next(plugin['version'] for plugin in data['plugins'] if plugin['name'] == 'sidekick'))")"
if [ "${CLAUDE_MARKETPLACE_VERSION}" = "${CODEX_VERSION}" ]; then
  assert_pass "Claude marketplace version matches plugin manifest (${CLAUDE_MARKETPLACE_VERSION})"
else
  assert_fail "marketplace version" "marketplace=${CLAUDE_MARKETPLACE_VERSION} manifest=${CODEX_VERSION}"
fi

echo "=== manifest_core_fields ==="
if python3 - "${CODEX_MANIFEST}" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
assert data["name"] == "sidekick"
assert data["skills"] == "./skills/"
assert "commands" not in data
assert data["hooks"] == "./hooks/hooks.json"
assert "outputStyles" not in data
assert data["interface"]["displayName"] == "Sidekick"
assert "Codex" in data["interface"]["shortDescription"]
PY
then
  assert_pass "Codex manifest is skills-only and keeps hook wiring registered"
else
  assert_fail "manifest core fields" "missing expected manifest data or unsupported Claude-only fields present"
fi

echo "=== claude_manifest_hooks_wired ==="
if python3 - "${CLAUDE_MANIFEST}" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
assert data["hooks"] == "./hooks/hooks.json"
PY
then
  assert_pass "Claude manifest points at the shared hooks/hooks.json bundle"
else
  assert_fail "claude manifest hooks" "Claude manifest is missing the shared hooks/hooks.json pointer"
fi

echo "=== manifest_interface_present ==="
if python3 - "${CODEX_MANIFEST}" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
interface = data["interface"]
assert interface["developerName"] == "Ālo Labs"
assert interface["category"] == "Development"
assert interface["websiteURL"] == "https://github.com/alo-exp/sidekick"
assert interface["brandColor"] == "#0F172A"
assert len(interface["defaultPrompt"]) == 3
PY
then
  assert_pass "Codex marketplace interface metadata is present"
else
  assert_fail "manifest interface" "interface metadata missing or malformed"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

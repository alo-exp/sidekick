#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Codex marketplace packaging tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIDEKICK_DIR="$(dirname "${SCRIPT_DIR}")"
MARKETPLACE_FILE="${CODEX_MARKETPLACE_FILE:-/Users/shafqat/projects/codex-plugins/.agents/plugins/marketplace.json}"
SIDEKICK_REF="$(git -C "${SIDEKICK_DIR}" rev-parse HEAD)"
SIDEKICK_VERSION="$(python3 -c "import json; print(json.load(open('${SIDEKICK_DIR}/.claude-plugin/plugin.json'))['version'])")"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

if [ ! -f "${MARKETPLACE_FILE}" ]; then
  echo -e "${green}SKIP${reset} marketplace manifest test: ${MARKETPLACE_FILE} missing"
  exit 0
fi

echo "=== marketplace_name ==="
MARKETPLACE_NAME="$(python3 - "${MARKETPLACE_FILE}" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
print(data["name"])
PY
)"
if [ "${MARKETPLACE_NAME}" = "alo-labs-codex" ]; then
  assert_pass "marketplace name is alo-labs-codex"
else
  assert_fail "marketplace name" "got ${MARKETPLACE_NAME}"
fi

echo "=== sidekick_entry_present ==="
if python3 - "${MARKETPLACE_FILE}" "${SIDEKICK_REF}" "${SIDEKICK_VERSION}" <<'PY'
import json
import sys

path = sys.argv[1]
expected_ref = sys.argv[2]
expected_version = sys.argv[3]
data = json.load(open(path))
plugins = {plugin["name"]: plugin for plugin in data["plugins"]}
sidekick = plugins["sidekick"]
assert sidekick["source"]["source"] == "url"
assert sidekick["source"]["url"] == "https://github.com/alo-exp/sidekick.git"
assert sidekick["source"]["ref"] == expected_ref
assert sidekick["version"] == expected_version
assert sidekick["policy"]["installation"] == "AVAILABLE"
assert sidekick["policy"]["authentication"] == "ON_INSTALL"
assert sidekick["category"] == "Development"
PY
then
  assert_pass "Sidekick marketplace entry is pinned to the current Sidekick commit and version"
else
  assert_fail "sidekick entry" "marketplace entry missing or not pinned to the expected ref"
fi

echo "=== marketplace_interface ==="
if python3 - "${MARKETPLACE_FILE}" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
assert data["interface"]["displayName"] == "Ālo Labs Codex Marketplace"
PY
then
  assert_pass "marketplace interface display name is present"
else
  assert_fail "marketplace interface" "display name missing"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Cursor marketplace release-gate mode regression tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT
FIXTURE_REPO="${TMP_ROOT}/repo"
mkdir -p "${FIXTURE_REPO}"

(
  cd "${ROOT}"
  COPYFILE_DISABLE=1 tar --exclude ./.git --exclude './~' --exclude './.kay' --exclude './.codex' -cf - .
) | (
  cd "${FIXTURE_REPO}"
  tar -xf -
)

git -C "${FIXTURE_REPO}" init -q
git -C "${FIXTURE_REPO}" config user.email "sidekick-tests@example.invalid"
git -C "${FIXTURE_REPO}" config user.name "Sidekick Tests"
git -C "${FIXTURE_REPO}" add .
git -C "${FIXTURE_REPO}" commit -qm "test fixture"
git -C "${FIXTURE_REPO}" tag -a "v$(python3 -c "import json; print(json.load(open('${FIXTURE_REPO}/.cursor-plugin/plugin.json'))['version'])")" -m "test tag"

FIXTURE_VERSION="$(python3 - "${FIXTURE_REPO}/.cursor-plugin/plugin.json" <<'PY'
import json
import sys

print(json.load(open(sys.argv[1]))["version"])
PY
)"
MARKETPLACE_REPO="${TMP_ROOT}/marketplace-repo"
MARKETPLACE_FILE="${MARKETPLACE_REPO}/.cursor-plugin/marketplace.json"
mkdir -p "$(dirname "${MARKETPLACE_FILE}")"
python3 - "${MARKETPLACE_FILE}" "${FIXTURE_VERSION}" <<'PY'
import json
import sys

path, version = sys.argv[1:3]
data = {
    "name": "alo-labs-cursor",
    "owner": {"name": "Ālo Labs", "email": "hello@alolabs.io"},
    "metadata": {
        "description": "Ālo Labs plugins for Cursor",
        "version": "1.0.0",
    },
    "plugins": [
        {
            "name": "sidekick",
            "source": {
                "source": "github",
                "repo": "alo-exp/sidekick",
                "ref": f"v{version}",
            },
            "description": "Sidekick test fixture",
            "version": version,
            "category": "development",
        }
    ],
}
open(path, "w", encoding="utf-8").write(json.dumps(data, indent=2) + "\n")
PY
git -C "${MARKETPLACE_REPO}" init -q
git -C "${MARKETPLACE_REPO}" config user.email "sidekick-tests@example.invalid"
git -C "${MARKETPLACE_REPO}" config user.name "Sidekick Tests"
git -C "${MARKETPLACE_REPO}" add .
git -C "${MARKETPLACE_REPO}" commit -qm "test marketplace fixture"

echo "=== T1: release mode passes with clean committed fixture ==="
if CURSOR_MARKETPLACE_FILE="${MARKETPLACE_FILE}" SIDEKICK_RELEASE_GATE=1 bash "${FIXTURE_REPO}/tests/test_cursor_marketplace_manifest.bash" >/tmp/sidekick-cursor-marketplace-clean.out 2>&1; then
  assert_pass "release-mode Cursor marketplace check passes on clean pinned fixture"
else
  assert_fail "release-mode Cursor marketplace check clean fixture" "$(cat /tmp/sidekick-cursor-marketplace-clean.out)"
fi

echo "=== T2: release mode fails when marketplace file is missing ==="
if CURSOR_MARKETPLACE_FILE="${TMP_ROOT}/missing-marketplace.json" SIDEKICK_RELEASE_GATE=1 bash "${FIXTURE_REPO}/tests/test_cursor_marketplace_manifest.bash" >/tmp/sidekick-cursor-marketplace-missing.out 2>&1; then
  assert_fail "release-mode Cursor marketplace check missing fixture" "expected failure but test passed"
else
  assert_pass "release-mode Cursor marketplace check fails when marketplace file is missing"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

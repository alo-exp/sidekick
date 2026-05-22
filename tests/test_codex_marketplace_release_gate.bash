#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Codex marketplace release-gate mode regression tests
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
  COPYFILE_DISABLE=1 tar --exclude ./.git --exclude './~' -cf - .
) | (
  cd "${FIXTURE_REPO}"
  tar -xf -
)

git -C "${FIXTURE_REPO}" init -q
git -C "${FIXTURE_REPO}" config user.email "sidekick-tests@example.invalid"
git -C "${FIXTURE_REPO}" config user.name "Sidekick Tests"
git -C "${FIXTURE_REPO}" add .
git -C "${FIXTURE_REPO}" commit -qm "test fixture"

FIXTURE_REF="$(git -C "${FIXTURE_REPO}" rev-parse HEAD)"
FIXTURE_VERSION="$(python3 - "${FIXTURE_REPO}/.codex-plugin/plugin.json" <<'PY'
import json
import sys

print(json.load(open(sys.argv[1]))["version"])
PY
)"
MARKETPLACE_REPO="${TMP_ROOT}/marketplace-repo"
MARKETPLACE_FILE="${MARKETPLACE_REPO}/.agents/plugins/marketplace.json"
mkdir -p "$(dirname "${MARKETPLACE_FILE}")"
python3 - "${MARKETPLACE_FILE}" "${FIXTURE_REF}" "${FIXTURE_VERSION}" <<'PY'
import json
import sys

path, ref, version = sys.argv[1:4]
data = {
    "name": "alo-labs-codex",
    "interface": {"displayName": "Ālo Labs Codex Marketplace"},
    "plugins": [
        {
            "name": "sidekick",
            "source": {
                "source": "url",
                "url": "https://github.com/alo-exp/sidekick.git",
                "ref": ref,
            },
            "version": version,
            "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"},
            "category": "Development",
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
if CODEX_MARKETPLACE_FILE="${MARKETPLACE_FILE}" SIDEKICK_RELEASE_GATE=1 bash "${FIXTURE_REPO}/tests/test_codex_marketplace_manifest.bash" >/tmp/sidekick-marketplace-clean.out 2>&1; then
  assert_pass "release-mode marketplace check passes on clean pinned fixture"
else
  assert_fail "release-mode marketplace check clean fixture" "$(cat /tmp/sidekick-marketplace-clean.out)"
fi

echo "=== T2: release mode fails closed when marketplace file is missing ==="
if CODEX_MARKETPLACE_FILE="${TMP_ROOT}/missing-marketplace.json" SIDEKICK_RELEASE_GATE=1 bash "${FIXTURE_REPO}/tests/test_codex_marketplace_manifest.bash" >/tmp/sidekick-marketplace-missing.out 2>&1; then
  assert_fail "missing marketplace release gate" "missing marketplace unexpectedly passed"
elif grep -Fq "marketplace manifest present" /tmp/sidekick-marketplace-missing.out; then
  assert_pass "missing marketplace release gate fails closed"
else
  assert_fail "missing marketplace release gate" "$(cat /tmp/sidekick-marketplace-missing.out)"
fi

echo "=== T3: release mode fails when fixture repo is dirty ==="
printf '\n# dirty release fixture\n' >> "${FIXTURE_REPO}/README.md"
if CODEX_MARKETPLACE_FILE="${MARKETPLACE_FILE}" SIDEKICK_RELEASE_GATE=1 bash "${FIXTURE_REPO}/tests/test_codex_marketplace_manifest.bash" >/tmp/sidekick-marketplace-dirty.out 2>&1; then
  assert_fail "dirty marketplace release gate" "dirty fixture unexpectedly passed"
elif grep -Fq "release metadata clean" /tmp/sidekick-marketplace-dirty.out; then
  assert_pass "dirty marketplace release gate fails closed"
else
  assert_fail "dirty marketplace release gate" "$(cat /tmp/sidekick-marketplace-dirty.out)"
fi

echo "=== T4: release mode fails when marketplace file is dirty ==="
git -C "${FIXTURE_REPO}" checkout -- README.md
python3 - "${MARKETPLACE_FILE}" <<'PY'
import json
import sys

path = sys.argv[1]
data = json.load(open(path))
data["plugins"][0]["version"] = data["plugins"][0]["version"] + "-dirty"
open(path, "w", encoding="utf-8").write(json.dumps(data, indent=2) + "\n")
PY
if CODEX_MARKETPLACE_FILE="${MARKETPLACE_FILE}" SIDEKICK_RELEASE_GATE=1 bash "${FIXTURE_REPO}/tests/test_codex_marketplace_manifest.bash" >/tmp/sidekick-marketplace-dirty-file.out 2>&1; then
  assert_fail "dirty marketplace file release gate" "dirty marketplace file unexpectedly passed"
elif grep -Fq "marketplace metadata clean" /tmp/sidekick-marketplace-dirty-file.out; then
  assert_pass "dirty marketplace file release gate fails closed"
else
  assert_fail "dirty marketplace file release gate" "$(cat /tmp/sidekick-marketplace-dirty-file.out)"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

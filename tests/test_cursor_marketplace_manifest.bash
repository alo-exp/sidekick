#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Cursor marketplace packaging tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIDEKICK_DIR="$(dirname "${SCRIPT_DIR}")"
HOST_MARKETPLACE_HOME="${SIDEKICK_HOST_HOME:-${HOME}}"
DEFAULT_MARKETPLACE_CANDIDATES=(
  "${HOST_MARKETPLACE_HOME}/.cursor/plugins/marketplaces/alo-labs-cursor/.cursor-plugin/marketplace.json"
  "${HOST_MARKETPLACE_HOME}/projects/alo-labs-cursor-marketplace/.cursor-plugin/marketplace.json"
)
MARKETPLACE_FILE="${CURSOR_MARKETPLACE_FILE:-}"
CHECK_EXTERNAL_MARKETPLACE=0
if [ -n "${MARKETPLACE_FILE}" ]; then
  CHECK_EXTERNAL_MARKETPLACE=1
elif [ "${SIDEKICK_RELEASE_GATE:-0}" = "1" ]; then
  for candidate in "${DEFAULT_MARKETPLACE_CANDIDATES[@]}"; do
    if [ -f "${candidate}" ]; then
      MARKETPLACE_FILE="${candidate}"
      break
    fi
  done
  CHECK_EXTERNAL_MARKETPLACE=1
fi

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

if [ "${CHECK_EXTERNAL_MARKETPLACE}" -ne 1 ]; then
  echo -e "${green}SKIP${reset} external Cursor marketplace pin test (set CURSOR_MARKETPLACE_FILE or SIDEKICK_RELEASE_GATE=1)"
  exit 0
fi

if [ ! -f "${MARKETPLACE_FILE}" ]; then
  if [ "${SIDEKICK_RELEASE_GATE:-0}" = "1" ]; then
    assert_fail "marketplace manifest present" "${MARKETPLACE_FILE:-<none>} missing in release-gate mode"
    echo ""
    echo "======================================="
    echo "Results: ${PASS} passed, ${FAIL} failed"
    echo "======================================="
    exit 1
  else
    echo -e "${green}SKIP${reset} marketplace manifest test: ${MARKETPLACE_FILE:-<none>} missing"
    exit 0
  fi
fi

echo "=== release_metadata_clean ==="
if [ "${SIDEKICK_RELEASE_GATE:-0}" = "1" ]; then
  if ! DIRTY_RELEASE_FILES="$(git -C "${SIDEKICK_DIR}" status --porcelain 2>&1)"; then
    assert_fail "release metadata clean" "git status failed:\n${DIRTY_RELEASE_FILES}"
  else
    DIRTY_RELEASE_FILES="$(
      printf '%s\n' "${DIRTY_RELEASE_FILES}" \
        | awk '$0 !~ /^\?\? \.kay(\/|$)/ { print }' \
        | sed -n '1,20p'
    )"
    if [ -z "${DIRTY_RELEASE_FILES}" ]; then
      assert_pass "release metadata and package surfaces are committed before release gate"
    else
      assert_fail "release metadata clean" "dirty files:\n${DIRTY_RELEASE_FILES}"
    fi
  fi
else
  echo "SKIP release metadata clean check (set SIDEKICK_RELEASE_GATE=1)"
fi

echo "=== marketplace_metadata_clean ==="
if [ "${SIDEKICK_RELEASE_GATE:-0}" = "1" ]; then
  MARKETPLACE_REPO="$(git -C "$(dirname "${MARKETPLACE_FILE}")" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -z "${MARKETPLACE_REPO}" ]; then
    assert_fail "marketplace metadata clean" "${MARKETPLACE_FILE} is not inside a git repo"
  elif ! DIRTY_MARKETPLACE_FILES="$(git -C "${MARKETPLACE_REPO}" status --porcelain -- "${MARKETPLACE_FILE}" 2>&1 | sed -n '1,20p')"; then
    assert_fail "marketplace metadata clean" "git status failed:\n${DIRTY_MARKETPLACE_FILES}"
  elif [ -z "${DIRTY_MARKETPLACE_FILES}" ]; then
    assert_pass "marketplace metadata file is committed before release gate"
  else
    assert_fail "marketplace metadata clean" "dirty marketplace file:\n${DIRTY_MARKETPLACE_FILES}"
  fi
else
  echo "SKIP marketplace metadata clean check (set SIDEKICK_RELEASE_GATE=1)"
fi

SIDEKICK_VERSION="$(python3 - "${SIDEKICK_DIR}/.cursor-plugin/plugin.json" <<'PY'
import json
import sys

print(json.load(open(sys.argv[1]))["version"])
PY
)"
SIDEKICK_TAG="v${SIDEKICK_VERSION}"

echo "=== marketplace_name ==="
MARKETPLACE_NAME="$(python3 - "${MARKETPLACE_FILE}" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
print(data["name"])
PY
)"
case "${MARKETPLACE_NAME}" in
  alo-labs-cursor)
    assert_pass "marketplace name is alo-labs-cursor"
    ;;
  *)
    assert_fail "marketplace name" "got ${MARKETPLACE_NAME}"
    ;;
esac

echo "=== sidekick_entry_present ==="
if python3 - "${MARKETPLACE_FILE}" "${SIDEKICK_VERSION}" "${SIDEKICK_TAG}" <<'PY'
import json
import sys

path = sys.argv[1]
expected_version = sys.argv[2]
expected_tag = sys.argv[3]
data = json.load(open(path))
plugins = {plugin["name"]: plugin for plugin in data["plugins"]}
sidekick = plugins["sidekick"]
assert sidekick["source"]["source"] == "github"
assert sidekick["source"]["repo"] == "alo-exp/sidekick"
assert sidekick["source"]["ref"] == expected_tag
assert sidekick["version"] == expected_version
assert sidekick.get("category", "").lower() == "development"
PY
then
  assert_pass "Sidekick Cursor marketplace entry is pinned to the current version tag"
else
  assert_fail "sidekick entry" "marketplace entry missing or not pinned to the expected ref"
fi

echo "=== sidekick_tag_content ==="
MARKETPLACE_REF="$(python3 - "${MARKETPLACE_FILE}" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
plugins = {plugin["name"]: plugin for plugin in data["plugins"]}
print(plugins["sidekick"]["source"]["ref"])
PY
)"
MARKETPLACE_VERSION="$(python3 - "${MARKETPLACE_FILE}" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
plugins = {plugin["name"]: plugin for plugin in data["plugins"]}
print(plugins["sidekick"]["version"])
PY
)"
if ! git -C "${SIDEKICK_DIR}" rev-parse --verify "${MARKETPLACE_REF}^{commit}" >/dev/null 2>&1; then
  echo "SKIP sidekick tag content (ref ${MARKETPLACE_REF} not available in local Sidekick checkout)"
else
  REF_VERSION="$(git -C "${SIDEKICK_DIR}" show "${MARKETPLACE_REF}:.cursor-plugin/plugin.json" | python3 -c 'import json, sys; print(json.load(sys.stdin)["version"])' 2>/dev/null || true)"
  if [ "${REF_VERSION}" = "${MARKETPLACE_VERSION}" ]; then
    assert_pass "Sidekick marketplace ref content version matches the advertised version"
  else
    assert_fail "sidekick tag content" "ref=${MARKETPLACE_REF} advertises=${MARKETPLACE_VERSION} contains=${REF_VERSION:-unreadable}"
  fi
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — post-release cleanup tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_SCRIPT="${SCRIPT_DIR}/post_release_cleanup.bash"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

echo "=== T1: Syntax check ==="
if bash -n "${CLEANUP_SCRIPT}" 2>&1; then
  assert_pass "post_release_cleanup.bash has no syntax errors"
else
  assert_fail "Syntax check" "bash -n failed"
fi

echo "=== T2: Cleanup semantics ==="
SANDBOX="$(mktemp -d)"
trap 'rm -rf "${SANDBOX}"' EXIT
cleanup_dirs=(.tmp .cache target build dist coverage .pytest_cache node_modules '~')
preserve_dirs=(.planning site/specs site/design)
git -C "${SANDBOX}" init -q
mkdir -p "${SANDBOX}/.claude-plugin" "${SANDBOX}/tests" "${SANDBOX}/skills/forge" "${SANDBOX}/hooks"
printf '{"name":"sidekick"}\n' > "${SANDBOX}/.claude-plugin/plugin.json"
touch "${SANDBOX}/tests/post_release_cleanup.bash" "${SANDBOX}/skills/forge/SKILL.md" "${SANDBOX}/hooks/hooks.json"
for dir in "${cleanup_dirs[@]}"; do
  mkdir -p "${SANDBOX}/${dir}"
done
for dir in "${preserve_dirs[@]}"; do
  mkdir -p "${SANDBOX}/${dir}"
done
mkdir -p "${SANDBOX}/keep"
touch "${SANDBOX}/keep/keep.txt"

OUTPUT="$(SIDEKICK_REPO_ROOT="${SANDBOX}" bash "${CLEANUP_SCRIPT}")"

for dir in "${cleanup_dirs[@]}"; do
  if [ ! -e "${SANDBOX}/${dir}" ]; then
    assert_pass "Cleanup removed ${dir}"
  else
    assert_fail "Cleanup removed ${dir}" "directory still present"
  fi
done

if [ -f "${SANDBOX}/keep/keep.txt" ]; then
  assert_pass "Cleanup leaves non-transient files alone"
else
  assert_fail "Non-transient files" "keep file was removed"
fi

if [ -d "${HOME}" ]; then
  assert_pass "Cleanup sandbox did not target real HOME"
else
  assert_fail "Cleanup sandbox real HOME" "real HOME is not accessible after cleanup"
fi

for dir in "${preserve_dirs[@]}"; do
  if [ -d "${SANDBOX}/${dir}" ]; then
    assert_pass "Cleanup preserves ${dir}"
  else
    assert_fail "Cleanup preserves ${dir}" "directory was removed"
  fi
done

if echo "${OUTPUT}" | grep -q 'post-release cleanup removed'; then
  assert_pass "Cleanup reports removed artifacts"
else
  assert_fail "Cleanup output" "missing removal summary"
fi

echo "=== T3: Idempotency ==="
SECOND_OUTPUT="$(SIDEKICK_REPO_ROOT="${SANDBOX}" bash "${CLEANUP_SCRIPT}")"
if echo "${SECOND_OUTPUT}" | grep -q 'no transient artifacts found'; then
  assert_pass "Cleanup is idempotent"
else
  assert_fail "Idempotency" "expected no-op summary on second run"
fi

echo "=== T4: Safety guards ==="
UNSAFE_ROOT="${SANDBOX}/unsafe-no-markers"
mkdir -p "${UNSAFE_ROOT}/.tmp"
if SIDEKICK_REPO_ROOT="${UNSAFE_ROOT}" bash "${CLEANUP_SCRIPT}" >/dev/null 2>&1; then
  assert_fail "Cleanup rejects roots without markers" "command succeeded"
else
  assert_pass "Cleanup rejects roots without markers"
fi
if [ -d "${UNSAFE_ROOT}/.tmp" ]; then
  assert_pass "Unsafe root artifact preserved after marker rejection"
else
  assert_fail "Unsafe root artifact preserved" "artifact was removed"
fi

MARKER_ONLY_ROOT="${SANDBOX}/marker-only-root"
mkdir -p "${MARKER_ONLY_ROOT}/.claude-plugin" "${MARKER_ONLY_ROOT}/tests" "${MARKER_ONLY_ROOT}/skills/forge" "${MARKER_ONLY_ROOT}/hooks" "${MARKER_ONLY_ROOT}/.tmp"
printf '{"name":"sidekick"}\n' > "${MARKER_ONLY_ROOT}/.claude-plugin/plugin.json"
touch "${MARKER_ONLY_ROOT}/tests/post_release_cleanup.bash" "${MARKER_ONLY_ROOT}/skills/forge/SKILL.md" "${MARKER_ONLY_ROOT}/hooks/hooks.json"
if SIDEKICK_REPO_ROOT="${MARKER_ONLY_ROOT}" bash "${CLEANUP_SCRIPT}" >/dev/null 2>&1; then
  assert_fail "Cleanup rejects marker-only roots" "command succeeded"
else
  assert_pass "Cleanup rejects marker-only roots"
fi
if [ -d "${MARKER_ONLY_ROOT}/.tmp" ]; then
  assert_pass "Marker-only root artifact preserved after rejection"
else
  assert_fail "Marker-only root artifact preserved" "artifact was removed"
fi

WRONG_NAME_ROOT="${SANDBOX}/wrong-name-root"
mkdir -p "${WRONG_NAME_ROOT}"
git -C "${WRONG_NAME_ROOT}" init -q
mkdir -p "${WRONG_NAME_ROOT}/.claude-plugin" "${WRONG_NAME_ROOT}/tests" "${WRONG_NAME_ROOT}/skills/forge" "${WRONG_NAME_ROOT}/hooks" "${WRONG_NAME_ROOT}/.tmp"
printf '{"name":"not-sidekick"}\n' > "${WRONG_NAME_ROOT}/.claude-plugin/plugin.json"
touch "${WRONG_NAME_ROOT}/tests/post_release_cleanup.bash" "${WRONG_NAME_ROOT}/skills/forge/SKILL.md" "${WRONG_NAME_ROOT}/hooks/hooks.json"
if SIDEKICK_REPO_ROOT="${WRONG_NAME_ROOT}" bash "${CLEANUP_SCRIPT}" >/dev/null 2>&1; then
  assert_fail "Cleanup rejects non-Sidekick plugin roots" "command succeeded"
else
  assert_pass "Cleanup rejects non-Sidekick plugin roots"
fi

SYMLINK_ROOT="${SANDBOX}/symlink-root"
mkdir -p "${SYMLINK_ROOT}"
git -C "${SYMLINK_ROOT}" init -q
OUTSIDE_ARTIFACT="${SANDBOX}/outside-artifact"
mkdir -p "${SYMLINK_ROOT}/.claude-plugin" "${SYMLINK_ROOT}/tests" "${SYMLINK_ROOT}/skills/forge" "${SYMLINK_ROOT}/hooks" "${OUTSIDE_ARTIFACT}"
printf '{"name":"sidekick"}\n' > "${SYMLINK_ROOT}/.claude-plugin/plugin.json"
touch "${SYMLINK_ROOT}/tests/post_release_cleanup.bash" "${SYMLINK_ROOT}/skills/forge/SKILL.md" "${SYMLINK_ROOT}/hooks/hooks.json"
ln -s "${OUTSIDE_ARTIFACT}" "${SYMLINK_ROOT}/.tmp"
if SIDEKICK_REPO_ROOT="${SYMLINK_ROOT}" bash "${CLEANUP_SCRIPT}" >/dev/null 2>&1; then
  assert_fail "Cleanup rejects symlinked cleanup paths outside root" "command succeeded"
else
  assert_pass "Cleanup rejects symlinked cleanup paths outside root"
fi
if [ -d "${OUTSIDE_ARTIFACT}" ]; then
  assert_pass "Outside symlink target preserved after rejection"
else
  assert_fail "Outside symlink target preserved" "target was removed"
fi

if SIDEKICK_REPO_ROOT="${HOME}" bash "${CLEANUP_SCRIPT}" >/dev/null 2>&1; then
  assert_fail "Cleanup rejects HOME root" "command succeeded"
else
  assert_pass "Cleanup rejects HOME root"
fi

if SIDEKICK_REPO_ROOT="/" bash "${CLEANUP_SCRIPT}" >/dev/null 2>&1; then
  assert_fail "Cleanup rejects filesystem root" "command succeeded"
else
  assert_pass "Cleanup rejects filesystem root"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

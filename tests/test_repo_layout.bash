#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — repository layout tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

expect_dir() {
  local path="$1"
  if [ -d "${ROOT}/${path}" ]; then
    assert_pass "directory present: ${path}"
  else
    assert_fail "directory present: ${path}" "missing"
  fi
}

expect_file() {
  local path="$1"
  if [ -f "${ROOT}/${path}" ]; then
    assert_pass "file present: ${path}"
  else
    assert_fail "file present: ${path}" "missing"
  fi
}

expect_valid_json() {
  local path="$1"
  if python3 -m json.tool "${ROOT}/${path}" >/dev/null 2>&1; then
    assert_pass "valid JSON: ${path}"
  else
    assert_fail "valid JSON: ${path}" "parse failed"
  fi
}

echo "=== T1: Top-level project shape ==="
for dir in .claude .claude-plugin .codex-plugin .forge .github .planning docs hooks output-styles sidekicks skills tests; do
  expect_dir "${dir}"
done

for file in .forge.toml .gitignore .silver-bullet.json AGENTS.md CHANGELOG.md CLAUDE.md README.md context.md install.sh silver-bullet.md; do
  expect_file "${file}"
done

echo "=== T2: No transient root artifacts ==="
for dir in .tmp .cache target build dist coverage .pytest_cache node_modules; do
  if [ -e "${ROOT}/${dir}" ]; then
    assert_fail "transient artifact absent: ${dir}" "unexpected root artifact present"
  else
    assert_pass "transient artifact absent: ${dir}"
  fi
done

echo "=== T3: Organized docs layout ==="
for dir in docs/ADR docs/help docs/internal docs/knowledge docs/lessons docs/workflows docs/sessions docs/specs docs/design; do
  expect_dir "${dir}"
done

for file in docs/doc-scheme.md docs/START-HERE.md docs/AUDIENCE.md docs/GLOSSARY.md docs/COMPATIBILITY.md docs/TESTING.md docs/ARCHITECTURE.md docs/CICD.md docs/pre-release-quality-gate.md docs/ADR/README.md; do
  expect_file "${file}"
done

echo "=== T4: Editor configs match this Bash/Markdown repo ==="
for file in .vscode/settings.json .vscode/tasks.json .vscode/launch.json .vscode/extensions.json; do
  expect_file "${file}"
  expect_valid_json "${file}"
done

if grep -R -q 'runOn"[[:space:]]*:[[:space:]]*"folderOpen"' "${ROOT}/.vscode"; then
  assert_fail "VS Code folder-open tasks absent" "automatic folder-open tasks are not allowed"
else
  assert_pass "VS Code folder-open tasks absent"
fi

if grep -R -q 'node ./public/fonts' "${ROOT}/.vscode"; then
  assert_fail "VS Code stale Node/font task absent" "stale Node task still present"
else
  assert_pass "VS Code stale Node/font task absent"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

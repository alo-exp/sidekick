#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — docs contract tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

expect_file() {
  local path="$1"
  if [ -f "${ROOT}/${path}" ]; then
    assert_pass "file present: ${path}"
  else
    assert_fail "file present: ${path}" "missing"
  fi
}

expect_contains() {
  local path="$1" needle="$2" label="$3"
  if grep -Fq -- "${needle}" "${ROOT}/${path}"; then
    assert_pass "${label}"
  else
    assert_fail "${label}" "missing '${needle}' in ${path}"
  fi
}

echo "=== T1: Reader docs exist ==="
for file in docs/START-HERE.md docs/AUDIENCE.md docs/GLOSSARY.md docs/COMPATIBILITY.md docs/ADR/README.md docs/ADR/2026-05-08-docs-system.md; do
  expect_file "${file}"
done

echo "=== T2: Scheme and gateway mention the reader docs ==="
for needle in 'docs/START-HERE.md' 'docs/AUDIENCE.md' 'docs/GLOSSARY.md' 'docs/COMPATIBILITY.md' 'docs/ADR/README.md'; do
  expect_contains "docs/doc-scheme.md" "${needle}" "doc-scheme references ${needle}"
done

for needle in 'docs/START-HERE.md' 'docs/AUDIENCE.md' 'docs/GLOSSARY.md' 'docs/COMPATIBILITY.md' 'docs/ADR/README.md'; do
  expect_contains "docs/knowledge/INDEX.md" "${needle}" "knowledge index references ${needle}"
done

echo "=== T3: Start-here and glossary content ==="
for needle in '# Start Here' 'What are you trying to do?' 'Install Sidekick' 'Delegate a task' 'Debug something that failed' 'Prepare for release' 'Extend or package a plugin' 'Understand the system shape'; do
  expect_contains "docs/START-HERE.md" "${needle}" "start-here contains ${needle}"
done

for needle in '# Audience' 'Reader Matrix' 'New user' 'Maintainer' 'Release operator' 'Plugin author' 'Claude user' 'Kay user' 'Kay operator'; do
  expect_contains "docs/AUDIENCE.md" "${needle}" "audience contains ${needle}"
done

for needle in '# Glossary' 'Code / Kay' 'host Codex' 'bridge' 'wrapper'; do
  expect_contains "docs/GLOSSARY.md" "${needle}" "glossary contains ${needle}"
done

for needle in '# Compatibility' 'Claude / Forge' 'Codex / Code / Kay' 'Execution identity' 'Provider precedence'; do
  expect_contains "docs/COMPATIBILITY.md" "${needle}" "compatibility contains ${needle}"
done

echo "=== T4: ADR home and decision record ==="
for needle in '# Architecture Decision Records' '2026-05-08-docs-system.md' 'Docs System Upgrade'; do
  expect_contains "docs/ADR/README.md" "${needle}" "ADR index contains ${needle}"
done
expect_contains "docs/ADR/2026-05-08-docs-system.md" 'Status: Accepted' "docs-system ADR accepted"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

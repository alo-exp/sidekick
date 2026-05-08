#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — help-site navigation tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
ROOT="/Users/shafqat/projects/sidekick/repo"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

expect_contains() {
  local path="$1" needle="$2" label="$3"
  if grep -Fq -- "${needle}" "${ROOT}/${path}"; then
    assert_pass "${label}"
  else
    assert_fail "${label}" "missing '${needle}' in ${path}"
  fi
}

echo "=== T1: Main docs landing page exposes reader docs ==="
for needle in 'Start Here' 'Audience' 'Glossary' 'Compatibility' 'ADRs' 'Start with the right doc'; do
  expect_contains "docs/index.html" "${needle}" "docs landing contains ${needle}"
done

echo "=== T2: Help center exposes task-first navigation ==="
for needle in 'Start Here' 'Audience' 'Glossary' 'Compatibility' 'Choose a task or topic' 'Pick the page that matches your role or your task'; do
  expect_contains "docs/help/index.html" "${needle}" "help index contains ${needle}"
done

echo "=== T3: Help search indexes the new docs pages ==="
for needle in '../START-HERE.md' '../AUDIENCE.md' '../GLOSSARY.md' '../COMPATIBILITY.md' '../ADR/README.md' 'Start Here — pick the right doc' 'Compatibility — Claude, Codex, and Kay'; do
  expect_contains "docs/help/search.js" "${needle}" "help search contains ${needle}"
done

echo "=== T4: Help pages link back to the docs layer ==="
for path in docs/help/getting-started/index.html docs/help/concepts/index.html docs/help/workflows/index.html docs/help/reference/index.html docs/help/troubleshooting/index.html; do
  expect_contains "${path}" '../../START-HERE.md' "${path} links to Start Here"
  expect_contains "${path}" '../../GLOSSARY.md' "${path} links to Glossary"
  expect_contains "${path}" '../../COMPATIBILITY.md' "${path} links to Compatibility"
done

echo "=== T5: Reference page exposes glossary and compatibility ==="
for needle in 'Glossary Matrix' 'Compatibility Matrix' '../../GLOSSARY.md' '../../COMPATIBILITY.md'; do
  expect_contains "docs/help/reference/index.html" "${needle}" "reference contains ${needle}"
done

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

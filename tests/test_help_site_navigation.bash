#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — help-site navigation tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

expect_not_contains() {
  local path="$1" needle="$2" label="$3"
  if grep -Fq -- "${needle}" "${ROOT}/${path}"; then
    assert_fail "${label}" "unexpected '${needle}' in ${path}"
  else
    assert_pass "${label}"
  fi
}

echo "=== T1: Main docs landing page exposes reader docs ==="
for needle in 'Start Here' 'Audience' 'Glossary' 'Compatibility' 'ADRs' 'Start with the right doc'; do
  expect_contains "docs/index.html" "${needle}" "docs landing contains ${needle}"
done

echo "=== T2: Help center exposes task-first navigation ==="
for needle in 'Start Here' 'Audience' 'Glossary' 'Compatibility' 'Choose a task or topic' 'Pick the page that matches your role or your task' 'Sidekick ships Forge and Kay' 'Claude Code and Codex can both route work to either agent' 'OpenCode Go remains Kay' 'code exec' 'codex' 'coder'; do
  expect_contains "docs/help/index.html" "${needle}" "help index contains ${needle}"
done
expect_not_contains "docs/help/index.html" "Claude Code users delegate to Forge" "help index removes stale host-specific Forge copy"
expect_not_contains "docs/help/index.html" "Code and Codex workflows route to Kay" "help index removes stale host-specific Kay copy"

echo "=== T3: Help search indexes the new docs pages ==="
for needle in '../START-HERE.md' '../AUDIENCE.md' '../GLOSSARY.md' '../COMPATIBILITY.md' '../ADR/README.md' 'Start Here — pick the right doc' 'Compatibility — Claude, Codex, and Kay' 'Sidekick ships Forge and Kay' 'Claude Code and Codex can both route work to either agent' 'OpenCode Go' 'code exec --full-auto' 'MiniMax M2.7' "anchor:'support'"; do
  expect_contains "docs/help/search.js" "${needle}" "help search contains ${needle}"
done
expect_not_contains "docs/help/search.js" "Claude Code users delegate to Forge" "help search removes stale host-specific Forge copy"
expect_not_contains "docs/help/search.js" "Code and Codex workflows route to Kay" "help search removes stale host-specific Kay copy"

echo "=== T4: Help pages link back to the docs layer ==="
for path in docs/help/getting-started/index.html docs/help/concepts/index.html docs/help/workflows/index.html docs/help/reference/index.html docs/help/troubleshooting/index.html; do
  expect_contains "${path}" '../../START-HERE.md' "${path} links to Start Here"
  expect_contains "${path}" '../../GLOSSARY.md' "${path} links to Glossary"
  expect_contains "${path}" '../../COMPATIBILITY.md' "${path} links to Compatibility"
done

echo "=== T5: Getting Started is host-aware ==="
for needle in 'Claude Code or Codex' 'Codex users should start with Compatibility' 'Claude Code and Codex plugin' 'Codex users should install the Codex-facing Sidekick package' 'Your First Kay Task' 'code exec --full-auto'; do
  expect_contains "docs/help/getting-started/index.html" "${needle}" "getting started contains ${needle}"
done

echo "=== T6: Reference page exposes glossary and compatibility ==="
for needle in 'Glossary Matrix' 'Compatibility Matrix' '../../GLOSSARY.md' '../../COMPATIBILITY.md'; do
  expect_contains "docs/help/reference/index.html" "${needle}" "reference contains ${needle}"
done

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

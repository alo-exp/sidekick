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

expect_not_contains() {
  local path="$1" needle="$2" label="$3"
  if grep -Fq -- "${needle}" "${ROOT}/${path}"; then
    assert_fail "${label}" "unexpected '${needle}' in ${path}"
  else
    assert_pass "${label}"
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

for needle in '# Audience' 'Reader Matrix' 'New user' 'Maintainer' 'Release operator' 'Plugin author' 'Claude Code user' 'Codex user' 'Kay user' 'Kay operator'; do
  expect_contains "docs/AUDIENCE.md" "${needle}" "audience contains ${needle}"
done

for needle in '# Glossary' 'host AI' 'Forge' 'Kay' 'legacy Code aliases' 'host Codex' 'bridge' 'wrapper'; do
  expect_contains "docs/GLOSSARY.md" "${needle}" "glossary contains ${needle}"
done
expect_not_contains "docs/GLOSSARY.md" 'MiniMax-backed `code` runtime' "glossary removes code as primary Kay runtime"

for needle in '# Compatibility' 'Host Surface' 'Execution Agent' 'Execution identity' 'Provider precedence' '`kay`'; do
  expect_contains "docs/COMPATIBILITY.md" "${needle}" "compatibility contains ${needle}"
done
expect_not_contains "docs/COMPATIBILITY.md" 'Claude / Forge' "compatibility removes stale Claude/Forge pairing"
expect_not_contains "docs/COMPATIBILITY.md" 'Codex / Kay' "compatibility removes stale Codex/Kay pairing"
expect_not_contains "docs/COMPATIBILITY.md" '| Execution identity | `forge` | `code` |' "compatibility removes code as primary execution identity"

echo "=== T4: ADR home and decision record ==="
for needle in '# Architecture Decision Records' '2026-05-08-docs-system.md' 'Docs System Upgrade'; do
  expect_contains "docs/ADR/README.md" "${needle}" "ADR index contains ${needle}"
done
expect_contains "docs/ADR/2026-05-08-docs-system.md" 'Status: Accepted' "docs-system ADR accepted"

echo "=== T5: Shared-host wording stays host-neutral ==="
for stale in 'Brain (Claude)' 'Kay/Claude pickers' 'Claude-to-sidekick roundtrip' 'Matches Claude Code plugin contract' 'The only Claude Code mechanism'; do
  expect_not_contains "docs/ARCHITECTURE.md" "${stale}" "architecture avoids stale host-specific wording: ${stale}"
done

for stale in 'Claude acts directly' 'Claude extracts learnings' 'Full Claude→Forge delegation'; do
  expect_not_contains "README.md" "${stale}" "README avoids stale host-specific wording: ${stale}"
done

for stale in 'Claude never writes code' 'Claude drives extraction explicitly'; do
  expect_not_contains "docs/PRD-Overview.md" "${stale}" "PRD overview avoids stale host-specific wording: ${stale}"
done

expect_not_contains "docs/pre-release-quality-gate.md" 'Claude acts directly' "release gate avoids stale host-specific L3 wording"
expect_contains "docs/pre-release-quality-gate.md" 'preserved while the command is still normalized' "release gate documents resume UUID normalization"
expect_not_contains "docs/pre-release-quality-gate.md" 'idempotent pass-through before `-p`' "release gate removes stale UUID pass-through wording"

echo "=== T6: README sidekick surfaces stay canonical ==="
expect_contains "README.md" '| Sidekick | Activation surface | Agent | Status |' "README sidekick table names activation surface"
expect_contains "README.md" '| **Forge** | `/forge` |' "README uses /forge activation surface"
expect_contains "README.md" '| **Kay** | `kay-delegate` |' "README uses kay-delegate activation surface"
expect_not_contains "README.md" '| **Forge** | `forge` |' "README does not list forge binary as the skill"
expect_not_contains "README.md" '| **Kay** | `kay` |' "README does not list kay binary as the skill"

echo "=== T7: Runtime context names current marker and Kay activation surfaces ==="
expect_contains "context.md" 'Kay activates through `kay-delegate` / `sidekick:kay-delegate`' "context names Kay activation surface before runtime command"
expect_contains "context.md" 'Active Forge delegation markers live under the active host session root (`.claude/sessions/...` for Claude Code, `.codex/sessions/...` for Codex).' "context documents Claude and Codex Forge marker roots"
expect_contains "context.md" 'Kay markers live under `.kay/sessions/...`.' "context documents Kay marker root"
expect_not_contains "context.md" 'Active delegation markers live under `.claude/sessions/...` for Forge and `.kay/sessions/...` for Kay.' "context removes stale single-host Forge marker copy"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

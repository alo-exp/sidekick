#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — docs contract tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST_VERSION="$(python3 -c "import json; print(json.load(open('${ROOT}/.claude-plugin/plugin.json'))['version'])")"

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
for file in site/START-HERE.md site/AUDIENCE.md site/GLOSSARY.md site/COMPATIBILITY.md site/ADR/README.md site/ADR/2026-05-08-docs-system.md; do
  expect_file "${file}"
done

echo "=== T2: Scheme and gateway mention the reader docs ==="
for needle in 'site/START-HERE.md' 'site/AUDIENCE.md' 'site/GLOSSARY.md' 'site/COMPATIBILITY.md' 'site/ADR/README.md'; do
  expect_contains "site/doc-scheme.md" "${needle}" "doc-scheme references ${needle}"
done

for needle in 'site/START-HERE.md' 'site/AUDIENCE.md' 'site/GLOSSARY.md' 'site/COMPATIBILITY.md' 'site/ADR/README.md'; do
  expect_contains "site/knowledge/INDEX.md" "${needle}" "knowledge index references ${needle}"
done

echo "=== T3: Start-here and glossary content ==="
for needle in '# Start Here' 'What are you trying to do?' 'Install Sidekick' 'Delegate a task' 'Debug something that failed' 'Prepare for release' 'Extend or package a plugin' 'Understand the system shape'; do
  expect_contains "site/START-HERE.md" "${needle}" "start-here contains ${needle}"
done

for needle in '# Audience' 'Reader Matrix' 'New user' 'Maintainer' 'Release operator' 'Plugin author' 'Claude Code user' 'Codex user' 'Kay user' 'Kay operator'; do
  expect_contains "site/AUDIENCE.md" "${needle}" "audience contains ${needle}"
done

for needle in '# Glossary' 'host AI' 'Forge' 'Kay' 'legacy Code aliases' 'host Codex' 'bridge' 'wrapper'; do
  expect_contains "site/GLOSSARY.md" "${needle}" "glossary contains ${needle}"
done
expect_not_contains "site/GLOSSARY.md" 'MiniMax-backed `code` runtime' "glossary removes code as primary Kay runtime"

for needle in '# Compatibility' 'Host Surface' 'Execution Agent' 'Execution identity' 'Provider precedence' '`kay`'; do
  expect_contains "site/COMPATIBILITY.md" "${needle}" "compatibility contains ${needle}"
done
expect_not_contains "site/COMPATIBILITY.md" 'Claude / Forge' "compatibility removes stale Claude/Forge pairing"
expect_not_contains "site/COMPATIBILITY.md" 'Codex / Kay' "compatibility removes stale Codex/Kay pairing"
expect_not_contains "site/COMPATIBILITY.md" '| Execution identity | `forge` | `code` |' "compatibility removes code as primary execution identity"

echo "=== T4: ADR home and decision record ==="
for needle in '# Architecture Decision Records' '2026-05-08-docs-system.md' 'Docs System Upgrade'; do
  expect_contains "site/ADR/README.md" "${needle}" "ADR index contains ${needle}"
done
expect_contains "site/ADR/2026-05-08-docs-system.md" 'Status: Accepted' "docs-system ADR accepted"

echo "=== T5: Shared-host wording stays host-neutral ==="
for stale in 'Brain (Claude)' 'Kay/Claude pickers' 'Claude-to-sidekick roundtrip' 'Matches Claude Code plugin contract' 'The only Claude Code mechanism'; do
  expect_not_contains "site/ARCHITECTURE.md" "${stale}" "architecture avoids stale host-specific wording: ${stale}"
done

for stale in 'Claude acts directly' 'Claude extracts learnings' 'Full Claude→Forge delegation'; do
  expect_not_contains "README.md" "${stale}" "README avoids stale host-specific wording: ${stale}"
done

for stale in 'Claude never writes code' 'Claude drives extraction explicitly'; do
  expect_not_contains "site/PRD-Overview.md" "${stale}" "PRD overview avoids stale host-specific wording: ${stale}"
done

expect_not_contains "site/pre-release-quality-gate.md" 'Claude acts directly' "release gate avoids stale host-specific L3 wording"
expect_contains "site/pre-release-quality-gate.md" 'preserved while the command is still normalized' "release gate documents resume UUID normalization"
expect_not_contains "site/pre-release-quality-gate.md" 'idempotent pass-through before `-p`' "release gate removes stale UUID pass-through wording"

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

echo "=== T8: Public docs version references match manifest ==="
expect_contains "site/PRD-Overview.md" "**Current milestone:** v${MANIFEST_VERSION}" "PRD overview current milestone matches manifest"
expect_contains "site/PRD-Overview.md" "Current release metadata remains \`v${MANIFEST_VERSION}\`" "PRD overview manifest row matches manifest"
expect_contains "site/PRD-Overview.md" "v${MANIFEST_VERSION} test suite" "PRD overview test-suite row matches manifest"
expect_contains "site/PRD-Overview.md" "validated as of v${MANIFEST_VERSION}" "PRD overview source-of-truth row matches manifest"
expect_not_contains "site/PRD-Overview.md" "v0.5.6" "PRD overview removes stale v0.5.6 references"

echo "=== T9: Release runner docs match current contracts ==="
expect_contains "README.md" "then runs every live-gated wrapper in skip-safe mode" "README documents expanded run_all scope"
expect_contains "site/TESTING.md" "then runs every live-gated wrapper in skip-safe mode" "testing docs document expanded run_all scope"
expect_contains "README.md" "runs the strict non-live tier" "README distinguishes release runner tier from quality-gate stage"
expect_contains "CHANGELOG.md" "dynamic tag refspecs" "changelog documents dynamic release refspec guard"
expect_contains "tests/run_release.bash" "CI should run tests/run_unit.bash" "release runner comment points CI at strict non-live runner"
expect_contains "site/pre-release-quality-gate.md" 'If release commits intentionally include `[skip ci]`' "release gate documents skip-CI local evidence path"
expect_contains "site/internal/pre-release-quality-gate.md" 'If release commits intentionally include `[skip ci]`' "internal release gate documents skip-CI local evidence path"
expect_contains "site/pre-release-quality-gate.md" 'recorded local evidence when `[skip ci]` is intentionally used' "release gate exit criteria allow skip-CI evidence"
expect_contains "site/internal/pre-release-quality-gate.md" 'recorded local evidence when `[skip ci]` is intentionally used' "internal release gate exit criteria allow skip-CI evidence"
expect_contains "site/internal/pre-release-quality-gate.md" "git push origin v<version>" "internal release gate documents release tag push"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

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

echo "=== T1: Homepage keeps Help Center access without the docs-map section ==="
for needle in 'How It Works' 'Sidekicks' 'Benchmark' 'Backends' 'Install' 'Help' 'Open Help Center'; do
  expect_contains "docs/index.html" "${needle}" "homepage contains ${needle}"
done
expect_not_contains "docs/index.html" "Start with the right doc" "homepage removes the docs-map headline"
expect_not_contains "docs/index.html" "id=\"docs-map\"" "homepage removes the docs-map section"

echo "=== T2: Help center exposes task-first navigation ==="
for needle in 'Start Here' 'Audience' 'Glossary' 'Compatibility' 'Choose a task or topic' 'Pick the page that matches your role or your task' 'Sidekick ships Forge and Kay' 'Claude Code and Codex can both route work to either agent' 'OpenCode Go remains Kay' 'code exec' 'codex' 'coder'; do
expect_contains "docs/help/index.html" "${needle}" "help index contains ${needle}"
done
for path in docs/help/index.html docs/help/getting-started/index.html docs/help/concepts/index.html docs/help/workflows/index.html docs/help/reference/index.html docs/help/troubleshooting/index.html; do
  expect_contains "${path}" "sidekick-theme-v2" "${path} uses versioned theme storage"
  expect_not_contains "${path}" "localStorage.getItem('sidekick-theme')" "${path} ignores legacy light theme preference on first load"
  expect_contains "${path}" "localStorage.removeItem('sidekick-theme')" "${path} clears legacy theme storage after a new choice"
done
expect_not_contains "docs/help/index.html" "Claude Code users delegate to Forge" "help index removes stale host-specific Forge copy"
expect_not_contains "docs/help/index.html" "Code and Codex workflows route to Kay" "help index removes stale host-specific Kay copy"
expect_not_contains "docs/help/getting-started/index.html" "SessionStart hooks install missing Forge and Kay assets" "getting started removes SessionStart runtime sync copy"
expect_not_contains "docs/help/concepts/index.html" "SessionStart runtime sync" "concepts removes SessionStart runtime sync copy"
expect_not_contains "docs/help/reference/index.html" "runtime-sync.sh" "reference removes runtime-sync hook row"
expect_not_contains "docs/help/troubleshooting/index.html" "runtime sync hook" "troubleshooting removes runtime sync repair guidance"
expect_not_contains "docs/help/getting-started/index.html" "~/.claude/settings.json" "getting started no longer uses manual settings JSON install"
expect_not_contains "docs/help/concepts/index.html" "OpenRouter (recommended)" "concepts does not label OpenRouter as the recommended provider"
expect_not_contains "docs/help/workflows/index.html" "AGENTS_UPDATE field is applied directly" "workflow does not claim L3 AGENTS_UPDATE is applied without confirmation"
expect_not_contains "docs/help/troubleshooting/index.html" "curl -fsSL https://forgecode.dev/cli | sh" "troubleshooting avoids unsafe curl-pipe install"

echo "=== T3: Help search indexes the new docs pages ==="
for needle in '../START-HERE.md' '../AUDIENCE.md' '../GLOSSARY.md' '../COMPATIBILITY.md' '../ADR/README.md' 'Start Here — pick the right doc' 'Compatibility — Claude, Codex, and Kay' 'Sidekick ships Forge and Kay' 'Claude Code and Codex can both route work to either agent' 'OpenCode Go' 'code exec --full-auto' 'MiniMax M2.7' "anchor:'support'"; do
  expect_contains "docs/help/search.js" "${needle}" "help search contains ${needle}"
done
expect_not_contains "docs/help/search.js" "Claude Code users delegate to Forge" "help search removes stale host-specific Forge copy"
expect_not_contains "docs/help/search.js" "Code and Codex workflows route to Kay" "help search removes stale host-specific Kay copy"
expect_not_contains "docs/help/search.js" "SessionStart sync" "help search removes SessionStart sync copy"
expect_not_contains "docs/help/search.js" "runtime sync repair" "help search removes runtime sync repair copy"

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
for needle in '/plugin install alo-labs/sidekick' 'codex plugin marketplace add alo-labs/sidekick' 'The SessionStart hooks only run first-run bootstrap and legacy hook cleanup' 'On activation, Forge checks four things' 'The PreToolUse hook injects <code>--conversation-id</code>, <code>--verbose</code>'; do
  expect_contains "docs/help/getting-started/index.html" "${needle}" "getting started current flow contains ${needle}"
done

echo "=== T6: Reference page exposes glossary and compatibility ==="
for needle in 'Glossary Matrix' 'Compatibility Matrix' '../../GLOSSARY.md' '../../COMPATIBILITY.md'; do
  expect_contains "docs/help/reference/index.html" "${needle}" "reference contains ${needle}"
done
for needle in 'SessionStart no longer updates or repairs Forge/Kay runtimes after install' 'rewrites <code>forge -p</code> calls to inject <code>--conversation-id</code>, <code>--verbose</code>' 'rewrites <code>code</code> / <code>codex</code> / <code>coder exec</code> calls to include <code>--full-auto</code>' 'host session marker' '~/.kay/sessions/&lt;session&gt;/.kay-delegation-active'; do
  expect_contains "docs/help/reference/index.html" "${needle}" "reference current hooks contain ${needle}"
done

echo "=== T7: Concepts and troubleshooting match current runtime behavior ==="
for needle in 'per-session health check; SessionStart does not update or repair runtimes' 'quality-gates + code-review' 'Forge output is treated as untrusted task output' '[<span class="key">compact</span>]'; do
  expect_contains "docs/help/concepts/index.html" "${needle}" "concepts current model contains ${needle}"
done
for needle in 'Forge Provider Configuration' 'Direct edits are denied after /forge or Kay mode starts' 'conversation database is not writable' 'AGENTS_UPDATE field will propose instructions'; do
  expect_contains "docs/help/troubleshooting/index.html" "${needle}" "troubleshooting current model contains ${needle}"
done

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

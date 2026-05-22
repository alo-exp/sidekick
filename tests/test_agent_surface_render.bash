#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — generated host skill surface tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
RENDERER="${PLUGIN_DIR}/scripts/render-agent-bundle.py"
SYNC="${PLUGIN_DIR}/scripts/sync-host-surfaces.sh"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

expect_file() {
  local path="$1"
  if [ -f "${PLUGIN_DIR}/${path}" ]; then
    assert_pass "file present: ${path}"
  else
    assert_fail "file present: ${path}" "missing"
  fi
}

expect_executable() {
  local path="$1"
  if [ -x "${PLUGIN_DIR}/${path}" ]; then
    assert_pass "executable present: ${path}"
  else
    assert_fail "executable present: ${path}" "missing or not executable"
  fi
}

expect_contains() {
  local path="$1" needle="$2" label="$3"
  if grep -Fq "$needle" "${PLUGIN_DIR}/${path}"; then
    assert_pass "$label"
  else
    assert_fail "$label" "missing: $needle"
  fi
}

expect_not_contains() {
  local path="$1" needle="$2" label="$3"
  if grep -Fq "$needle" "${PLUGIN_DIR}/${path}"; then
    assert_fail "$label" "unexpected: $needle"
  else
    assert_pass "$label"
  fi
}

echo "=== T1: renderer and host bundles exist ==="
expect_file "scripts/render-agent-bundle.py"
expect_executable "scripts/sync-host-surfaces.sh"
expect_file "agents/claude/forge/SKILL.md"
expect_file "agents/codex/forge/SKILL.md"
expect_file "agents/claude/codex-delegate/SKILL.md"
expect_file "agents/codex/codex-delegate/SKILL.md"

echo "=== T2: canonical skills use host placeholders ==="
for path in \
  skills/forge/SKILL.md \
  skills/forge-stop/SKILL.md \
  skills/codex-delegate/SKILL.md \
  skills/codex-stop/SKILL.md; do
  expect_contains "$path" "SIDEKICK_HOST_SESSION_ID" "canonical ${path} uses host session placeholder"
  expect_not_contains "$path" "CLAUDE_SESSION_ID" "canonical ${path} has no Claude session literal"
  expect_not_contains "$path" "CODEX_THREAD_ID" "canonical ${path} has no Codex thread literal"
  expect_not_contains "$path" ".claude/sessions" "canonical ${path} has no Claude session path"
  expect_not_contains "$path" ".codex/sessions" "canonical ${path} has no Codex session path"
done

echo "=== T3: generated Claude skills are Claude-specific ==="
for path in \
  agents/claude/forge/SKILL.md \
  agents/claude/forge-stop/SKILL.md \
  agents/claude/codex-delegate/SKILL.md \
  agents/claude/codex-stop/SKILL.md; do
  expect_contains "$path" "CLAUDE_SESSION_ID" "Claude generated ${path} uses Claude session var"
  expect_not_contains "$path" "CODEX_THREAD_ID" "Claude generated ${path} has no Codex thread var"
  expect_not_contains "$path" "SIDEKICK_HOST_SESSION_ID" "Claude generated ${path} has no unresolved placeholder"
done
for path in \
  agents/claude/forge/SKILL.md \
  agents/claude/forge-stop/SKILL.md \
  agents/claude/codex-delegate/SKILL.md; do
  expect_contains "$path" ".claude/sessions" "Claude generated ${path} uses Claude session path"
done

echo "=== T4: generated Codex skills are Codex-specific ==="
for path in \
  agents/codex/forge/SKILL.md \
  agents/codex/forge-stop/SKILL.md \
  agents/codex/codex-delegate/SKILL.md \
  agents/codex/codex-stop/SKILL.md; do
  expect_contains "$path" "CODEX_THREAD_ID" "Codex generated ${path} uses Codex thread var"
  expect_not_contains "$path" "CLAUDE_SESSION_ID" "Codex generated ${path} has no Claude session var"
  expect_not_contains "$path" "SIDEKICK_HOST_SESSION_ID" "Codex generated ${path} has no unresolved placeholder"
done
for path in \
  agents/codex/forge/SKILL.md \
  agents/codex/forge-stop/SKILL.md \
  agents/codex/codex-delegate/SKILL.md; do
  expect_contains "$path" ".codex/sessions" "Codex generated ${path} uses Codex session path"
done

echo "=== T5: generated bundles are in sync with renderer ==="
if [ -f "${RENDERER}" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}" 2>/dev/null || true' EXIT
  if python3 "${RENDERER}" render --agent claude --source-root "${PLUGIN_DIR}/skills" --dest-root "${tmp}/claude" \
    && python3 "${RENDERER}" render --agent codex --source-root "${PLUGIN_DIR}/skills" --dest-root "${tmp}/codex" \
    && diff -qr "${tmp}/claude" "${PLUGIN_DIR}/agents/claude" >/tmp/sidekick-agent-claude.diff 2>&1 \
    && diff -qr "${tmp}/codex" "${PLUGIN_DIR}/agents/codex" >/tmp/sidekick-agent-codex.diff 2>&1; then
    assert_pass "generated host bundles match renderer output"
  else
    assert_fail "generated host bundles in sync" "$(cat /tmp/sidekick-agent-claude.diff /tmp/sidekick-agent-codex.diff 2>/dev/null | head -20)"
  fi
else
  assert_fail "generated host bundles in sync" "renderer missing"
fi

echo "=== T6: renderer refuses unsafe destinations ==="
if python3 "${RENDERER}" render --agent claude --source-root "${PLUGIN_DIR}/skills" --dest-root "${PLUGIN_DIR}" >/tmp/sidekick-render-unsafe.out 2>&1; then
  assert_fail "renderer destination guard" "repo root destination unexpectedly accepted"
elif grep -Fq "refusing unsafe render destination" /tmp/sidekick-render-unsafe.out; then
  assert_pass "renderer destination guard rejects repo root"
else
  assert_fail "renderer destination guard" "$(cat /tmp/sidekick-render-unsafe.out)"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

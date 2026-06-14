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

expect_absent() {
  local path="$1"
  if [ ! -e "${PLUGIN_DIR}/${path}" ]; then
    assert_pass "path absent: ${path}"
  else
    assert_fail "path absent: ${path}" "unexpected path exists"
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
expect_file "agents/claude/kay-delegate/SKILL.md"
expect_file "agents/codex/kay-delegate/SKILL.md"
expect_file "agents/claude/codex-delegate/SKILL.md"
expect_file "agents/codex/codex-delegate/SKILL.md"

echo "=== T1b: cursor host bundle exists ==="
expect_file "agents/cursor/kay-delegate/SKILL.md"
expect_file "agents/cursor/codex-delegate/SKILL.md"

echo "=== T2: canonical skills use host placeholders ==="
for path in \
  skills/kay-delegate/SKILL.md \
  skills/kay-stop/SKILL.md \
  skills/codex-delegate/SKILL.md \
  skills/codex-stop/SKILL.md; do
  expect_contains "$path" "SIDEKICK_HOST_SESSION_ID" "canonical ${path} uses host session placeholder"
  expect_contains "$path" "CLAUDE_SESSION_ID" "canonical ${path} includes Claude fallback"
  expect_contains "$path" "CODEX_THREAD_ID" "canonical ${path} includes Codex fallback"
  expect_not_contains "$path" ".claude/sessions" "canonical ${path} has no Claude session path"
  expect_not_contains "$path" ".codex/sessions" "canonical ${path} has no Codex session path"
done

echo "=== T3: generated Claude skills are Claude-specific ==="
for path in \
  agents/claude/kay-delegate/SKILL.md \
  agents/claude/kay-stop/SKILL.md \
  agents/claude/codex-delegate/SKILL.md \
  agents/claude/codex-stop/SKILL.md; do
  expect_contains "$path" "CLAUDE_SESSION_ID" "Claude generated ${path} uses Claude session var"
  expect_not_contains "$path" "CODEX_THREAD_ID" "Claude generated ${path} has no Codex thread var"
  expect_not_contains "$path" "SIDEKICK_HOST_SESSION_ID" "Claude generated ${path} has no unresolved placeholder"
done
for path in \
  agents/claude/kay-delegate/SKILL.md \
  agents/claude/codex-delegate/SKILL.md; do
  expect_contains "$path" ".claude/sessions" "Claude generated ${path} uses Claude session path"
done

echo "=== T4: generated Codex skills are Codex-specific ==="
for path in \
  agents/codex/kay-delegate/SKILL.md \
  agents/codex/kay-stop/SKILL.md \
  agents/codex/codex-delegate/SKILL.md \
  agents/codex/codex-stop/SKILL.md; do
  expect_contains "$path" "CODEX_THREAD_ID" "Codex generated ${path} uses Codex thread var"
  expect_not_contains "$path" "CLAUDE_SESSION_ID" "Codex generated ${path} has no Claude session var"
  expect_not_contains "$path" "SIDEKICK_HOST_SESSION_ID" "Codex generated ${path} has no unresolved placeholder"
done
for path in \
  agents/codex/kay-delegate/SKILL.md \
  agents/codex/codex-delegate/SKILL.md; do
  expect_contains "$path" ".codex/sessions" "Codex generated ${path} uses Codex session path"
done

echo "=== T4b: generated Cursor skills are Cursor-specific ==="
for path in \
  agents/cursor/kay-delegate/SKILL.md \
  agents/cursor/kay-stop/SKILL.md \
  agents/cursor/codex-delegate/SKILL.md \
  agents/cursor/codex-stop/SKILL.md; do
  expect_contains "$path" "SIDEKICK_SESSION_ID" "Cursor generated ${path} uses SIDEKICK_SESSION_ID"
  expect_not_contains "$path" "CODEX_THREAD_ID" "Cursor generated ${path} has no Codex thread var"
  expect_not_contains "$path" "CLAUDE_SESSION_ID" "Cursor generated ${path} has no Claude session var"
done
for path in \
  agents/cursor/kay-delegate/SKILL.md \
  agents/cursor/codex-delegate/SKILL.md; do
  expect_contains "$path" ".cursor/sessions" "Cursor generated ${path} uses Cursor session path"
done

echo "=== T5: redundant Kay alias is absent and wrappers point at host-specific surfaces ==="
for agent in claude codex cursor; do
  expect_absent "agents/${agent}/kay:delegate/SKILL.md"
  expect_contains "agents/${agent}/codex-delegate.md" "generated host skill at codex-delegate/SKILL.md" "${agent} flat Codex wrapper names generated skill surface"
  expect_not_contains "agents/${agent}/codex-delegate.md" 'skills/codex-delegate/SKILL.md' "${agent} flat Codex wrapper does not point at canonical skills tree"
  expect_contains "agents/${agent}/kay-delegate/SKILL.md" "agents/${agent}/kay-stop/SKILL.md" "${agent} Kay skill names generated stop skill"
done

echo "=== T6: generated bundles are in sync with renderer ==="
if [ -f "${RENDERER}" ]; then
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/sidekick-agent-render.XXXXXX")"
  trap 'rm -rf "${tmp}" 2>/dev/null || true' EXIT
  if python3 "${RENDERER}" render --agent claude --source-root "${PLUGIN_DIR}/skills" --dest-root "${tmp}/claude" \
    && python3 "${RENDERER}" render --agent codex --source-root "${PLUGIN_DIR}/skills" --dest-root "${tmp}/codex" \
    && python3 "${RENDERER}" render --agent cursor --source-root "${PLUGIN_DIR}/skills" --dest-root "${tmp}/cursor" \
    && diff -qr "${tmp}/claude" "${PLUGIN_DIR}/agents/claude" >"${tmp}/sidekick-agent-claude.diff" 2>&1 \
    && diff -qr "${tmp}/codex" "${PLUGIN_DIR}/agents/codex" >"${tmp}/sidekick-agent-codex.diff" 2>&1 \
    && diff -qr "${tmp}/cursor" "${PLUGIN_DIR}/agents/cursor" >"${tmp}/sidekick-agent-cursor.diff" 2>&1; then
    assert_pass "generated host bundles match renderer output"
  else
    assert_fail "generated host bundles in sync" "$(cat "${tmp}/sidekick-agent-claude.diff" "${tmp}/sidekick-agent-codex.diff" "${tmp}/sidekick-agent-cursor.diff" 2>/dev/null | head -20)"
  fi
else
  assert_fail "generated host bundles in sync" "renderer missing"
fi

echo "=== T7: renderer refuses unsafe destinations ==="
if python3 "${RENDERER}" render --agent claude --source-root "${PLUGIN_DIR}/skills" --dest-root "${PLUGIN_DIR}" >/tmp/sidekick-render-unsafe.out 2>&1; then
  assert_fail "renderer destination guard" "repo root destination unexpectedly accepted"
elif grep -Fq "refusing unsafe render destination" /tmp/sidekick-render-unsafe.out; then
  assert_pass "renderer destination guard rejects repo root"
else
  assert_fail "renderer destination guard" "$(cat /tmp/sidekick-render-unsafe.out)"
fi

echo "=== T8: renderer refuses unsafe sanitize roots ==="
if python3 "${RENDERER}" sanitize --agent codex --root "${PLUGIN_DIR}" >/tmp/sidekick-sanitize-unsafe.out 2>&1; then
  assert_fail "renderer sanitize guard" "repo root sanitize unexpectedly accepted"
elif grep -Fq "refusing unsafe sanitize root" /tmp/sidekick-sanitize-unsafe.out; then
  assert_pass "renderer sanitize guard rejects repo root"
else
  assert_fail "renderer sanitize guard" "$(cat /tmp/sidekick-sanitize-unsafe.out)"
fi

echo "=== T9: renderer requires Sidekick-owned temp roots and explicit replacement ==="
unsafe_tmp="$(mktemp -d)"
safe_tmp="$(mktemp -d "${TMPDIR:-/tmp}/sidekick-agent-render.XXXXXX")"
mkdir -p "${safe_tmp}/claude"
if python3 "${RENDERER}" render --agent claude --source-root "${PLUGIN_DIR}/skills" --dest-root "${unsafe_tmp}/claude" >/tmp/sidekick-render-temp-unsafe.out 2>&1; then
  assert_fail "renderer temp guard" "generic temp destination unexpectedly accepted"
elif grep -Fq "Sidekick-owned temp dir" /tmp/sidekick-render-temp-unsafe.out; then
  assert_pass "renderer rejects generic temp destinations"
else
  assert_fail "renderer temp guard" "$(cat /tmp/sidekick-render-temp-unsafe.out)"
fi
if python3 "${RENDERER}" render --agent claude --source-root "${PLUGIN_DIR}/skills" --dest-root "${safe_tmp}/claude" >/tmp/sidekick-render-existing.out 2>&1; then
  assert_fail "renderer existing destination guard" "existing destination unexpectedly accepted without --force"
elif grep -Fq "without --force" /tmp/sidekick-render-existing.out; then
  assert_pass "renderer refuses existing destinations without --force"
else
  assert_fail "renderer existing destination guard" "$(cat /tmp/sidekick-render-existing.out)"
fi
if python3 "${RENDERER}" render --agent claude --source-root "${PLUGIN_DIR}/skills" --dest-root "${safe_tmp}/claude" --force >/tmp/sidekick-render-force.out 2>&1; then
  assert_pass "renderer --force replaces existing Sidekick-owned temp destination"
else
  assert_fail "renderer --force temp render" "$(cat /tmp/sidekick-render-force.out)"
fi
rm -rf "${unsafe_tmp}" "${safe_tmp}"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

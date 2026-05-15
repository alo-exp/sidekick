#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — skills/forge/SKILL.md Tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0; SKIP=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
SKILL_FILE="${PLUGIN_DIR}/skills/forge/SKILL.md"

green='\033[0;32m'; red='\033[0;31m'; yellow='\033[0;33m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }
skip()        { echo -e "${yellow}SKIP${reset} $1: $2"; SKIP=$((SKIP+1)); }

if [ ! -f "${SKILL_FILE}" ]; then
  echo "ERROR: ${SKILL_FILE} not found"
  exit 1
fi

echo "=== T1: YAML frontmatter contains name: forge-delegate ==="
grep -q 'name: forge-delegate' "${SKILL_FILE}" && assert_pass "name: forge-delegate present" || assert_fail "YAML frontmatter" "name: forge-delegate not found"

echo "=== T2: Activation section present ==="
grep -q '## Activation' "${SKILL_FILE}" && assert_pass "Activation section present" || assert_fail "Activation section" "not found"

echo "=== T3: Health Check subsection present ==="
grep -q 'Health Check' "${SKILL_FILE}" && assert_pass "Health Check subsection present" || assert_fail "Health Check" "not found"

echo "=== T3b: Credentials schema is array-only ==="
if grep -q "type == \\\"array\\\"" "${SKILL_FILE}" \
  && grep -q 'auth_details' "${SKILL_FILE}" \
  && ! grep -q 'elif type == "object"' "${SKILL_FILE}" \
  && ! grep -q '.api_key' "${SKILL_FILE}"; then
  assert_pass "Credentials schema is array-only"
else
  assert_fail "Credentials schema" "legacy flat schema support still present"
fi

echo "=== T4: Deactivation section present ==="
grep -q 'Deactivat' "${SKILL_FILE}" && assert_pass "Deactivation section present" || assert_fail "Deactivation" "not found"

echo "=== T5: Level 1 fallback section present ==="
grep -q 'Level 1' "${SKILL_FILE}" && assert_pass "Level 1 fallback present" || assert_fail "Level 1 fallback" "not found"

echo "=== T6: Level 2 fallback section present ==="
grep -q 'Level 2' "${SKILL_FILE}" && assert_pass "Level 2 fallback present" || assert_fail "Level 2 fallback" "not found"

echo "=== T7: Level 3 fallback section present ==="
grep -q 'Level 3' "${SKILL_FILE}" && assert_pass "Level 3 fallback present" || assert_fail "Level 3 fallback" "not found"

echo "=== T8: AGENTS.md Mentoring section present ==="
grep -q 'AGENTS.md' "${SKILL_FILE}" && grep -q 'Mentoring' "${SKILL_FILE}" && assert_pass "AGENTS.md Mentoring section present" || assert_fail "AGENTS.md Mentoring" "not found"

echo "=== T9: Token Optimization section present ==="
grep -q 'Token' "${SKILL_FILE}" && grep -q 'Optim' "${SKILL_FILE}" && assert_pass "Token Optimization section present" || assert_fail "Token Optimization" "not found"

echo "=== T10: Skill Injection section present ==="
grep -q 'Skill Injection' "${SKILL_FILE}" && assert_pass "Skill Injection section present" || assert_fail "Skill Injection" "not found"

echo "=== T11: Canonical stop skill note present ==="
if grep -q 'skills/forge-stop/SKILL.md' "${SKILL_FILE}" \
  && grep -qiE 'canonical|source of truth' "${SKILL_FILE}" \
  && ! grep -q 'skills/forge-history/SKILL.md' "${SKILL_FILE}"; then
  assert_pass "Canonical stop skill note present"
else
  assert_fail "Canonical stop note" "missing canonical stop-skill note or stale forge-history reference present"
fi

echo "=== T12: Level 3 fallback uses host project boundary ==="
if grep -q '\$CLAUDE_PROJECT_DIR' "${SKILL_FILE}" \
  && grep -q 'active host project directory' "${SKILL_FILE}" \
  && grep -q 'sidekick forge-level3 start' "${SKILL_FILE}" \
  && grep -q 'sidekick forge-level3 stop' "${SKILL_FILE}" \
  && ! grep -q 'limited to `\$CODEX_PROJECT_DIR` (the Claude Code runtime project directory)' "${SKILL_FILE}"; then
  assert_pass "Level 3 fallback boundary and marker controls are host-aware"
else
  assert_fail "Level 3 fallback boundary" "missing host-aware project boundary, marker controls, or still uses stale Codex-only Claude wording"
fi

echo "=== T13: forge-history skill file removed ==="
if [ ! -f "${PLUGIN_DIR}/skills/forge-history/SKILL.md" ]; then
  assert_pass "forge-history skill file removed"
else
  assert_fail "forge-history removal" "skills/forge-history/SKILL.md still present"
fi

echo "=== T13b: /forge:delegate alias is backed by a shipped skill ==="
FORGE_ALIAS="${PLUGIN_DIR}/skills/forge:delegate/SKILL.md"
if [ -f "${FORGE_ALIAS}" ] \
  && grep -q '^name: forge:delegate' "${FORGE_ALIAS}" \
  && grep -q 'skills/forge/SKILL.md' "${FORGE_ALIAS}" \
  && grep -q '/forge-stop' "${FORGE_ALIAS}"; then
  assert_pass "Forge delegate alias skill present"
else
  assert_fail "Forge delegate alias" "missing /forge:delegate backing skill or canonical references"
fi

echo "=== T14: legacy flat Forge skill has current provider guidance ==="
LEGACY_FLAT="${PLUGIN_DIR}/skills/forge.md"
if [ -f "${LEGACY_FLAT}" ] \
  && grep -q 'user-invocable: false' "${LEGACY_FLAT}" \
  && grep -q 'MiniMax-M2.7' "${LEGACY_FLAT}" \
  && ! grep -qiE 'OpenRouter|open_router|qwen/qwen3-coder-plus|gemma-4' "${LEGACY_FLAT}"; then
  assert_pass "legacy flat Forge skill avoids stale provider promotion"
else
  assert_fail "legacy flat Forge provider guidance" "missing hidden flag/current MiniMax guidance or stale OpenRouter/Qwen/Gemma copy present"
fi

echo "=== T15: legacy flat Forge step references resolve ==="
if [ -f "${LEGACY_FLAT}" ]; then
  missing_steps=()
  for step in 0 0A 1 2 3 4 5 6 7 8 9; do
    if ! grep -q "^## STEP ${step}\\b" "${LEGACY_FLAT}"; then
      missing_steps+=("${step}")
    fi
  done
  if [ "${#missing_steps[@]}" -eq 0 ]; then
    assert_pass "legacy flat Forge step references resolve"
  else
    assert_fail "legacy flat Forge steps" "missing STEP headings: ${missing_steps[*]}"
  fi
else
  assert_fail "legacy flat Forge steps" "skills/forge.md missing"
fi

echo "=== T16: Forge skill uses shared-host actor wording ==="
stale_actor_patterns=(
  'When active, Claude delegates'
  'Claude MUST NOT directly use'
  'Claude reports progress'
  'After each Forge output, Claude runs'
  'Claude rewrites'
  'Claude decomposes'
  'Claude asks the user'
  'Before each delegation, Claude performs'
  'Claude extracts'
  'Claude must formulate'
  'Forge made that Claude fixed'
)
stale_found=()
for pattern in "${stale_actor_patterns[@]}"; do
  if grep -Fq "${pattern}" "${SKILL_FILE}"; then
    stale_found+=("${pattern}")
  fi
done
if [ "${#stale_found[@]}" -eq 0 ]; then
  assert_pass "Forge skill shared-host actor wording"
else
  assert_fail "Forge skill shared-host actor wording" "stale actor phrases present: ${stale_found[*]}"
fi

echo "=== T17: Forge skill documents resume UUID normalization ==="
if grep -q 'preserves that UUID while still normalizing the command' "${SKILL_FILE}" \
  && grep -q 'A `--conversation-id` token after `-p` is treated as prompt text' "${SKILL_FILE}" \
  && ! grep -q 'passes through unchanged (idempotent)' "${SKILL_FILE}"; then
  assert_pass "Forge skill resume UUID wording is current"
else
  assert_fail "Forge skill resume UUID wording" "missing normalization wording or stale idempotent pass-through copy present"
fi

echo "=== T18: Project .forge.toml remains compaction-only ==="
if grep -q 'compaction defaults only' "${SKILL_FILE}" \
  && grep -q '~/forge/.forge.toml' "${SKILL_FILE}" \
  && ! grep -q 'compaction and session defaults' "${SKILL_FILE}"; then
  assert_pass "Project .forge.toml compaction-only wording is current"
else
  assert_fail "Project .forge.toml wording" "missing compaction-only wording or stale session defaults copy present"
fi

echo "=== T19: Forge stop clears Level 3 marker ==="
STOP_SKILL="${PLUGIN_DIR}/skills/forge-stop/SKILL.md"
if grep -q '.forge-level3-active' "${SKILL_FILE}" \
  && grep -q '.forge-level3-active' "${STOP_SKILL}" \
  && grep -q 'sibling' "${STOP_SKILL}" \
  && grep -q 'Level 3 must be re-entered explicitly' "${SKILL_FILE}"; then
  assert_pass "Forge activation and stop workflows clear stale Level 3 state"
else
  assert_fail "Forge Level 3 cleanup wording" "missing stale Level 3 marker cleanup in activation or stop workflow"
fi

echo "=== T20: Forge skill marker paths use shared session resolver ==="
if grep -q 'SIDEKICK_SESSION="${SIDEKICK_SESSION_ID:-${CODEX_THREAD_ID:-${CLAUDE_SESSION_ID:-${SESSION_ID:-}}}}"' "${SKILL_FILE}" \
  && grep -q 'SIDEKICK_SESSION="${SIDEKICK_SESSION_ID:-${CODEX_THREAD_ID:-${CLAUDE_SESSION_ID:-${SESSION_ID:-}}}}"' "${STOP_SKILL}" \
	  && grep -q '\${HOME}/.claude/sessions/\${SIDEKICK_SESSION}/.forge-delegation-active' "${SKILL_FILE}" \
	  && grep -q '\${HOME}/.claude/sessions/\${SIDEKICK_SESSION}/.forge-delegation-active' "${STOP_SKILL}" \
	  && grep -q '\${HOME}/.claude/sessions/\${SIDEKICK_SESSION}/.forge-level3-active' "${STOP_SKILL}" \
	  && grep -q '\${HOME}/.sidekick/sessions/\${SIDEKICK_SESSION}/active-sidekick' "${SKILL_FILE}" \
	  && grep -q '\${HOME}/.kay/sessions/\${SIDEKICK_SESSION}/.kay-delegation-active' "${SKILL_FILE}" \
	  && ! grep -q 'sessions/${CLAUDE_SESSION_ID}/.forge-delegation-active' "${SKILL_FILE}" \
	  && ! grep -q 'sessions/${CLAUDE_SESSION_ID}/.forge-delegation-active' "${STOP_SKILL}"; then
  assert_pass "Forge activation and stop share the hook session resolver"
else
  assert_fail "Forge session resolver" "activation/stop marker paths do not mirror hook session id precedence"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

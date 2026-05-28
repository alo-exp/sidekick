#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Codex and Kay skill surface tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
CODEX_DELEGATE_FILE="${PLUGIN_DIR}/skills/codex-delegate/SKILL.md"
CODEX_DELEGATE_LEGACY_FILE="${PLUGIN_DIR}/skills/codex-delegate.md"
CODEX_STOP_FILE="${PLUGIN_DIR}/skills/codex-stop/SKILL.md"
KAY_DELEGATE_FILE="${PLUGIN_DIR}/skills/kay-delegate/SKILL.md"
KAY_STOP_FILE="${PLUGIN_DIR}/skills/kay-stop/SKILL.md"
KAY_ALIAS_FILE="${PLUGIN_DIR}/skills/kay:delegate/SKILL.md"
REGISTRY_FILE="${PLUGIN_DIR}/sidekicks/registry.json"
REMOVED_CODEX_FILE="${PLUGIN_DIR}/skills/codex/SKILL.md"
REMOVED_CODEX_LEGACY="${PLUGIN_DIR}/skills/codex.md"
REMOVED_HISTORY_FILE="${PLUGIN_DIR}/skills/codex-history/SKILL.md"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

for path in \
  "${CODEX_DELEGATE_FILE}" \
  "${CODEX_DELEGATE_LEGACY_FILE}" \
  "${CODEX_STOP_FILE}" \
  "${KAY_DELEGATE_FILE}" \
  "${KAY_STOP_FILE}" \
  "${KAY_ALIAS_FILE}" \
  "${REGISTRY_FILE}"; do
  [ -f "${path}" ] || { echo "ERROR: ${path} missing"; exit 1; }
done

echo "=== T1: canonical codex-delegate frontmatter ==="
if grep -q '^---$' "${CODEX_DELEGATE_FILE}" \
  && grep -q '^name: codex-delegate' "${CODEX_DELEGATE_FILE}"; then
  assert_pass "codex-delegate frontmatter present"
else
  assert_fail "codex-delegate frontmatter" "missing YAML frontmatter or name: codex-delegate"
fi

echo "=== T2: codex-delegate documents the OpenAI Codex CLI contract ==="
if grep -q 'codex exec' "${CODEX_DELEGATE_FILE}" \
  && grep -q 'gpt-5.4-mini' "${CODEX_DELEGATE_FILE}" \
  && grep -q 'xhigh' "${CODEX_DELEGATE_FILE}" \
  && grep -q -- '--sandbox workspace-write' "${CODEX_DELEGATE_FILE}" \
  && grep -q -- '--ask-for-approval never' "${CODEX_DELEGATE_FILE}" \
  && grep -q 'OpenAI Codex CLI' "${CODEX_DELEGATE_FILE}" \
  && ! grep -q 'kay exec --full-auto' "${CODEX_DELEGATE_FILE}"; then
  assert_pass "codex-delegate documents Codex CLI routing"
else
  assert_fail "codex-delegate routing" "missing Codex CLI command/model/reasoning guidance or still documents Kay runtime"
fi

echo "=== T3: codex-delegate stays canonical and host-neutral ==="
if grep -q 'SIDEKICK_HOST_HOME' "${CODEX_DELEGATE_FILE}" \
  && grep -q 'SIDEKICK_SESSION_ID' "${CODEX_DELEGATE_FILE}" \
  && grep -q 'SIDEKICK_HOST_SESSION_ID' "${CODEX_DELEGATE_FILE}" \
  && grep -q 'CODEX_THREAD_ID' "${CODEX_DELEGATE_FILE}" \
  && grep -q 'CLAUDE_SESSION_ID' "${CODEX_DELEGATE_FILE}" \
  && grep -q '\.codex-delegation-active' "${CODEX_DELEGATE_FILE}" \
  && grep -q '\.sidekick/sessions' "${CODEX_DELEGATE_FILE}" \
  && grep -q 'active-sidekick' "${CODEX_DELEGATE_FILE}" \
  && grep -q 'Codex sidekick mode activated' "${CODEX_DELEGATE_FILE}" \
  && ! grep -q '\.claude/sessions' "${CODEX_DELEGATE_FILE}" \
  && ! grep -q '\.codex/sessions' "${CODEX_DELEGATE_FILE}"; then
  assert_pass "codex-delegate keeps host-neutral activation source"
else
  assert_fail "codex-delegate activation marker" "missing host-neutral session marker flow or still hard-codes a host session path"
fi

echo "=== T4: codex-stop frontmatter and host-neutral marker handling ==="
if grep -q '^---$' "${CODEX_STOP_FILE}" \
  && grep -q '^name: codex-stop' "${CODEX_STOP_FILE}" \
  && grep -q 'SIDEKICK_HOST_HOME' "${CODEX_STOP_FILE}" \
  && grep -q 'SIDEKICK_SESSION_ID' "${CODEX_STOP_FILE}" \
  && grep -q 'SIDEKICK_HOST_SESSION_ID' "${CODEX_STOP_FILE}" \
  && grep -q 'CODEX_THREAD_ID' "${CODEX_STOP_FILE}" \
  && grep -q 'CLAUDE_SESSION_ID' "${CODEX_STOP_FILE}" \
  && grep -q '\.codex-delegation-active' "${CODEX_STOP_FILE}" \
  && grep -q 'active-sidekick' "${CODEX_STOP_FILE}" \
  && grep -q 'Direct-host mode restored' "${CODEX_STOP_FILE}" \
  && ! grep -q '\.claude/sessions' "${CODEX_STOP_FILE}" \
  && ! grep -q '\.codex/sessions' "${CODEX_STOP_FILE}"; then
  assert_pass "codex-stop keeps host-neutral marker workflow"
else
  assert_fail "codex-stop" "missing host-neutral session resolution or still hard-codes a host session path"
fi

echo "=== T5: canonical kay-delegate frontmatter ==="
if grep -q '^---$' "${KAY_DELEGATE_FILE}" \
  && grep -q '^name: kay-delegate' "${KAY_DELEGATE_FILE}"; then
  assert_pass "kay-delegate frontmatter present"
else
  assert_fail "kay-delegate frontmatter" "missing YAML frontmatter or name: kay-delegate"
fi

echo "=== T6: kay-delegate remains the Kay runtime contract ==="
if grep -q 'kay exec --full-auto' "${KAY_DELEGATE_FILE}" \
  && grep -q 'for candidate in kay code coder' "${KAY_DELEGATE_FILE}" \
  && grep -q 'No Kay-compatible runtime found' "${KAY_DELEGATE_FILE}" \
  && grep -q '\.kay-delegation-active' "${KAY_DELEGATE_FILE}" \
  && ! grep -q 'gpt-5.4-mini' "${KAY_DELEGATE_FILE}"; then
  assert_pass "Kay canonical workflow remains Kay-specific"
else
  assert_fail "kay canonical workflow" "missing Kay runtime guidance or polluted with Codex-only routing"
fi

echo "=== T7: kay-stop exists and preserves Kay audit state ==="
if grep -q '^---$' "${KAY_STOP_FILE}" \
  && grep -q '^name: kay-stop' "${KAY_STOP_FILE}" \
  && grep -q '\.kay-delegation-active' "${KAY_STOP_FILE}" \
  && grep -q '\.kay/conversations.idx' "${KAY_STOP_FILE}"; then
  assert_pass "kay-stop marker workflow present"
else
  assert_fail "kay-stop" "missing Kay marker workflow or audit preservation note"
fi

echo "=== T7b: Codex and Kay require post-task host verification and recovery ==="
verification_missing=()
failure_codes=(
  MISSED_REQUIREMENT
  INTEGRATION_ERROR
  REGRESSION
  WRONG_LOGIC
  SYNTAX_ERROR
  WRONG_FILE
  UNVERIFIED_ASSUMPTION
  KNOWLEDGE_GAP
  MISUNDERSTOOD_TASK
  TRIAL_INCOMPLETE
  API_FAILURE
  EXECUTION_ERROR_EXTERNAL
)
for surface in "${CODEX_DELEGATE_FILE}" "${KAY_DELEGATE_FILE}"; do
  for required in \
    'Host Verification and Recovery' \
    'after every sidekick task' \
    'original task prompt' \
    'STATUS: SUCCESS' \
    'relaunch' \
    'handhold'; do
    if ! grep -Fq "${required}" "${surface}"; then
      verification_missing+=("${surface}:${required}")
    fi
  done
  for code in "${failure_codes[@]}"; do
    if ! grep -Fq "\`${code}\`" "${surface}"; then
      verification_missing+=("${surface}:${code}")
    fi
  done
done
if [ "${#verification_missing[@]}" -eq 0 ]; then
  assert_pass "Codex and Kay document host verification taxonomy and relaunch loop"
else
  assert_fail "Codex/Kay host verification" "missing: ${verification_missing[*]}"
fi

echo "=== T8: legacy flat wrapper now points to Codex canonical skill ==="
if grep -q '^---$' "${CODEX_DELEGATE_LEGACY_FILE}" \
  && grep -q '^name: codex-delegate' "${CODEX_DELEGATE_LEGACY_FILE}" \
  && grep -q '^user-invocable: false' "${CODEX_DELEGATE_LEGACY_FILE}" \
  && grep -q 'skills/codex-delegate/SKILL.md' "${CODEX_DELEGATE_LEGACY_FILE}" \
  && grep -qi 'deprecated' "${CODEX_DELEGATE_LEGACY_FILE}" \
  && grep -q '^# Codex' "${CODEX_DELEGATE_LEGACY_FILE}" \
  && ! grep -q '^# Kay' "${CODEX_DELEGATE_LEGACY_FILE}"; then
  assert_pass "legacy codex wrapper points to Codex canonical skill"
else
  assert_fail "legacy codex wrapper" "missing canonical Codex reference, hidden flag, or updated wrapper wording"
fi

echo "=== T9: /kay:delegate alias points at the explicit Kay canonical skill ==="
if grep -q '^name: kay:delegate' "${KAY_ALIAS_FILE}" \
  && grep -q 'skills/kay-delegate/SKILL.md' "${KAY_ALIAS_FILE}" \
  && grep -q '/sidekick:kay-stop' "${KAY_ALIAS_FILE}" \
  && ! grep -q 'skills/codex-delegate/SKILL.md' "${KAY_ALIAS_FILE}"; then
  assert_pass "Kay delegate alias references explicit Kay canonical skill"
else
  assert_fail "Kay delegate alias" "missing /kay:delegate backing skill or still points at codex-delegate"
fi

echo "=== T10: sidekick registry exposes separate Codex and Kay entries ==="
if python3 - "${REGISTRY_FILE}" <<'PY'
import json
import sys

registry = json.load(open(sys.argv[1], "r", encoding="utf-8"))

codex = registry["codex"]
kay = registry["kay"]

assert codex["display_name"] == "Codex"
assert codex["marker_file"] == ".codex/sessions/${CODEX_THREAD_ID}/.codex-delegation-active"
assert codex["idx_dir"] == ".codex"
assert codex["delegate_command"] == "codex exec"
assert codex["stop_command"] == "/sidekick:codex-stop"
assert codex["skill"] == "skills/codex-delegate/SKILL.md"
assert codex["skill_legacy"] == "skills/codex-delegate.md"
assert codex["output_style"] == "output-styles/codex.md"

assert kay["display_name"] == "Kay"
assert kay["skill"] == "skills/kay-delegate/SKILL.md"
assert kay["stop_command"] == "/sidekick:kay-stop"
assert kay["output_style"] == "output-styles/kay.md"
PY
then
  assert_pass "registry separates Codex and Kay runtime surfaces"
else
  assert_fail "sidekick registry" "missing Codex entry or Kay still points at Codex-owned surfaces"
fi

echo "=== T11: removed codex canonical/history skills stay absent ==="
if [ ! -f "${REMOVED_CODEX_FILE}" ] \
  && [ ! -f "${REMOVED_CODEX_LEGACY}" ] \
  && [ ! -f "${REMOVED_HISTORY_FILE}" ]; then
  assert_pass "removed codex legacy/history skill files stay absent"
else
  assert_fail "removed skill files" "one or more removed codex legacy/history files still present"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

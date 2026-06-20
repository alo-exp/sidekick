#!/usr/bin/env bash
# Sidekick Plugin — Cursor install script tests

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
INSTALL_SCRIPT="${REPO_ROOT}/scripts/install-cursor.sh"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

export HOME="${TMP_ROOT}/home"
export CURSOR_HOME="${HOME}/.cursor"
mkdir -p "${HOME}/.claude/plugins" "${CURSOR_HOME}"

echo "=== install_without_merge_leaves_hooks_untouched ==="
printf '{"version":1,"hooks":{"preToolUse":[{"command":"existing-hook"}]}}\n' > "${CURSOR_HOME}/hooks.json"
if bash "${INSTALL_SCRIPT}" --no-register-claude-import >/tmp/sidekick-cursor-install.out 2>&1; then
  if python3 - "${CURSOR_HOME}/hooks.json" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
entries = data.get("hooks", {}).get("preToolUse", [])
assert len(entries) == 1
assert entries[0]["command"] == "existing-hook"
PY
  then
    assert_pass "default install does not merge hooks"
  else
    assert_fail "default install does not merge hooks" "hooks.json was modified unexpectedly"
  fi
else
  assert_fail "default install does not merge hooks" "$(cat /tmp/sidekick-cursor-install.out)"
fi

echo "=== install_merge_hooks_only_updates_sidekick_entries ==="
if bash "${INSTALL_SCRIPT}" --merge-hooks-only --no-register-claude-import >/tmp/sidekick-cursor-merge.out 2>&1; then
  if python3 - "${CURSOR_HOME}/hooks.json" "${CURSOR_HOME}/plugins/cache/alo-labs/sidekick/current" <<'PY'
import json
import sys

hooks_path, install_path = sys.argv[1:3]
data = json.load(open(hooks_path))
entries = data.get("hooks", {}).get("preToolUse", [])
assert any(entry.get("command") == "existing-hook" for entry in entries)
assert any("codex-delegation-enforcer.sh" in entry.get("command", "") for entry in entries)
assert any(install_path in entry.get("command", "") for entry in entries if "codex-delegation-enforcer.sh" in entry.get("command", ""))
PY
  then
    assert_pass "merge-hooks-only preserves existing hooks and adds Sidekick"
  else
    assert_fail "merge-hooks-only preserves existing hooks and adds Sidekick" "$(cat /tmp/sidekick-cursor-merge.out)"
  fi
else
  assert_fail "merge-hooks-only preserves existing hooks and adds Sidekick" "$(cat /tmp/sidekick-cursor-merge.out)"
fi

echo "=== cursor_skill_frontmatter_has_argument_hint ==="
for entry in "kay-delegate:kay" "kay-stop:kay-stop" "codex-delegate:codex" "codex-stop:codex-stop"; do
  skill_path="${entry%%:*}"
  skill_name="${entry##*:}"
  path="${REPO_ROOT}/agents/cursor/${skill_path}/SKILL.md"
  if grep -q '^name: '"${skill_name}"'$' "${path}" \
    && grep -q '^argument-hint:' "${path}"; then
    assert_pass "cursor ${skill_path} frontmatter ready for slash menu"
  else
    assert_fail "cursor ${skill_path} frontmatter ready for slash menu" "missing name or argument-hint in ${path}"
  fi
done

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

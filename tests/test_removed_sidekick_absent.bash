#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin -- removed sidekick absence contract tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

echo "=== T1: Forge runtime and skill surfaces are removed ==="
removed_paths=(
  ".forge"
  ".forge.toml"
  "skills/forge"
  "skills/forge.md"
  "skills/forge-stop"
  "skills/forge:delegate"
  "agents/claude/forge"
  "agents/claude/forge.md"
  "agents/claude/forge-stop"
  "agents/claude/forge:delegate"
  "agents/codex/forge"
  "agents/codex/forge.md"
  "agents/codex/forge-stop"
  "agents/codex/forge:delegate"
  "hooks/forge-delegation-enforcer.sh"
  "hooks/forge-progress-surface.sh"
  "output-styles/forge.md"
)
present=()
for rel in "${removed_paths[@]}"; do
  if [ -e "${PLUGIN_DIR}/${rel}" ]; then
    present+=("${rel}")
  fi
done
if [ "${#present[@]}" -eq 0 ]; then
  assert_pass "Forge runtime, skill, hook, and output-style files are absent"
else
  assert_fail "Forge file removal" "still present: ${present[*]}"
fi

echo "=== T2: registry and plugin manifests no longer expose Forge ==="
if python3 - "${PLUGIN_DIR}" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
registry = json.loads((root / "sidekicks/registry.json").read_text())
claude = json.loads((root / ".claude-plugin/plugin.json").read_text())
codex = json.loads((root / ".codex-plugin/plugin.json").read_text())
marketplace = json.loads((root / ".claude-plugin/marketplace.json").read_text())

assert "forge" not in registry
for manifest in (claude, codex):
    blob = json.dumps(manifest).lower()
    assert "forge" not in blob
    assert "forgecode" not in blob
blob = json.dumps(marketplace).lower()
assert "forge" not in blob
assert "forgecode" not in blob
PY
then
  assert_pass "registry and manifests are Forge-free"
else
  assert_fail "registry/manifests" "Forge still appears in registry or plugin metadata"
fi

echo "=== T3: hooks and runners no longer contain Forge release stages ==="
stale=()
for rel in \
  "hooks/hooks.json" \
  "tests/run_unit.bash" \
  "tests/run_all.bash" \
  "tests/run_release.bash" \
  "tests/test_runner_contract.bash"; do
  if grep -Eqi 'SIDEKICK_LIVE_FORGE|smoke/run_smoke|run_live_e2e|test_forge_(e2e|enforcer|progress|skill|v[0-9])' "${PLUGIN_DIR}/${rel}"; then
    stale+=("${rel}")
  fi
done
if [ "${#stale[@]}" -eq 0 ]; then
  assert_pass "active hooks and release runners no longer reference Forge"
else
  assert_fail "active runner/hook references" "Forge references remain in: ${stale[*]}"
fi

echo "=== T4: public current-state docs no longer advertise Forge ==="
stale_docs=()
for rel in \
  "README.md" \
  "context.md" \
  "site/ARCHITECTURE.md" \
  "site/COMPATIBILITY.md" \
  "site/PRD-Overview.md" \
  "site/GLOSSARY.md" \
  "site/START-HERE.md" \
  "site/TESTING.md" \
  "site/pre-release-quality-gate.md" \
  "site/index.html" \
  "site/help/index.html" \
  "site/help/getting-started/index.html" \
  "site/help/concepts/index.html" \
  "site/help/workflows/index.html" \
  "site/help/reference/index.html" \
  "site/help/troubleshooting/index.html" \
  "site/help/search.js" \
  "site/og-image.html"; do
  if grep -Eqi 'Forge|forge|ForgeCode|/forge|SIDEKICK_LIVE_FORGE' "${PLUGIN_DIR}/${rel}"; then
    stale_docs+=("${rel}")
  fi
done
if [ "${#stale_docs[@]}" -eq 0 ]; then
  assert_pass "current public docs are Forge-free"
else
  assert_fail "public docs" "Forge references remain in: ${stale_docs[*]}"
fi

echo "=== T5: internal packaging guide no longer advertises Forge ==="
if grep -Eqi 'Forge|forge|ForgeCode|/forge|SIDEKICK_LIVE_FORGE' "${PLUGIN_DIR}/site/internal/codex-command-packaging-guide.md"; then
  assert_fail "internal packaging guide" "Forge references remain in site/internal/codex-command-packaging-guide.md"
else
  assert_pass "internal packaging guide is Forge-free"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

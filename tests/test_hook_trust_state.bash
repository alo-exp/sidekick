#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — hook trust seeding regression tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
INSTALL_SH="${PLUGIN_DIR}/install.sh"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

copy_snapshot() {
  local dest="$1"
  mkdir -p "${dest}/hooks/lib" "${dest}/hooks" "${dest}/skills/forge" "${dest}/skills/codex-stop" "${dest}/sidekicks" "${dest}/output-styles" "${dest}/.claude-plugin" "${dest}/.codex-plugin"

  cp "${INSTALL_SH}" "${dest}/install.sh"
  cp "${PLUGIN_DIR}/hooks/hooks.json" "${dest}/hooks/hooks.json"
  cp "${PLUGIN_DIR}/hooks/lib/sidekick-registry.sh" "${dest}/hooks/lib/sidekick-registry.sh"
  cp "${PLUGIN_DIR}/hooks/forge-delegation-enforcer.sh" "${dest}/hooks/forge-delegation-enforcer.sh"
  cp "${PLUGIN_DIR}/hooks/codex-delegation-enforcer.sh" "${dest}/hooks/codex-delegation-enforcer.sh"
  cp "${PLUGIN_DIR}/hooks/scrub-legacy-user-hooks.py" "${dest}/hooks/scrub-legacy-user-hooks.py"
  cp "${PLUGIN_DIR}/hooks/validate-release-gate.sh" "${dest}/hooks/validate-release-gate.sh"
  cp "${PLUGIN_DIR}/skills/forge/SKILL.md" "${dest}/skills/forge/SKILL.md"
  cp "${PLUGIN_DIR}/skills/codex-stop/SKILL.md" "${dest}/skills/codex-stop/SKILL.md"
  cp "${PLUGIN_DIR}/sidekicks/registry.json" "${dest}/sidekicks/registry.json"
  cp "${PLUGIN_DIR}/output-styles/forge.md" "${dest}/output-styles/forge.md"
  cp "${PLUGIN_DIR}/output-styles/codex.md" "${dest}/output-styles/codex.md"
  cp "${PLUGIN_DIR}/.claude-plugin/plugin.json" "${dest}/.claude-plugin/plugin.json"
  cp "${PLUGIN_DIR}/.codex-plugin/plugin.json" "${dest}/.codex-plugin/plugin.json"
}

seed_host_state() {
  local home="$1"

  mkdir -p "${home}/.Codex" "${home}/.codex"

  cat > "${home}/.Codex/config.toml" <<'EOF'
[hooks.state]

[hooks.state."sidekick@alo-labs-codex-local:hooks/hooks.json:session_start:0:0"]
trusted_hash = "sha256:0000000000000000000000000000000000000000000000000000000000000000"

[hooks.state."sidekick@alo-labs-codex-local:hooks/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:1111111111111111111111111111111111111111111111111111111111111111"

[hooks.state."topgun@alo-labs-codex:hooks/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:072e5c1c6aed14dfe251ecc1314ccfd5ad3b806248e4a95aa31a4adbcf07d851"
EOF

  cat > "${home}/.codex/config.toml" <<'EOF'
[hooks.state]

[hooks.state."sidekick@alo-labs-codex-local:hooks/hooks.json:session_start:0:0"]
trusted_hash = "sha256:0000000000000000000000000000000000000000000000000000000000000000"

[hooks.state."sidekick@alo-labs-codex-local:hooks/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:1111111111111111111111111111111111111111111111111111111111111111"

[hooks.state."topgun@alo-labs-codex:hooks/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:072e5c1c6aed14dfe251ecc1314ccfd5ad3b806248e4a95aa31a4adbcf07d851"
EOF

  cat > "${home}/.codex/hooks.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo mirrored-lower"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "echo lower-post"
          }
        ]
      }
    ]
  }
}
EOF

  cat > "${home}/.Codex/hooks.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo mirrored-upper"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "echo upper-pre"
          }
        ]
      }
    ]
  }
}
EOF
}

assert_trust_state() {
  local desc="$1"
  local config_path="$2"
  local package_hooks="$3"
  local codex_lower_hooks="$4"

  if python3 - "$config_path" "$package_hooks" "$codex_lower_hooks" <<'PY' >/dev/null 2>&1
import hashlib
import json
import pathlib
import re
import sys

config_path = pathlib.Path(sys.argv[1])
package_hooks_path = pathlib.Path(sys.argv[2])
lower_hooks_path = pathlib.Path(sys.argv[3])
home = config_path.parent.parent

def event_slug(name: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()

def trusted_hash(command: str) -> str:
    return "sha256:" + hashlib.sha256(command.encode("utf-8")).hexdigest()

def hooks_data_for(path: pathlib.Path) -> dict:
    if not path.is_file():
        return {}
    data = json.loads(path.read_text())
    hooks = data.get("hooks", {})
    return hooks if isinstance(hooks, dict) else {}

expected_sources = {
    "sidekick@alo-labs-codex:hooks/hooks.json": package_hooks_path,
    str(lower_hooks_path): lower_hooks_path,
}

expected = {}
for prefix, source_path in expected_sources.items():
    for event_name, groups in hooks_data_for(source_path).items():
        if not isinstance(groups, list):
            continue
        slug = event_slug(event_name)
        for group_index, group in enumerate(groups):
            if not isinstance(group, dict):
                continue
            hooks = group.get("hooks", [])
            if not isinstance(hooks, list):
                continue
            for hook_index, hook in enumerate(hooks):
                if not isinstance(hook, dict):
                    continue
                key = f"{prefix}:{slug}:{group_index}:{hook_index}"
                expected[key] = trusted_hash(str(hook.get("command", "")))

def parse_state(raw_text: str) -> dict[str, str]:
    state = {}
    current_key = None
    for line in raw_text.splitlines():
        stripped = line.strip()
        match = re.match(r'^\[hooks\.state\."(.+)"\]$', stripped)
        if match:
            current_key = match.group(1)
            continue
        if current_key is not None and stripped.startswith("trusted_hash = "):
            hash_match = re.match(r'^trusted_hash = "(sha256:[0-9a-f]{64})"$', stripped)
            if hash_match:
                state[current_key] = hash_match.group(1)
            continue
        if stripped.startswith("[") and not stripped.startswith('[hooks.state.'):
            current_key = None
    return state

actual = {
    key: digest
    for key, digest in parse_state(config_path.read_text()).items()
    if (
      key.startswith("sidekick@")
      or key.startswith(str(lower_hooks_path))
    )
}

if actual != expected:
    raise SystemExit(1)

if any("sidekick@alo-labs-codex-local" in key for key in parse_state(config_path.read_text())):
    raise SystemExit(1)
PY
  then
    assert_pass "$desc"
  else
    assert_fail "$desc" "hook trust state did not match the exact live source surface"
fi
}

legacy_codex_alias_mode() {
  python3 - "$1" "$2" <<'PY'
import os
from pathlib import Path
import sys

legacy = Path(sys.argv[1])
lower = Path(sys.argv[2])
try:
    print("alias" if os.path.samefile(legacy, lower) else "distinct")
except FileNotFoundError:
    print("missing")
PY
}

WORKDIR="$(mktemp -d "${HOME}/.sidekick-hook-trust.XXXXXX")"
trap 'rm -rf "${WORKDIR}" 2>/dev/null || true' EXIT

SOURCE_SNAPSHOT="${WORKDIR}/source-snapshot"
HOME_DIR="${WORKDIR}/home"
TARGET_ROOT="${HOME_DIR}/.codex/plugins/cache/alo-labs-codex/sidekick/0.5.5"
LEGACY_BACKUP_ROOT="${HOME_DIR}/.codex/legacy-uppercase-backups"

copy_snapshot "${SOURCE_SNAPSHOT}"
seed_host_state "${HOME_DIR}"

mkdir -p "${TARGET_ROOT}"

echo "=== T1: clean reinstall seeds trust from the exact package-local and mirrored hook sources ==="
if env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_SESSION_ID -u CLAUDE_PROJECT_DIR -u CLAUDE_THREAD_ID \
  HOME="${HOME_DIR}" \
  SIDEKICK_PLUGIN_ROOT="${SOURCE_SNAPSHOT}" \
  CODEX_PLUGIN_ROOT="${TARGET_ROOT}" \
  SIDEKICK_CLEAN_REINSTALL=1 \
  SIDEKICK_INSTALL_FORGE=0 \
  SIDEKICK_INSTALL_CODE=0 \
  bash "${SOURCE_SNAPSHOT}/install.sh" >/tmp/sidekick-hook-trust-1.out 2>/tmp/sidekick-hook-trust-1.err
then
  assert_pass "clean reinstall completed"
else
  assert_fail "clean reinstall" "installer failed on the trust-seeding pass"
  cat /tmp/sidekick-hook-trust-1.out 2>/dev/null || true
  cat /tmp/sidekick-hook-trust-1.err 2>/dev/null || true
  exit 1
fi

assert_trust_state "trust seeded from package-local and mirrored hook sources" \
  "${HOME_DIR}/.codex/config.toml" \
  "${TARGET_ROOT}/hooks/hooks.json" \
  "${HOME_DIR}/.codex/hooks.json"

if [ -d "${LEGACY_BACKUP_ROOT}" ] && [ -n "$(find "${LEGACY_BACKUP_ROOT}" -mindepth 1 -maxdepth 2 -type f -print -quit 2>/dev/null)" ]; then
  assert_pass "legacy uppercase Codex state was archived under the lowercase backup root"
else
  assert_fail "legacy uppercase backup" "backup archive missing after clean reinstall"
fi

LEGACY_ALIAS_MODE="$(legacy_codex_alias_mode "${HOME_DIR}/.Codex" "${HOME_DIR}/.codex")"
if [ "${LEGACY_ALIAS_MODE}" = "alias" ] || [ ! -e "${HOME_DIR}/.Codex" ]; then
  assert_pass "uppercase ~/.Codex is treated as migration-only after the lowercase install becomes valid"
else
  assert_fail "uppercase retirement" "~/.Codex is still present as an active path"
fi

FIRST_PASS_CONFIG="${WORKDIR}/config.after-first-pass.toml"
FIRST_PASS_LOWER_CONFIG="${WORKDIR}/config.after-first-pass.lower.toml"
cp "${HOME_DIR}/.codex/config.toml" "${FIRST_PASS_CONFIG}"
cp "${HOME_DIR}/.codex/config.toml" "${FIRST_PASS_LOWER_CONFIG}"

echo "=== T2: reinstall is stable and does not reintroduce hook-review churn ==="
if env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_SESSION_ID -u CLAUDE_PROJECT_DIR -u CLAUDE_THREAD_ID \
  HOME="${HOME_DIR}" \
  SIDEKICK_PLUGIN_ROOT="${SOURCE_SNAPSHOT}" \
  CODEX_PLUGIN_ROOT="${TARGET_ROOT}" \
  SIDEKICK_CLEAN_REINSTALL=1 \
  SIDEKICK_INSTALL_FORGE=0 \
  SIDEKICK_INSTALL_CODE=0 \
  bash "${SOURCE_SNAPSHOT}/install.sh" >/tmp/sidekick-hook-trust-2.out 2>/tmp/sidekick-hook-trust-2.err
then
  assert_pass "second clean reinstall completed"
else
  assert_fail "second clean reinstall" "installer failed on the stability pass"
  cat /tmp/sidekick-hook-trust-2.out 2>/dev/null || true
  cat /tmp/sidekick-hook-trust-2.err 2>/dev/null || true
  exit 1
fi

if cmp -s "${FIRST_PASS_CONFIG}" "${HOME_DIR}/.codex/config.toml"; then
  assert_pass "hook trust state is stable across reinstall"
else
  assert_fail "stable hook trust state" "config.toml changed on the second clean reinstall"
fi

if cmp -s "${FIRST_PASS_LOWER_CONFIG}" "${HOME_DIR}/.codex/config.toml"; then
  assert_pass "lower host trust state is stable across reinstall"
else
  assert_fail "stable lower host trust state" "lower config.toml changed on the second clean reinstall"
fi

if grep -Fq 'topgun@alo-labs-codex' "${HOME_DIR}/.codex/config.toml"; then
  assert_pass "unrelated trust state is preserved"
else
  assert_fail "unrelated trust state" "topgun trust entry was lost"
fi

LEGACY_ALIAS_MODE="$(legacy_codex_alias_mode "${HOME_DIR}/.Codex" "${HOME_DIR}/.codex")"
if [ "${LEGACY_ALIAS_MODE}" = "alias" ] || [ ! -e "${HOME_DIR}/.Codex" ]; then
  assert_pass "uppercase ~/.Codex remains migration-only after the second reinstall"
else
  assert_fail "uppercase retirement" "~/.Codex returned during the second reinstall"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

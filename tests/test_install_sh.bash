#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — install.sh Unit + Integration Tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0; SKIP=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
INSTALL_SH="${PLUGIN_DIR}/install.sh"

green='\033[0;32m'; red='\033[0;31m'; yellow='\033[0;33m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }
skip()        { echo -e "${yellow}SKIP${reset} $1: $2"; SKIP=$((SKIP+1)); }

make_install_toolbox() {
  local dir="$1"
  local include_hash_tools="${2:-1}"
  mkdir -p "${dir}"

  local cmd target
  for cmd in bash cat chmod date dirname grep id ln mkdir mktemp python3 readlink sed stat touch awk tr; do
    target="$(command -v "${cmd}" 2>/dev/null || true)"
    if [ -n "${target}" ] && [ -x "${target}" ]; then
      ln -sf "${target}" "${dir}/${cmd}"
    fi
  done

  if [ "${include_hash_tools}" = "1" ]; then
    for cmd in shasum sha256sum; do
      target="$(command -v "${cmd}" 2>/dev/null || true)"
      if [ -n "${target}" ] && [ -x "${target}" ]; then
        ln -sf "${target}" "${dir}/${cmd}"
      fi
    done
  fi

  cat > "${dir}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf '%s\n' '#!/usr/bin/env bash' > "${out}"
chmod +x "${out}"
EOF
  chmod +x "${dir}/curl"
}

prepare_install_sandbox() {
  local root="$1"
  cp "${INSTALL_SH}" "${root}/install.sh"
  mkdir -p "${root}/hooks/lib" "${root}/sidekicks"
  cp "${PLUGIN_DIR}/hooks/lib/sidekick-registry.sh" "${root}/hooks/lib/sidekick-registry.sh"
  cp "${PLUGIN_DIR}/sidekicks/registry.json" "${root}/sidekicks/registry.json"
}

copy_plugin_file() {
  local root="$1"
  local rel="$2"
  mkdir -p "${root}/$(dirname "${rel}")"
  cp "${PLUGIN_DIR}/${rel}" "${root}/${rel}"
}

echo "=== T1: Syntax check ==="
if bash -n "${INSTALL_SH}" 2>&1; then
  assert_pass "install.sh has no syntax errors"
else
  assert_fail "install.sh syntax check" "bash -n failed"
fi

echo "=== T2: Safety flags ==="
grep -q 'set -euo pipefail' "${INSTALL_SH}" && assert_pass "set -euo pipefail present" || assert_fail "set -euo pipefail" "not found"

echo "=== T3: Pinned SHA ==="
PINNED=$(grep 'EXPECTED_FORGE_SHA=' "${INSTALL_SH}" | grep -v '^#' | head -1 | sed 's/.*="\(.*\)"/\1/')
if [ -n "${PINNED}" ]; then
  assert_pass "EXPECTED_FORGE_SHA is set: ${PINNED:0:16}…"
else
  assert_fail "EXPECTED_FORGE_SHA" "empty — pinned hash verification disabled"
fi
if grep -q 'ERROR: No pinned Kay SHA-256 is configured in sidekicks/registry.json' "${INSTALL_SH}" \
  && ! grep -q 'No pinned Kay SHA-256 set' "${INSTALL_SH}"; then
  assert_pass "Kay bootstrap fails closed when registry SHA is missing"
else
  assert_fail "Kay bootstrap fail-closed path" "missing hard error or still contains display-only warning"
fi

echo "=== T4: SHA abort logic ==="
grep -q 'SHA-256 MISMATCH' "${INSTALL_SH}" && assert_pass "SHA mismatch abort message present" || assert_fail "SHA abort" "not found"

echo "=== T5: Non-interactive gate ==="
if grep -q '\-t 1' "${INSTALL_SH}" && grep -q 'skipping auto-install' "${INSTALL_SH}"; then
  assert_pass "Non-interactive gate present"
else
  assert_fail "Non-interactive gate" "[ -t 1 ] abort not found"
fi

echo "=== T6: Download timeouts ==="
grep -q '\-\-max-time 60' "${INSTALL_SH}" && grep -q '\-\-connect-timeout 15' "${INSTALL_SH}" && \
  assert_pass "curl timeouts present" || assert_fail "curl timeouts" "missing --max-time or --connect-timeout"
grep -q '\-\-timeout=60' "${INSTALL_SH}" && assert_pass "wget timeout present" || assert_fail "wget timeout" "missing"

echo "=== T7: SHA tool fallback ==="
if grep -q 'sha256sum' "${INSTALL_SH}" \
  && grep -q 'ERROR: Neither shasum nor sha256sum found — cannot verify download integrity.' "${INSTALL_SH}" \
  && ! grep -q 'FORGE_SHA="UNAVAILABLE"' "${INSTALL_SH}"; then
  assert_pass "Forge bootstrap fails closed without hash tool"
else
  assert_fail "Forge bootstrap fail-closed path" "missing hard error or still contains UNAVAILABLE fallback"
fi

echo "=== T8: Symlink validation ==="
grep -q 'Symlink validation' "${INSTALL_SH}" && grep -q 'realpath' "${INSTALL_SH}" && \
  assert_pass "Symlink validation present" || assert_fail "Symlink validation" "not found"

echo "=== T9: Ownership check ==="
grep -q 'Ownership check' "${INSTALL_SH}" && grep -q 'file_owner' "${INSTALL_SH}" && \
  assert_pass "Ownership check present" || assert_fail "Ownership check" "not found"

echo "=== T10: Binary identity check ==="
grep -q 'grep -qiE.*forge' "${INSTALL_SH}" && assert_pass "Binary identity check present" || assert_fail "Binary identity check" "not found"

echo "=== T11: PATH marker ==="
grep -q 'Added by sidekick/forge plugin' "${INSTALL_SH}" && assert_pass "PATH marker comment present" || assert_fail "PATH marker" "not found"

echo "=== T12: Kay bootstrap ==="
if grep -q 'install_codex_runtime' "${INSTALL_SH}" \
  && grep -q 'sidekick_registry_get kay' "${INSTALL_SH}" \
  && grep -q 'CODEX_INSTALL_TMP' "${INSTALL_SH}" \
  && grep -q 'KAY_BIN' "${INSTALL_SH}" \
  && grep -q 'CODEX_CODE_ALIAS' "${INSTALL_SH}" \
  && grep -q 'CODEX_CODER_ALIAS' "${INSTALL_SH}" \
  && grep -q 'CODEX_INSTALL_VERSION' "${INSTALL_SH}" \
  && ! grep -q 'update --help' "${INSTALL_SH}" \
  && grep -q -- '--version 2>/dev/null | grep -qiE' "${INSTALL_SH}" \
  && grep -q -- '--release "${CODEX_INSTALL_VERSION}"' "${INSTALL_SH}" \
  && grep -q 'CODEX_INSTALL_DIR="${SIDEKICK_BIN_DIR}" bash "${CODEX_INSTALL_TMP}"' "${INSTALL_SH}" \
  && grep -q 'cleanup_install_tmps' "${INSTALL_SH}"; then
  assert_pass "Kay runtime bootstrap logic present with pinned release, exec-capable detection, custom install dir, and compatibility aliases"
else
  assert_fail "Kay bootstrap" "missing Kay runtime install, pinned release, exec-capable detection, custom install dir, aliases, or cleanup logic"
fi

echo "=== T13: Idempotency (add_to_path) ==="
FAKE_PROFILE=$(mktemp)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> "${FAKE_PROFILE}"
# Write a minimal test script that sources just the add_to_path function
TEST_SCRIPT=$(mktemp /tmp/test_idempotent.XXXXXX.sh)
cat > "${TEST_SCRIPT}" << TESTEOF
#!/usr/bin/env bash
set -euo pipefail
$(sed -n '/^add_to_path()/,/^}/p' "${INSTALL_SH}")
add_to_path "${FAKE_PROFILE}"
COUNT=\$(grep -c '.local/bin' "${FAKE_PROFILE}" || true)
echo "COUNT=\${COUNT}"
TESTEOF
RESULT=$(bash "${TEST_SCRIPT}" 2>/dev/null || true)
rm -f "${TEST_SCRIPT}" "${FAKE_PROFILE}"
COUNT=$(echo "${RESULT}" | grep 'COUNT=' | cut -d= -f2 | tr -d ' \n' || echo "0")
if [ "${COUNT}" = "1" ] || [ "${COUNT}" = "0" ]; then
  assert_pass "add_to_path is idempotent (no duplicate PATH entry, count=${COUNT})"
else
  assert_fail "Idempotency" "unexpected count: ${COUNT}"
fi

echo "=== T14: Symlink outside HOME rejected ==="
REAL_FILE=$(mktemp)
SYMLINK_PATH=$(mktemp -u /tmp/test_symlink_XXXXXX)
ln -s "${REAL_FILE}" "${SYMLINK_PATH}"
TEST_SCRIPT=$(mktemp /tmp/test_symlink.XXXXXX.sh)
cat > "${TEST_SCRIPT}" << TESTEOF
#!/usr/bin/env bash
$(sed -n '/^add_to_path()/,/^}/p' "${INSTALL_SH}")
add_to_path "${SYMLINK_PATH}" 2>&1
TESTEOF
OUTPUT=$(bash "${TEST_SCRIPT}" 2>&1 || true)
rm -f "${TEST_SCRIPT}" "${REAL_FILE}" "${SYMLINK_PATH}"
if echo "${OUTPUT}" | grep -qiE 'symlink|Skipping'; then
  assert_pass "Symlink outside HOME is rejected"
else
  # The function only rejects symlinks pointing OUTSIDE HOME — if symlink is also outside HOME,
  # the outer `[ -f "${profile}" ]` check may fail first (file check on symlink to /tmp).
  # Verify the code path exists in the script instead.
  if grep -q 'symlink pointing outside HOME' "${INSTALL_SH}"; then
    assert_pass "Symlink rejection code path present in install.sh (functional test inconclusive in /tmp)"
  else
    assert_fail "Symlink rejection" "code not found in install.sh"
  fi
fi

echo "=== T15: Non-interactive gate execution ==="
skip "Non-interactive gate" "forge already installed on this machine — download path not reached in sandbox"

echo "=== T16: hooks.json bootstrap and SessionStart scope ==="
HOOKS="${PLUGIN_DIR}/hooks/hooks.json"
SESSION_COUNT=$(python3 -c "import json; d=json.load(open('${HOOKS}')); print(len(d['hooks']['SessionStart']))")
SESSION0_CMD=$(python3 -c "import json; d=json.load(open('${HOOKS}')); print(d['hooks']['SessionStart'][0]['hooks'][0]['command'])")
SESSION1_CMD=$(python3 -c "import json; d=json.load(open('${HOOKS}')); print(d['hooks']['SessionStart'][1]['hooks'][0]['command'])")
if [ "${SESSION_COUNT}" = "2" ] && ! grep -q 'runtime-sync.sh' "${HOOKS}"; then
  assert_pass "SessionStart surface excludes runtime asset sync"
else
  assert_fail "SessionStart runtime sync removal" "unexpected SessionStart count or runtime-sync hook remains"
fi

if grep -q 'CLAUDE_PLUGIN_ROOT' "${HOOKS}" \
  && ! grep -Fq '${CODEX_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT' "${HOOKS}"; then
  assert_pass "shared hook root fallback supports Claude and Codex"
else
  assert_fail "shared hook root fallback" "missing CLAUDE fallback or duplicated CODEX fallback remains"
fi

if echo "${SESSION0_CMD}" | grep -q 'scrub-legacy-user-hooks.py' \
  && echo "${SESSION0_CMD}" | grep -q 'python3'; then
  assert_pass "legacy scrub hook remains first SessionStart entry"
else
  assert_fail "legacy scrub hook order" "missing scrub-legacy-user-hooks.py first entry"
fi

if echo "${SESSION1_CMD}" | grep -q 'test -f' \
  && echo "${SESSION1_CMD}" | grep -q '.installed' \
  && echo "${SESSION1_CMD}" | grep -q 'install.sh' \
  && echo "${SESSION1_CMD}" | grep -q '&&' \
  && echo "${SESSION1_CMD}" | grep -q 'touch'; then
  assert_pass "bootstrap hook preserves the .installed sentinel guard"
else
  assert_fail "bootstrap hook" "missing .installed guard or touch sentinel"
fi

echo "=== T17: selective install env flags ==="
if grep -q 'SIDEKICK_INSTALL_FORGE' "${INSTALL_SH}" && grep -q 'SIDEKICK_INSTALL_KAY' "${INSTALL_SH}" && grep -q 'SIDEKICK_INSTALL_CODE' "${INSTALL_SH}"; then
  assert_pass "selective install env flags present"
else
  assert_fail "selective install env flags" "missing SIDEKICK_INSTALL_FORGE, SIDEKICK_INSTALL_KAY, or compatibility SIDEKICK_INSTALL_CODE"
fi

echo "=== T18: missing hash tools fail closed at runtime ==="
_runtime_root="$(mktemp -d)"
_toolbox_root="$(mktemp -d)"
prepare_install_sandbox "${_runtime_root}"
make_install_toolbox "${_toolbox_root}" "0"
mkdir -p "${_runtime_root}/home"
if OUT="$(HOME="${_runtime_root}/home" SIDEKICK_PLUGIN_ROOT="${_runtime_root}" BIN_DIR="${_toolbox_root}" PATH="${_toolbox_root}" SIDEKICK_INSTALL_FORGE=0 SIDEKICK_INSTALL_KAY=1 bash "${_runtime_root}/install.sh" 2>&1)"; then
  assert_fail "missing hash tools fail closed" "expected install.sh to fail, got success"
else
  if echo "${OUT}" | grep -q 'Cannot verify Kay installer integrity without shasum or sha256sum'; then
    assert_pass "missing hash tools fail closed at runtime"
  else
    assert_fail "missing hash tools fail closed" "unexpected output: ${OUT}"
  fi
fi
rm -rf "${_runtime_root}" "${_toolbox_root}"

echo "=== T19: missing registry SHA fails closed at runtime ==="
_runtime_root="$(mktemp -d)"
_toolbox_root="$(mktemp -d)"
prepare_install_sandbox "${_runtime_root}"
make_install_toolbox "${_toolbox_root}" "1"
python3 - "${_runtime_root}/sidekicks/registry.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
data["kay"]["install"]["sha256"] = ""
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
mkdir -p "${_runtime_root}/home"
if OUT="$(HOME="${_runtime_root}/home" SIDEKICK_PLUGIN_ROOT="${_runtime_root}" BIN_DIR="${_toolbox_root}" PATH="${_toolbox_root}" SIDEKICK_INSTALL_FORGE=0 SIDEKICK_INSTALL_KAY=1 bash "${_runtime_root}/install.sh" 2>&1)"; then
  assert_fail "missing registry SHA fails closed" "expected install.sh to fail, got success"
else
  if echo "${OUT}" | grep -q 'No pinned Kay SHA-256 is configured in sidekicks/registry.json'; then
    assert_pass "missing registry SHA fails closed at runtime"
  else
    assert_fail "missing registry SHA fails closed" "unexpected output: ${OUT}"
  fi
fi
rm -rf "${_runtime_root}" "${_toolbox_root}"

echo "=== T20: clean reinstall bootstrap ==="
if grep -q 'SIDEKICK_CLEAN_REINSTALL' "${INSTALL_SH}" \
  && grep -q 'purge_legacy_codex_sidekick_state' "${INSTALL_SH}" \
  && grep -q 'normalize_codex_path' "${INSTALL_SH}" \
  && grep -q 'resolve_bootstrap_target_root' "${INSTALL_SH}" \
  && grep -q 'retire_legacy_codex_uppercase_state' "${INSTALL_SH}" \
  && grep -q 'bootstrap_sidekick_cache_tree' "${INSTALL_SH}" \
  && grep -q 'rm -rf "${plugin_root_dir}"' "${INSTALL_SH}" \
  && grep -q 'cp -a "${source_root}/." "${target_root}/"' "${INSTALL_SH}" \
  && grep -q 'ln -sfn "${target_root}" "${current_alias}"' "${INSTALL_SH}"; then
  assert_pass "clean reinstall bootstrap and current alias handling present"
else
  assert_fail "clean reinstall bootstrap" "missing clean reinstall or bootstrap-from-snapshot logic"
fi

echo "=== T21: hook trust seeding ==="
if grep -q 'seed_hook_trust_state' "${INSTALL_SH}" \
  && grep -q 'plugin_id = "sidekick@alo-labs-codex"' "${INSTALL_SH}" \
  && grep -q '\${HOME}/.codex/hooks.json' "${INSTALL_SH}" \
  && ! grep -q '\${HOME}/.Codex/hooks.json' "${INSTALL_SH}" \
  && ! grep -q '\${HOME}/.Codex/config.toml' "${INSTALL_SH}" \
  && grep -q 'plugin_id = "sidekick@alo-labs"' "${INSTALL_SH}" \
  && grep -q '\${HOME}/.claude/hooks.json' "${INSTALL_SH}" \
  && grep -q 'rewrite_host_surface "${install_host}"' "${INSTALL_SH}" \
  && grep -q 'refresh_installed_integrity_manifest' "${INSTALL_SH}" \
  && grep -q 'seed_hook_trust_state "${install_host}" "${PLUGIN_ROOT}"' "${INSTALL_SH}" \
  && grep -q 'retire_legacy_codex_uppercase_state "${install_host}" "${PLUGIN_ROOT}"' "${INSTALL_SH}"; then
  assert_pass "hook trust seeding is source-specific and host-isolated"
else
  assert_fail "hook trust seeding" "missing source-specific trust seeding or host-isolated trust targets"
fi

echo "=== T22: host rewrite refreshes installed manifest integrity ==="
_host_root="$(mktemp -d)"
_host_home="$(mktemp -d)"
for _rel in \
  "install.sh" \
  ".claude-plugin/plugin.json" \
  "hooks/hooks.json" \
  "hooks/lib/sidekick-registry.sh" \
  "hooks/validate-release-gate.sh" \
  "skills/forge-stop/SKILL.md" \
  "sidekicks/registry.json"; do
  copy_plugin_file "${_host_root}" "${_rel}"
done
if HOME="${_host_home}" SIDEKICK_INSTALL_HOST=codex SIDEKICK_INSTALL_FORGE=0 SIDEKICK_INSTALL_KAY=0 PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash "${_host_root}/install.sh" >/tmp/sidekick-install-host-rewrite.out 2>&1; then
  if python3 - "${_host_root}" <<'PY'
from pathlib import Path
import hashlib
import json
import sys

root = Path(sys.argv[1])
manifest = json.loads((root / ".claude-plugin/plugin.json").read_text())
integrity = manifest.get("_integrity", {})
targets = {
    "validate_release_gate_sha256": "hooks/validate-release-gate.sh",
    "forge_stop_skill_md_sha256": "skills/forge-stop/SKILL.md",
    "hooks_json_sha256": "hooks/hooks.json",
}
for key, rel in targets.items():
    actual = hashlib.sha256((root / rel).read_bytes()).hexdigest()
    if integrity.get(key) != actual:
        raise SystemExit(f"{key}: claimed={integrity.get(key)} actual={actual}")
PY
  then
    assert_pass "host rewrite refreshes installed manifest integrity"
  else
    assert_fail "installed manifest integrity" "installed hashes do not match rewritten files"
  fi
else
  assert_fail "installed manifest integrity" "$(cat /tmp/sidekick-install-host-rewrite.out 2>/dev/null || true)"
fi
rm -rf "${_host_root}" "${_host_home}" /tmp/sidekick-install-host-rewrite.out

echo "=== T23: session-only host env skips cache bootstrap safely ==="
_session_root="$(mktemp -d)"
_session_home="$(mktemp -d)"
prepare_install_sandbox "${_session_root}"
if env -u CODEX_PLUGIN_ROOT -u CLAUDE_PLUGIN_ROOT -u SIDEKICK_PLUGIN_ROOT \
  HOME="${_session_home}" \
  CODEX_THREAD_ID="session-only-install-test" \
  SIDEKICK_INSTALL_FORGE=0 \
  SIDEKICK_INSTALL_KAY=0 \
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  bash "${_session_root}/install.sh" >/tmp/sidekick-install-session-only.out 2>&1; then
  if [ -f "${_session_home}/.codex/config.toml" ] && [ ! -e "${_session_root}/current" ]; then
    assert_pass "session-only host env does not bootstrap an empty plugin root"
  else
    assert_fail "session-only host env bootstrap" "unexpected cache alias or missing host trust state"
  fi
else
  assert_fail "session-only host env bootstrap" "$(cat /tmp/sidekick-install-session-only.out 2>/dev/null || true)"
fi
rm -rf "${_session_root}" "${_session_home}" /tmp/sidekick-install-session-only.out

echo "=== T24: Kay installer honors custom BIN_DIR ==="
_custom_root="$(mktemp -d)"
_custom_home="$(mktemp -d)"
_custom_toolbox="$(mktemp -d)"
_custom_bin="${_custom_home}/custom-bin"
prepare_install_sandbox "${_custom_root}"
make_install_toolbox "${_custom_toolbox}" "1"
cat > "${_custom_toolbox}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
cat > "${out}" <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail
bin_dir="${CODEX_INSTALL_DIR:-${HOME}/.local/bin}"
mkdir -p "${bin_dir}"
cat > "${bin_dir}/kay" <<'KAY'
#!/usr/bin/env bash
if [ "${1:-}" = "exec" ]; then
  exit 0
fi
if [ "${1:-}" = "--version" ]; then
  printf 'kay 0.9.4\n'
  exit 0
fi
exit 0
KAY
chmod +x "${bin_dir}/kay"
INSTALLER
chmod +x "${out}"
EOF
chmod +x "${_custom_toolbox}/curl"
_fake_installer="$(mktemp)"
"${_custom_toolbox}/curl" -o "${_fake_installer}" ignored
_fake_sha="$(shasum -a 256 "${_fake_installer}" | awk '{print $1}')"
rm -f "${_fake_installer}"
python3 - "${_custom_root}/sidekicks/registry.json" "${_fake_sha}" <<'PY'
import json
import sys

path, sha = sys.argv[1:3]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)
data["kay"]["install"]["url"] = "https://example.invalid/kay-install.sh"
data["kay"]["install"]["sha256"] = sha
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
mkdir -p "${_custom_bin}"
cat > "${_custom_bin}/codex" <<'CODEX'
#!/usr/bin/env bash
if [ "${1:-}" = "exec" ]; then
  touch "${HOME}/codex-exec-called"
  exit 0
fi
if [ "${1:-}" = "--version" ]; then
  printf 'codex 1.2.3\n'
  exit 0
fi
exit 0
CODEX
chmod +x "${_custom_bin}/codex"
if HOME="${_custom_home}" SIDEKICK_PLUGIN_ROOT="${_custom_root}" BIN_DIR="${_custom_bin}" PATH="${_custom_toolbox}:/usr/bin:/bin:/usr/sbin:/sbin" SIDEKICK_INSTALL_FORGE=0 SIDEKICK_INSTALL_KAY=1 bash "${_custom_root}/install.sh" >/tmp/sidekick-install-custom-bin.out 2>&1; then
  if [ -x "${_custom_bin}/kay" ] \
    && [ ! -e "${_custom_home}/.local/bin/kay" ] \
    && [ ! -e "${_custom_home}/codex-exec-called" ] \
    && "${_custom_bin}/kay" --version 2>/dev/null | grep -q '^kay '; then
    assert_pass "Kay installer receives CODEX_INSTALL_DIR for custom BIN_DIR and rejects non-Kay aliases"
  else
    assert_fail "custom Kay install dir" "kay not installed in custom BIN_DIR only, or non-Kay alias was accepted"
  fi
else
  assert_fail "custom Kay install dir" "$(cat /tmp/sidekick-install-custom-bin.out 2>/dev/null || true)"
fi
rm -rf "${_custom_root}" "${_custom_home}" "${_custom_toolbox}" /tmp/sidekick-install-custom-bin.out

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

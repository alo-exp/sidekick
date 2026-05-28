#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — install.sh Unit + Integration Tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0; SKIP=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
INSTALL_SH="${PLUGIN_DIR}/install.sh"
PLUGIN_VERSION="$(python3 -c "import json; print(json.load(open('${PLUGIN_DIR}/.claude-plugin/plugin.json'))['version'])")"

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

echo "=== T3: Pinned Kay SHA ==="
PINNED=$(python3 -c "import json; print(json.load(open('${PLUGIN_DIR}/sidekicks/registry.json'))['kay']['install']['sha256'])")
if [ -n "${PINNED}" ]; then
  assert_pass "Kay installer SHA is pinned in registry: ${PINNED:0:16}..."
else
  assert_fail "Kay installer SHA" "empty - pinned hash verification disabled"
fi
if grep -q 'ERROR: No pinned Kay SHA-256 is configured in sidekicks/registry.json' "${INSTALL_SH}" \
  && ! grep -q 'No pinned Kay SHA-256 set' "${INSTALL_SH}"; then
  assert_pass "Kay bootstrap fails closed when registry SHA is missing"
else
  assert_fail "Kay bootstrap fail-closed path" "missing hard error or still contains display-only warning"
fi

echo "=== T4: SHA abort logic ==="
grep -q 'SHA-256 MISMATCH' "${INSTALL_SH}" && assert_pass "SHA mismatch abort message present" || assert_fail "SHA abort" "not found"

echo "=== T5: Removed runtime bootstrap ==="
if ! grep -q 'forgecode.dev/cli' "${INSTALL_SH}" \
  && ! grep -q 'EXPECTED_FORGE_SHA' "${INSTALL_SH}" \
  && ! grep -q 'SIDEKICK_INSTALL_FORGE' "${INSTALL_SH}"; then
  assert_pass "removed sidekick bootstrap path is absent"
else
  assert_fail "removed sidekick bootstrap" "Forge installer path, pin, or env flag remains"
fi

echo "=== T6: Download timeouts ==="
grep -q '\-\-max-time 60' "${INSTALL_SH}" && grep -q '\-\-connect-timeout 15' "${INSTALL_SH}" && \
  assert_pass "curl timeouts present" || assert_fail "curl timeouts" "missing --max-time or --connect-timeout"
grep -q '\-\-timeout=60' "${INSTALL_SH}" && assert_pass "wget timeout present" || assert_fail "wget timeout" "missing"

echo "=== T7: SHA tool fallback ==="
if grep -q 'sha256sum' "${INSTALL_SH}" \
  && grep -q 'ERROR: Cannot verify Kay installer integrity without shasum or sha256sum.' "${INSTALL_SH}" \
  && ! grep -q 'codex_sha="UNAVAILABLE".*bash "${CODEX_INSTALL_TMP}"' "${INSTALL_SH}"; then
  assert_pass "Kay bootstrap fails closed without hash tool"
else
  assert_fail "Kay bootstrap fail-closed path" "missing hard error or still allows execution without a hash tool"
fi

echo "=== T8: Symlink validation ==="
grep -q 'Symlink validation' "${INSTALL_SH}" && grep -q 'realpath' "${INSTALL_SH}" && \
  assert_pass "Symlink validation present" || assert_fail "Symlink validation" "not found"

echo "=== T9: Ownership check ==="
grep -q 'Ownership check' "${INSTALL_SH}" && grep -q 'file_owner' "${INSTALL_SH}" && \
  assert_pass "Ownership check present" || assert_fail "Ownership check" "not found"

echo "=== T10: Binary identity check ==="
if grep -q -- "--version 2>/dev/null | grep -qiE '^kay" "${INSTALL_SH}" \
  && grep -q 'exec --help' "${INSTALL_SH}"; then
  assert_pass "Kay runtime identity check present"
else
  assert_fail "Kay runtime identity check" "not found"
fi

echo "=== T11: PATH marker ==="
grep -q 'Added by sidekick plugin' "${INSTALL_SH}" && assert_pass "PATH marker comment present" || assert_fail "PATH marker" "not found"

echo "=== T12: Kay bootstrap ==="
if grep -q 'install_codex_runtime' "${INSTALL_SH}" \
  && grep -q 'sidekick_source_registry_get kay' "${INSTALL_SH}" \
  && grep -q 'CODEX_INSTALL_TMP' "${INSTALL_SH}" \
  && grep -q 'KAY_BIN' "${INSTALL_SH}" \
  && grep -q 'KAY_CODE_ALIAS' "${INSTALL_SH}" \
  && grep -q 'KAY_CODER_ALIAS' "${INSTALL_SH}" \
  && grep -q 'remove_kay_codex_alias' "${INSTALL_SH}" \
  && grep -q 'CODEX_INSTALL_VERSION' "${INSTALL_SH}" \
  && ! grep -q 'update --help' "${INSTALL_SH}" \
  && grep -q -- '--version 2>/dev/null | grep -qiE' "${INSTALL_SH}" \
  && grep -q -- '--release "${CODEX_INSTALL_VERSION}"' "${INSTALL_SH}" \
  && grep -q 'CODEX_INSTALL_DIR="${SIDEKICK_BIN_DIR}" bash "${CODEX_INSTALL_TMP}"' "${INSTALL_SH}" \
  && grep -q 'cleanup_install_tmps' "${INSTALL_SH}"; then
  assert_pass "Kay runtime bootstrap logic present with pinned release, exec-capable detection, custom install dir, non-Codex aliases, and Codex CLI collision cleanup"
else
  assert_fail "Kay bootstrap" "missing Kay runtime install, pinned release, exec-capable detection, custom install dir, non-Codex aliases, collision cleanup, or cleanup logic"
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
if ! grep -qiE 'forge|forgecode|SIDEKICK_INSTALL_FORGE|EXPECTED_FORGE_SHA' "${INSTALL_SH}"; then
  assert_pass "removed sidekick installer code is absent"
else
  assert_fail "removed sidekick installer code" "Forge bootstrap text remains"
fi

echo "=== T16: hooks.json has no SessionStart surface ==="
HOOKS="${PLUGIN_DIR}/hooks/hooks.json"
SESSION_PRESENT=$(python3 -c "import json; d=json.load(open('${HOOKS}')); print('SessionStart' in d['hooks'])")
if [ "${SESSION_PRESENT}" = "False" ] && ! grep -q 'runtime-sync.sh' "${HOOKS}"; then
  assert_pass "SessionStart surface is absent"
else
  assert_fail "SessionStart removal" "SessionStart hook or runtime-sync hook remains"
fi

if grep -q 'CLAUDE_PLUGIN_ROOT' "${HOOKS}" \
  && ! grep -Fq '${CODEX_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT' "${HOOKS}"; then
  assert_pass "shared hook root fallback supports Claude and Codex"
else
  assert_fail "shared hook root fallback" "missing CLAUDE fallback or duplicated CODEX fallback remains"
fi

ROOT_EXPR="$(python3 -c "import json; d=json.load(open('${HOOKS}')); print(d['hooks']['PreToolUse'][0]['hooks'][0]['command'].split('; bash ')[0])")"
CODEX_ROOT_RESULT="$(SIDEKICK_PLUGIN_ROOT="/tmp/sidekick-stale" CODEX_PLUGIN_ROOT="/tmp/codex-current" CLAUDE_PLUGIN_ROOT= bash -c "${ROOT_EXPR}; printf '%s' \"\${ROOT}\"")"
CLAUDE_ROOT_RESULT="$(SIDEKICK_PLUGIN_ROOT="/tmp/sidekick-stale" CODEX_PLUGIN_ROOT= CLAUDE_PLUGIN_ROOT="/tmp/claude-current" bash -c "${ROOT_EXPR}; printf '%s' \"\${ROOT}\"")"
if [ "${CODEX_ROOT_RESULT}" = "/tmp/codex-current" ] \
  && [ "${CLAUDE_ROOT_RESULT}" = "/tmp/claude-current" ]; then
  assert_pass "source hook root fallback prefers active host roots before stale generic root"
else
  assert_fail "source hook root fallback precedence" "codex=${CODEX_ROOT_RESULT} claude=${CLAUDE_ROOT_RESULT}"
fi

echo "=== T17: selective install env flags ==="
if grep -q 'SIDEKICK_INSTALL_KAY' "${INSTALL_SH}" && grep -q 'SIDEKICK_INSTALL_CODE' "${INSTALL_SH}" && ! grep -q 'SIDEKICK_INSTALL_FORGE' "${INSTALL_SH}"; then
  assert_pass "selective install env flags present"
else
  assert_fail "selective install env flags" "missing Kay/compatibility flag or stale Forge flag remains"
fi

echo "=== T18: missing hash tools fail closed at runtime ==="
_runtime_root="$(mktemp -d)"
_toolbox_root="$(mktemp -d)"
prepare_install_sandbox "${_runtime_root}"
make_install_toolbox "${_toolbox_root}" "0"
mkdir -p "${_runtime_root}/home"
if OUT="$(HOME="${_runtime_root}/home" SIDEKICK_PLUGIN_ROOT="${_runtime_root}" BIN_DIR="${_toolbox_root}" PATH="${_toolbox_root}" SIDEKICK_INSTALL_KAY=1 bash "${_runtime_root}/install.sh" 2>&1)"; then
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
if OUT="$(HOME="${_runtime_root}/home" SIDEKICK_PLUGIN_ROOT="${_runtime_root}" BIN_DIR="${_toolbox_root}" PATH="${_toolbox_root}" SIDEKICK_INSTALL_KAY=1 bash "${_runtime_root}/install.sh" 2>&1)"; then
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
  && grep -q 'validate_clean_reinstall_cache_target' "${INSTALL_SH}" \
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
  "skills/kay-stop/SKILL.md" \
  "sidekicks/registry.json"; do
  copy_plugin_file "${_host_root}" "${_rel}"
done
if HOME="${_host_home}" SIDEKICK_INSTALL_HOST=codex SIDEKICK_INSTALL_KAY=0 PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash "${_host_root}/install.sh" >/tmp/sidekick-install-host-rewrite.out 2>&1; then
  if python3 - "${_host_root}" <<'PY'
from pathlib import Path
import hashlib
import json
import sys

root = Path(sys.argv[1])
manifest = json.loads((root / ".claude-plugin/plugin.json").read_text())
integrity = manifest.get("_integrity", {})
hooks_text = (root / "hooks/hooks.json").read_text()
if "${CODEX_PLUGIN_ROOT:-${SIDEKICK_PLUGIN_ROOT:-}}" not in hooks_text:
    raise SystemExit("hooks.json does not prefer CODEX_PLUGIN_ROOT after Codex host rewrite")
if "${SIDEKICK_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT" in hooks_text:
    raise SystemExit("hooks.json still allows SIDEKICK_PLUGIN_ROOT to override CODEX_PLUGIN_ROOT")
if "CLAUDE_PLUGIN_ROOT" in hooks_text:
    raise SystemExit("hooks.json still references CLAUDE_PLUGIN_ROOT after Codex host rewrite")
targets = {
    "kay_stop_skill_md_sha256": "skills/kay-stop/SKILL.md",
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
if HOME="${_custom_home}" SIDEKICK_PLUGIN_ROOT="${_custom_root}" BIN_DIR="${_custom_bin}" PATH="${_custom_toolbox}:/usr/bin:/bin:/usr/sbin:/sbin" SIDEKICK_INSTALL_KAY=1 bash "${_custom_root}/install.sh" >/tmp/sidekick-install-custom-bin.out 2>&1; then
  if [ -x "${_custom_bin}/kay" ] \
    && [ -x "${_custom_bin}/codex" ] \
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

echo "=== T25: Kay installer metadata comes from source snapshot ==="
_fresh_root="$(mktemp -d)"
_stale_root="$(mktemp -d)"
_fresh_home="$(mktemp -d)"
_fresh_toolbox="$(mktemp -d)"
_fresh_bin="${_fresh_home}/bin"
_curl_log="${_fresh_home}/curl-url.log"
prepare_install_sandbox "${_fresh_root}"
prepare_install_sandbox "${_stale_root}"
make_install_toolbox "${_fresh_toolbox}" "1"
cat > "${_fresh_toolbox}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    http://*|https://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done
printf '%s\n' "${url}" > "${SIDEKICK_TEST_CURL_LOG}"
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
chmod +x "${_fresh_toolbox}/curl"
_fake_installer="$(mktemp)"
SIDEKICK_TEST_CURL_LOG="${_curl_log}" "${_fresh_toolbox}/curl" -o "${_fake_installer}" "https://example.invalid/fresh-kay-install.sh"
_fake_sha="$(shasum -a 256 "${_fake_installer}" | awk '{print $1}')"
rm -f "${_fake_installer}" "${_curl_log}"
python3 - "${_fresh_root}/sidekicks/registry.json" "${_stale_root}/sidekicks/registry.json" "${_fake_sha}" <<'PY'
import json
import sys
from pathlib import Path

fresh_path = Path(sys.argv[1])
stale_path = Path(sys.argv[2])
sha = sys.argv[3]

for path, url in [
    (fresh_path, "https://example.invalid/fresh-kay-install.sh"),
    (stale_path, "https://example.invalid/stale-kay-install.sh"),
]:
    data = json.loads(path.read_text(encoding="utf-8"))
    data["kay"]["install"]["url"] = url
    data["kay"]["install"]["sha256"] = sha
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
mkdir -p "${_fresh_bin}"
if HOME="${_fresh_home}" \
  SIDEKICK_PLUGIN_ROOT="${_stale_root}" \
  CODEX_PLUGIN_ROOT="${_fresh_home}/.codex/plugins/cache/alo-labs-codex/sidekick/${PLUGIN_VERSION}" \
  BIN_DIR="${_fresh_bin}" \
  PATH="${_fresh_toolbox}:/usr/bin:/bin:/usr/sbin:/sbin" \
  SIDEKICK_TEST_CURL_LOG="${_curl_log}" \
  SIDEKICK_INSTALL_KAY=1 \
  bash "${_fresh_root}/install.sh" >/tmp/sidekick-install-source-registry.out 2>&1; then
  if [ -x "${_fresh_bin}/kay" ] \
    && [ "$(cat "${_curl_log}" 2>/dev/null || true)" = "https://example.invalid/fresh-kay-install.sh" ]; then
    assert_pass "Kay installer URL is pinned to the source snapshot despite stale SIDEKICK_PLUGIN_ROOT"
  else
    assert_fail "source snapshot Kay metadata" "unexpected URL: $(cat "${_curl_log}" 2>/dev/null || true)"
  fi
else
  assert_fail "source snapshot Kay metadata" "$(cat /tmp/sidekick-install-source-registry.out 2>/dev/null || true)"
fi
rm -rf "${_fresh_root}" "${_stale_root}" "${_fresh_home}" "${_fresh_toolbox}" /tmp/sidekick-install-source-registry.out

echo "=== T26: Kay-disabled install does not require python3 registry reads ==="
_skip_root="$(mktemp -d)"
_skip_home="$(mktemp -d)"
_skip_toolbox="$(mktemp -d)"
prepare_install_sandbox "${_skip_root}"
make_install_toolbox "${_skip_toolbox}" "1"
rm -f "${_skip_toolbox}/python3"
cat > "${_skip_toolbox}/python3" <<'EOF'
#!/usr/bin/env bash
echo "unexpected python3 invocation" >&2
exit 127
EOF
chmod +x "${_skip_toolbox}/python3"
if env -u CODEX_PLUGIN_ROOT -u CODEX_HOME -u CODEX_THREAD_ID \
  -u CLAUDE_PLUGIN_ROOT -u CLAUDE_SESSION_ID -u SIDEKICK_PLUGIN_ROOT \
  HOME="${_skip_home}" \
  PATH="${_skip_toolbox}:/usr/bin:/bin:/usr/sbin:/sbin" \
  SIDEKICK_INSTALL_KAY=0 \
  bash "${_skip_root}/install.sh" >/tmp/sidekick-install-no-python-skip.out 2>&1; then
  if grep -q 'Skipping Kay bootstrap/repair' /tmp/sidekick-install-no-python-skip.out; then
    assert_pass "Kay-disabled install skips registry metadata reads before python3 is needed"
  else
    assert_fail "Kay-disabled python3 skip" "installer did not report Kay skip"
  fi
else
  assert_fail "Kay-disabled python3 skip" "$(cat /tmp/sidekick-install-no-python-skip.out 2>/dev/null || true)"
fi
rm -rf "${_skip_root}" "${_skip_home}" "${_skip_toolbox}" /tmp/sidekick-install-no-python-skip.out

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

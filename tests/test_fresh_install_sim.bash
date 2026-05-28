#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin -- Fresh Install Simulation
# Uses sandboxed HOME to avoid touching the real system.
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0; SKIP=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
INSTALL_SH="${PLUGIN_DIR}/install.sh"
KAY_VERSION="$(python3 -c "import json; d=json.load(open('${PLUGIN_DIR}/sidekicks/registry.json')); print(d['kay']['install']['version'])")"

green='\033[0;32m'; red='\033[0;31m'; yellow='\033[0;33m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }
assert_skip() { echo -e "${yellow}SKIP${reset} $1: $2"; SKIP=$((SKIP+1)); }

make_kay_stub() {
  local path="$1"
  cat > "${path}" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  --version)
    printf 'kay ${KAY_VERSION#v}\\n'
    ;;
  exec)
    if [ "\${2:-}" = "--help" ]; then
      printf 'kay exec help\\n'
      exit 0
    fi
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "${path}"
}

prepare_install_sandbox() {
  local root="$1"
  mkdir -p "${root}/hooks/lib" "${root}/sidekicks"
  cp "${INSTALL_SH}" "${root}/install.sh"
  cp "${PLUGIN_DIR}/hooks/lib/sidekick-registry.sh" "${root}/hooks/lib/sidekick-registry.sh"
  cp "${PLUGIN_DIR}/sidekicks/registry.json" "${root}/sidekicks/registry.json"
}

TMP_ROOT="$(mktemp -d)"
SANDBOX="$(mktemp -d "${TMP_ROOT}/sidekick-fresh-XXXXXX")"
INSTALL_ROOT="${TMP_ROOT}/install-tree"
trap 'rm -rf "${TMP_ROOT}" 2>/dev/null || true' EXIT
echo "Sandbox: ${SANDBOX}"
prepare_install_sandbox "${INSTALL_ROOT}"

echo "=== F1: Removed runtime installer is absent ==="
if ! grep -qiE 'forge|forgecode|SIDEKICK_INSTALL_FORGE|EXPECTED_FORGE_SHA' "${INSTALL_SH}"; then
  assert_pass "removed sidekick bootstrap code is absent"
else
  assert_fail "removed sidekick bootstrap code" "stale Forge installer text remains"
fi

echo "=== F2: Kay SHA mismatch abort logic ==="
if grep -q 'Kay SHA-256 MISMATCH' "${INSTALL_SH}" && grep -q 'exit 1' "${INSTALL_SH}"; then
  assert_pass "Kay SHA mismatch abort is present"
else
  assert_fail "Kay SHA mismatch abort" "not found"
fi

echo "=== F3: PATH idempotency in sandboxed HOME ==="
FAKE_ZSHRC="${SANDBOX}/.zshrc"
echo 'export PATH="$HOME/.local/bin:$PATH"' > "${FAKE_ZSHRC}"
FAKE_BIN="${SANDBOX}/.local/bin"
mkdir -p "${FAKE_BIN}"
make_kay_stub "${FAKE_BIN}/kay"
ln -sf kay "${FAKE_BIN}/code"
ln -sf kay "${FAKE_BIN}/coder"
ln -sf kay "${FAKE_BIN}/codex"
HOME="${SANDBOX}" PATH="${FAKE_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" SIDEKICK_INSTALL_KAY=1 bash "${INSTALL_ROOT}/install.sh" 2>&1 </dev/null || true
COUNT="$(grep -c '.local/bin' "${FAKE_ZSHRC}" 2>/dev/null || echo 1)"
if [ "${COUNT}" -le 1 ]; then
  assert_pass "add_to_path is idempotent - no duplicate PATH entry (count=${COUNT})"
else
  assert_fail "PATH idempotency" "${COUNT} .local/bin entries in .zshrc"
fi
if [ ! -e "${FAKE_BIN}/codex" ]; then
  assert_pass "stale Kay-owned codex alias is removed"
else
  assert_fail "stale Kay codex alias cleanup" "expected installer to remove ${FAKE_BIN}/codex"
fi

echo "=== F4: PATH marker added to fresh .zshrc ==="
FRESH="${SANDBOX}/fresh_home"
mkdir -p "${FRESH}/.local/bin"
touch "${FRESH}/.zshrc"
make_kay_stub "${FRESH}/.local/bin/kay"
ln -sf kay "${FRESH}/.local/bin/code"
ln -sf kay "${FRESH}/.local/bin/coder"
INSTALL_OUTPUT="$(HOME="${FRESH}" PATH="${FRESH}/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin" SIDEKICK_INSTALL_KAY=1 bash "${INSTALL_ROOT}/install.sh" 2>&1 </dev/null || true)"
if grep -q 'Added by sidekick plugin' "${FRESH}/.zshrc"; then
  assert_pass "Marker comment added to .zshrc"
else
  assert_fail "Marker in shell profile" "not found in .zshrc; output=${INSTALL_OUTPUT}"
fi
if grep -q '.local/bin' "${FRESH}/.zshrc"; then
  assert_pass "PATH entry added to .zshrc"
else
  assert_fail "PATH in shell profile" "not found in .zshrc"
fi

echo "=== F5: Kay compatibility aliases do not shadow Codex CLI ==="
if [ -L "${FRESH}/.local/bin/code" ] && [ -L "${FRESH}/.local/bin/coder" ] && [ ! -e "${FRESH}/.local/bin/codex" ]; then
  assert_pass "Kay compatibility aliases are present without a codex shadow alias"
else
  assert_fail "Kay compatibility aliases" "expected code/coder symlinks and no codex alias"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

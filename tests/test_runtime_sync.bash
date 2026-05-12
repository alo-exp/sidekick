#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — runtime sync behavior tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
SYNC_SH="${PLUGIN_DIR}/hooks/runtime-sync.sh"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

make_runtime_stub() {
  local path="$1"
  cat > "${path}" <<'EOF'
#!/usr/bin/env bash
name="$(basename "$0")"
log="${SYNC_LOG:?}"

case "${1:-}" in
  update)
    if [ "${2:-}" = "--help" ]; then
      exit 0
    fi
    printf '%s:update\n' "${name}" >> "${log}"
    exit 0
    ;;
  --version)
    printf '%s 1.0.0\n' "${name}"
    exit 0
    ;;
  *)
    printf '%s:%s force=%s\n' "${name}" "$*" "${SIDEKICK_FORCE_REINSTALL:-unset}" >> "${log}"
    exit 0
    ;;
esac
EOF
  chmod +x "${path}"
}

make_install_stub() {
  local path="$1"
  cat > "${path}" <<'EOF'
#!/usr/bin/env bash
log="${SYNC_LOG:?}"
printf 'install forge=%s code=%s force=%s\n' "${SIDEKICK_INSTALL_FORGE:-unset}" "${SIDEKICK_INSTALL_CODE:-unset}" "${SIDEKICK_FORCE_REINSTALL:-unset}" >> "${log}"
EOF
  chmod +x "${path}"
}

run_case() {
  local name="$1"
  local setup_fn="$2"
  local expect_fn="$3"

  local root
  root="$(mktemp -d)"
  trap 'rm -rf "${root}" 2>/dev/null || true' RETURN
  mkdir -p "${root}/bin"
  make_install_stub "${root}/install.sh"
  "${setup_fn}" "${root}"

  mkdir -p "${root}/home"
  SYNC_LOG="${root}/sync.log" \
    CLAUDE_PLUGIN_ROOT="${root}" \
    HOME="${root}/home" \
    BIN_DIR="${root}/bin" \
    PATH="${root}/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "${SYNC_SH}" >/dev/null 2>&1

  if "${expect_fn}" "${root}/sync.log"; then
    assert_pass "${name}"
  else
    assert_fail "${name}" "log assertions failed"
    cat "${root}/sync.log" 2>/dev/null || true
  fi
}

setup_both_present() {
  local root="$1"
  make_runtime_stub "${root}/bin/runtime-stub"
  ln -s runtime-stub "${root}/bin/forge"
  ln -s runtime-stub "${root}/bin/codex"
  ln -s runtime-stub "${root}/bin/code"
  ln -s runtime-stub "${root}/bin/coder"
}

setup_code_update_unsupported() {
  local root="$1"
  make_runtime_stub "${root}/bin/runtime-stub"
  ln -s runtime-stub "${root}/bin/forge"
  cat > "${root}/bin/code" <<'EOF'
#!/usr/bin/env bash
log="${SYNC_LOG:?}"
case "${1:-}" in
  update)
    if [ "${2:-}" = "--help" ]; then
      exit 1
    fi
    printf 'code:update-fallback\n' >> "${log}"
    exit 0
    ;;
  --version)
    printf 'code 1.0.0\n'
    exit 0
    ;;
esac
EOF
  chmod +x "${root}/bin/code"
  ln -s code "${root}/bin/codex"
  ln -s code "${root}/bin/coder"
}

setup_forge_missing() {
  local root="$1"
  make_runtime_stub "${root}/bin/runtime-stub"
  ln -s runtime-stub "${root}/bin/codex"
  ln -s runtime-stub "${root}/bin/code"
  ln -s runtime-stub "${root}/bin/coder"
}

setup_code_missing() {
  local root="$1"
  make_runtime_stub "${root}/bin/runtime-stub"
  ln -s runtime-stub "${root}/bin/forge"
}

setup_both_missing() {
  local root="$1"
  :
}

setup_forge_update_unsupported() {
  local root="$1"
  cat > "${root}/bin/forge" <<'EOF'
#!/usr/bin/env bash
log="${SYNC_LOG:?}"
case "${1:-}" in
  update)
    if [ "${2:-}" = "--help" ]; then
      exit 1
    fi
    printf 'forge:update-fallback\n' >> "${log}"
    exit 0
    ;;
  --version)
    printf 'forge 1.0.0\n'
    exit 0
    ;;
esac
EOF
  chmod +x "${root}/bin/forge"
  make_runtime_stub "${root}/bin/runtime-stub"
  ln -s runtime-stub "${root}/bin/codex"
  ln -s runtime-stub "${root}/bin/code"
  ln -s runtime-stub "${root}/bin/coder"
}

expect_updates() {
  local log="$1"
  grep -q '^forge:update$' "${log}" && grep -q '^code:update$' "${log}" && ! grep -q '^install ' "${log}"
}

expect_forge_install_only() {
  local log="$1"
  grep -q '^install forge=1 code=0 force=1$' "${log}" && ! grep -q 'update' "${log}"
}

expect_code_install_only() {
  local log="$1"
  grep -q '^install forge=0 code=1 force=1$' "${log}" && ! grep -q 'update' "${log}"
}

expect_bootstrap_install() {
  local log="$1"
  grep -q '^install forge=unset code=unset force=unset$' "${log}" && ! grep -q 'update' "${log}"
}

expect_forge_repair_plus_code_update() {
  local log="$1"
  grep -q '^install forge=1 code=0 force=1$' "${log}" && grep -q '^code:update$' "${log}" && ! grep -q '^forge:update$' "${log}"
}

expect_code_repair_plus_forge_update() {
  local log="$1"
  grep -q '^install forge=0 code=1 force=1$' "${log}" && grep -q '^forge:update$' "${log}" && ! grep -q '^code:update$'
}

echo "=== T1: built-in updates run when both runtimes are present ==="
run_case "built-in updates" setup_both_present expect_updates

echo "=== T2: missing Forge triggers selective Forge repair only ==="
run_case "forge repair" setup_forge_missing expect_forge_install_only

echo "=== T3: missing Code triggers selective Code repair only ==="
run_case "code repair" setup_code_missing expect_code_install_only

echo "=== T4: both runtimes missing triggers the bootstrap installer ==="
run_case "bootstrap install" setup_both_missing expect_bootstrap_install

echo "=== T5: unsupported Forge update falls back to selective Forge repair ==="
run_case "forge fallback" setup_forge_update_unsupported expect_forge_repair_plus_code_update

echo "=== T6: unsupported Code update falls back to selective Code repair ==="
run_case "code fallback" setup_code_update_unsupported expect_code_repair_plus_forge_update

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

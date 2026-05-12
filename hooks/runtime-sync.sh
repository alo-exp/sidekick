#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — runtime sync helper
# =============================================================================
# Runs on SessionStart after the one-time bootstrap has completed.
# Uses each runtime's native update flow when available; falls back to the
# installer path only when a runtime is missing or cannot self-update.
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
INSTALL_SH="${PLUGIN_ROOT}/install.sh"
SIDEKICK_BIN_DIR="${BIN_DIR:-${HOME}/.local/bin}"

export PATH="${SIDEKICK_BIN_DIR}:${PATH}"

log() {
  printf '[forge-plugin] %s\n' "$*"
}

resolve_forge_binary() {
  local candidate="${SIDEKICK_BIN_DIR}/forge"
  [ -x "${candidate}" ] || return 1
  printf '%s' "${candidate}"
}

resolve_codex_binary() {
  local candidate
  for candidate in "${SIDEKICK_BIN_DIR}/code" "${SIDEKICK_BIN_DIR}/codex" "${SIDEKICK_BIN_DIR}/coder"; do
    if [ -x "${candidate}" ]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  return 1
}

repair_runtime() {
  local runtime="$1"
  case "${runtime}" in
    forge)
      log "Repairing ForgeCode with the bootstrap installer."
      if ! SIDEKICK_INSTALL_FORGE=1 SIDEKICK_INSTALL_CODE=0 SIDEKICK_FORCE_REINSTALL=1 bash "${INSTALL_SH}"; then
        log "WARNING: ForgeCode repair failed."
        return 1
      fi
      ;;
    code)
      log "Repairing Code with the bootstrap installer."
      if ! SIDEKICK_INSTALL_FORGE=0 SIDEKICK_INSTALL_CODE=1 SIDEKICK_FORCE_REINSTALL=1 bash "${INSTALL_SH}"; then
        log "WARNING: Code repair failed."
        return 1
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

sync_or_repair() {
  local runtime_key="$1"
  local runtime_label="$2"
  local binary="$3"
  local update_output=""

  if ! "${binary}" update --help >/dev/null 2>&1; then
    log "${runtime_label} update command is unavailable; falling back to installer repair."
    repair_runtime "${runtime_key}"
    return $?
  fi

  log "Checking ${runtime_label} for updates."
  if update_output="$("${binary}" update 2>&1)"; then
    if [ -n "${update_output}" ]; then
      printf '%s\n' "${update_output}" | sed "s/^/[forge-plugin] ${runtime_label}: /"
    else
      log "${runtime_label} update completed."
    fi
    return 0
  fi

  log "${runtime_label} update failed; attempting installer repair."
  if [ -n "${update_output}" ]; then
    printf '%s\n' "${update_output}" | sed "s/^/[forge-plugin] ${runtime_label}: /" >&2
  fi
  repair_runtime "${runtime_key}"
}

main() {
  local forge_bin=""
  local codex_bin=""

  forge_bin="$(resolve_forge_binary || true)"
  codex_bin="$(resolve_codex_binary || true)"

  if [ -z "${forge_bin}" ] || [ -z "${codex_bin}" ]; then
    if [ -z "${forge_bin}" ] && [ -z "${codex_bin}" ]; then
      log "ForgeCode and Code are missing; running the bootstrap installer."
      bash "${INSTALL_SH}" || {
        log "WARNING: bootstrap installer failed."
        return 1
      }
      return 0
    fi

    if [ -z "${forge_bin}" ]; then
      repair_runtime forge || return 1
    fi

    if [ -z "${codex_bin}" ]; then
      repair_runtime code || return 1
    fi

    return 0
  fi

  sync_or_repair forge ForgeCode "${forge_bin}" || return 1
  sync_or_repair code Code "${codex_bin}" || return 1
}

main "$@"

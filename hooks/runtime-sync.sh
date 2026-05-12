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

# shellcheck source=hooks/lib/sidekick-registry.sh
source "${PLUGIN_ROOT}/hooks/lib/sidekick-registry.sh"

KAY_INSTALL_VERSION="$(sidekick_registry_get kay '.[$sidekick].install.version')"
KAY_INSTALL_URL="$(sidekick_registry_get kay '.[$sidekick].install.url')"

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
  local install_output=""
  case "${runtime}" in
    forge)
      log "Repairing ForgeCode with the bootstrap installer."
      if ! install_output="$(SIDEKICK_INSTALL_FORGE=1 SIDEKICK_INSTALL_CODE=0 SIDEKICK_FORCE_REINSTALL=1 bash "${INSTALL_SH}" 2>&1)"; then
        if [ -n "${install_output}" ]; then
          printf '%s\n' "${install_output}" | sed "s/^/[forge-plugin] ForgeCode installer: /" >&2
        fi
        log "WARNING: ForgeCode repair failed."
        return 1
      fi
      if [ -n "${install_output}" ]; then
        printf '%s\n' "${install_output}" | sed "s/^/[forge-plugin] ForgeCode installer: /"
      fi
      ;;
    code)
      log "Repairing Code with the bootstrap installer."
      if ! install_output="$(SIDEKICK_INSTALL_FORGE=0 SIDEKICK_INSTALL_CODE=1 SIDEKICK_FORCE_REINSTALL=1 bash "${INSTALL_SH}" 2>&1)"; then
        if [ -n "${install_output}" ]; then
          printf '%s\n' "${install_output}" | sed "s/^/[forge-plugin] Code installer: /" >&2
        fi
        if printf '%s' "${install_output}" | grep -qiE 'Could not find SHA-256 digest for release asset|missing SHA-256 digest|No assets found'; then
          log "ERROR: Kay ${KAY_INSTALL_VERSION} is the latest configured Code release, but the upstream release is missing the installable asset digest."
          log "ERROR: Sidekick will keep the current Code runtime in place until Kay publishes complete release assets."
          if [ -n "${KAY_INSTALL_URL}" ]; then
            log "ERROR: Kay release source: ${KAY_INSTALL_URL}"
          fi
        else
          log "WARNING: Code repair failed."
        fi
        return 1
      fi
      if [ -n "${install_output}" ]; then
        printf '%s\n' "${install_output}" | sed "s/^/[forge-plugin] Code installer: /"
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
  local repair_context=""

  if [ "${runtime_key}" = "code" ] && [ -n "${KAY_INSTALL_VERSION}" ]; then
    repair_context=" for Kay ${KAY_INSTALL_VERSION}"
  fi

  if ! "${binary}" update --help >/dev/null 2>&1; then
    log "${runtime_label} update command is unavailable; falling back to installer repair${repair_context}."
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

  log "${runtime_label} update failed; attempting installer repair${repair_context}."
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

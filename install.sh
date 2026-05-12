#!/usr/bin/env bash
# Forge Plugin — auto-install script
# Called by the SessionStart bootstrap hook and the runtime repair path.
# Installs or repairs the Forge and Code runtimes and adds them to PATH.
# Provider/API key setup is guided interactively by the forge skill in Claude.
#
# SECURITY NOTE (R8-2): This script runs non-interactively under the SessionStart hook.
# Ctrl+C is not available to cancel the download. The SHA-256 of the downloaded script is
# logged to ~/.local/share/forge-plugin-install-sha.log — verify it against the official
# release hash at https://forgecode.dev/releases after the session starts.

set -euo pipefail

SIDEKICK_BIN_DIR="${BIN_DIR:-${HOME}/.local/bin}"
FORGE_BIN="${SIDEKICK_BIN_DIR}/forge"
CODEX_BIN="${SIDEKICK_BIN_DIR}/code"
CODEX_CODE_ALIAS="${SIDEKICK_BIN_DIR}/codex"
CODEX_CODER_ALIAS="${SIDEKICK_BIN_DIR}/coder"
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_PLUGIN_ROOT="${PLUGIN_ROOT}"
SIDEKICK_PLUGIN_ROOT="${SIDEKICK_PLUGIN_ROOT:-${SOURCE_PLUGIN_ROOT}}"
export SIDEKICK_PLUGIN_ROOT
FORGE_INSTALL_TMP=""
CODEX_INSTALL_TMP=""
INSTALL_FORGE="${SIDEKICK_INSTALL_FORGE:-1}"
INSTALL_CODE="${SIDEKICK_INSTALL_CODE:-1}"
FORCE_REINSTALL="${SIDEKICK_FORCE_REINSTALL:-0}"
CLEAN_REINSTALL="${SIDEKICK_CLEAN_REINSTALL:-0}"

# shellcheck source=hooks/lib/sidekick-registry.sh
source "${PLUGIN_ROOT}/hooks/lib/sidekick-registry.sh"

detect_install_host() {
  if [ -n "${SIDEKICK_INSTALL_HOST:-}" ]; then
    printf '%s' "${SIDEKICK_INSTALL_HOST}"
    return 0
  fi

  if [ -n "${CODEX_PLUGIN_ROOT:-}" ] || [ -n "${CODEX_HOME:-}" ] || [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_PROJECT_DIR:-}" ]; then
    printf '%s' "codex"
    return 0
  fi

  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || [ -n "${CLAUDE_SESSION_ID:-}" ] || [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    printf '%s' "claude"
    return 0
  fi

  return 1
}

rewrite_host_surface() {
  local host="${1:-}"
  local rewrite_target="${PLUGIN_ROOT}"

  [ -n "${host}" ] || return 0

  echo "[forge-plugin] Rewriting installed surface for ${host}."

  python3 - "${rewrite_target}" "${host}" <<'PY'
from pathlib import Path
import json
import sys

root = Path(sys.argv[1])
host = sys.argv[2]

if host not in {"codex", "claude"}:
    raise SystemExit(0)

replacements = {
    "codex": [
        ("ROOT=\"${SIDEKICK_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}}\";", "ROOT=\"${CODEX_PLUGIN_ROOT:-${SIDEKICK_PLUGIN_ROOT:-}}\";"),
        ("if [[ -n \"${CLAUDE_PLUGIN_ROOT:-}\" ]]; then\n    printf '%s' \"${CLAUDE_PLUGIN_ROOT}\"\n    return 0\n  fi\n", ""),
        ("if [[ -n \"${CLAUDE_SESSION_ID:-}\" ]]; then\n    printf '%s' \"${CLAUDE_SESSION_ID}\"\n    return 0\n  fi\n", ""),
        ("local root=\"${SIDEKICK_PROJECT_DIR:-${CODEX_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}}\"", "local root=\"${SIDEKICK_PROJECT_DIR:-${CODEX_PROJECT_DIR:-$PWD}}\""),
        ("marker_template=\"${marker_template//\\${CODEX_THREAD_ID}/$session_id}\"", "marker_template=\"${marker_template//\\${CODEX_THREAD_ID}/$session_id}\""),
        ("marker_template=\"${marker_template//\\$CODEX_THREAD_ID/$session_id}\"", "marker_template=\"${marker_template//\\$CODEX_THREAD_ID/$session_id}\""),
        ("~/.claude", "~/.codex"),
        (".claude/", ".codex/"),
        ("CLAUDE_PLUGIN_ROOT", "CODEX_PLUGIN_ROOT"),
        ("CLAUDE_PROJECT_DIR", "CODEX_PROJECT_DIR"),
        ("CLAUDE_SESSION_ID", "CODEX_THREAD_ID"),
        (".claude/sessions/${CODEX_THREAD_ID}", ".codex/sessions/${CODEX_THREAD_ID}"),
    ],
    "claude": [
        ("ROOT=\"${SIDEKICK_PLUGIN_ROOT:-${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}}\";", "ROOT=\"${CLAUDE_PLUGIN_ROOT:-${SIDEKICK_PLUGIN_ROOT:-}}\";"),
        ("if [[ -n \"${CODEX_PLUGIN_ROOT:-}\" ]]; then\n    printf '%s' \"${CODEX_PLUGIN_ROOT}\"\n    return 0\n  fi\n", ""),
        ("if [[ -n \"${CODEX_THREAD_ID:-}\" ]]; then\n    printf '%s' \"${CODEX_THREAD_ID}\"\n    return 0\n  fi\n", ""),
        ("local root=\"${SIDEKICK_PROJECT_DIR:-${CODEX_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}}\"", "local root=\"${SIDEKICK_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}\""),
        ("marker_template=\"${marker_template//\\${CODEX_THREAD_ID}/$session_id}\"", "marker_template=\"${marker_template//\\${CLAUDE_SESSION_ID}/$session_id}\""),
        ("marker_template=\"${marker_template//\\$CODEX_THREAD_ID/$session_id}\"", "marker_template=\"${marker_template//\\$CLAUDE_SESSION_ID/$session_id}\""),
        ("~/.codex", "~/.claude"),
        (".codex/", ".claude/"),
        ("CODEX_PLUGIN_ROOT", "CLAUDE_PLUGIN_ROOT"),
        ("CODEX_PROJECT_DIR", "CLAUDE_PROJECT_DIR"),
        ("CODEX_THREAD_ID", "CLAUDE_SESSION_ID"),
        (".codex/sessions/${CODEX_THREAD_ID}", ".claude/sessions/${CLAUDE_SESSION_ID}"),
    ],
}

for rel in [
    "hooks/hooks.json",
    "hooks/lib/sidekick-registry.sh",
    "sidekicks/registry.json",
    "skills/forge/SKILL.md",
    "skills/codex-stop/SKILL.md",
    "hooks/forge-delegation-enforcer.sh",
    "hooks/codex-delegation-enforcer.sh",
]:
    path = root / rel
    if not path.exists():
        continue
    text = path.read_text(encoding="utf-8")
    original = text
    for old, new in replacements[host]:
        text = text.replace(old, new)
    if text != original:
        path.write_text(text, encoding="utf-8")
PY
}

purge_legacy_codex_sidekick_state() {
  python3 - "${HOME}/.Codex/config.toml" "${HOME}/.codex/config.toml" "${HOME}/.Codex/plugins/installed_plugins.json" "${HOME}/.codex/plugins/installed_plugins.json" <<'PY'
import json
import pathlib
import sys

config_paths = [pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])]
registry_paths = [pathlib.Path(sys.argv[3]), pathlib.Path(sys.argv[4])]

legacy_plugin_prefix = "sidekick@"

for config_path in config_paths:
    if not config_path.is_file():
        continue

    text = config_path.read_text()
    lines = text.splitlines()
    output = []
    changed = False
    i = 0

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if (
            stripped.startswith('[plugins."')
            and stripped.endswith('"]')
            and stripped[len('[plugins."'):-2].startswith(legacy_plugin_prefix)
        ) or (
            stripped.startswith('[hooks.state."')
            and stripped.endswith('"]')
            and stripped[len('[hooks.state."'):-2].startswith(legacy_plugin_prefix)
        ):
            changed = True
            i += 1
            while i < len(lines) and not lines[i].startswith("["):
                i += 1
            continue
        output.append(line)
        i += 1

    if changed:
        new_text = "\n".join(output)
        if text.endswith("\n"):
            new_text += "\n"
        config_path.write_text(new_text)

for registry_path in registry_paths:
    if not registry_path.is_file():
        continue

    try:
        data = json.loads(registry_path.read_text())
    except Exception:
        continue

    plugins = data.get("plugins")
    if not isinstance(plugins, dict):
        continue

    removed = False
    for plugin_id in list(plugins):
        if isinstance(plugin_id, str) and plugin_id.startswith(legacy_plugin_prefix):
            del plugins[plugin_id]
            removed = True

    if removed:
        registry_path.write_text(json.dumps(data, indent=2) + "\n")
PY
}

bootstrap_sidekick_cache_tree() {
  local host="${1:-}"
  local source_root="${2:-}"
  local target_root="${3:-}"
  local current_alias plugin_root_dir

  [ -n "${host}" ] || return 0
  [ -n "${source_root}" ] || return 0
  [ -n "${target_root}" ] || return 0
  plugin_root_dir="$(dirname "${target_root}")"

  if [ "${CLEAN_REINSTALL}" = "1" ]; then
    case "${host}" in
      codex)
        purge_legacy_codex_sidekick_state
        ;;
    esac
    if [ "${source_root}" != "${plugin_root_dir}" ] && [[ "${source_root}" != "${plugin_root_dir}/"* ]]; then
      rm -rf "${plugin_root_dir}"
    fi
  fi

  if [ ! -d "${target_root}" ]; then
    mkdir -p "${plugin_root_dir}"
    cp -a "${source_root}/." "${target_root}/"
  fi

  current_alias="${plugin_root_dir}/current"
  ln -sfn "${target_root}" "${current_alias}"

  PLUGIN_ROOT="${target_root}"
}

cleanup_install_tmps() {
  rm -f "${FORGE_INSTALL_TMP:-}" "${CODEX_INSTALL_TMP:-}" 2>/dev/null || true
}

trap cleanup_install_tmps EXIT

# R8-3/R10-1: Pinned SHA-256 of the ForgeCode install script (https://forgecode.dev/cli).
# This enables automated mismatch-abort before execution.
# UPDATE THIS VALUE when upgrading ForgeCode — fetch the new hash with:
#   curl -fsSL https://forgecode.dev/cli | shasum -a 256
# Verify the hash matches the official release at: https://forgecode.dev/releases
# Leave blank ("") only if you intentionally want display-only verification.
# (SENTINEL FINDING-R7-7/R8-3/R10-1: supply chain hardening)
EXPECTED_FORGE_SHA="512d41a611962a8d07a7efac54fba2718867ca28ce9d5d1d02da465b141ce05a"
CODEX_INSTALL_URL="$(sidekick_registry_get kay '.[$sidekick].install.url')"
CODEX_INSTALL_SHA="$(sidekick_registry_get kay '.[$sidekick].install.sha256')"

if [ "${INSTALL_FORGE}" = "1" ]; then
  echo "[forge-plugin] Checking ForgeCode installation..."

  # --- Install forge binary if not present ---
  if [ "${FORCE_REINSTALL}" = "1" ] || [ ! -x "${FORGE_BIN}" ]; then
    if [ "${FORCE_REINSTALL}" = "1" ] && [ -x "${FORGE_BIN}" ]; then
      echo "[forge-plugin] Forcing ForgeCode reinstall from the bootstrap installer."
    fi
    echo "[forge-plugin] Installing ForgeCode..."
    # Download install script to a temp file first — do NOT pipe directly to sh.
    # Downloading to a file avoids stream-injection attacks and prints the SHA-256
    # so the user can verify the download matches a known-good release.
    # (SENTINEL FINDING-7.1: supply chain hardening)
    FORGE_INSTALL_TMP=$(mktemp "${TMPDIR:-/tmp}/forge-install.XXXXXX")
    # R8-6: Add download timeouts to prevent indefinite hang on slow/stalled connections.
    if command -v curl &>/dev/null; then
      curl -fsSL --max-time 60 --connect-timeout 15 https://forgecode.dev/cli -o "${FORGE_INSTALL_TMP}"
    elif command -v wget &>/dev/null; then
      wget -qO "${FORGE_INSTALL_TMP}" --timeout=60 https://forgecode.dev/cli
    else
      echo "[forge-plugin] ERROR: Neither curl nor wget found. Install ForgeCode manually from https://forgecode.dev" >&2
      exit 1
    fi
    # R7-8: shasum availability check with sha256sum fallback
    if command -v shasum &>/dev/null; then
      FORGE_SHA=$(shasum -a 256 "${FORGE_INSTALL_TMP}" | awk '{print $1}')
    elif command -v sha256sum &>/dev/null; then
      FORGE_SHA=$(sha256sum "${FORGE_INSTALL_TMP}" | awk '{print $1}')
    else
      echo "[forge-plugin] ERROR: Neither shasum nor sha256sum found — cannot verify download integrity." >&2
      exit 1
    fi
    FORGE_SHA_LOG="${HOME}/.local/share/forge-plugin-install-sha.log"
    mkdir -p "$(dirname "${FORGE_SHA_LOG}")"
    echo "[forge-plugin] Install script SHA-256: ${FORGE_SHA}"
    echo "[forge-plugin] IMPORTANT: Compare this hash against the official release at:"
    echo "[forge-plugin]   https://forgecode.dev/releases  (or GitHub releases page)"
    echo "[forge-plugin] If hashes do not match, delete ${FORGE_INSTALL_TMP} and abort."
    # Log SHA to a persistent file so the user can verify even in non-interactive contexts
    printf '%s  %s  (downloaded %s)\n' "${FORGE_SHA}" "forgecode-install.sh" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${FORGE_SHA_LOG}"
    echo "[forge-plugin] SHA logged to: ${FORGE_SHA_LOG}"

    # R8-3: If a pinned SHA is set, abort on mismatch before executing the script.
    if [ -n "${EXPECTED_FORGE_SHA}" ]; then
      if [ "${FORGE_SHA}" != "${EXPECTED_FORGE_SHA}" ]; then
        echo "[forge-plugin] ERROR: SHA-256 MISMATCH — aborting installation." >&2
        echo "[forge-plugin]   Got:      ${FORGE_SHA}" >&2
        echo "[forge-plugin]   Expected: ${EXPECTED_FORGE_SHA}" >&2
        echo "[forge-plugin]   Verify the release at: https://forgecode.dev/releases" >&2
        exit 1
      fi
      echo "[forge-plugin] SHA-256 verified against pinned hash — OK."
    else
      # R9-1/R9-9: Warn when no pin is active so the verification gap is explicit.
      echo "[forge-plugin] NOTICE: No pinned SHA-256 set — verification is display-only."
      echo "[forge-plugin]   To enable automated verification, set EXPECTED_FORGE_SHA in install.sh."
    fi

    # R9-2: Interactive execution gate (co-patch with R9-3 hooks.json change).
    # When running non-interactively (SessionStart hook) with no pinned hash, skip
    # execution and ask the user to install manually from an interactive terminal.
    # This ensures a human can verify the SHA before the downloaded script is run.
    # When a pinned hash is set and verified above, non-interactive execution is safe.
    # (SENTINEL FINDING-R9-2/R9-3: interactive gate + sentinel co-patch)
    if [ ! -t 1 ] && [ -z "${EXPECTED_FORGE_SHA}" ]; then
      echo "[forge-plugin] NOTICE: Cannot execute downloaded installer without user verification." >&2
      echo "[forge-plugin]   Running non-interactively with no pinned SHA — skipping auto-install." >&2
      echo "[forge-plugin]   To install ForgeCode, open a terminal and run:" >&2
      echo "[forge-plugin]     bash \"${BASH_SOURCE[0]}\"" >&2
      echo "[forge-plugin]   The SHA-256 will be displayed and you can verify it before proceeding." >&2
      # Exit 0 so the .installed sentinel IS written (via && in hooks.json) and this
      # message only appears once — not on every subsequent Claude session.
      exit 0
    fi

    # R6-1: In non-interactive mode Ctrl+C may not be available; give a short window anyway.
    sleep 5
    bash "${FORGE_INSTALL_TMP}"
    echo "[forge-plugin] ForgeCode installed."
    # NOTE (SENTINEL-S4): The forge-sb skill is bundled with the Sidekick plugin via
    # .forge/skills/ and does not require a secondary network fetch.  The previous
    # `curl | bash` from raw.githubusercontent.com was removed because it executed
    # unsigned remote code without checksum verification (arbitrary code execution risk).
  else
    echo "[forge-plugin] ForgeCode already installed."
  fi
else
  echo "[forge-plugin] Skipping ForgeCode bootstrap/repair (SIDEKICK_INSTALL_FORGE=0)."
fi

# --- Ensure Code runtime is installed and aliased ---
if [ "${INSTALL_CODE}" = "1" ]; then
  echo "[forge-plugin] Checking Code installation..."

  ensure_codex_aliases() {
    local source_bin="$1"
    mkdir -p "$(dirname "${CODEX_CODE_ALIAS}")"
    case "$(basename "${source_bin}")" in
      code)
        ln -sf "${source_bin}" "${CODEX_CODE_ALIAS}"
        ln -sf "${source_bin}" "${CODEX_CODER_ALIAS}"
        ;;
      codex)
        ln -sf "${source_bin}" "${SIDEKICK_BIN_DIR}/code"
        ln -sf "${source_bin}" "${CODEX_CODER_ALIAS}"
        ;;
      coder)
        ln -sf "${source_bin}" "${SIDEKICK_BIN_DIR}/code"
        ln -sf "${source_bin}" "${CODEX_CODE_ALIAS}"
        ;;
      *)
        ln -sf "${source_bin}" "${CODEX_CODE_ALIAS}"
        ln -sf "${source_bin}" "${CODEX_CODER_ALIAS}"
        ;;
    esac
    echo "[forge-plugin] Installed Code aliases: code, codex, coder -> ${source_bin}"
  }

resolve_codex_binary() {
  local candidate

  for candidate in "${SIDEKICK_BIN_DIR}/code" "${SIDEKICK_BIN_DIR}/codex" "${SIDEKICK_BIN_DIR}/coder"; do
    if [ -x "${candidate}" ] \
      && { "${candidate}" exec --help >/dev/null 2>&1 || "${candidate}" update --help >/dev/null 2>&1; }; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  return 1
}

install_codex_runtime() {
  local codex_sha codex_source force_reinstall="${FORCE_REINSTALL:-0}"

  if [ "${force_reinstall}" != "1" ]; then
    codex_source="$(resolve_codex_binary || true)"
    if [ -n "${codex_source}" ]; then
      ensure_codex_aliases "${codex_source}"
      echo "[forge-plugin] Code runtime already installed; aliases refreshed."
      return 0
    fi
  else
    echo "[forge-plugin] Forcing Code reinstall from the bootstrap installer."
  fi

  echo "[forge-plugin] Installing pinned Kay/Code runtime release..."
  CODEX_INSTALL_TMP=$(mktemp "${TMPDIR:-/tmp}/codex-install.XXXXXX")
  if command -v curl &>/dev/null; then
    curl -fsSL --max-time 60 --connect-timeout 15 "${CODEX_INSTALL_URL}" -o "${CODEX_INSTALL_TMP}"
  elif command -v wget &>/dev/null; then
    wget -qO "${CODEX_INSTALL_TMP}" --timeout=60 "${CODEX_INSTALL_URL}"
  else
    echo "[forge-plugin] ERROR: Neither curl nor wget found. Install Code manually from https://github.com/alo-labs/kay/releases" >&2
    exit 1
  fi

  if command -v shasum &>/dev/null; then
    codex_sha=$(shasum -a 256 "${CODEX_INSTALL_TMP}" | awk '{print $1}')
  elif command -v sha256sum &>/dev/null; then
    codex_sha=$(sha256sum "${CODEX_INSTALL_TMP}" | awk '{print $1}')
  else
    echo "[forge-plugin] WARNING: Neither shasum nor sha256sum found — cannot verify Code installer integrity." >&2
    codex_sha="UNAVAILABLE"
  fi

  echo "[forge-plugin] Code installer SHA-256: ${codex_sha}"
  echo "[forge-plugin] IMPORTANT: Compare this hash against the pinned registry entry before proceeding."

  if [ -z "${CODEX_INSTALL_SHA}" ]; then
    echo "[forge-plugin] ERROR: No pinned Code SHA-256 is configured in sidekicks/registry.json." >&2
    exit 1
  fi

  if [ "${codex_sha}" = "UNAVAILABLE" ]; then
    echo "[forge-plugin] ERROR: Cannot verify Code installer integrity without shasum or sha256sum." >&2
    exit 1
  fi

  if [ "${codex_sha}" != "${CODEX_INSTALL_SHA}" ]; then
    echo "[forge-plugin] ERROR: Code SHA-256 MISMATCH — aborting installation." >&2
    echo "[forge-plugin]   Got:      ${codex_sha}" >&2
    echo "[forge-plugin]   Expected: ${CODEX_INSTALL_SHA}" >&2
    exit 1
  fi

  echo "[forge-plugin] Code installer verified against pinned hash — OK."

  bash "${CODEX_INSTALL_TMP}"

  codex_source="$(resolve_codex_binary || true)"
  if [ -z "${codex_source}" ]; then
    echo "[forge-plugin] ERROR: Code install completed but code binary was not found." >&2
    exit 1
  fi

  ensure_codex_aliases "${codex_source}"
  echo "[forge-plugin] Code runtime ready."
}

  install_codex_runtime
else
  echo "[forge-plugin] Skipping Code bootstrap/repair (SIDEKICK_INSTALL_CODE=0)."
fi

if bootstrap_host="$(detect_install_host 2>/dev/null)"; then
  bootstrap_sidekick_cache_tree "${bootstrap_host}" "${SOURCE_PLUGIN_ROOT}" "${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
fi

if install_host="$(detect_install_host 2>/dev/null)"; then
  rewrite_host_surface "${install_host}"
fi

# --- Ensure PATH includes ~/.local/bin in common shell profiles ---
# Appends a single idempotent line (only if .local/bin not already present).
# Each addition is preceded by a marker comment so it can be easily found and
# removed if you want to undo this change.
# (SENTINEL FINDING-10.1: persistence transparency)
if [ "${INSTALL_FORGE}" = "1" ] || [ "${INSTALL_CODE}" = "1" ]; then
  add_to_path() {
    local profile="$1"
    local marker='# Added by sidekick/forge plugin (https://github.com/alo-exp/sidekick) — remove this block to undo'
    local line="export PATH=\"${SIDEKICK_BIN_DIR}:\$PATH\""
    if [ -f "${profile}" ] && ! (grep -qF "${SIDEKICK_BIN_DIR}" "${profile}" || grep -qF '$HOME/.local/bin' "${profile}"); then
      # R6-5: Symlink validation — refuse to append to a profile that is a symlink
      # pointing outside the user's home directory (potential symlink hijack).
      if [ -L "${profile}" ]; then
        local real_target
        real_target=$(realpath "${profile}" 2>/dev/null || readlink -f "${profile}" 2>/dev/null || echo "")
        local home_prefix
        home_prefix=$(realpath "${HOME}" 2>/dev/null || echo "${HOME}")
        if [[ "${real_target}" != "${home_prefix}/"* ]]; then
          echo "[forge-plugin] WARNING: ${profile} is a symlink pointing outside HOME (${real_target}). Skipping PATH addition." >&2
          return 0
        fi
      fi
      # R7-5: Ownership check — refuse to append to a profile not owned by the current user.
      local file_owner
      file_owner=$(stat -c '%U' "${profile}" 2>/dev/null || stat -f '%Su' "${profile}" 2>/dev/null || echo "")
      local current_user="${USER:-$(id -un)}"
      if [ -n "${file_owner}" ] && [ "${file_owner}" != "${current_user}" ]; then
        echo "[forge-plugin] WARNING: ${profile} is owned by '${file_owner}', not '${current_user}'. Skipping PATH addition." >&2
        return 0
      fi
      printf '\n%s\n%s\n' "${marker}" "${line}" >> "${profile}"
      echo "[forge-plugin] Added ${SIDEKICK_BIN_DIR} to PATH in ${profile} (marker: 'Added by sidekick/forge plugin')"
    fi
  }

  # --- Pre-consent notice before shell profile modification ---
  # (SENTINEL FINDING-10.1 R2: pre-consent hardening)
  if [ -t 1 ]; then
    # Interactive terminal: give user a cancellation window
    echo "[forge-plugin] NOTICE: About to add ${SIDEKICK_BIN_DIR} to PATH in:"
    echo "[forge-plugin]   ~/.zshrc, ~/.bashrc, ~/.bash_profile (if they exist and don't already have it)"
    echo "[forge-plugin] This makes the 'forge' command available in new terminal sessions."
    echo "[forge-plugin] Press Ctrl+C within 10 seconds to cancel, or wait to proceed."
    sleep 10
  else
    # Non-interactive (SessionStart hook context): print notice with undo instructions
    echo "[forge-plugin] NOTICE: Adding ${SIDEKICK_BIN_DIR} to PATH in shell profiles (if not already present)."
    echo "[forge-plugin] To undo: remove lines marked 'Added by sidekick/forge plugin' from ~/.zshrc etc."
  fi

  add_to_path "${HOME}/.zshrc"
  add_to_path "${HOME}/.bashrc"
  add_to_path "${HOME}/.bash_profile"

  export PATH="${HOME}/.local/bin:${PATH}"

  # --- Verify installation ---
  # R6-10: Binary identity check — confirm the 'forge' binary is actually ForgeCode,
  # not a different tool that happens to share the name.
  if [ -x "${FORGE_BIN}" ]; then
    VERSION=$("${FORGE_BIN}" --version 2>/dev/null || echo "unknown")
    # ForgeCode --version output contains "forge" or "forgecode"; warn if it doesn't.
    if echo "${VERSION}" | grep -qiE 'forge|forgecode'; then
      echo "[forge-plugin] ForgeCode ${VERSION} ready."
    else
      echo "[forge-plugin] WARNING: Binary at ${FORGE_BIN} reported version '${VERSION}'." >&2
      echo "[forge-plugin] WARNING: This does not look like ForgeCode. Verify the binary manually." >&2
    fi
  else
    echo "[forge-plugin] WARNING: forge binary not found after install. Check PATH." >&2
  fi

  # --- Credential file permissions hardening ---
  # S4-FIX: Ensure ~/forge/.credentials.json is never world-readable.
  # If the file already exists (written by STEP 0A setup or a prior install),
  # enforce 600 permissions so only the owning user can read it.
  # This is also called after every install/re-install for idempotent safety.
  CREDS_FILE="${HOME}/forge/.credentials.json"
  if [ -f "${CREDS_FILE}" ]; then
    chmod 600 "${CREDS_FILE}"
    echo "[forge-plugin] Credential file permissions set to 600 (user-only read/write)."
  fi
fi

echo "[forge-plugin] Setup complete. Ask Claude to configure your OpenRouter API key."

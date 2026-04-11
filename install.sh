#!/usr/bin/env bash
# Forge Plugin — auto-install script
# Called once by SessionStart hook (hooks/hooks.json) via .installed sentinel.
# Installs the ForgeCode binary and adds it to PATH.
# Provider/API key setup is guided interactively by the forge skill in Claude.

set -euo pipefail

FORGE_BIN="${HOME}/.local/bin/forge"

echo "[forge-plugin] Checking ForgeCode installation..."

# --- Install forge binary if not present ---
if [ ! -f "${FORGE_BIN}" ] && ! command -v forge &>/dev/null; then
  echo "[forge-plugin] Installing ForgeCode..."
  # Download install script to a temp file first — do NOT pipe directly to sh.
  # Downloading to a file avoids stream-injection attacks and prints the SHA-256
  # so the user can verify the download matches a known-good release.
  # (SENTINEL FINDING-7.1: supply chain hardening)
  FORGE_INSTALL_TMP=$(mktemp /tmp/forge-install.XXXXXX.sh)
  trap 'rm -f "${FORGE_INSTALL_TMP}"' EXIT
  if command -v curl &>/dev/null; then
    curl -fsSL https://forgecode.dev/cli -o "${FORGE_INSTALL_TMP}"
  elif command -v wget &>/dev/null; then
    wget -qO "${FORGE_INSTALL_TMP}" https://forgecode.dev/cli
  else
    echo "[forge-plugin] ERROR: Neither curl nor wget found. Install ForgeCode manually from https://forgecode.dev" >&2
    exit 1
  fi
  FORGE_SHA=$(shasum -a 256 "${FORGE_INSTALL_TMP}" | awk '{print $1}')
  FORGE_SHA_LOG="${HOME}/.local/share/forge-plugin-install-sha.log"
  mkdir -p "$(dirname "${FORGE_SHA_LOG}")"
  echo "[forge-plugin] Install script SHA-256: ${FORGE_SHA}"
  echo "[forge-plugin] IMPORTANT: Compare this hash against the official release at:"
  echo "[forge-plugin]   https://forgecode.dev/releases  (or GitHub releases page)"
  echo "[forge-plugin] If hashes do not match, delete ${FORGE_INSTALL_TMP} and abort."
  # Log SHA to a persistent file so the user can verify even in non-interactive contexts
  printf '%s  %s  (downloaded %s)\n' "${FORGE_SHA}" "forgecode-install.sh" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${FORGE_SHA_LOG}"
  echo "[forge-plugin] SHA logged to: ${FORGE_SHA_LOG}"
  # R6-1: In non-interactive mode Ctrl+C may not be available; give a short window anyway.
  sleep 5
  bash "${FORGE_INSTALL_TMP}"
  echo "[forge-plugin] ForgeCode installed."
else
  echo "[forge-plugin] ForgeCode already installed."
fi

# --- Ensure PATH includes ~/.local/bin in common shell profiles ---
# Appends a single idempotent line (only if .local/bin not already present).
# Each addition is preceded by a marker comment so it can be easily found and
# removed if you want to undo this change.
# (SENTINEL FINDING-10.1: persistence transparency)
add_to_path() {
  local profile="$1"
  local marker='# Added by sidekick/forge plugin (https://github.com/alo-exp/sidekick) — remove this block to undo'
  local line='export PATH="$HOME/.local/bin:$PATH"'
  if [ -f "${profile}" ] && ! grep -qF '.local/bin' "${profile}"; then
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
    printf '\n%s\n%s\n' "${marker}" "${line}" >> "${profile}"
    echo "[forge-plugin] Added ~/.local/bin to PATH in ${profile} (marker: 'Added by sidekick/forge plugin')"
  fi
}

# --- Pre-consent notice before shell profile modification ---
# (SENTINEL FINDING-10.1 R2: pre-consent hardening)
if [ -t 1 ]; then
  # Interactive terminal: give user a cancellation window
  echo "[forge-plugin] NOTICE: About to add ~/.local/bin to PATH in:"
  echo "[forge-plugin]   ~/.zshrc, ~/.bashrc, ~/.bash_profile (if they exist and don't already have it)"
  echo "[forge-plugin] This makes the 'forge' command available in new terminal sessions."
  echo "[forge-plugin] Press Ctrl+C within 10 seconds to cancel, or wait to proceed."
  sleep 10
else
  # Non-interactive (SessionStart hook context): print notice with undo instructions
  echo "[forge-plugin] NOTICE: Adding ~/.local/bin to PATH in shell profiles (if not already present)."
  echo "[forge-plugin] To undo: remove lines marked 'Added by sidekick/forge plugin' from ~/.zshrc etc."
fi

add_to_path "${HOME}/.zshrc"
add_to_path "${HOME}/.bashrc"
add_to_path "${HOME}/.bash_profile"

export PATH="${HOME}/.local/bin:${PATH}"

# --- Verify installation ---
# R6-10: Binary identity check — confirm the 'forge' binary is actually ForgeCode,
# not a different tool that happens to share the name.
if command -v forge &>/dev/null || [ -f "${FORGE_BIN}" ]; then
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

echo "[forge-plugin] Setup complete. Ask Claude to configure your OpenRouter API key."

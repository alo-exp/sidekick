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
  curl -fsSL https://forgecode.dev/cli | sh
  echo "[forge-plugin] ForgeCode installed."
else
  echo "[forge-plugin] ForgeCode already installed."
fi

# --- Ensure PATH includes ~/.local/bin in common shell profiles ---
add_to_path() {
  local profile="$1"
  local line='export PATH="$HOME/.local/bin:$PATH"'
  if [ -f "${profile}" ] && ! grep -qF '.local/bin' "${profile}"; then
    echo "${line}" >> "${profile}"
    echo "[forge-plugin] Added ~/.local/bin to PATH in ${profile}"
  fi
}

add_to_path "${HOME}/.zshrc"
add_to_path "${HOME}/.bashrc"
add_to_path "${HOME}/.bash_profile"

export PATH="${HOME}/.local/bin:${PATH}"

# --- Verify installation ---
if command -v forge &>/dev/null || [ -f "${FORGE_BIN}" ]; then
  VERSION=$("${FORGE_BIN}" --version 2>/dev/null || echo "unknown")
  echo "[forge-plugin] ForgeCode ${VERSION} ready."
else
  echo "[forge-plugin] WARNING: forge binary not found after install. Check PATH." >&2
fi

echo "[forge-plugin] Setup complete. Ask Claude to configure your OpenRouter API key."

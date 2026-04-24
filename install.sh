#!/usr/bin/env bash
# Forge Plugin — auto-install script
# Called once by SessionStart hook (hooks/hooks.json) via .installed sentinel.
# Installs the ForgeCode binary and adds it to PATH.
# Provider/API key setup is guided interactively by the forge skill in Claude.
#
# SECURITY NOTE (R8-2): This script runs non-interactively under the SessionStart hook.
# Ctrl+C is not available to cancel the download. The SHA-256 of the downloaded script is
# logged to ~/.local/share/forge-plugin-install-sha.log — verify it against the official
# release hash at https://forgecode.dev/releases after the session starts.

set -euo pipefail

FORGE_BIN="${HOME}/.local/bin/forge"

# R8-3/R10-1: Pinned SHA-256 of the ForgeCode install script (https://forgecode.dev/cli).
# This enables automated mismatch-abort before execution.
# UPDATE THIS VALUE when upgrading ForgeCode — fetch the new hash with:
#   curl -fsSL https://forgecode.dev/cli | shasum -a 256
# Verify the hash matches the official release at: https://forgecode.dev/releases
# Leave blank ("") only if you intentionally want display-only verification.
# (SENTINEL FINDING-R7-7/R8-3/R10-1: supply chain hardening)
EXPECTED_FORGE_SHA="512d41a611962a8d07a7efac54fba2718867ca28ce9d5d1d02da465b141ce05a"

echo "[forge-plugin] Checking ForgeCode installation..."

# --- Install forge binary if not present ---
if [ ! -f "${FORGE_BIN}" ] && ! command -v forge &>/dev/null; then
  echo "[forge-plugin] Installing ForgeCode..."
  # Download install script to a temp file first — do NOT pipe directly to sh.
  # Downloading to a file avoids stream-injection attacks and prints the SHA-256
  # so the user can verify the download matches a known-good release.
  # (SENTINEL FINDING-7.1: supply chain hardening)
  FORGE_INSTALL_TMP=$(mktemp "${TMPDIR:-/tmp}/forge-install.XXXXXX")
  trap 'rm -f "${FORGE_INSTALL_TMP}"' EXIT
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
    echo "[forge-plugin] WARNING: Neither shasum nor sha256sum found — cannot verify download integrity." >&2
    FORGE_SHA="UNAVAILABLE"
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
  if [ -n "${EXPECTED_FORGE_SHA}" ] && [ "${FORGE_SHA}" != "UNAVAILABLE" ]; then
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
    # R7-5: Ownership check — refuse to append to a profile not owned by the current user.
    local file_owner
    file_owner=$(stat -c '%U' "${profile}" 2>/dev/null || stat -f '%Su' "${profile}" 2>/dev/null || echo "")
    local current_user="${USER:-$(id -un)}"
    if [ -n "${file_owner}" ] && [ "${file_owner}" != "${current_user}" ]; then
      echo "[forge-plugin] WARNING: ${profile} is owned by '${file_owner}', not '${current_user}'. Skipping PATH addition." >&2
      return 0
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

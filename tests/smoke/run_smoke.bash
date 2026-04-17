#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Live Forge Smoke Harness
# =============================================================================
# Hits the real `forge` binary on $PATH. Gated behind SIDEKICK_LIVE_FORGE=1 so
# CI never runs it. Intended to run pre-release on the maintainer's machine,
# where Forge is already installed and configured.
#
# What this DOES test
#   - `forge --version` returns a semver-ish string (binary reachable)
#   - `forge -p "..."` with a trivial prompt returns exit 0 AND emits STATUS:
#     … on stdout (proves tool-use + structured output pathway works)
#
# What this does NOT test
#   - Delegation enforcement (that's covered by the unit suite)
#   - Specific model quality (that's covered by the live E2E driver in
#     tests/run_live_e2e.bash)
#
# Exit codes
#   0 — smoke passed, OR env var absent (skipped cleanly)
#   1 — smoke failed (forge unreachable or STATUS missing)
# =============================================================================

set -uo pipefail

green='\033[0;32m'; red='\033[0;31m'; yellow='\033[0;33m'; bold='\033[1m'; reset='\033[0m'

if [[ "${SIDEKICK_LIVE_FORGE:-}" != "1" ]]; then
  echo -e "${yellow}Smoke harness skipped${reset} (set SIDEKICK_LIVE_FORGE=1 to run against the real forge binary)."
  exit 0
fi

echo -e "${bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"
echo -e "${bold}Sidekick live-Forge smoke harness${reset}"
echo -e "${bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"

PASS=0; FAIL=0
pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

# -----------------------------------------------------------------------------
# Precondition: forge on PATH
# -----------------------------------------------------------------------------
echo "=== smoke_forge_on_path ==="
if command -v forge >/dev/null 2>&1; then
  pass "smoke_forge_on_path ($(command -v forge))"
else
  fail "smoke_forge_on_path" "forge not on PATH"
  echo "Aborting smoke — forge binary required."
  exit 1
fi

# -----------------------------------------------------------------------------
# Check: version reachable
# -----------------------------------------------------------------------------
echo "=== smoke_forge_version ==="
_ver_out="$(forge --version 2>&1 || true)"
if [[ "$_ver_out" == *"forge"* ]] || [[ "$_ver_out" =~ [0-9]+\.[0-9]+ ]]; then
  pass "smoke_forge_version (${_ver_out})"
else
  fail "smoke_forge_version" "unexpected: ${_ver_out}"
fi

# -----------------------------------------------------------------------------
# Check: trivial forge -p round-trip
#
# We ask Forge to emit the sidekick STATUS: pattern directly. This is the
# shape every Sidekick delegation expects to see; if Forge + the model +
# tool-use + prompt rendering are all working, the response will contain it.
# Timeout-bounded so a hung API call fails the smoke instead of the runner.
# -----------------------------------------------------------------------------
echo "=== smoke_forge_p_structured_output ==="
_timeout_bin=""
if command -v gtimeout >/dev/null 2>&1; then _timeout_bin="gtimeout"
elif command -v timeout >/dev/null 2>&1; then _timeout_bin="timeout"
fi

_prompt='Respond with exactly two lines and nothing else:
STATUS: SUCCESS
FILES_CHANGED: []'

if [[ -n "$_timeout_bin" ]]; then
  _forge_out="$("$_timeout_bin" 60 forge -p "$_prompt" 2>&1 || true)"
else
  _forge_out="$(forge -p "$_prompt" 2>&1 || true)"
fi

# Strip ANSI so STATUS: detection is robust to colored output.
_forge_clean="$(printf '%s' "$_forge_out" | sed $'s/\x1b\\[[0-9;]*m//g')"

if printf '%s' "$_forge_clean" | grep -q 'STATUS:'; then
  pass "smoke_forge_p_structured_output"
else
  fail "smoke_forge_p_structured_output" "no STATUS: line in forge -p output"
  echo "--- forge output (first 30 lines) ---"
  printf '%s\n' "$_forge_clean" | head -n 30
  echo "--- end ---"
fi

echo ""
echo -e "${bold}═══════════════════════════════════════════${reset}"
if [[ "$FAIL" -eq 0 ]]; then
  echo -e "${green}${bold}SMOKE PASSED${reset} ($PASS checks)"
else
  echo -e "${red}${bold}SMOKE FAILED${reset} ($FAIL of $((PASS+FAIL)) failed)"
fi
echo -e "${bold}═══════════════════════════════════════════${reset}"

exit "$FAIL"

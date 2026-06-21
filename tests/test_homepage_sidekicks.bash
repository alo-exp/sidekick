#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin -- homepage current sidekick surface tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PAGE="${ROOT}/site/index.html"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

expect_contains() {
  local needle="$1" label="$2"
  if grep -Fq -- "${needle}" "${PAGE}"; then pass "${label}"; else fail "${label}" "missing ${needle}"; fi
}

expect_absent() {
  local needle="$1" label="$2"
  if grep -Fqi -- "${needle}" "${PAGE}"; then fail "${label}" "unexpected ${needle}"; else pass "${label}"; fi
}

echo "=== T1: homepage exposes supported sidekicks ==="
expect_contains "Sidekick 0.8.4" "homepage shows release version"
expect_contains "Cursor" "homepage includes Cursor host"
expect_contains "Kay sidekick" "homepage includes Kay"
expect_contains "Codex sidekick" "homepage includes Codex"
expect_contains "/sidekick:kay" "homepage shows Kay activation"
expect_contains "/sidekick:kay-stop" "homepage shows Kay stop"
expect_contains "/sidekick:codex" "homepage shows Codex activation"
expect_contains "/sidekick:codex-stop" "homepage shows Codex stop"
expect_contains "gpt-5.4-mini" "homepage documents Codex model"

echo "=== T2: homepage documents verification and release evidence ==="
expect_contains "Host verification" "homepage includes host verification"
expect_contains "SIDEKICK_LIVE_CODEX=1" "homepage includes live release gate flag"
expect_contains "Help" "homepage links help"
expect_contains "Compatibility" "homepage links compatibility"
expect_contains "Testing" "homepage links testing"

echo "=== T3: removed sidekick copy is absent ==="
expect_absent "forge" "homepage is free of removed sidekick text"
expect_absent "/forge" "homepage is free of removed activation commands"
expect_absent "forgecode" "homepage is free of removed runtime text"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

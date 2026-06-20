#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin -- social preview tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PAGE="${ROOT}/site/og-image.html"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

contains() {
  local needle="$1" label="$2"
  if grep -Fq -- "${needle}" "${PAGE}"; then pass "${label}"; else fail "${label}" "missing ${needle}"; fi
}

absent() {
  local needle="$1" label="$2"
  if grep -Fqi -- "${needle}" "${PAGE}"; then fail "${label}" "unexpected ${needle}"; else pass "${label}"; fi
}

echo "=== T1: preview reflects supported sidekicks ==="
contains "Kay + Codex Delegation" "preview title names Kay and Codex"
contains "/sidekick:kay" "preview includes Kay activation"
contains "/sidekick:codex" "preview includes Codex activation"
contains "host verifies every result" "preview states host verification"

echo "=== T2: preview has no removed sidekick copy ==="
absent "forge" "preview is free of removed sidekick text"
absent "forgecode" "preview is free of removed runtime text"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

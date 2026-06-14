#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin -- docs contract tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

contains() {
  local rel="$1" needle="$2" label="$3"
  if grep -Fq -- "${needle}" "${ROOT}/${rel}"; then pass "${label}"; else fail "${label}" "missing ${needle} in ${rel}"; fi
}

absent_i() {
  local rel="$1" needle="$2" label="$3"
  if grep -Fqi -- "${needle}" "${ROOT}/${rel}"; then fail "${label}" "unexpected ${needle} in ${rel}"; else pass "${label}"; fi
}

current_docs=(
  README.md
  context.md
  site/ARCHITECTURE.md
  site/COMPATIBILITY.md
  site/PRD-Overview.md
  site/GLOSSARY.md
  site/START-HERE.md
  site/TESTING.md
)

echo "=== T1: docs expose Kay and Codex only ==="
contains "README.md" "/sidekick:kay-delegate" "README documents Kay activation"
contains "README.md" "/sidekick:codex-delegate" "README documents Codex activation"
contains "README.md" "gpt-5.4-mini" "README documents Codex model"
contains "context.md" "active-sidekick" "context documents active selector"
contains "site/COMPATIBILITY.md" "Kay compatibility aliases" "compatibility documents Kay aliases"
contains "site/COMPATIBILITY.md" "Cursor host" "compatibility documents Cursor host"
contains "site/ARCHITECTURE.md" "Supported Sidekicks" "architecture documents supported sidekicks"
contains "site/GLOSSARY.md" "Host verification" "glossary defines host verification"
contains "site/TESTING.md" "SIDEKICK_LIVE_CODEX=1" "testing documents live release flag"

echo "=== T2: current docs have no removed sidekick surface ==="
for rel in "${current_docs[@]}"; do
  absent_i "${rel}" "forge" "${rel} is free of removed sidekick text"
  absent_i "${rel}" "/forge" "${rel} is free of removed activation commands"
  absent_i "${rel}" "forgecode" "${rel} is free of removed runtime text"
done

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] || exit 1

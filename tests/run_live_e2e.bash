#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Live Forge End-to-End Driver
# =============================================================================
# Pre-release check that exercises a FULL Claude→Forge delegation round-trip
# against the real forge binary and the real model, on a seeded buggy
# testapp. Gated behind SIDEKICK_LIVE_FORGE=1. Never runs in CI.
#
# Flow
#   1. Copy tests/testapp/ to $TMPDIR so the canonical source never mutates.
#   2. Run the testapp's unittest — baseline MUST fail (bug is real).
#   3. Send Forge a 5-field task prompt (OBJECTIVE/CONTEXT/DESIRED STATE/
#      SUCCESS CRITERIA/INJECTED SKILLS) asking it to fix `add`.
#   4. Re-run the testapp's unittest — MUST now pass (all 3 tests).
#   5. Assert calc.py changed (bug fixed with a `+`).
#   6. Print the path to the sandbox so the maintainer can inspect.
#
# Exit codes
#   0 — E2E passed, OR env var absent (skipped cleanly)
#   1 — any assertion failed, or forge returned non-zero, or timeout tripped
# =============================================================================

set -uo pipefail

green='\033[0;32m'; red='\033[0;31m'; yellow='\033[0;33m'; bold='\033[1m'; reset='\033[0m'

if [[ "${SIDEKICK_LIVE_FORGE:-}" != "1" ]]; then
  echo -e "${yellow}Live E2E skipped${reset} (set SIDEKICK_LIVE_FORGE=1 to run the full testapp round-trip)."
  exit 0
fi

echo -e "${bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"
echo -e "${bold}Sidekick live-Forge E2E driver${reset}"
echo -e "${bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"

if ! command -v forge >/dev/null 2>&1; then
  echo -e "${red}FAIL${reset}: forge not on PATH"
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo -e "${red}FAIL${reset}: python3 not on PATH"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTAPP_SRC="$SCRIPT_DIR/testapp"
[[ -f "$TESTAPP_SRC/calc.py" && -f "$TESTAPP_SRC/test_calc.py" ]] || {
  echo -e "${red}FAIL${reset}: testapp source not found at $TESTAPP_SRC"
  exit 1
}

SANDBOX="$(mktemp -d -t sidekick-e2e.XXXXXX)"
cp "$TESTAPP_SRC/calc.py" "$TESTAPP_SRC/test_calc.py" "$SANDBOX/"
echo "Sandbox: $SANDBOX"

PASS=0; FAIL=0
pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

_timeout_bin=""
if command -v gtimeout >/dev/null 2>&1; then _timeout_bin="gtimeout"
elif command -v timeout >/dev/null 2>&1; then _timeout_bin="timeout"
fi
timeout_run() {
  local seconds="$1"; shift
  if [[ -n "$_timeout_bin" ]]; then
    "$_timeout_bin" "$seconds" "$@"
  else
    "$@"
  fi
}

run_unittest() {
  # Run from inside the sandbox so `from calc import ...` resolves.
  ( cd "$SANDBOX" && python3 -m unittest test_calc 2>&1 )
}

# -----------------------------------------------------------------------------
echo "=== e2e_baseline_fails ==="
_base="$(run_unittest || true)"
if printf '%s' "$_base" | grep -qE 'FAILED \(failures='; then
  pass "e2e_baseline_fails (bug is live)"
else
  fail "e2e_baseline_fails" "expected baseline failure, got:
$_base"
  echo "Aborting E2E."
  exit 1
fi

# -----------------------------------------------------------------------------
# Task prompt — the same 5-field shape the /forge skill uses for real
# delegations. Kept under 600 tokens so weaker models also handle it.
# -----------------------------------------------------------------------------
read -r -d '' TASK_PROMPT <<'EOF' || true
OBJECTIVE: Fix the bug in calc.py so that the add function returns the sum of its two arguments instead of the difference.

CONTEXT:
- Working directory contains calc.py and test_calc.py.
- calc.py currently defines add as return a - b — this is the bug.
- test_calc.py (pure stdlib unittest) asserts add(2,3)==5 and add(-1,1)==0.
- sub is already correct and must NOT be changed.

DESIRED STATE:
- calc.py's add returns a + b.
- sub is unchanged (still a - b).
- No new files, no new imports.

SUCCESS CRITERIA:
- Running python3 -m unittest test_calc from this directory exits 0 with all 3 tests passing.
- calc.py is syntactically valid Python 3.

INJECTED SKILLS: quality-gates, testing-strategy

After making the edit, verify by running the tests.
EOF

echo "=== e2e_forge_delegation ==="
echo "Sending 5-field prompt to forge (timeout 180s)..."
# Capture full output + exit code.
set +e
FORGE_OUT="$(timeout_run 180 forge -C "$SANDBOX" -p "$TASK_PROMPT" 2>&1)"
FORGE_RC=$?
set -e
echo "forge rc=$FORGE_RC"
echo "--- forge output (tail 40 lines) ---"
printf '%s\n' "$FORGE_OUT" | tail -n 40
echo "--- end forge output ---"

if [[ "$FORGE_RC" -eq 0 ]]; then
  pass "e2e_forge_delegation (rc=0)"
else
  fail "e2e_forge_delegation" "forge exited non-zero (rc=$FORGE_RC)"
fi

# -----------------------------------------------------------------------------
echo "=== e2e_calc_py_patched ==="
if grep -qE '^[[:space:]]*return[[:space:]]+a[[:space:]]*\+[[:space:]]*b' "$SANDBOX/calc.py"; then
  pass "e2e_calc_py_patched (add now returns a+b)"
else
  fail "e2e_calc_py_patched" "calc.py still broken:
$(cat "$SANDBOX/calc.py")"
fi

# -----------------------------------------------------------------------------
echo "=== e2e_sub_preserved ==="
# sub should still be `a - b` — forge shouldn't have over-fixed.
_sub_line="$(awk '/^def sub/,/^$/' "$SANDBOX/calc.py")"
if printf '%s' "$_sub_line" | grep -qE 'return[[:space:]]+a[[:space:]]*-[[:space:]]*b'; then
  pass "e2e_sub_preserved"
else
  fail "e2e_sub_preserved" "sub function changed unexpectedly:
$_sub_line"
fi

# -----------------------------------------------------------------------------
echo "=== e2e_tests_pass_after_fix ==="
_post="$(run_unittest || true)"
if printf '%s' "$_post" | grep -qE '^OK$' && printf '%s' "$_post" | grep -qE 'Ran 3 tests'; then
  pass "e2e_tests_pass_after_fix"
else
  fail "e2e_tests_pass_after_fix" "unittest output:
$_post"
fi

# -----------------------------------------------------------------------------
echo ""
echo -e "${bold}═══════════════════════════════════════════${reset}"
if [[ "$FAIL" -eq 0 ]]; then
  echo -e "${green}${bold}LIVE E2E PASSED${reset} ($PASS checks)"
  echo "Sandbox preserved for inspection: $SANDBOX"
else
  echo -e "${red}${bold}LIVE E2E FAILED${reset} ($FAIL of $((PASS+FAIL)) failed)"
  echo "Sandbox preserved for inspection: $SANDBOX"
fi
echo -e "${bold}═══════════════════════════════════════════${reset}"

exit "$FAIL"

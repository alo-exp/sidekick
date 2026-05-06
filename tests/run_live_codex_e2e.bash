#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Live Codex End-to-End Driver
# =============================================================================
# Pre-release check that exercises a FULL Claude→Codex delegation round-trip
# against the real Codex binary and the real model, on a seeded buggy testapp.
# Gated behind SIDEKICK_LIVE_CODEX=1. Never runs in CI.
#
# Flow
#   1. Copy tests/testapp/ to $TMPDIR so the canonical source never mutates.
#   2. Run the testapp's unittest — baseline MUST fail (bug is real).
#   3. Send Codex a 5-field task prompt (OBJECTIVE/CONTEXT/DESIRED STATE/
#      SUCCESS CRITERIA/INJECTED SKILLS) asking it to fix `add`.
#   4. Re-run the testapp's unittest — MUST now pass (all 3 tests).
#   5. Assert calc.py changed (bug fixed with a `+`).
#   6. Print the path to the sandbox so the maintainer can inspect.
#
# Exit codes
#   0 — E2E passed, OR env var absent (skipped cleanly)
#   1 — any assertion failed, or Codex returned non-zero, or timeout tripped
# =============================================================================

set -uo pipefail

green='\033[0;32m'; red='\033[0;31m'; yellow='\033[0;33m'; bold='\033[1m'; reset='\033[0m'

if [[ "${SIDEKICK_LIVE_CODEX:-}" != "1" ]]; then
  echo -e "${yellow}Live E2E skipped${reset} (set SIDEKICK_LIVE_CODEX=1 to run the full Codex round-trip)."
  exit 0
fi

echo -e "${bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"
echo -e "${bold}Sidekick live-Codex E2E driver${reset}"
echo -e "${bold}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${reset}"

if ! command -v codex >/dev/null 2>&1 && ! command -v code >/dev/null 2>&1 && ! command -v coder >/dev/null 2>&1; then
  echo -e "${red}FAIL${reset}: codex/code/coder not on PATH"
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo -e "${red}FAIL${reset}: python3 not on PATH"
  exit 1
fi

resolve_codex_binary() {
  for candidate in codex code coder; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

prepare_codex_runner() {
  local bin="$1"
  local help_file
  help_file="$(mktemp)"
  CODEX_RUNNER=()

  if "${bin}" exec --help >"${help_file}" 2>&1; then
    if grep -q -- '--full-auto' "${help_file}"; then
      CODEX_RUNNER=( "${bin}" exec --full-auto )
    elif grep -q -- '--dangerously-bypass-approvals-and-sandbox' "${help_file}"; then
      CODEX_RUNNER=( "${bin}" exec --skip-git-repo-check --ephemeral --dangerously-bypass-approvals-and-sandbox )
    else
      CODEX_RUNNER=( "${bin}" exec )
    fi
  elif "${bin}" --help 2>&1 | grep -q -- '--no-approval'; then
    CODEX_RUNNER=( "${bin}" --no-approval )
  else
    CODEX_RUNNER=( "${bin}" )
  fi

  rm -f "${help_file}"
}

run_with_timeout() {
  local secs="$1"; shift
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${secs}" "$@"
  elif command -v timeout >/dev/null 2>&1; then
    timeout "${secs}" "$@"
  else
    "$@"
  fi
}

CODEX_BIN="$(resolve_codex_binary)"
prepare_codex_runner "${CODEX_BIN}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTAPP_SRC="${SCRIPT_DIR}/testapp"
[[ -f "${TESTAPP_SRC}/calc.py" && -f "${TESTAPP_SRC}/test_calc.py" ]] || {
  echo -e "${red}FAIL${reset}: testapp source not found at ${TESTAPP_SRC}"
  exit 1
}

SANDBOX="$(mktemp -d -t sidekick-codex-e2e.XXXXXX)"
cp "${TESTAPP_SRC}/calc.py" "${TESTAPP_SRC}/test_calc.py" "${SANDBOX}/"
echo "Sandbox: ${SANDBOX}"

PASS=0; FAIL=0
pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

run_unittest() {
  ( cd "${SANDBOX}" && python3 -m unittest test_calc 2>&1 )
}

echo "=== e2e_baseline_fails ==="
_base="$(run_unittest || true)"
if printf '%s' "${_base}" | grep -qE 'FAILED \(failures='; then
  pass "e2e_baseline_fails (bug is live)"
else
  fail "e2e_baseline_fails" "expected baseline failure, got:
${_base}"
  echo "Aborting E2E."
  exit 1
fi

read -r -d '' TASK_PROMPT <<'EOF' || true
OBJECTIVE: Fix the bug in calc.py so that the add function returns the sum of its two arguments instead of the difference.

CONTEXT:
- Working directory contains calc.py and test_calc.py.
- calc.py currently defines add as return a - b, which is wrong.
- test_calc.py asserts add(2,3)==5 and add(-1,1)==0.
- sub is already correct and must NOT be changed.

DESIRED STATE:
- calc.py's add returns a + b.
- sub is unchanged.
- No new files or imports.

SUCCESS CRITERIA:
- python3 -m unittest test_calc exits 0 with all 3 tests passing.
- calc.py is syntactically valid Python 3.

INJECTED SKILLS: quality-gates, testing-strategy

After making the edit, verify by running the tests.
EOF

echo "=== e2e_codex_delegation ==="
echo "Sending 5-field prompt to Codex (timeout 180s)..."
set +e
CODEX_OUT="$(cd "${SANDBOX}" && run_with_timeout 180 "${CODEX_RUNNER[@]}" "${TASK_PROMPT}" 2>&1)"
CODEX_RC=$?
set -e
echo "codex rc=${CODEX_RC}"
echo "--- codex output (tail 40 lines) ---"
printf '%s\n' "${CODEX_OUT}" | tail -n 40
echo "--- end codex output ---"

if [[ "${CODEX_RC}" -eq 0 ]]; then
  pass "e2e_codex_delegation (rc=0)"
else
  fail "e2e_codex_delegation" "Codex exited non-zero (rc=${CODEX_RC})"
fi

echo "=== e2e_calc_py_patched ==="
if grep -qE '^[[:space:]]*return[[:space:]]+a[[:space:]]*\+[[:space:]]*b' "${SANDBOX}/calc.py"; then
  pass "e2e_calc_py_patched (add now returns a+b)"
else
  fail "e2e_calc_py_patched" "calc.py still broken:
$(cat "${SANDBOX}/calc.py")"
fi

echo "=== e2e_sub_preserved ==="
_sub_line="$(awk '/^def sub/,/^$/' "${SANDBOX}/calc.py")"
if printf '%s' "${_sub_line}" | grep -qE 'return[[:space:]]+a[[:space:]]*-[[:space:]]*b'; then
  pass "e2e_sub_preserved"
else
  fail "e2e_sub_preserved" "sub function changed unexpectedly:
${_sub_line}"
fi

echo "=== e2e_tests_pass_after_fix ==="
_post="$(run_unittest || true)"
if printf '%s' "${_post}" | grep -qE '^OK$' && printf '%s' "${_post}" | grep -qE 'Ran 3 tests'; then
  pass "e2e_tests_pass_after_fix"
else
  fail "e2e_tests_pass_after_fix" "unittest output:
${_post}"
fi

echo ""
echo -e "${bold}═══════════════════════════════════════════${reset}"
if [[ "${FAIL}" -eq 0 ]]; then
  echo -e "${green}${bold}LIVE E2E PASSED${reset} ($PASS checks)"
  echo "Sandbox preserved for inspection: ${SANDBOX}"
else
  echo -e "${red}${bold}LIVE E2E FAILED${reset} ($FAIL of $((PASS+FAIL)) failed)"
  echo "Sandbox preserved for inspection: ${SANDBOX}"
fi
echo -e "${bold}═══════════════════════════════════════════${reset}"

exit "${FAIL}"

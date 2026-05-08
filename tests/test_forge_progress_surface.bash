#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — hooks/forge-progress-surface.sh Tests (Phase 7)
# =============================================================================
# Covers SURF-01..05 + ACT-04 (style marker visibility).
# All tests sandbox HOME so the real marker file is never touched.

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
HOOK_FILE="${PLUGIN_DIR}/hooks/forge-progress-surface.sh"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

if [ ! -f "${HOOK_FILE}" ]; then
  echo "ERROR: ${HOOK_FILE} not found"
  exit 1
fi

HOME_SANDBOX="$(mktemp -d)"
trap 'rm -rf "${HOME_SANDBOX}"' EXIT
mkdir -p "${HOME_SANDBOX}/.claude"

run_hook() {
  local json="$1"
  HOME="${HOME_SANDBOX}" bash "${HOOK_FILE}" <<< "${json}" 2>/dev/null
}

# -----------------------------------------------------------------------------
echo "=== test_noop_when_marker_absent ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"x\""},"tool_response":{"output":"STATUS: SUCCESS\nFILES_CHANGED: [foo]\nASSUMPTIONS: []\nPATTERNS_DISCOVERED: []"}}')"
if [ -z "${_out}" ]; then
  assert_pass "test_noop_when_marker_absent"
else
  assert_fail "test_noop_when_marker_absent" "expected empty, got: '${_out}'"
fi

# Activate marker for all remaining tests.
touch "${HOME_SANDBOX}/.claude/.forge-delegation-active"

# -----------------------------------------------------------------------------
echo "=== test_noop_when_tool_not_bash ==="
_out="$(run_hook '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x"},"tool_response":{"output":"STATUS: SUCCESS"}}')"
if [ -z "${_out}" ]; then
  assert_pass "test_noop_when_tool_not_bash"
else
  assert_fail "test_noop_when_tool_not_bash" "got: '${_out}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_noop_when_command_lacks_forge_p ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"git status"},"tool_response":{"output":"nothing to commit"}}')"
if [ -z "${_out}" ]; then
  assert_pass "test_noop_when_command_lacks_forge_p"
else
  assert_fail "test_noop_when_command_lacks_forge_p" "got: '${_out}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_noop_when_output_lacks_status ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"x\""},"tool_response":{"output":"[FORGE] working...\n[FORGE] still working"}}')"
if [ -z "${_out}" ]; then
  assert_pass "test_noop_when_output_lacks_status"
else
  assert_fail "test_noop_when_output_lacks_status" "got: '${_out}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_emits_summary_when_status_block_present ==="
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge --conversation-id 12345678-aaaa-bbbb-cccc-1234567890ab --verbose -p \"Refactor utils\""},"tool_response":{"output":"[FORGE] Reading utils.py...\n[FORGE] STATUS: SUCCESS\n[FORGE] FILES_CHANGED: [utils.py]\n[FORGE] ASSUMPTIONS: []\n[FORGE] PATTERNS_DISCOVERED: []"}}')"
_ctx="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
if echo "${_ctx}" | grep -q 'STATUS: SUCCESS' \
    && echo "${_ctx}" | grep -q 'FILES_CHANGED: \[utils.py\]' \
    && echo "${_ctx}" | grep -q '/forge-stop' \
    && echo "${_ctx}" | grep -q '\[FORGE-SUMMARY\]' \
    && echo "${_ctx}" | grep -q '\[UNTRUSTED\]'; then
  assert_pass "test_emits_summary_when_status_block_present"
else
  assert_fail "test_emits_summary_when_status_block_present" "ctx='${_ctx}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_ansi_stripped_before_status_parse ==="
# Embed ANSI color codes in the output; expect them stripped from the summary.
_ansi_output=$'\x1b[31m[FORGE] STATUS: SUCCESS\x1b[0m\n\x1b[32m[FORGE] FILES_CHANGED: [foo.py]\x1b[0m\n[FORGE] ASSUMPTIONS: []\n[FORGE] PATTERNS_DISCOVERED: []'
_json="$(jq -cn --arg o "$_ansi_output" '{tool_name:"Bash",tool_input:{command:"forge -p \"x\""},tool_response:{output:$o}}')"
_out="$(run_hook "$_json")"
_ctx="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
# Assert no raw ESC byte in the context.
if [ -n "${_ctx}" ] && ! printf '%s' "${_ctx}" | grep -q $'\x1b'; then
  assert_pass "test_ansi_stripped_before_status_parse"
else
  assert_fail "test_ansi_stripped_before_status_parse" "ctx='${_ctx}'"
fi

# -----------------------------------------------------------------------------
echo "=== test_replay_hint_absent_when_no_conversation_id ==="
# Command with forge -p but no --conversation-id (unusual, but possible if a
# different hook or direct call slipped through). Summary should still emit,
# just without a replay hint.
_out="$(run_hook '{"tool_name":"Bash","tool_input":{"command":"forge -p \"x\""},"tool_response":{"output":"STATUS: SUCCESS\nFILES_CHANGED: []\nASSUMPTIONS: []\nPATTERNS_DISCOVERED: []"}}')"
_ctx="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
if echo "${_ctx}" | grep -q 'STATUS: SUCCESS' \
    && echo "${_ctx}" | grep -q '/forge-stop' \
    && echo "${_ctx}" | grep -q 'no conversation-id captured' \
    && echo "${_ctx}" | grep -q '\[UNTRUSTED\]'; then
  assert_pass "test_replay_hint_absent_when_no_conversation_id"
else
  assert_fail "test_replay_hint_absent_when_no_conversation_id" "ctx='${_ctx}'"
fi

# -----------------------------------------------------------------------------
# STRIP-01: multi-line OSC sequence must be fully consumed in slurp mode.
# The attack: an OSC opener (\x1b]) on one line with its BEL terminator on a
# later line. The OSC body contains text mimicking a STATUS: block. In
# line-by-line mode (-pe) the regex cannot match across lines so the OSC body
# text leaks as plain text. With -0777 (slurp mode) the entire input is one
# string and the s///g regex consumes the whole OSC sequence including its
# multi-line body before extract_status_block runs.
echo "=== test_strip_ansi_multiline_osc_slurp_mode ==="
# Craft Forge output: a legitimate STATUS block is followed by an OSC escape
# where the opener (\x1b]) is on line N and the BEL terminator (\x07) is on
# line N+2, with "OSCHIDDEN" text on the line in between. In line-by-line mode
# (-pe) the OSC regex only sees one line at a time so it cannot match the
# sequence that spans three lines — "OSCHIDDEN" leaks into the output.
# In slurp mode (-0777 -pe) the full input is one string, the regex matches
# across the embedded newlines, and "OSCHIDDEN" is fully consumed.
#
# The OSC body is placed AFTER the STATUS block so that extract_status_block
# runs after strip_ansi; if strip_ansi fails to remove it the body text would
# still not appear in additionalContext (awk stops at PATTERNS_DISCOVERED).
# Therefore this test exercises strip_ansi directly by sourcing the function.
_osc_multiline=$'[FORGE] STATUS: SUCCESS\n[FORGE] FILES_CHANGED: [foo.py]\n[FORGE] ASSUMPTIONS: []\n[FORGE] PATTERNS_DISCOVERED: []\n\x1b]OSCHIDDEN\nmore-body\x07'
# Source the hook to access strip_ansi directly (source-guard in the file
# prevents main() from running when sourced from a non-zero BASH_SOURCE index).
_stripped="$(printf '%s' "$_osc_multiline" | ( source "${HOOK_FILE}"; strip_ansi ) 2>/dev/null)"
if ! printf '%s' "${_stripped}" | grep -q 'OSCHIDDEN' \
    && ! printf '%s' "${_stripped}" | grep -q 'more-body'; then
  assert_pass "test_strip_ansi_multiline_osc_slurp_mode"
else
  assert_fail "test_strip_ansi_multiline_osc_slurp_mode" "OSC body text leaked through strip_ansi; output='${_stripped}'"
fi

# -----------------------------------------------------------------------------
# RDRCT-01: sk- redaction must cover:
#   (a) tokens using dots, slashes, and base64 '+' chars (broadened char class)
#   (b) short tokens (10-char suffix, reduced from 16)
#   (c) tokens at end-of-line (no trailing \b needed)
echo "=== test_sk_token_redaction_broadened ==="
# Build a STATUS block containing three sk- token variants that the old
# narrow regex would NOT catch:
#   sk-proj/abc.def+xyz1234567890  (slash, dot, plus — old class missed these)
#   sk-A1234567890                 (11-char suffix — old {16,} minimum missed it)
#   sk-base64+token/value12345     (end-of-line without trailing word boundary)
_sk_output='STATUS: SUCCESS
sk-proj/abc.def+xyz1234567890 is a token
sk-A1234567890 short key
sk-base64+token/value12345
FILES_CHANGED: []
ASSUMPTIONS: []
PATTERNS_DISCOVERED: []'
_json_sk="$(jq -cn --arg o "$_sk_output" '{tool_name:"Bash",tool_input:{command:"forge -p \"x\""},tool_response:{output:$o}}')"
_out_sk="$(run_hook "$_json_sk")"
_ctx_sk="$(printf '%s' "$_out_sk" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
if [ -n "${_ctx_sk}" ] \
    && ! printf '%s' "${_ctx_sk}" | grep -qF 'sk-proj/abc.def+xyz1234567890' \
    && ! printf '%s' "${_ctx_sk}" | grep -qF 'sk-A1234567890' \
    && ! printf '%s' "${_ctx_sk}" | grep -qF 'sk-base64+token/value12345'; then
  assert_pass "test_sk_token_redaction_broadened"
else
  assert_fail "test_sk_token_redaction_broadened" "sk- token not redacted; ctx='${_ctx_sk}'"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

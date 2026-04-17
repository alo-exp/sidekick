#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — v1.2 Coverage Gap Tests
# =============================================================================
# Fills coverage gaps identified by retroactive audit of:
#   - hooks/forge-delegation-enforcer.sh
#   - hooks/forge-progress-surface.sh
#
# These assertions complement the phase-scoped suites in
# test_forge_enforcer_hook.bash and test_forge_progress_surface.bash — they
# cover branches those suites left implicit (mutating-command variants,
# env-var prefix, long task-hint truncation, 20-line summary cap, stdout
# fallback, unknown tool name pass-through).
# -----------------------------------------------------------------------------

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
ENFORCER="${PLUGIN_DIR}/hooks/forge-delegation-enforcer.sh"
SURFACE="${PLUGIN_DIR}/hooks/forge-progress-surface.sh"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

[ -f "$ENFORCER" ] || { echo "ERROR: $ENFORCER not found"; exit 1; }
[ -f "$SURFACE" ]  || { echo "ERROR: $SURFACE not found"; exit 1; }

HOME_SBX="$(mktemp -d)"
PROJ_SBX="$(mktemp -d)"
STUB_DIR="$HOME_SBX/bin"
trap 'rm -rf "$HOME_SBX" "$PROJ_SBX"' EXIT
mkdir -p "$HOME_SBX/.claude" "$STUB_DIR"

cat > "$STUB_DIR/forge" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$STUB_DIR/forge"

touch "$HOME_SBX/.claude/.forge-delegation-active"

STUB_PATH="$STUB_DIR:$PATH"

run_enf() {
  HOME="$HOME_SBX" CLAUDE_PROJECT_DIR="$PROJ_SBX" PATH="$STUB_PATH" \
    bash "$ENFORCER" <<< "$1" 2>/dev/null
}

run_surf() {
  HOME="$HOME_SBX" bash "$SURFACE" <<< "$1" 2>/dev/null
}

# =============================================================================
# Enforcer coverage gaps
# =============================================================================

# -----------------------------------------------------------------------------
# test_is_mutating_sed_inplace
# `sed -i` (BSD/GNU) mutates files and must be denied when /forge mode is on.
# -----------------------------------------------------------------------------
echo "=== test_is_mutating_sed_inplace ==="
_out="$(run_enf '{"tool_name":"Bash","tool_input":{"command":"sed -i s/foo/bar/ README.md"}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ "$_dec" = "deny" ]; then pass "test_is_mutating_sed_inplace"
else fail "test_is_mutating_sed_inplace" "dec='$_dec' out='$_out'"; fi

# -----------------------------------------------------------------------------
# test_is_mutating_awk_inplace
# `awk -i inplace` is a real GNU-awk extension that mutates files.
# -----------------------------------------------------------------------------
echo "=== test_is_mutating_awk_inplace ==="
_out="$(run_enf '{"tool_name":"Bash","tool_input":{"command":"awk -i inplace {print} file.txt"}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ "$_dec" = "deny" ]; then pass "test_is_mutating_awk_inplace"
else fail "test_is_mutating_awk_inplace" "dec='$_dec' out='$_out'"; fi

# -----------------------------------------------------------------------------
# test_has_write_redirect_append
# `>>` is a write redirect just like `>`; must be denied.
# -----------------------------------------------------------------------------
echo "=== test_has_write_redirect_append ==="
_out="$(run_enf '{"tool_name":"Bash","tool_input":{"command":"echo hi >> /tmp/out"}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ "$_dec" = "deny" ]; then pass "test_has_write_redirect_append"
else fail "test_has_write_redirect_append" "dec='$_dec' out='$_out'"; fi

# -----------------------------------------------------------------------------
# test_has_write_redirect_devnull_is_passthrough
# `> /dev/null` and `2>/dev/null` are benign; must NOT be denied.
# -----------------------------------------------------------------------------
echo "=== test_has_write_redirect_devnull_is_passthrough ==="
_all=1
for _c in 'grep foo bar.txt > /dev/null' 'ls nosuchfile 2>/dev/null' 'cat x >/dev/null 2>&1'; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_enf "$_j")"
  if [ -n "$_out" ]; then
    fail "test_has_write_redirect_devnull_is_passthrough[$_c]" "got='$_out'"
    _all=0
  fi
done
[ "$_all" = "1" ] && pass "test_has_write_redirect_devnull_is_passthrough"

# -----------------------------------------------------------------------------
# test_env_prefix_before_forge_p
# `FOO=bar forge -p "..."` must strip env-prefix then rewrite normally.
# -----------------------------------------------------------------------------
echo "=== test_env_prefix_before_forge_p ==="
_out="$(run_enf '{"tool_name":"Bash","tool_input":{"command":"FORGE_LOG=debug forge -p \"refactor\""}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
_cmd="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null)"
if [ "$_dec" = "allow" ] && echo "$_cmd" | grep -Eq -- '--conversation-id [0-9a-f]{8}-'; then
  pass "test_env_prefix_before_forge_p"
else
  fail "test_env_prefix_before_forge_p" "dec='$_dec' cmd='$_cmd'"
fi

# -----------------------------------------------------------------------------
# test_task_hint_truncated_to_80_chars
# Long -p arg must be truncated to 80 chars in the idx row.
# -----------------------------------------------------------------------------
echo "=== test_task_hint_truncated_to_80_chars ==="
# Fresh project sandbox for this test.
rm -rf "$PROJ_SBX"; PROJ_SBX="$(mktemp -d)"
_long='This is a very long task hint that definitely exceeds eighty characters total xxxxxxxxxxxxxxxxx'
_j="$(jq -cn --arg c "forge -p \"$_long\"" '{tool_name:"Bash",tool_input:{command:$c}}')"
run_enf "$_j" >/dev/null
_hint="$(awk -F'\t' '{print $4}' "$PROJ_SBX/.forge/conversations.idx" 2>/dev/null || echo '')"
if [ "${#_hint}" -eq 80 ] && echo "$_hint" | grep -q '^This is a very long task'; then
  pass "test_task_hint_truncated_to_80_chars"
else
  fail "test_task_hint_truncated_to_80_chars" "len=${#_hint} hint='$_hint'"
fi

# -----------------------------------------------------------------------------
# test_task_hint_strips_tab_and_newline
# Embedded tabs/newlines inside the -p arg must be replaced with spaces so a
# single idx row stays well-formed.
# -----------------------------------------------------------------------------
echo "=== test_task_hint_strips_tab_and_newline ==="
rm -rf "$PROJ_SBX"; PROJ_SBX="$(mktemp -d)"
# printf the control chars then feed as JSON via jq --arg to preserve them.
_hinty=$'line1\tline2\nline3'
_cmd="$(printf 'forge -p "%s"' "$_hinty")"
_j="$(jq -cn --arg c "$_cmd" '{tool_name:"Bash",tool_input:{command:$c}}')"
run_enf "$_j" >/dev/null
_rows="$(wc -l < "$PROJ_SBX/.forge/conversations.idx" 2>/dev/null | tr -d ' ' || echo 0)"
_field4="$(awk -F'\t' '{print $4}' "$PROJ_SBX/.forge/conversations.idx" 2>/dev/null || echo '')"
if [[ "$_rows" == "1" && "$_field4" != *$'\t'* && "$_field4" != *$'\n'* && -n "$_field4" ]]; then
  pass "test_task_hint_strips_tab_and_newline"
else
  fail "test_task_hint_strips_tab_and_newline" "rows=$_rows field4='$_field4'"
fi

# -----------------------------------------------------------------------------
# test_unknown_tool_silent_passthrough
# Tool names outside {Write,Edit,NotebookEdit,Bash} must exit 0 with no output.
# -----------------------------------------------------------------------------
echo "=== test_unknown_tool_silent_passthrough ==="
_all=1
for _tn in Task Read Grep Glob; do
  _j="$(jq -cn --arg t "$_tn" '{tool_name:$t,tool_input:{pattern:"foo"}}')"
  _out="$(run_enf "$_j")"
  if [ -n "$_out" ]; then
    fail "test_unknown_tool_silent_passthrough[$_tn]" "got='$_out'"
    _all=0
  fi
done
[ "$_all" = "1" ] && pass "test_unknown_tool_silent_passthrough"

# -----------------------------------------------------------------------------
# test_readonly_single_word_commands
# Broader coverage of is_read_only — single-word tools that should pass through.
# -----------------------------------------------------------------------------
echo "=== test_readonly_single_word_commands ==="
_all=1
for _c in 'jq . file.json' 'awk {print} file' 'env' 'printenv HOME' 'date -u' 'uname -a' 'wc -l file' 'head -5 file'; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_enf "$_j")"
  if [ -n "$_out" ]; then
    fail "test_readonly_single_word_commands[$_c]" "got='$_out'"
    _all=0
  fi
done
[ "$_all" = "1" ] && pass "test_readonly_single_word_commands"

# -----------------------------------------------------------------------------
# test_unclassified_command_denied
# Commands that are neither forge-p, read-only, nor in the mutating list get
# denied conservatively.
# -----------------------------------------------------------------------------
echo "=== test_unclassified_command_denied ==="
_out="$(run_enf '{"tool_name":"Bash","tool_input":{"command":"mystery_tool --do-stuff"}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
_rsn="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
if [ "$_dec" = "deny" ] && echo "$_rsn" | grep -q 'could not be classified'; then
  pass "test_unclassified_command_denied"
else
  fail "test_unclassified_command_denied" "dec='$_dec' reason='$_rsn'"
fi

# =============================================================================
# Progress surface coverage gaps
# =============================================================================

# -----------------------------------------------------------------------------
# test_surface_caps_status_block_at_20_lines
# If Forge emits a huge STATUS block (malformed tail), the summary must be
# capped at 20 lines so the transcript isn't flooded.
# -----------------------------------------------------------------------------
echo "=== test_surface_caps_status_block_at_20_lines ==="
_big="[FORGE] STATUS: SUCCESS"
for i in $(seq 1 30); do _big="$_big"$'\n'"[FORGE] extra line $i"; done
_big="$_big"$'\n'"[FORGE] PATTERNS_DISCOVERED: []"
_j="$(jq -cn --arg o "$_big" '{tool_name:"Bash",tool_input:{command:"forge -p \"x\""},tool_response:{output:$o}}')"
_out="$(run_surf "$_j")"
_ctx="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
# Count lines that start with [FORGE-SUMMARY] and carry a status-block payload.
_body_lines="$(printf '%s\n' "$_ctx" | grep -c '^\[FORGE-SUMMARY\] \[FORGE\]' || true)"
# awk's "count >= 20 { exit }" fires AFTER printing the 20th line.
if [ "$_body_lines" -le 20 ] && [ "$_body_lines" -ge 1 ]; then
  pass "test_surface_caps_status_block_at_20_lines (body_lines=$_body_lines)"
else
  fail "test_surface_caps_status_block_at_20_lines" "body_lines=$_body_lines ctx='$_ctx'"
fi

# -----------------------------------------------------------------------------
# test_surface_uses_stdout_fallback_when_output_absent
# Some Claude Code harnesses surface the raw stdout under
# tool_response.stdout instead of tool_response.output. The hook's jq expression
# must handle both.
# -----------------------------------------------------------------------------
echo "=== test_surface_uses_stdout_fallback_when_output_absent ==="
_j='{"tool_name":"Bash","tool_input":{"command":"forge -p \"x\""},"tool_response":{"stdout":"STATUS: SUCCESS\nFILES_CHANGED: []\nASSUMPTIONS: []\nPATTERNS_DISCOVERED: []"}}'
_out="$(run_surf "$_j")"
_ctx="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
if echo "$_ctx" | grep -q 'STATUS: SUCCESS' && echo "$_ctx" | grep -q '\[FORGE-SUMMARY\]'; then
  pass "test_surface_uses_stdout_fallback_when_output_absent"
else
  fail "test_surface_uses_stdout_fallback_when_output_absent" "ctx='$_ctx'"
fi

# -----------------------------------------------------------------------------
# v1.2.2 hardening coverage — SENTINEL L1/L2/I1 fixes.
# -----------------------------------------------------------------------------

# test_validate_uuid_accepts_valid
# gen_uuid override with canonical 8-4-4-4-12 lowercase hex must survive
# validate_uuid and reach the rewritten command.
echo "=== test_validate_uuid_accepts_valid ==="
_valid_uuid="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
_j="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"forge -p \\\"hello\\\"\"}}"
_out="$(SIDEKICK_TEST_UUID_OVERRIDE="$_valid_uuid" run_enf "$_j")"
if echo "$_out" | jq -er '.hookSpecificOutput.permissionDecision == "allow"' >/dev/null 2>&1 \
   && echo "$_out" | grep -qF -- "--conversation-id $_valid_uuid"; then
  pass "test_validate_uuid_accepts_valid"
else
  fail "test_validate_uuid_accepts_valid" "out='$_out'"
fi

# test_validate_uuid_rejects_shell_metacharacters
# A malformed override containing shell metacharacters must be rejected by
# validate_uuid → decision becomes deny, not an allow with spliced injection.
echo "=== test_validate_uuid_rejects_shell_metacharacters ==="
_bad_uuid="; rm -rf / #"
_out="$(SIDEKICK_TEST_UUID_OVERRIDE="$_bad_uuid" run_enf "$_j")"
if echo "$_out" | jq -er '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
   && ! echo "$_out" | grep -qF 'rm -rf'; then
  pass "test_validate_uuid_rejects_shell_metacharacters"
else
  fail "test_validate_uuid_rejects_shell_metacharacters" "out='$_out'"
fi

# test_validate_uuid_rejects_uppercase
# RFC 4122 canonical form is lowercase; uppercase input must be rejected so the
# regex surface stays narrow.
echo "=== test_validate_uuid_rejects_uppercase ==="
_upper_uuid="AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
_out="$(SIDEKICK_TEST_UUID_OVERRIDE="$_upper_uuid" run_enf "$_j")"
if echo "$_out" | jq -er '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
  pass "test_validate_uuid_rejects_uppercase"
else
  fail "test_validate_uuid_rejects_uppercase" "out='$_out'"
fi

# test_env_prefix_with_forge_inside_value
# FINDING-R16-L1: a command with an env-var whose VALUE contains the literal
# "forge " must NOT land the --conversation-id injection inside that value.
# The rewritten command's env-prefix must be preserved verbatim and the
# injection must appear immediately after the real forge token.
echo "=== test_env_prefix_with_forge_inside_value ==="
_valid_uuid="11111111-2222-3333-4444-555555555555"
_j='{"tool_name":"Bash","tool_input":{"command":"FOO=forge_trap forge -p \"task\""}}'
_out="$(SIDEKICK_TEST_UUID_OVERRIDE="$_valid_uuid" run_enf "$_j")"
_cmd="$(echo "$_out" | jq -r '.hookSpecificOutput.updatedInput.command // empty' 2>/dev/null)"
# Expect: "FOO=forge_trap forge --conversation-id 1111… --verbose -p "task" …pipes"
if [[ "$_cmd" == "FOO=forge_trap forge --conversation-id $_valid_uuid --verbose -p \"task\""* ]]; then
  pass "test_env_prefix_with_forge_inside_value"
else
  fail "test_env_prefix_with_forge_inside_value" "cmd='$_cmd'"
fi

# test_surface_redacts_authorization_header
# FINDING-R16-I1: Authorization: Bearer <token> must be redacted before the
# STATUS block is spliced into additionalContext.
echo "=== test_surface_redacts_authorization_header ==="
_payload='{"tool_name":"Bash","tool_input":{"command":"forge -p x"},"tool_response":{"output":"STATUS: ok\nAuthorization: Bearer sk-abc123456789012345678\nPATTERNS_DISCOVERED: none"}}'
_out="$(run_surf "$_payload")"
_ctx="$(echo "$_out" | jq -r '.hookSpecificOutput.additionalContext // empty')"
if echo "$_ctx" | grep -q "Authorization: \[REDACTED\]" \
   && ! echo "$_ctx" | grep -q 'sk-abc123456789012345678'; then
  pass "test_surface_redacts_authorization_header"
else
  fail "test_surface_redacts_authorization_header" "ctx='$_ctx'"
fi

# test_surface_redacts_api_key_and_provider_tokens
# Redaction must also catch api_key=<val>, ghp_… GitHub tokens, and xoxb-…
# Slack tokens in a single pass.
echo "=== test_surface_redacts_api_key_and_provider_tokens ==="
_payload='{"tool_name":"Bash","tool_input":{"command":"forge -p x"},"tool_response":{"output":"STATUS: ok\napi_key=supersecret123\nghp_AAAAAAAAAAAAAAAAAAAA12345\nslack: xoxb-12345678901234567890\nPATTERNS_DISCOVERED: none"}}'
_out="$(run_surf "$_payload")"
_ctx="$(echo "$_out" | jq -r '.hookSpecificOutput.additionalContext // empty')"
if echo "$_ctx" | grep -q 'api_key=\[REDACTED\]' \
   && echo "$_ctx" | grep -q '\[REDACTED-GH-TOKEN\]' \
   && echo "$_ctx" | grep -q '\[REDACTED-SLACK-TOKEN\]' \
   && ! echo "$_ctx" | grep -q 'supersecret123' \
   && ! echo "$_ctx" | grep -q 'ghp_AAAAAAAAAAAAAAAAAAAA12345' \
   && ! echo "$_ctx" | grep -q 'xoxb-12345678901234567890'; then
  pass "test_surface_redacts_api_key_and_provider_tokens"
else
  fail "test_surface_redacts_api_key_and_provider_tokens" "ctx='$_ctx'"
fi

# -----------------------------------------------------------------------------
echo ""
echo "======================================="
echo "Results: $PASS passed, $FAIL failed"
echo "======================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1

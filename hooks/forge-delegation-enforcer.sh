#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Forge Delegation Enforcer (PreToolUse hook)  v1.3
# =============================================================================
# Sources hooks/lib/enforcer-utils.sh. Adds path allowlist (PATH-01/02/03),
# MCP filesystem dispatch (ENF-07), chain/pipe denial (ENF-06/08), and
# export_env_prefix for FORGE_LEVEL_3 prefix bypass (ENF-04).
#
# Exit-code contract: 0+empty=pass-through; 0+JSON=decision; 2+stderr=fatal.
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

MARKER_FILE="${HOME}/.claude/.forge-delegation-active"

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib/enforcer-utils.sh
source "${HOOK_DIR}/lib/enforcer-utils.sh"

# gen_uuid — lowercase RFC 4122 UUID. Honors SIDEKICK_TEST_UUID_OVERRIDE (tests only).
gen_uuid() {
  if [[ -n "${SIDEKICK_TEST_UUID_OVERRIDE:-}" ]]; then
    echo "$SIDEKICK_TEST_UUID_OVERRIDE"
    return 0
  fi
  uuidgen | tr 'A-Z' 'a-z'
}

# validate_uuid — 8-4-4-4-12 lowercase hex check; prevents metacharacter injection.
validate_uuid() {
  [[ "$1" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

# emit_decision — print hookSpecificOutput JSON. $1=allow|deny $2=reason $3=rewritten-cmd(opt).
emit_decision() {
  local decision="$1"
  local reason="$2"
  local updated_cmd="${3:-}"

  if [[ -n "$updated_cmd" ]]; then
    jq -cn \
      --arg d "$decision" \
      --arg r "$reason" \
      --arg c "$updated_cmd" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r, updatedInput: {command: $c}}}'
  else
    jq -cn \
      --arg d "$decision" \
      --arg r "$reason" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  fi
}

# Canonical deny reason for direct file edits.
DENY_EDIT_REASON='Sidekick /forge mode is active: direct file edits are delegated to Forge. Use: Bash { command: "forge -p \"<your task description>\"" }. To temporarily bypass for Level 3 takeover, set FORGE_LEVEL_3=1 in the Bash environment.'

deny_direct_edit() {
  emit_decision "deny" "$DENY_EDIT_REASON" ""
}

# PATH-01/02/03: .planning/** and docs/** edits pass through when /forge is active.
decide_write_edit() {
  local tool_input_json="$1"
  local file_path
  file_path="$(printf '%s' "$tool_input_json" | jq -r '.file_path // .path // empty')"
  if is_allowed_doc_path "$file_path"; then
    return 0
  fi
  deny_direct_edit
}

decide_notebook_edit() { deny_direct_edit; }

# ENF-07: deny mcp__filesystem__* write tools (with path allowlist).
decide_mcp_write() {
  local tool_input_json="$1"
  local file_path
  file_path="$(printf '%s' "$tool_input_json" | jq -r '.path // .file_path // empty')"
  if is_allowed_doc_path "$file_path"; then
    return 0
  fi
  deny_direct_edit
}

# Audit index + activation-lifecycle helpers.
resolve_forge_dir() {
  printf '%s/.forge' "${CLAUDE_PROJECT_DIR:-$PWD}"
}

ensure_forge_dir_and_idx() {
  local dir
  dir="$(resolve_forge_dir)"
  mkdir -p "$dir" 2>/dev/null || return 1
  touch -a "$dir/conversations.idx" 2>/dev/null || return 1
  return 0
}

# db_precheck — sentinel-gated health check. Returns 0 if DB writable.
db_precheck() {
  local dir sentinel
  dir="$(resolve_forge_dir)"
  sentinel="$dir/.db_check_ok"
  if [[ -f "$sentinel" ]] && ! [[ "$MARKER_FILE" -nt "$sentinel" ]]; then
    return 0
  fi
  if forge conversation list >/dev/null 2>&1; then
    mkdir -p "$dir" 2>/dev/null || true
    touch "$sentinel" 2>/dev/null || true
    return 0
  fi
  return 1
}

# extract_task_hint — derive -p argument from command via python3 shlex.
extract_task_hint() {
  local cmd="$1"
  local hint=""
  if command -v python3 >/dev/null 2>&1; then
    hint="$(python3 -c '
import shlex, sys
try:
    toks = shlex.split(sys.argv[1])
    if "-p" in toks:
        i = toks.index("-p")
        if i + 1 < len(toks):
            sys.stdout.write(toks[i+1])
except Exception:
    pass
' "$cmd" 2>/dev/null || true)"
  fi
  [[ -z "$hint" ]] && hint="(task hint unavailable)"
  hint="${hint//$'\t'/ }"
  hint="${hint//$'\n'/ }"
  printf '%s' "${hint:0:80}"
}

# append_idx_row — write one tab-separated line to .forge/conversations.idx.
append_idx_row() {
  local uuid hint dir idx
  uuid="$1"
  hint="$2"
  dir="$(resolve_forge_dir)"
  idx="$dir/conversations.idx"
  if [[ -f "$idx" ]] && grep -qF "$uuid" "$idx" 2>/dev/null; then
    return 0
  fi
  local tag_suffix sidekick_tag
  tag_suffix="${uuid##*-}"
  tag_suffix="${tag_suffix:0:8}"
  sidekick_tag="sidekick-$(date +%s)-$tag_suffix"
  {
    printf '%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$uuid" "$sidekick_tag" "$hint" >> "$idx"
  } 2>/dev/null || true
  return 0
}

# Enforcer-specific helpers (not in lib).
has_conversation_id() {
  [[ "$1" =~ (^|[[:space:]])--conversation-id([[:space:]]|=) ]]
}

is_forge_p() {
  local cmd stripped
  cmd="$1"
  stripped="$(strip_env_prefix "$cmd")"
  [[ "$stripped" =~ ^forge([[:space:]]|$) ]] || return 1
  [[ "$stripped" =~ (^|[[:space:]])-p([[:space:]]|$) ]] || return 1
  return 0
}

# decide_bash — Bash tool classifier + forge -p rewrite.
decide_bash() {
  local tool_input_json cmd
  tool_input_json="$1"
  cmd="$(printf '%s' "$tool_input_json" | jq -r '.command // empty')"
  [[ -z "$cmd" ]] && return 0

  # ENF-04: export any leading env-var prefix assignments (e.g. FORGE_LEVEL_3=1)
  # into this hook's environment so the bypass check at step 3 can see them.
  export_env_prefix "$cmd"

  # 1. forge -p rewrite / idempotent passthrough.
  if is_forge_p "$cmd"; then
    if has_conversation_id "$cmd"; then
      local existing_uuid
      existing_uuid="$(printf '%s' "$cmd" | sed -n 's/.*--conversation-id[[:space:]=]\([^[:space:]]*\).*/\1/p')"
      if [[ -z "$existing_uuid" ]] || ! validate_uuid "$existing_uuid"; then
        emit_decision "deny" "Sidekick: --conversation-id value is not a valid lowercase RFC 4122 UUID. Supply a valid UUID or omit --conversation-id to let the hook auto-generate one." ""
        return 0
      fi
      return 0
    fi
    if ! db_precheck; then
      emit_decision "deny" "Sidekick: Forge DB not writable ('forge conversation list' failed). Deactivate via /forge:deactivate, resolve the Forge state, and re-activate." ""
      return 0
    fi
    ensure_forge_dir_and_idx || true
    local uuid rewritten pipes hint stripped env_prefix
    uuid="$(gen_uuid)"
    if ! validate_uuid "$uuid"; then
      emit_decision "deny" "Sidekick: refusing to inject malformed UUID (check SIDEKICK_TEST_UUID_OVERRIDE)." ""
      return 0
    fi
    stripped="$(strip_env_prefix "$cmd")"
    env_prefix="${cmd%"$stripped"}"
    rewritten="${env_prefix}forge --conversation-id ${uuid} --verbose ${stripped#forge }"
    pipes=" 2> >(sed 's/^/[FORGE-LOG] /' >&2) | sed 's/^/[FORGE] /'"
    rewritten="${rewritten}${pipes}"
    emit_decision "allow" "Sidekick: injected --conversation-id + --verbose + output prefixing." "$rewritten"
    hint="$(extract_task_hint "$cmd")"
    append_idx_row "$uuid" "$hint"
    return 0
  fi

  # 1b. ENF-06: Chain bypass — deny if any &&/; segment is mutating.
  if has_mutating_chain_segment "$cmd"; then
    if [[ "${FORGE_LEVEL_3:-}" == "1" ]]; then return 0; fi
    emit_decision "deny" "Sidekick /forge mode: command chain contains a mutating segment. Use forge -p or set FORGE_LEVEL_3=1 for Level 3 takeover." ""
    return 0
  fi

  # 1c. ENF-08: Pipe bypass — deny if any | segment is mutating.
  # is_forge_p check above already returned early for forge -p pipes;
  # this scanner only runs for non-forge commands.
  if has_mutating_pipe_segment "$cmd"; then
    if [[ "${FORGE_LEVEL_3:-}" == "1" ]]; then return 0; fi
    emit_decision "deny" "Sidekick /forge mode: pipe chain contains a mutating segment. Use forge -p or set FORGE_LEVEL_3=1 for Level 3 takeover." ""
    return 0
  fi

  # 2. read-only passthrough.
  if is_read_only "$cmd"; then
    return 0
  fi

  # 3. mutating command handling.
  if is_mutating "$cmd"; then
    if [[ "${FORGE_LEVEL_3:-}" == "1" ]]; then
      return 0
    fi
    emit_decision "deny" "Sidekick /forge mode: mutating command denied. Delegate via forge -p, or set FORGE_LEVEL_3=1 to bypass for a Level 3 takeover." ""
    return 0
  fi

  # 4. Unclassified → conservative deny.
  emit_decision "deny" "Sidekick /forge mode: command could not be classified. Delegate via forge -p or set FORGE_LEVEL_3=1." ""
}

# main — entry point.
main() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "forge-delegation-enforcer: jq not found on PATH" >&2
    exit 2
  fi

  local input
  input="$(cat)"

  local tool_name tool_input
  if ! tool_name="$(printf '%s' "$input" | jq -er '.tool_name // empty' 2>/dev/null)"; then
    echo "forge-delegation-enforcer: malformed PreToolUse JSON on stdin" >&2
    exit 2
  fi
  if [[ -z "$tool_name" ]]; then
    echo "forge-delegation-enforcer: malformed PreToolUse JSON on stdin" >&2
    exit 2
  fi
  tool_input="$(printf '%s' "$input" | jq -c '.tool_input // {}')"

  if [[ ! -f "$MARKER_FILE" ]]; then
    exit 0
  fi

  case "$tool_name" in
    Write|Edit)     decide_write_edit "$tool_input" ;;
    NotebookEdit)   decide_notebook_edit "$tool_input" ;;
    Bash)           decide_bash "$tool_input" ;;
    mcp__filesystem__write_file|mcp__filesystem__edit_file|\
    mcp__filesystem__move_file|mcp__filesystem__create_directory)
                    decide_mcp_write "$tool_input" ;;
    *)              exit 0 ;;
  esac
}

# Source-guard: run main() only when executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0:-}" ]]; then
  main "$@"
fi

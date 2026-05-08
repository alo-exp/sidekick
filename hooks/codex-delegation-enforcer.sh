#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Codex Delegation Enforcer (PreToolUse hook)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

MARKER_FILE="${HOME}/.claude/.codex-delegation-active"
SIDEKICK_NAME="codex"

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib/enforcer-utils.sh
source "${HOOK_DIR}/lib/enforcer-utils.sh"
# shellcheck source=hooks/lib/sidekick-registry.sh
source "${HOOK_DIR}/lib/sidekick-registry.sh"

gen_uuid() {
  sidekick_gen_uuid
}

validate_uuid() {
  sidekick_validate_uuid "$1"
}

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

delegate_command() {
  sidekick_registry_get "$SIDEKICK_NAME" '.[$sidekick].delegate_command'
}

resolve_codex_binary_name() {
  local candidate
  for candidate in codex code coder; do
    if command -v "$candidate" >/dev/null 2>&1; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

deny_reason() {
  printf 'Sidekick /codex mode is active: direct file edits are delegated to Codex. Use: Bash { command: "%s --full-auto \"<your task description>\"" } or `code exec` / `coder exec` if `codex` is unavailable.' "$(delegate_command)"
}

deny_direct_edit() {
  emit_decision "deny" "$(deny_reason)" ""
}

decide_write_edit() {
  local tool_input_json="$1"
  local file_path
  file_path="$(printf '%s' "$tool_input_json" | jq -r '.file_path // .path // empty')"
  if is_allowed_doc_path "$file_path"; then
    return 0
  fi
  deny_direct_edit
}

decide_notebook_edit() {
  deny_direct_edit
}

decide_mcp_write() {
  local tool_input_json="$1"
  local file_path
  file_path="$(printf '%s' "$tool_input_json" | jq -r '.path // .file_path // empty')"
  if is_allowed_doc_path "$file_path"; then
    return 0
  fi
  deny_direct_edit
}

has_codex_exec() {
  local cmd stripped
  cmd="$1"
  stripped="$(strip_env_prefix "$cmd")"
  [[ "$stripped" =~ ^(codex|code|coder)([[:space:]]|$) ]] || return 1
  [[ "$stripped" =~ (^|[[:space:]])exec([[:space:]]|$) ]] || return 1
  return 0
}

rewrite_codex_exec() {
  local cmd="$1"
  local stripped env_prefix rewritten binary_name prefix_prompt original_binary remainder after_exec

  stripped="$(strip_env_prefix "$cmd")"
  env_prefix="${cmd%"$stripped"}"
  original_binary="$(printf '%s' "$stripped" | awk '{print $1}')"
  binary_name="$(resolve_codex_binary_name || printf '%s' "$original_binary")"
  remainder="${stripped#${original_binary} }"
  after_exec="${remainder#exec }"

  if printf '%s' "$stripped" | grep -q -- '--full-auto'; then
    prefix_prompt="${binary_name} ${remainder}"
  else
    prefix_prompt="${binary_name} exec --full-auto ${after_exec}"
  fi

  rewritten="${env_prefix}${prefix_prompt}"
  rewritten="${rewritten} 2> >(sed 's/^/[CODEX-LOG] /' >&2) | sed 's/^/[CODEX] /'"

  printf '%s' "$rewritten"
}

decide_bash() {
  local tool_input_json cmd stripped uuid hint rewritten
  tool_input_json="$1"
  cmd="$(printf '%s' "$tool_input_json" | jq -r '.command // empty')"
  [[ -z "$cmd" ]] && return 0

  export_env_prefix "$cmd"

  if has_codex_exec "$cmd"; then
    stripped="$(strip_env_prefix "$cmd")"
    if ! resolve_codex_binary_name >/dev/null 2>&1; then
      emit_decision "deny" "Sidekick /codex mode: Codex runtime is not on PATH. Install the Codex sidekick package and re-run /codex." ""
      return 0
    fi
    uuid="$(gen_uuid)"
    if ! validate_uuid "$uuid"; then
      emit_decision "deny" "Sidekick /codex mode: refusing to record malformed audit UUID." ""
      return 0
    fi
    hint="$(sidekick_extract_exec_prompt "$stripped")"
    [[ -z "$hint" ]] && hint="(task hint unavailable)"
    sidekick_ensure_idx "$SIDEKICK_NAME" || true
    sidekick_append_idx_row "$SIDEKICK_NAME" "$uuid" "$hint"
    rewritten="$(rewrite_codex_exec "$cmd")"
    emit_decision "allow" "Sidekick: injected --full-auto and output prefixing." "$rewritten"
    return 0
  fi

  if has_mutating_chain_segment "$cmd"; then
    emit_decision "deny" "Sidekick /codex mode: command chain contains a mutating segment. Use codex exec --full-auto, code exec --full-auto, or coder exec --full-auto." ""
    return 0
  fi

  if has_mutating_pipe_segment "$cmd"; then
    emit_decision "deny" "Sidekick /codex mode: pipe chain contains a mutating segment. Use codex exec --full-auto, code exec --full-auto, or coder exec --full-auto." ""
    return 0
  fi

  if is_read_only "$cmd"; then
    return 0
  fi

  if is_mutating "$cmd"; then
    emit_decision "deny" "Sidekick /codex mode: mutating command denied. Delegate via codex exec --full-auto, code exec --full-auto, or coder exec --full-auto." ""
    return 0
  fi

  emit_decision "deny" "Sidekick /codex mode: command could not be classified. Delegate via codex exec --full-auto, code exec --full-auto, or coder exec --full-auto." ""
}

main() {
  if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Sidekick /codex mode requires jq for hook enforcement. Install jq and re-run /codex."}}'
    exit 0
  fi

  [[ -f "$MARKER_FILE" ]] || exit 0

  local input tool_name tool_input
  input="$(cat)"
  tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
  tool_input="$(printf '%s' "$input" | jq -c '.tool_input // {}' 2>/dev/null)"

  case "$tool_name" in
    Write|Edit)
      decide_write_edit "$tool_input"
      ;;
    NotebookEdit)
      decide_notebook_edit
      ;;
    Bash)
      decide_bash "$tool_input"
      ;;
    mcp__filesystem__write_file|mcp__filesystem__edit_file|mcp__filesystem__move_file|mcp__filesystem__create_directory)
      decide_mcp_write "$tool_input"
      ;;
    *)
      return 0
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0:-}" ]]; then
  main "$@"
fi

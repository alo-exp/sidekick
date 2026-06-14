#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — host-specific hook I/O helpers (Claude/Codex vs Cursor)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

[[ -n "${_SIDEKICK_HOOK_IO_LOADED:-}" ]] && return 0
_SIDEKICK_HOOK_IO_LOADED=1

SIDEKICK_HOOK_INPUT=""

sidekick_is_cursor_host() {
  case "${SIDEKICK_HOOK_HOST:-}" in
    cursor) return 0 ;;
  esac
  if [[ -n "${CURSOR_VERSION:-}" ]] || [[ -n "${CURSOR_PROJECT_DIR:-}" ]]; then
    return 0
  fi
  return 1
}

sidekick_hook_host() {
  if sidekick_is_cursor_host; then
    printf '%s' 'cursor'
    return 0
  fi
  printf '%s' 'claude_codex'
}

sidekick_bind_hook_session_from_input() {
  local input="${1:-}"
  local conversation_id=""

  [[ -n "$input" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  conversation_id="$(printf '%s' "$input" | jq -r '.conversation_id // .session_id // empty' 2>/dev/null || true)"
  if [[ -n "$conversation_id" ]]; then
    export SIDEKICK_SESSION_ID="$conversation_id"
  fi
}

sidekick_normalize_tool_name() {
  local tool_name="$1"
  case "$tool_name" in
    Shell) printf '%s' 'Bash' ;;
    StrReplace) printf '%s' 'Edit' ;;
    MCP:*)
      local suffix="${tool_name#MCP:}"
      suffix="${suffix# }"
      printf '%s' "mcp__${suffix// /__}"
      ;;
    *) printf '%s' "$tool_name" ;;
  esac
}

sidekick_emit_pre_tool_decision() {
  local decision="$1"
  local reason="$2"
  local updated_cmd="${3:-}"

  if sidekick_is_cursor_host; then
    local permission="allow"
    case "$decision" in
      deny) permission="deny" ;;
      allow) permission="allow" ;;
      *) permission="$decision" ;;
    esac
    if [[ -n "$updated_cmd" ]]; then
      jq -cn \
        --arg p "$permission" \
        --arg um "$reason" \
        --arg am "$reason" \
        --arg cmd "$updated_cmd" \
        '{permission: $p, user_message: $um, agent_message: $am, updated_input: {command: $cmd}}'
    else
      jq -cn \
        --arg p "$permission" \
        --arg um "$reason" \
        --arg am "$reason" \
        '{permission: $p, user_message: $um, agent_message: $am}'
    fi
    return 0
  fi

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

sidekick_emit_post_tool_context() {
  local payload="$1"

  if sidekick_is_cursor_host; then
    jq -cn --arg ctx "$payload" '{additional_context: $ctx}'
    return 0
  fi

  jq -cn --arg ctx "$payload" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
}

sidekick_emit_jq_missing_denial() {
  local sidekick_name="${1:-sidekick}"
  local reason="Sidekick /${sidekick_name} mode requires jq for hook enforcement. Install jq and re-run."

  if sidekick_is_cursor_host; then
    jq -cn --arg um "$reason" --arg am "$reason" \
      '{permission: "deny", user_message: $um, agent_message: $am}'
    return 0
  fi

  printf '%s\n' "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"${reason}\"}}"
}

sidekick_delegate_shell_hint() {
  local delegate_cmd="$1"
  if sidekick_is_cursor_host; then
    printf 'Shell with command: %s "<your task description>"' "$delegate_cmd"
    return 0
  fi
  printf 'Bash { command: '\''%s "<your task description>"'\'' }' "$delegate_cmd"
}

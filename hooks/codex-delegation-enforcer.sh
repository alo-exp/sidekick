#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Kay Delegation Enforcer (PreToolUse hook)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib/enforcer-utils.sh
source "${HOOK_DIR}/lib/enforcer-utils.sh"
# shellcheck source=hooks/lib/sidekick-registry.sh
source "${HOOK_DIR}/lib/sidekick-registry.sh"

SIDEKICK_NAME="kay"
MARKER_FILE="$(sidekick_session_marker_file "$SIDEKICK_NAME" 2>/dev/null || true)"

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
  for candidate in kay code codex coder; do
    if command -v "$candidate" >/dev/null 2>&1 \
      && "$candidate" --version 2>/dev/null | grep -qiE '^kay([[:space:]]|$)' \
      && "$candidate" exec --help >/dev/null 2>&1; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

deny_reason() {
  printf 'Sidekick /kay mode is active: direct file edits are delegated to Kay. Use: Bash { command: "%s --full-auto \"<your task description>\"" }. Legacy code/codex/coder aliases remain compatibility-only.' "$(delegate_command)"
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
  [[ "$stripped" =~ ^(kay|code|codex|coder)([[:space:]]|$) ]] || return 1
  [[ "$stripped" =~ (^|[[:space:]])exec([[:space:]]|$) ]] || return 1
  return 0
}

rewrite_codex_exec() {
  local cmd="$1"
  local stripped binary_name original_binary

  stripped="$(strip_env_prefix "$cmd")"
  original_binary="$(printf '%s' "$stripped" | awk '{print $1}')"
  binary_name="$(resolve_codex_binary_name || printf '%s' "$original_binary")"

  python3 - "$binary_name" "$stripped" "${HOOK_DIR}/lib/sidekick-safe-runner.sh" <<'PY'
import shlex
import sys

binary_name, cmd, runner_path = sys.argv[1:4]

try:
    lexer = shlex.shlex(cmd, posix=True, punctuation_chars='|;&()<>')
    lexer.whitespace_split = True
    tokens = list(lexer)
except Exception:
    raise SystemExit(1)

if len(tokens) < 3 or tokens[0] not in {"kay", "code", "codex", "coder"} or tokens[1] != "exec":
    raise SystemExit(1)

for tok in tokens:
    if tok in {";", "&&", "||", "|", "&", ">", "<", "(", ")"}:
        raise SystemExit(1)

if "--full-auto" not in tokens[2:]:
    tokens.insert(2, "--full-auto")

tokens[0] = binary_name
rewritten = " ".join(shlex.quote(tok) for tok in ["bash", runner_path, "kay"] + tokens)
print(rewritten)
PY
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
      emit_decision "deny" "Sidekick /kay mode: no Kay-compatible runtime is on PATH. Install the Kay sidekick package and re-run /kay." ""
      return 0
    fi
    uuid="$(gen_uuid)"
	    if ! validate_uuid "$uuid"; then
	      emit_decision "deny" "Sidekick /kay mode: refusing to record malformed audit UUID." ""
	      return 0
	    fi
	    if ! rewritten="$(rewrite_codex_exec "$cmd")"; then
	      emit_decision "deny" "Sidekick /kay mode: refusing to rewrite malformed Kay exec invocation." ""
	      return 0
	    fi
	    hint="$(sidekick_extract_exec_prompt "$stripped")"
	    [[ -z "$hint" ]] && hint="(task hint unavailable)"
	    if ! sidekick_ensure_idx "$SIDEKICK_NAME"; then
	      emit_decision "deny" "Sidekick /kay mode: Kay audit index is not writable or is outside the project. Remove any symlinked .kay path and re-run /kay." ""
	      return 0
	    fi
	    if ! sidekick_append_idx_row "$SIDEKICK_NAME" "$uuid" "$hint"; then
	      emit_decision "deny" "Sidekick /kay mode: Kay audit index could not record the delegated task. Check .kay/conversations.idx permissions and re-run /kay." ""
	      return 0
	    fi
	    emit_decision "allow" "Sidekick: injected --full-auto and safe output surface." "$rewritten"
    return 0
  fi

  if has_non_readonly_chain_segment "$cmd"; then
    emit_decision "deny" "Sidekick /kay mode: command chain contains a non-read-only segment. Use kay exec --full-auto." ""
    return 0
  fi

  if has_non_readonly_pipe_segment "$cmd"; then
    emit_decision "deny" "Sidekick /kay mode: pipe chain contains a non-read-only segment. Use kay exec --full-auto." ""
    return 0
  fi

  if is_read_only "$cmd"; then
    return 0
  fi

  if is_mutating "$cmd"; then
    emit_decision "deny" "Sidekick /kay mode: mutating command denied. Delegate via kay exec --full-auto." ""
    return 0
  fi

  emit_decision "deny" "Sidekick /kay mode: command could not be classified. Delegate via kay exec --full-auto." ""
}

main() {
  sidekick_active_mode_allows "$SIDEKICK_NAME" || exit 0

  if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Sidekick /kay mode requires jq for hook enforcement. Install jq and re-run /kay."}}'
    exit 0
  fi

  [[ -n "$MARKER_FILE" ]] || exit 0
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

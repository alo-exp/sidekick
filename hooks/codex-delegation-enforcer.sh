#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Kay/Codex Delegation Enforcer (PreToolUse hook)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib/enforcer-utils.sh
source "${HOOK_DIR}/lib/enforcer-utils.sh"
# shellcheck source=hooks/lib/sidekick-registry.sh
source "${HOOK_DIR}/lib/sidekick-registry.sh"

SIDEKICK_NAME=""
MARKER_FILE=""

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

resolve_kay_binary_name() {
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

resolve_codex_binary_name() {
  if ! command -v codex >/dev/null 2>&1; then
    return 1
  fi
  if codex --version 2>/dev/null | grep -qiE '^kay([[:space:]]|$)'; then
    return 1
  fi
  if ! codex exec --help 2>/dev/null | grep -q -- '--ask-for-approval'; then
    return 1
  fi
  printf '%s' 'codex'
}

deny_reason() {
  case "$SIDEKICK_NAME" in
    kay)
      printf 'Sidekick /kay mode is active: direct file edits are delegated to Kay. Use: Bash { command: "%s --full-auto \"<your task description>\"" }. Sidekick injects the OpenCode Go provider and task model automatically; legacy code/codex/coder aliases remain compatibility-only.' "$(delegate_command)"
      ;;
    codex)
      printf 'Sidekick /codex-delegate mode is active: direct file edits are delegated to Codex. Use: Bash { command: "%s \"<your task description>\"" }. Sidekick injects -m gpt-5.4-mini, -c model_reasoning_effort=xhigh, --sandbox workspace-write, and --ask-for-approval never automatically.' "$(delegate_command)"
      ;;
  esac
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

has_delegate_exec_command() {
  local cmd stripped
  cmd="$1"
  stripped="$(strip_env_prefix "$cmd")"

  case "$SIDEKICK_NAME" in
    kay)
      [[ "$stripped" =~ ^(kay|code|codex|coder)([[:space:]]|$) ]] || return 1
      ;;
    codex)
      [[ "$stripped" =~ ^codex([[:space:]]|$) ]] || return 1
      ;;
    *)
      return 1
      ;;
  esac

  [[ "$stripped" =~ (^|[[:space:]])exec([[:space:]]|$) ]]
}

rewrite_kay_exec() {
  local cmd="$1"
  local stripped binary_name original_binary prompt route_provider route_model

  stripped="$(strip_env_prefix "$cmd")"
  original_binary="$(printf '%s' "$stripped" | awk '{print $1}')"
  binary_name="$(resolve_kay_binary_name || printf '%s' "$original_binary")"
  prompt="$(sidekick_extract_exec_prompt_raw "$stripped")"
  route_provider="$(sidekick_kay_model_provider)"
  route_model="$(sidekick_kay_model_for_prompt "$prompt")"

  python3 - "$binary_name" "$stripped" "$route_provider" "$route_model" "${HOOK_DIR}/lib/sidekick-safe-runner.sh" <<'PY'
import shlex
import sys

binary_name, cmd, model_provider, model_name, runner_path = sys.argv[1:6]

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

filtered = [tokens[0], tokens[1]]
i = 2
while i < len(tokens):
    tok = tokens[i]
    if tok == "-c" and i + 1 < len(tokens):
        config = tokens[i + 1]
        if config.startswith("model_provider=") or config.startswith("model="):
            i += 2
            continue
    filtered.append(tok)
    i += 1

tokens = filtered
route_tokens = ["-c", f"model_provider={model_provider}", "-c", f"model={model_name}"]
tokens[2:2] = route_tokens

if "--full-auto" not in tokens[2:]:
    tokens.insert(2 + len(route_tokens), "--full-auto")

tokens[0] = binary_name
rewritten = " ".join(shlex.quote(tok) for tok in ["bash", runner_path, "kay"] + tokens)
print(rewritten)
PY
}

rewrite_codex_exec() {
  local cmd="$1"
  local binary_name

  binary_name="$(resolve_codex_binary_name)" || return 1

  python3 - "$binary_name" "$cmd" "${HOOK_DIR}/lib/sidekick-safe-runner.sh" <<'PY'
import shlex
import sys

binary_name, cmd, runner_path = sys.argv[1:4]

try:
    lexer = shlex.shlex(cmd, posix=True, punctuation_chars='|;&()<>')
    lexer.whitespace_split = True
    tokens = list(lexer)
except Exception:
    raise SystemExit(1)

if len(tokens) < 3 or tokens[0] != "codex" or tokens[1] != "exec":
    raise SystemExit(1)

for tok in tokens:
    if tok in {";", "&&", "||", "|", "&", ">", "<", "(", ")"}:
        raise SystemExit(1)

filtered = [tokens[0], tokens[1]]
i = 2
while i < len(tokens):
    tok = tokens[i]
    nxt = tokens[i + 1] if i + 1 < len(tokens) else ""
    if tok in {"-m", "--model"} and nxt:
      i += 2
      continue
    if tok.startswith("--model="):
      i += 1
      continue
    if tok == "-c" and nxt:
      if nxt.startswith("model_reasoning_effort="):
        i += 2
        continue
      filtered.extend([tok, nxt])
      i += 2
      continue
    if tok in {"--sandbox", "--ask-for-approval"} and nxt:
      i += 2
      continue
    if tok.startswith("--sandbox=") or tok.startswith("--ask-for-approval="):
      i += 1
      continue
    if tok == "--full-auto":
      i += 1
      continue
    filtered.append(tok)
    i += 1

tokens = filtered
route_tokens = [
    "-m", "gpt-5.4-mini",
    "-c", "model_reasoning_effort=xhigh",
    "--sandbox", "workspace-write",
    "--ask-for-approval", "never",
]
tokens[2:2] = route_tokens
tokens[0] = binary_name
rewritten = " ".join(shlex.quote(tok) for tok in ["bash", runner_path, "codex"] + tokens)
print(rewritten)
PY
}

runtime_ready() {
  case "$SIDEKICK_NAME" in
    kay) resolve_kay_binary_name >/dev/null 2>&1 ;;
    codex) resolve_codex_binary_name >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

rewrite_delegate_exec() {
  case "$SIDEKICK_NAME" in
    kay) rewrite_kay_exec "$1" ;;
    codex) rewrite_codex_exec "$1" ;;
    *) return 1 ;;
  esac
}

missing_runtime_reason() {
  case "$SIDEKICK_NAME" in
    kay)
      printf '%s' 'Sidekick /kay mode: no Kay-compatible runtime is on PATH. Install the Kay sidekick package and re-run /kay.'
      ;;
    codex)
      printf '%s' 'Sidekick /codex-delegate mode: no OpenAI Codex CLI runtime is on PATH. Install the local OpenAI Codex CLI and re-run /codex-delegate.'
      ;;
  esac
}

malformed_rewrite_reason() {
  case "$SIDEKICK_NAME" in
    kay)
      printf '%s' 'Sidekick /kay mode: refusing to rewrite malformed Kay exec invocation.'
      ;;
    codex)
      printf '%s' 'Sidekick /codex-delegate mode: refusing to rewrite malformed Codex exec invocation.'
      ;;
  esac
}

idx_not_writable_reason() {
  case "$SIDEKICK_NAME" in
    kay)
      printf '%s' 'Sidekick /kay mode: Kay audit index is not writable or is outside the project. Remove any symlinked .kay path and re-run /kay.'
      ;;
    codex)
      printf '%s' 'Sidekick /codex-delegate mode: Codex audit index is not writable or is outside the project. Remove any symlinked .codex path and re-run /codex-delegate.'
      ;;
  esac
}

idx_append_reason() {
  case "$SIDEKICK_NAME" in
    kay)
      printf '%s' 'Sidekick /kay mode: Kay audit index could not record the delegated task. Check .kay/conversations.idx permissions and re-run /kay.'
      ;;
    codex)
      printf '%s' 'Sidekick /codex-delegate mode: Codex audit index could not record the delegated task. Check .codex/conversations.idx permissions and re-run /codex-delegate.'
      ;;
  esac
}

mutating_chain_reason() {
  case "$SIDEKICK_NAME" in
    kay)
      printf '%s' 'Sidekick /kay mode: command chain contains a non-read-only segment. Use kay exec --full-auto.'
      ;;
    codex)
      printf '%s' 'Sidekick /codex-delegate mode: command chain contains a non-read-only segment. Delegate via codex exec.'
      ;;
  esac
}

mutating_pipe_reason() {
  case "$SIDEKICK_NAME" in
    kay)
      printf '%s' 'Sidekick /kay mode: pipe chain contains a non-read-only segment. Use kay exec --full-auto.'
      ;;
    codex)
      printf '%s' 'Sidekick /codex-delegate mode: pipe chain contains a non-read-only segment. Delegate via codex exec.'
      ;;
  esac
}

mutating_denied_reason() {
  case "$SIDEKICK_NAME" in
    kay)
      printf '%s' 'Sidekick /kay mode: mutating command denied. Delegate via kay exec --full-auto.'
      ;;
    codex)
      printf '%s' 'Sidekick /codex-delegate mode: mutating command denied. Delegate via codex exec with the Sidekick-managed GPT-5.4-mini contract.'
      ;;
  esac
}

unclassified_reason() {
  case "$SIDEKICK_NAME" in
    kay)
      printf '%s' 'Sidekick /kay mode: command could not be classified. Delegate via kay exec --full-auto.'
      ;;
    codex)
      printf '%s' 'Sidekick /codex-delegate mode: command could not be classified. Delegate via codex exec with the Sidekick-managed GPT-5.4-mini contract.'
      ;;
  esac
}

allow_rewrite_reason() {
  case "$SIDEKICK_NAME" in
    kay)
      printf '%s' 'Sidekick: injected --full-auto and safe output surface.'
      ;;
    codex)
      printf '%s' 'Sidekick: injected Codex runtime flags and safe output surface.'
      ;;
  esac
}

decide_bash() {
  local tool_input_json cmd stripped uuid hint rewritten
  tool_input_json="$1"
  cmd="$(printf '%s' "$tool_input_json" | jq -r '.command // empty')"
  [[ -z "$cmd" ]] && return 0

  export_env_prefix "$cmd"

  if has_delegate_exec_command "$cmd"; then
    stripped="$(strip_env_prefix "$cmd")"
    if ! runtime_ready; then
      emit_decision "deny" "$(missing_runtime_reason)" ""
      return 0
    fi
    uuid="$(sidekick_gen_uuid)"
    if ! sidekick_validate_uuid "$uuid"; then
      emit_decision "deny" "Sidekick /${SIDEKICK_NAME} mode: refusing to record malformed audit UUID." ""
      return 0
    fi
    if ! rewritten="$(rewrite_delegate_exec "$cmd")"; then
      emit_decision "deny" "$(malformed_rewrite_reason)" ""
      return 0
    fi
    hint="$(sidekick_extract_exec_prompt "$stripped")"
    [[ -z "$hint" ]] && hint="(task hint unavailable)"
    if ! sidekick_ensure_idx "$SIDEKICK_NAME"; then
      emit_decision "deny" "$(idx_not_writable_reason)" ""
      return 0
    fi
    if ! sidekick_append_idx_row "$SIDEKICK_NAME" "$uuid" "$hint"; then
      emit_decision "deny" "$(idx_append_reason)" ""
      return 0
    fi
    emit_decision "allow" "$(allow_rewrite_reason)" "$rewritten"
    return 0
  fi

  if has_non_readonly_chain_segment "$cmd"; then
    emit_decision "deny" "$(mutating_chain_reason)" ""
    return 0
  fi

  if has_non_readonly_pipe_segment "$cmd"; then
    emit_decision "deny" "$(mutating_pipe_reason)" ""
    return 0
  fi

  if is_read_only "$cmd"; then
    return 0
  fi

  if is_mutating "$cmd"; then
    emit_decision "deny" "$(mutating_denied_reason)" ""
    return 0
  fi

  emit_decision "deny" "$(unclassified_reason)" ""
}

main() {
  SIDEKICK_NAME="$(sidekick_active_mode 2>/dev/null || true)"
  case "$SIDEKICK_NAME" in
    kay|codex) ;;
    *) exit 0 ;;
  esac

  MARKER_FILE="$(sidekick_session_marker_file "$SIDEKICK_NAME" 2>/dev/null || true)"

  if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Sidekick /${SIDEKICK_NAME} mode requires jq for hook enforcement. Install jq and re-run.\"}}"
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

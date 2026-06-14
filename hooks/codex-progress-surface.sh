#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Kay/Codex Progress Surface (PostToolUse hook)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib/enforcer-utils.sh
source "${HOOK_DIR}/lib/enforcer-utils.sh"
# shellcheck source=hooks/lib/sidekick-registry.sh
source "${HOOK_DIR}/lib/sidekick-registry.sh"
# shellcheck source=hooks/lib/sidekick-hook-io.sh
source "${HOOK_DIR}/lib/sidekick-hook-io.sh"

SIDEKICK_NAME=""
MARKER_FILE=""

strip_ansi() {
  perl -0777 -pe '
    s/\x1b\[[0-9;?]*[ -\/]*[@-~]//g;
    s/\x1b\][^\x07\x1b]*(\x07|\x1b\\)//g;
    s/\x1b[@-Z\\-_]//g;
    s/[\x00-\x08\x0b-\x1f\x7f]//g;
  '
}

extract_status_block() {
  awk '
    /^[[:space:]]*\[(CODEX|KAY)\][[:space:]]+STATUS:/ { inblk=1 }
    /^[[:space:]]*STATUS:/ && !inblk { inblk=1 }
    inblk { print; count++ }
    /PATTERNS_DISCOVERED:/ { if (inblk) { exit } }
    count >= 20 { exit }
  '
}

is_delegate_exec_command() {
  local cmd="$1"
  python3 - "$cmd" "$SIDEKICK_NAME" <<'PY'
from pathlib import Path
import shlex
import sys

cmd, mode = sys.argv[1:3]

try:
    tokens = shlex.split(cmd)
except Exception:
    raise SystemExit(1)

aliases = {"kay", "code", "coder"} if mode == "kay" else {"codex"}

if len(tokens) >= 2 and tokens[0] in aliases and tokens[1] == "exec":
    raise SystemExit(0)

for index, token in enumerate(tokens):
    if Path(token).name == "sidekick-safe-runner.sh":
        rest = tokens[index + 1:]
        if mode == "kay" and len(rest) >= 3 and rest[0] == "kay" and rest[1] in aliases and rest[2] == "exec":
            raise SystemExit(0)
        if mode == "codex" and len(rest) >= 3 and rest[0] == "codex" and rest[1] == "codex" and rest[2] == "exec":
            raise SystemExit(0)

raise SystemExit(1)
PY
}

summary_prefix() {
  case "$SIDEKICK_NAME" in
    kay) printf '%s' '[KAY-SUMMARY]' ;;
    codex) printf '%s' '[CODEX-SUMMARY]' ;;
  esac
}

display_name() {
  sidekick_registry_get "$SIDEKICK_NAME" '.[$sidekick].display_name'
}

stop_command() {
  sidekick_registry_get "$SIDEKICK_NAME" '.[$sidekick].stop_command'
}

main() {
  local input tool_name normalized_tool cmd output summary header footer payload prefix name

  if ! command -v jq >/dev/null 2>&1; then
    exit 0
  fi

  input="$(head -c 2097152)"
  sidekick_bind_hook_session_from_input "$input"

  SIDEKICK_NAME="$(sidekick_active_mode 2>/dev/null || true)"
  case "$SIDEKICK_NAME" in
    kay|codex) ;;
    *) exit 0 ;;
  esac

  SIDEKICK_HOOK_INPUT="$input"

  MARKER_FILE="$(sidekick_session_marker_file "$SIDEKICK_NAME" 2>/dev/null || true)"
  [[ -n "$MARKER_FILE" ]] || exit 0
  [[ -f "$MARKER_FILE" ]] || exit 0

  tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
  normalized_tool="$(sidekick_normalize_tool_name "$tool_name")"
  [[ "$normalized_tool" = "Bash" ]] || exit 0

  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  [[ -n "$cmd" ]] || exit 0
  cmd="$(strip_env_prefix "$cmd")"
  is_delegate_exec_command "$cmd" || exit 0

  output="$(printf '%s' "$input" | jq -r '.tool_response.output // .tool_response.stdout // empty' 2>/dev/null || true)"
  [[ -n "$output" ]] || exit 0

  summary="$(printf '%s' "$output" | strip_ansi | extract_status_block | sidekick_redact_sensitive_text)"
  [[ -n "$summary" ]] || exit 0

  prefix="$(summary_prefix)"
  name="$(display_name)"
  header="${prefix} [UNTRUSTED] === ${name} task complete ==="
  footer="${prefix} [UNTRUSTED] Stop delegation: $(stop_command)"
  payload="$(printf '%s\n%s\n%s' "$header" "$(printf '%s' "$summary" | sed "s/^/${prefix} [UNTRUSTED] /")" "$footer")"

  sidekick_emit_post_tool_context "$payload"
}

if [[ "${BASH_SOURCE[0]}" == "${0:-}" ]]; then
  main "$@"
fi

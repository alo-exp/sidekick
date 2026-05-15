#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Kay Progress Surface (PostToolUse hook)
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

# -----------------------------------------------------------------------------
# strip_ansi — remove control sequences before summarizing output.
# -----------------------------------------------------------------------------
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

is_kay_exec_command() {
  local cmd="$1"
  python3 - "$cmd" <<'PY'
from pathlib import Path
import shlex
import sys

try:
    tokens = shlex.split(sys.argv[1])
except Exception:
    raise SystemExit(1)

aliases = {"kay", "code", "codex", "coder"}
if len(tokens) >= 2 and tokens[0] in aliases and tokens[1] == "exec":
    raise SystemExit(0)

for index, token in enumerate(tokens):
    if Path(token).name == "sidekick-safe-runner.sh":
        rest = tokens[index + 1:]
        if len(rest) >= 3 and rest[0] == "kay" and rest[1] in aliases and rest[2] == "exec":
            raise SystemExit(0)

raise SystemExit(1)
PY
}

main() {
  if ! command -v jq >/dev/null 2>&1; then
    exit 0
  fi

  [[ -n "$MARKER_FILE" ]] || exit 0
  [[ -f "$MARKER_FILE" ]] || exit 0

  local input tool_name cmd output summary header footer payload
  input="$(head -c 2097152)"
  tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
  [[ "$tool_name" = "Bash" ]] || exit 0

  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  [[ -n "$cmd" ]] || exit 0
  cmd="$(strip_env_prefix "$cmd")"
  is_kay_exec_command "$cmd" || exit 0

  output="$(printf '%s' "$input" | jq -r '.tool_response.output // .tool_response.stdout // empty' 2>/dev/null || true)"
  [[ -n "$output" ]] || exit 0

  summary="$(printf '%s' "$output" | strip_ansi | extract_status_block | sidekick_redact_sensitive_text)"
  [[ -n "$summary" ]] || exit 0

  header="[KAY-SUMMARY] [UNTRUSTED] === Kay task complete ==="
  footer="[KAY-SUMMARY] [UNTRUSTED] Stop delegation: $(jq -r --arg sidekick "$SIDEKICK_NAME" '.[$sidekick].stop_command' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../sidekicks/registry.json")"
  payload="$(printf '%s\n%s\n%s' "$header" "$(printf '%s' "$summary" | sed 's/^/[KAY-SUMMARY] [UNTRUSTED] /')" "$footer")"

  jq -cn --arg ctx "$payload" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
}

if [[ "${BASH_SOURCE[0]}" == "${0:-}" ]]; then
  main "$@"
fi

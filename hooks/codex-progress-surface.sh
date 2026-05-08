#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Codex Progress Surface (PostToolUse hook)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

MARKER_FILE="${HOME}/.claude/.codex-delegation-active"
SIDEKICK_NAME="codex"

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
    /^[[:space:]]*\[CODEX\][[:space:]]+STATUS:/ { inblk=1 }
    /^[[:space:]]*STATUS:/ && !inblk { inblk=1 }
    inblk { print; count++ }
    /PATTERNS_DISCOVERED:/ { if (inblk) { exit } }
    count >= 20 { exit }
  '
}

main() {
  if ! command -v jq >/dev/null 2>&1; then
    exit 0
  fi

  [[ -f "$MARKER_FILE" ]] || exit 0

  local input tool_name cmd output summary header footer payload
  input="$(head -c 2097152)"
  tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
  [[ "$tool_name" = "Bash" ]] || exit 0

  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  [[ -n "$cmd" ]] || exit 0
  [[ "$cmd" =~ ^(codex|code|coder)[[:space:]]+exec([[:space:]]|$) ]] || exit 0

  output="$(printf '%s' "$input" | jq -r '.tool_response.output // .tool_response.stdout // empty' 2>/dev/null || true)"
  [[ -n "$output" ]] || exit 0

  summary="$(printf '%s' "$output" | strip_ansi | extract_status_block | perl -pe '
    s/(?i)(authorization:\s*)(?:bearer\s+)?\S+.*$/${1}[REDACTED]/g;
    s/(?i)(api[_-]?key\s*[:=]\s*)\S+/${1}[REDACTED]/g;
    s/sk-[A-Za-z0-9_\-\.\/+]{10,}(?=\s|[\'"'"'">},]|$)/[REDACTED-SK-TOKEN]/g;
    s/\bgh[pousra]_[A-Za-z0-9]{20,}\b/[REDACTED-GH-TOKEN]/g;
    s/\bgithub_pat_[A-Za-z0-9_]{20,}\b/[REDACTED-GH-TOKEN]/g;
    s/\bxox[abprse]-[A-Za-z0-9-]{10,}\b/[REDACTED-SLACK-TOKEN]/g;
  ')"
  [[ -n "$summary" ]] || exit 0

  header="[CODEX-SUMMARY] [UNTRUSTED] === Codex task complete ==="
  footer="[CODEX-SUMMARY] [UNTRUSTED] Stop delegation: $(jq -r --arg sidekick "$SIDEKICK_NAME" '.[$sidekick].stop_command' "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../sidekicks/registry.json")"
  payload="$(printf '%s\n%s\n%s' "$header" "$(printf '%s' "$summary" | sed 's/^/[CODEX-SUMMARY] [UNTRUSTED] /')" "$footer")"

  jq -cn --arg ctx "$payload" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
}

if [[ "${BASH_SOURCE[0]}" == "${0:-}" ]]; then
  main "$@"
fi

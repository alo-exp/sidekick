#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Cursor sessionStart hook (bind SIDEKICK_SESSION_ID)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

main() {
  local input conversation_id

  if ! command -v jq >/dev/null 2>&1; then
    exit 0
  fi

  input="$(cat)"
  conversation_id="$(printf '%s' "$input" | jq -r '.conversation_id // .session_id // empty' 2>/dev/null || true)"
  [[ -n "$conversation_id" ]] || exit 0

  jq -cn --arg sid "$conversation_id" '{env: {SIDEKICK_SESSION_ID: $sid}}'
}

if [[ "${BASH_SOURCE[0]}" == "${0:-}" ]]; then
  main "$@"
fi

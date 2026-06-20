#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Cursor sessionEnd hook (clear session-scoped delegation)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib/sidekick-registry.sh
source "${HOOK_DIR}/lib/sidekick-registry.sh"

clear_session_markers() {
  local session_id="$1"
  local active_file kay_marker codex_marker provider_file

  active_file="${HOME}/.sidekick/sessions/${session_id}/active-sidekick"
  provider_file="${HOME}/.sidekick/sessions/${session_id}/kay-provider"
  kay_marker="${HOME}/.kay/sessions/${session_id}/.kay-delegation-active"
  codex_marker="${HOME}/.codex/sessions/${session_id}/.codex-delegation-active"

  rm -f "${kay_marker}" "${codex_marker}" "${provider_file}"
  rm -f "${active_file}"
}

main() {
  local input conversation_id session_id

  if ! command -v jq >/dev/null 2>&1; then
    exit 0
  fi

  input="$(cat)"
  conversation_id="$(printf '%s' "$input" | jq -r '.conversation_id // .session_id // empty' 2>/dev/null || true)"
  [[ -n "$conversation_id" ]] || exit 0

  session_id="${SIDEKICK_SESSION_ID:-${conversation_id}}"
  clear_session_markers "$session_id"
  exit 0
}

if [[ "${BASH_SOURCE[0]}" == "${0:-}" ]]; then
  main "$@"
fi

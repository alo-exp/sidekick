---
name: codex-stop
description: Canonical Codex stop workflow. Use /sidekick:codex-stop to deactivate delegation and return to direct host behavior.
---

# Codex Stop Workflow

Stop Codex mode and restore normal direct-host behavior.

## Procedure

1. Resolve the active host session id, then check whether the matching Codex marker exists:
   ```bash
   if [[ -z "${SIDEKICK_HOST_HOME:-}" ]]; then
     if [[ -n "${CODEX_HOME:-${CODEX_THREAD_ID:-${CODEX_PROJECT_DIR:-${CODEX_PLUGIN_ROOT:-}}}}" ]]; then
       SIDEKICK_HOST_HOME="${CODEX_HOME:-${HOME}/.codex}"
     elif [[ -n "${CLAUDE_SESSION_ID:-${CLAUDE_PROJECT_DIR:-${CLAUDE_PLUGIN_ROOT:-}}}" ]]; then
       SIDEKICK_HOST_HOME="${HOME}/.claude"
     else
       echo "No host home found for Codex mode"; exit 1
     fi
   fi
   SIDEKICK_SESSION="${SIDEKICK_SESSION_ID:-${SIDEKICK_HOST_SESSION_ID:-${CODEX_THREAD_ID:-${CLAUDE_SESSION_ID:-${SESSION_ID:-}}}}}"
   test -n "${SIDEKICK_SESSION}" || { echo "No host session id found for Codex mode"; exit 1; }
   CODEX_STATE_ROOT="${HOME}/.codex"
   test -f "${CODEX_STATE_ROOT}/sessions/${SIDEKICK_SESSION}/.codex-delegation-active"
   ```
   - **If yes:** delete it and clear the shared active-sidekick marker only if it still points at Codex:
     ```bash
     rm -f "${CODEX_STATE_ROOT}/sessions/${SIDEKICK_SESSION}/.codex-delegation-active"
     ACTIVE_FILE="${HOME}/.sidekick/sessions/${SIDEKICK_SESSION}/active-sidekick"
     if [ -f "${ACTIVE_FILE}" ] && [ "$(cat "${ACTIVE_FILE}")" = "codex" ]; then
       rm -f "${ACTIVE_FILE}"
     fi
     ```
     Then confirm: **"Codex sidekick mode deactivated for this session. Direct-host mode restored."**
   - **If no:** confirm: **"Codex sidekick mode is not currently active."**

## Notes

- `.codex/conversations.idx` is preserved across deactivation as the Sidekick-owned Codex audit ledger.
- Deactivation does not touch the local OpenAI Codex CLI's own runtime history or any project files.

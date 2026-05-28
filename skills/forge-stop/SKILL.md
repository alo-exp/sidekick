---
name: forge-stop
description: Canonical Forge stop workflow. Use /forge-stop to deactivate delegation and return to direct host behavior.
---

# Forge Stop Workflow

Stop Forge-first mode and restore normal direct-host behavior.

## Procedure

1. Resolve the active host session id, then check whether the matching Forge marker exists:
   ```bash
   if [[ -z "${SIDEKICK_HOST_HOME:-}" ]]; then
     if [[ -n "${CODEX_HOME:-${CODEX_THREAD_ID:-${CODEX_PROJECT_DIR:-${CODEX_PLUGIN_ROOT:-}}}}" ]]; then
       SIDEKICK_HOST_HOME="${CODEX_HOME:-${HOME}/.codex}"
     elif [[ -n "${CLAUDE_SESSION_ID:-${CLAUDE_PROJECT_DIR:-${CLAUDE_PLUGIN_ROOT:-}}}" ]]; then
       SIDEKICK_HOST_HOME="${HOME}/.claude"
     else
       echo "No host home found for Forge mode"; exit 1
     fi
   fi
   SIDEKICK_SESSION="${SIDEKICK_SESSION_ID:-${SIDEKICK_HOST_SESSION_ID:-${CODEX_THREAD_ID:-${CLAUDE_SESSION_ID:-${SESSION_ID:-}}}}}"
   test -n "${SIDEKICK_SESSION}" || { echo "No host session id found for Forge mode"; exit 1; }
   test -f "${SIDEKICK_HOST_HOME}/sessions/${SIDEKICK_SESSION}/.forge-delegation-active"
   ```
   - **If yes:** delete it and the sibling Level 3 marker with:
     ```bash
     rm -f "${SIDEKICK_HOST_HOME}/sessions/${SIDEKICK_SESSION}/.forge-delegation-active" \
       "${SIDEKICK_HOST_HOME}/sessions/${SIDEKICK_SESSION}/.forge-level3-active"
     ACTIVE_FILE="${HOME}/.sidekick/sessions/${SIDEKICK_SESSION}/active-sidekick"
     if [ -f "${ACTIVE_FILE}" ] && [ "$(cat "${ACTIVE_FILE}")" = "forge" ]; then
       rm -f "${ACTIVE_FILE}"
     fi
     ```
     Then attempt to revert the active output style to `default` (or the prior style if tracked). Confirm: **"Forge-first mode deactivated for this session. Direct-host mode restored."**
   - **If no:** acknowledge: **"Forge-first mode is not currently active."**

## Notes

- `.forge/conversations.idx` is preserved across deactivation as a durable audit trail of Forge tasks issued from this project.
- After deactivation, the PreToolUse enforcer hook and PostToolUse progress-surface hook both become no-ops for this session (they are gated on the same marker file).
- Deactivation does not delete any project files, AGENTS.md content, or Forge database state. It only removes session markers.

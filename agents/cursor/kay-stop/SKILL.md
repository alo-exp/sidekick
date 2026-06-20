---
name: kay-stop
description: Canonical Kay stop workflow. Use /sidekick:kay-stop to deactivate delegation and return to direct host behavior.
argument-hint: ""
---

# Kay Stop Workflow

Stop Kay mode and restore normal direct-host behavior.

## Procedure

1. Resolve the active host session id, then check whether the matching Kay marker exists:
   ```bash
   SIDEKICK_SESSION="${SIDEKICK_SESSION_ID:-${SESSION_ID:-}}"
   test -n "${SIDEKICK_SESSION}" || { echo "No host session id found for Kay mode"; exit 1; }
   KAY_STATE_ROOT="${HOME}/.kay"
   test -f "${KAY_STATE_ROOT}/sessions/${SIDEKICK_SESSION}/.kay-delegation-active"
   ```
   - **If yes:** delete it and clear the shared active-sidekick marker only if it still points at Kay:
     ```bash
     rm -f "${KAY_STATE_ROOT}/sessions/${SIDEKICK_SESSION}/.kay-delegation-active"
     ACTIVE_FILE="${HOME}/.sidekick/sessions/${SIDEKICK_SESSION}/active-sidekick"
     if [ -f "${ACTIVE_FILE}" ] && [ "$(cat "${ACTIVE_FILE}")" = "kay" ]; then
       rm -f "${ACTIVE_FILE}"
     fi
     ```
     Then confirm: **"Kay sidekick mode deactivated for this session. Direct-host mode restored."**
   - **If no:** confirm: **"Kay sidekick mode is not currently active."**

## Notes

- `.kay/conversations.idx` is preserved across deactivation as the Sidekick-owned Kay audit ledger.
- Deactivation does not touch Kay runtime history, the legacy `~/.code/history.jsonl` compatibility history file, or any project files.
- On Cursor, the sessionEnd hook also clears session-scoped Kay markers when the chat session ends.

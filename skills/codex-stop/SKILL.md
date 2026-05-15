---
name: kay-stop
description: Canonical Kay stop workflow. Use /kay-stop to deactivate delegation and return to direct host behavior.
---

# Kay Stop Workflow

Stop Kay mode and restore normal direct-host behavior.

## Procedure

1. Resolve the active host session id, then check whether the matching Kay marker exists:
   ```bash
   SIDEKICK_SESSION="${SIDEKICK_SESSION_ID:-${CODEX_THREAD_ID:-${CLAUDE_SESSION_ID:-${SESSION_ID:-}}}}"
   test -n "${SIDEKICK_SESSION}" || { echo "No host session id found for Kay mode"; exit 1; }
   test -f "${HOME}/.kay/sessions/${SIDEKICK_SESSION}/.kay-delegation-active"
   ```
   - **If yes:** delete it and clear the shared active-sidekick marker only if it still points at Kay:
     ```bash
     rm -f "${HOME}/.kay/sessions/${SIDEKICK_SESSION}/.kay-delegation-active"
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

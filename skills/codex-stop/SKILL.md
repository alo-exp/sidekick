---
name: kay-stop
description: Canonical Kay stop workflow. Use /kay-stop to deactivate delegation and return to direct Claude behavior.
---

# Kay Stop Workflow

Stop Kay mode and restore normal Claude behavior.

## Procedure

1. Check whether `~/.kay/sessions/${CODEX_THREAD_ID}/.kay-delegation-active` exists.
   - **If yes:** delete it, then confirm: **"Kay sidekick mode deactivated for this session. Claude-direct mode restored."**
   - **If no:** confirm: **"Kay sidekick mode is not currently active."**

## Notes

- `.kay/conversations.idx` is preserved across deactivation as the Sidekick-owned Kay audit ledger.
- Deactivation does not touch the native `~/.code/history.jsonl` history file or any project files.

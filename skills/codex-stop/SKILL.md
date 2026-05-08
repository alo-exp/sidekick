---
name: codex-stop
description: Canonical Codex stop workflow. Use /codex-stop to deactivate delegation and return to direct Claude behavior.
---

# Codex Stop Workflow

Stop Codex mode and restore normal Claude behavior.

## Procedure

1. Check whether `~/.claude/.codex-delegation-active` exists.
   - **If yes:** delete it, then confirm: **"Codex sidekick mode deactivated. Claude-direct mode restored."**
   - **If no:** confirm: **"Codex sidekick mode is not currently active."**

## Notes

- `.codex/conversations.idx` is preserved across deactivation as the Sidekick-owned Codex audit ledger.
- Deactivation does not touch Codex’s native `~/.code/history.jsonl` history file or any project files.

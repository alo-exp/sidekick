---
name: forge-stop
description: Deactivate Forge-first delegation mode and return to direct Claude implementation.
---

# /forge-stop — Stop Forge Delegation

Stop Forge-first mode and restore normal Claude behavior.

## Procedure

1. Check if `~/.claude/.forge-delegation-active` exists.
   - **If yes:** delete it, then attempt to revert the active output style to `default` (or the prior style if tracked). Confirm: **"Forge-first mode deactivated. Claude-direct mode restored."**
   - **If no:** acknowledge: **"Forge-first mode is not currently active."**

## Notes

- `.forge/conversations.idx` is preserved across deactivation — it is a durable audit trail of every Forge task issued from this project and is accessible via `/forge-history`.
- After deactivation, the PreToolUse enforcer hook and PostToolUse progress-surface hook both become no-ops (they are gated on the same marker file).
- Deactivation does not delete any project files, AGENTS.md content, or Forge database state. It only removes the session marker.

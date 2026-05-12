---
name: forge-stop
description: Canonical Forge stop workflow. Use /forge-stop to deactivate delegation and return to direct Claude behavior.
---

# Forge Stop Workflow

Stop Forge-first mode and restore normal Claude behavior.

## Procedure

1. Check if `~/.claude/sessions/${CODEX_THREAD_ID}/.forge-delegation-active` exists.
   - **If yes:** delete it, then attempt to revert the active output style to `default` (or the prior style if tracked). Confirm: **"Forge-first mode deactivated for this session. Claude-direct mode restored."**
   - **If no:** acknowledge: **"Forge-first mode is not currently active."**

## Notes

- `.forge/conversations.idx` is preserved across deactivation as a durable audit trail of Forge tasks issued from this project.
- After deactivation, the PreToolUse enforcer hook and PostToolUse progress-surface hook both become no-ops for this session (they are gated on the same marker file).
- Deactivation does not delete any project files, AGENTS.md content, or Forge database state. It only removes the session marker.

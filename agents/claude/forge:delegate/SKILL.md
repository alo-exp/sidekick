---
name: forge:delegate
description: Alias activation surface for Forge delegation mode. Use when the user asks for /forge:delegate.
---

# /forge:delegate

This is a user-facing alias for the canonical Forge activation skill at
`forge/SKILL.md` in this generated claude skill root (`agents/claude/forge/SKILL.md` in the repository).

When invoked, follow the canonical `/forge` workflow exactly:

1. Run the Forge readiness checks.
2. Create the current-session Forge marker only after readiness passes.
3. Delegate implementation work to Forge while the host AI remains the planner,
   reviewer, communicator, and mentor.

To stop Forge delegation, invoke `/forge-stop`.

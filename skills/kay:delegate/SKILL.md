---
name: kay:delegate
description: Alias activation surface for Kay delegation mode. Use when the user asks for /kay:delegate.
---

# /kay:delegate

This is a user-facing alias for the canonical Kay delegation skill at
`skills/codex-delegate/SKILL.md`.

When invoked, follow the canonical `kay-delegate` workflow exactly:

1. Verify the Kay runtime and provider configuration.
2. Create the current-session Kay marker.
3. Delegate implementation work through Kay while the host AI remains the
   planner, reviewer, communicator, and mentor.

To stop Kay delegation, invoke `/kay-stop`.

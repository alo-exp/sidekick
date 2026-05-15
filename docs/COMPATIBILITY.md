# Compatibility

> How the same Sidekick ideas map across Claude Code, Codex, Forge, and Kay.

---

| Concern | Host Surface | Execution Agent | Notes |
|---------|--------------|-----------------|-------|
| Canonical instruction body | Claude Code and Codex plugin skills | `skills/<name>/SKILL.md` | Skills stay canonical regardless of host. |
| Command discoverability | Claude command surface, Codex marketplace skills, and plugin-prefixed pickers | Forge and Kay delegate/stop skills | Wrappers are for discovery, not for source text. |
| Execution identity | Host AI remains advisor, reviewer, and mentor | `forge` or `kay` | Sidekick should launch the active runtime binary, not a deprecated compatibility alias. |
| Provider precedence | Host asks for the backend path the user wants | MiniMax Coding for Forge; MiniMax.io and OpenCode Go for Kay | Provider choice is runtime-owned and should stay explicit. |
| Run history | Host session markers and progress summaries | Forge-owned or Kay-owned audit/index state | History is intentionally separate. |
| Shared environment | Project docs, tasks, help, and agent conventions | Agent-local runtime state such as `.forge/` or `.kay/` | The user should feel continuity without duplicated writable state. |
| Runtime differences | Same host can choose either execution agent | Forge fallback ladder and mentoring loop; Kay native `kay exec` flow | Do not assume one runtime automatically supports the other's UX surface. |

## Reading the Matrix

- If you need to know where a behavior lives, start with this table.
- If you need terminology, read [GLOSSARY.md](GLOSSARY.md).
- If you need installation or task flow, read [START-HERE.md](START-HERE.md).

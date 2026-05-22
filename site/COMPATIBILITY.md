# Compatibility

> How the same Sidekick ideas map across Claude Code, Codex, Forge, and Kay.

---

| Concern | Host Surface | Execution Agent | Notes |
|---------|--------------|-----------------|-------|
| Canonical instruction body | Claude Code and Codex plugin skills | `skills/<name>/SKILL.md` | Skills stay canonical and host-agnostic regardless of host. |
| Generated host skill surface | Claude and Codex plugin manifests | `agents/claude/<name>/SKILL.md`, `agents/codex/<name>/SKILL.md` | Generated from `skills/`; do not edit directly. |
| Command discoverability | Claude command surface, Codex marketplace skills, and plugin-prefixed pickers | Forge and Kay delegate/stop skills | Wrappers are for discovery, not for source text. |
| Execution identity | Host AI remains advisor, reviewer, and mentor | `forge` or `kay` | Sidekick should launch the active runtime binary, not a deprecated compatibility alias. |
| Provider precedence | Host asks for the backend path the user wants | MiniMax Coding for Forge; OpenCode Go provider routing for Kay delegation with MiMo-V2.5-Pro for non-trivial and vision / visual reasoning work, MiniMax M2.7 for trivial work, and DeepSeek V4 Flash for test running / issue reporting / completion verification | Provider choice is runtime-owned and should stay explicit. |
| Run history | Host session markers and progress summaries | Forge-owned or Kay-owned audit/index state | History is intentionally separate. |
| Shared environment | Project docs, tasks, help, and agent conventions | Agent-local runtime state such as `.forge/` or `.kay/` | The user should feel continuity without duplicated writable state. |
| Runtime differences | Same host can choose either execution agent | Forge fallback ladder and mentoring loop; Kay native `kay exec` flow | Do not assume one runtime automatically supports the other's UX surface. |

## Reading the Matrix

- If you need to know where a behavior lives, start with this table.
- If you need terminology, read [GLOSSARY.md](GLOSSARY.md).
- If you need installation or task flow, read [START-HERE.md](START-HERE.md).

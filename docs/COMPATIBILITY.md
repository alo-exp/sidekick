# Compatibility

> How the same Sidekick ideas map across Claude, Codex, and Kay.

---

| Concern | Claude / Forge | Codex / Code / Kay | Notes |
|---------|----------------|--------------------|-------|
| Canonical instruction body | `skills/<name>/SKILL.md` | `skills/<name>/SKILL.md` | Skills stay canonical in both runtimes. |
| Command discoverability | Claude command surface and wrappers | Kay skill bridges plus wrapper commands where supported | The wrapper is for discovery, not for source text. |
| Execution identity | `forge` | `code` | Sidekick should launch the active runtime binary, not a preinstalled fallback. |
| Provider precedence | OpenRouter / Forge defaults | MiniMax-backed `code` defaults | Provider choice is runtime-owned and should stay explicit. |
| Run history | Forge-owned audit/index state | Kay-owned audit/index state | History is intentionally separate. |
| Shared environment | Project docs, tasks, help, and agent conventions | Host Codex tools, skills, hooks, MCPs, and agents by reference | The user should feel continuity without duplicated writable state. |
| Runtime differences | Forge-specific fallback ladder and mentoring loop | Kay-specific `code exec` flow and native extension line | Do not assume one runtime automatically supports the other's UX surface. |

## Reading the Matrix

- If you need to know where a behavior lives, start with this table.
- If you need terminology, read [GLOSSARY.md](GLOSSARY.md).
- If you need installation or task flow, read [START-HERE.md](START-HERE.md).

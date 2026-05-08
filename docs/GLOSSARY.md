# Glossary

> Canonical terms for Sidekick docs.

---

| Term | Meaning |
|------|---------|
| **Sidekick** | The Ālo Labs plugin system that hosts multiple coding-agent runtimes under one host-side orchestration layer. |
| **Forge** | The ForgeCode sidekick runtime. It is the Claude-oriented delegation path used by the Forge skill set. |
| **Code / Kay** | The Every Code extension line that powers the MiniMax-backed `code` runtime. `Kay` is the Sidekick packaging identity for that runtime. |
| **host Codex** | The user-installed Codex environment that Kay consumes by reference for shared tools, skills, hooks, MCPs, and agent assets. |
| **delegate** | To hand execution of a coding task to a sidekick while Claude stays in the orchestration role. |
| **skill** | The canonical instruction body for a capability. In Sidekick, skills are the source of truth. |
| **command** | A runtime-facing wrapper or discoverability surface that points to a canonical skill body. |
| **bridge** | A thin compatibility layer that makes a skill or command visible in a runtime's native picker or import path. |
| **wrapper** | A minimal command file that exists for discoverability and routing, not as the source of truth for the workflow body. |

## Canonical Rules

- Skills carry the real instruction text.
- Commands point to skills when a runtime needs slash-command discoverability.
- Compatibility layers should not duplicate long-form workflow text.
- Runtime-specific docs should point back to this glossary instead of redefining terms.

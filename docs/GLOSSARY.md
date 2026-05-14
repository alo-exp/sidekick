# Glossary

> Canonical terms for Sidekick docs.

---

| Term | Meaning |
|------|---------|
| **Sidekick** | The Ālo Labs plugin system that hosts multiple coding-agent runtimes under one host-side orchestration layer. |
| **Forge** | The ForgeCode sidekick runtime. It is the Claude-oriented delegation path used by the Forge skill set. |
| **Kay** | The OSS Codex-lineage execution agent packaged by Sidekick. `kay` is the canonical binary; legacy Code aliases (`code`, `codex`, `coder`) are compatibility-only. |
| **host Codex** | The user-installed Codex environment that can host the Sidekick plugin and route work to Forge or Kay. |
| **delegate** | To hand execution of a coding task to a sidekick while Claude stays in the orchestration role. |
| **skill** | The canonical instruction body for a capability. In Sidekick, skills are the source of truth. |
| **selector** | A host/runtime picker entry (for example `sidekick:forge-stop`) that resolves directly to a canonical skill body. |
| **bridge** | A thin compatibility layer that makes a skill visible in a runtime's native picker or import path. |
| **wrapper** | A minimal compatibility skill (or alias file) that points to canonical workflow content without duplicating it. |

## Canonical Rules

- Skills carry the real instruction text and are the runtime contract.
- Compatibility layers should not duplicate long-form workflow text.
- Runtime-specific docs should point back to this glossary instead of redefining terms.

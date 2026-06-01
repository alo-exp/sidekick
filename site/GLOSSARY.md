# Glossary

> Canonical terms for current Sidekick docs.

| Term | Meaning |
| --- | --- |
| **Sidekick** | The Alo Labs plugin that gives Claude Code and Codex a shared delegation layer for supported coding sidekicks. |
| **host AI** | The Claude Code or Codex session that plans, delegates, reviews, verifies, and communicates with the user. |
| **sidekick** | A supported child runtime that performs bounded implementation work after activation. Current sidekicks are Kay and Codex. |
| **Kay** | The Kay runtime installed and repaired through Sidekick. Kay tasks run through `kay exec`. |
| **Codex sidekick** | The local OpenAI Codex CLI used as a child runtime through `codex exec`, pinned to `gpt-5.4-mini` with extra-high reasoning. |
| **delegate** | To hand a bounded coding task from the host AI to the active sidekick. |
| **active-sidekick** | The shared session selector at `~/.sidekick/sessions/<session>/active-sidekick`. It contains `kay` or `codex`. |
| **marker** | A project-local file showing that a sidekick is active in the current host session. |
| **Host verification** | The host-owned review pass that checks requirements, diffs, tests, integration behavior, assumptions, and failure classes before reporting completion. |
| **generated host bundle** | A rendered skill surface under `agents/claude/` or `agents/codex/`, produced from canonical files under `skills/`. |
| **registry** | `sidekicks/registry.json`, the shared metadata for runtime names, marker paths, commands, and install details. |
| **release gate** | The test sequence that proves public docs, generated surfaces, manifests, hooks, and live sidekick paths are aligned. |

## Canonical Rules

- The host AI owns final correctness.
- Kay and Codex are mutually exclusive in a host session.
- Canonical workflow text lives under `skills/`.
- Generated host bundles are render outputs.
- Public docs should name only the supported sidekicks: Kay and Codex.

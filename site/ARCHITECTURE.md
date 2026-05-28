# Architecture

Sidekick has four active layers.

1. **Skills** define the canonical Kay and Codex delegation workflows.
2. **Generated host bundles** render those skills for Claude Code and Codex host environments.
3. **Hooks** enforce active-sidekick boundaries, inject required runtime flags, and surface bounded output.
4. **Registry and manifests** publish only supported sidekicks and integrity hashes.

## Supported Sidekicks

| Sidekick | Runtime | Hook Behavior |
| --- | --- | --- |
| Kay | `kay exec` | Adds full-auto execution and Kay routing config |
| Codex | `codex exec` | Adds model, reasoning, sandbox, and approval policy |

The host verifies the task result and relaunches the active sidekick for any missed work.

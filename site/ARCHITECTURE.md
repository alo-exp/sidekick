# Architecture

> Current Sidekick architecture for the Kay and Codex sidekicks.

**Plugin version:** Sidekick 0.7.0
**Hosts:** Claude Code and Codex
**Stack:** Shell/Bash plus Markdown
**Supported sidekicks:** Kay and Codex

## System Overview

Sidekick gives Claude Code and Codex a shared delegation layer. The host AI stays responsible for planning, user communication, review, and final correctness. The active sidekick performs bounded implementation work through its native runtime.

The system has two durable roles:

| Role | Responsibility |
| --- | --- |
| Host AI | Plans the task, activates one sidekick, delegates bounded work, reviews changes, runs verification, and reports to the user. |
| Active sidekick | Performs implementation work as a child runtime. Kay uses `kay exec`; Codex uses `codex exec`. |

## Supported Sidekicks

| Sidekick | Activate | Runtime | State root |
| --- | --- | --- | --- |
| Kay | `/sidekick:kay-delegate` | `kay exec` | `.kay/sessions/<session>` |
| Codex | `/sidekick:codex-delegate` | `codex exec` with `gpt-5.4-mini` and extra-high reasoning | `.codex/sessions/<session>` |

Kay defaults to OpenCode Go routing. `/sidekick:kay-delegate xiaomi` selects Xiaomi routing, and `/sidekick:kay-delegate ocg` forces OpenCode Go routing. `SIDEKICK_KAY_PROVIDER` is still supported as an environment override.

## Delegation Boundary

Only one sidekick may be active in a host session. The shared selector is:

```text
~/.sidekick/sessions/<session>/active-sidekick
```

The selector contains `kay` or `codex`. Per-sidekick markers live under the project:

```text
.kay/sessions/<session>/.kay-delegation-active
.codex/sessions/<session>/.codex-delegation-active
```

Hooks use this state to decide which runtime boundary is active. Direct host mutations are blocked while a sidekick owns implementation work, and supported child-runtime commands are routed through bounded progress surfaces.

## Canonical Sources

| Surface | Path | Notes |
| --- | --- | --- |
| Kay delegate skill | `skills/kay-delegate/SKILL.md` | Canonical Kay activation workflow. |
| Kay stop skill | `skills/kay-stop/SKILL.md` | Canonical Kay deactivation workflow. |
| Codex delegate skill | `skills/codex-delegate/SKILL.md` | Canonical Codex activation workflow. |
| Codex stop skill | `skills/codex-stop/SKILL.md` | Canonical Codex deactivation workflow. |
| Registry | `sidekicks/registry.json` | Runtime names, commands, markers, and install metadata. |
| Generated host bundles | `agents/claude/`, `agents/codex/` | Rendered from `skills/`; do not edit by hand. |
| Renderer | `scripts/sync-host-surfaces.sh` | Rebuilds generated host surfaces. |

Generated copies are implementation artifacts. Update the canonical skill first, then run:

```bash
bash scripts/sync-host-surfaces.sh
```

## Runtime Flow

```text
User request
  -> Host AI scopes task and chooses the active sidekick
  -> Sidekick writes active-sidekick session state
  -> Host delegates through kay exec or codex exec
  -> Progress surface returns bounded task output
  -> Host verifies diff, tests, assumptions, and integration behavior
  -> Host reports completion or relaunches the active sidekick
```

## Host Verification

The host verification pass checks for at least these failure classes:

- `MISSED_REQUIREMENT`
- `INTEGRATION_ERROR`
- `REGRESSION`
- `WRONG_LOGIC`
- `SYNTAX_ERROR`
- `WRONG_FILE`
- `UNVERIFIED_ASSUMPTION`
- `KNOWLEDGE_GAP`
- `MISUNDERSTOOD_TASK`
- `TRIAL_INCOMPLETE`
- `API_FAILURE`
- `EXECUTION_ERROR_EXTERNAL`

A sidekick result is accepted only after this verification pass confirms the requested behavior in the repository.

## Design Principles

1. Keep the host accountable for correctness.
2. Allow exactly one active sidekick per host session.
3. Keep Kay and Codex state isolated from each other.
4. Keep canonical workflow text under `skills/`.
5. Render generated host bundles mechanically.
6. Make every release check reproducible through Bash test runners.

## Related Docs

- [Start Here](START-HERE.md)
- [Compatibility](COMPATIBILITY.md)
- [Glossary](GLOSSARY.md)
- [Testing](TESTING.md)
- [Help](help/)

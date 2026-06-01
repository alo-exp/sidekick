# Product Requirements Overview

> Product-level summary for the current Sidekick site and plugin contract.

**Current public version:** Sidekick 0.7.0
**Supported sidekicks:** Kay and Codex
**Primary users:** Developers using Claude Code or Codex who want delegated implementation with host-owned review.

## Product Vision

Sidekick turns the host AI into a planner, reviewer, verifier, and user-facing coordinator. Implementation work is delegated to a supported sidekick while the host remains accountable for the final repository state.

## Core Value

When Kay or Codex delegation is active, the host should not treat its own implementation tools as the normal path. The active sidekick performs bounded work through `kay exec` or `codex exec`, while the host reviews the result, runs checks, and relaunches the active sidekick when verification fails.

The one thing that must work above all else:

> A sidekick task is not done until the host verifies it against the original prompt and repository behavior.

## Supported Sidekicks

| Sidekick | Runtime | Activation | Stop |
| --- | --- | --- | --- |
| Kay | `kay exec` | `/sidekick:kay-delegate` | `/sidekick:kay-stop` |
| Codex | `codex exec` using `gpt-5.4-mini` with extra-high reasoning | `/sidekick:codex-delegate` | `/sidekick:codex-stop` |

Kay also accepts `/sidekick:kay-delegate xiaomi`, `/sidekick:kay-delegate ocg`, and `SIDEKICK_KAY_PROVIDER` for provider routing.

## Requirement Areas

| Area | Requirement |
| --- | --- |
| Activation | Exactly one sidekick can be active in a host session. |
| Runtime routing | Kay uses `kay exec`; Codex uses the local OpenAI Codex CLI through `codex exec`. |
| State isolation | Kay and Codex keep separate project-local markers and lookup ledgers. |
| Host verification | The host checks requirements, diffs, tests, assumptions, and integration behavior after every sidekick task. |
| Generated surfaces | Host bundles under `agents/claude/` and `agents/codex/` render from canonical skills. |
| Registry alignment | `sidekicks/registry.json`, hooks, docs, and tests agree on supported sidekicks. |
| Release evidence | `tests/run_unit.bash`, `tests/run_all.bash`, and the live Codex release gate stay documented and runnable. |

## Explicit Non-Goals

- Supporting more than one active sidekick in the same host session.
- Treating child-runtime success output as sufficient proof.
- Editing generated host bundles without updating canonical skill sources.
- Installing the local OpenAI Codex CLI automatically; users provide that runtime.
- Replacing project-specific tests with Sidekick's generic verification rules.

## Source Of Truth

- Runtime registry: `sidekicks/registry.json`
- Canonical workflows: `skills/kay-delegate/SKILL.md`, `skills/kay-stop/SKILL.md`, `skills/codex-delegate/SKILL.md`, `skills/codex-stop/SKILL.md`
- Site entry point: `site/index.html`
- Help content: `site/help/`
- Release checks: `site/TESTING.md`

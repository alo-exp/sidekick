# Documentation Scheme

> How Sidekick organizes current project documentation.

## Structure

Project documentation lives in three layers:

| Layer | Location | Lifespan | What goes here |
| --- | --- | --- | --- |
| Planning | `.planning/` | Per milestone | Specs, plans, reviews, and verification trail. |
| Project docs | `site/` | Durable | Architecture, testing, release process, help, decisions, knowledge, and internal audit material. |
| Public entry | `README.md` | Permanent | External overview and quick commands. |

## Repository Layout

| Group | Path | Purpose |
| --- | --- | --- |
| Plugin manifests | `.claude-plugin/`, `.codex-plugin/` | Runtime packaging and install metadata. |
| Runtime orchestration | `.claude/`, `.kay/`, `.codex/`, `hooks/`, `skills/`, `output-styles/`, `sidekicks/` | Sidekick behavior, enforcement, and user-facing entry points. |
| Documentation | `site/` | Durable product, test, process, help, and audit docs. |
| Planning | `.planning/` | Milestone and workflow artifacts. |
| Tests | `tests/` | Unit, integration, docs, release, and live-gated checks. |
| Root contracts | `README.md`, `AGENTS.md`, `CLAUDE.md`, `silver-bullet.md`, `context.md` | Human entry points and operating rules. |

## Reader-First Docs

| Doc | Purpose |
| --- | --- |
| `site/START-HERE.md` | Task-first navigation. |
| `site/AUDIENCE.md` | Reader matrix and entry points. |
| `site/GLOSSARY.md` | Canonical current terms. |
| `site/COMPATIBILITY.md` | Host and sidekick runtime mapping. |
| `site/ARCHITECTURE.md` | Current system model. |
| `site/TESTING.md` | Test strategy and release evidence. |
| `site/CICD.md` | CI, Pages deployment, and release flow. |
| `site/pre-release-quality-gate.md` | Manual pre-release gate. |

## Stable Subareas

- `site/index.html` and `site/help/` are the public docs surface.
- `site/internal/` holds reviews, audits, and release-gate references.
- `site/ADR/` holds durable architecture and documentation decisions.
- `site/workflows/` holds durable workflow documentation.
- `site/knowledge/` and `site/lessons/` hold project memory.
- `site/specs/` and `site/design/` preserve archived spec and design material.

## Doc Types

| Type | Primary locations | Question answered |
| --- | --- | --- |
| Tutorial | `site/help/getting-started/`, `site/START-HERE.md` | How do I begin? |
| Explanation | `site/help/concepts/`, `site/ARCHITECTURE.md` | Why is it built this way? |
| How-to | `site/help/workflows/`, `site/help/troubleshooting/` | How do I do or fix a task? |
| Reference | `site/help/reference/`, `site/GLOSSARY.md`, `site/COMPATIBILITY.md` | What does each term, command, or runtime difference mean? |

## Update Triggers

| Event | What updates |
| --- | --- |
| Sidekick support changes | `README.md`, `context.md`, `site/index.html`, `site/help/`, `site/ARCHITECTURE.md`, `site/COMPATIBILITY.md`, `site/GLOSSARY.md`, `site/TESTING.md`. |
| Skill text changes | Canonical `skills/`, generated host bundles, integrity hashes, and relevant help/reference docs. |
| Release flow changes | `site/TESTING.md`, `site/CICD.md`, `site/pre-release-quality-gate.md`. |
| Public site changes | Homepage, Help, preview source, and site contract tests. |

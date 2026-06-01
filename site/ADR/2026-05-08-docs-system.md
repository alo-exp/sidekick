# ADR 2026-05-08: Docs System Upgrade

Status: Accepted
Date: 2026-05-08

## Context

Sidekick's docs scheme kept the repository organized, but readers still needed a clearer path from role or task to the right document. The docs also needed a canonical glossary, compatibility matrix, and durable place for docs-system decisions.

## Decision

Keep `site/doc-scheme.md` as the placement contract, then add a reader-first layer:

- `site/START-HERE.md` for task-first navigation.
- `site/AUDIENCE.md` for reader roles and entry points.
- `site/GLOSSARY.md` for canonical terms.
- `site/COMPATIBILITY.md` for Claude Code, Codex, Kay, and Codex sidekick differences.
- `site/ADR/` for durable docs-system decisions.

The public Help section remains the task-oriented surface and links back to these docs.

## Consequences

- New readers have a single page that tells them where to begin.
- Canonical terms stop drifting across docs.
- Runtime differences are visible in one place.
- Important docs decisions have a stable home separate from knowledge notes and lessons.
- `doc-scheme.md` can stay short and structural.

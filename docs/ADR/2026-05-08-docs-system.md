# ADR 2026-05-08: Docs System Upgrade

Status: Accepted
**Date:** 2026-05-08

## Context

Sidekick's docs scheme already kept the repository organized, but it was still mostly a placement contract. It did not yet give readers a clear "where do I start?" path, a canonical glossary, a runtime compatibility matrix, or a dedicated home for durable docs decisions.

The docs system also needed a stronger way to signal the intent of each doc:

- tutorial
- explanation
- how-to
- reference

## Decision

We will keep `docs/doc-scheme.md` as the placement contract, then add a reader-first layer around it:

- `docs/START-HERE.md` for task-first navigation
- `docs/AUDIENCE.md` for reader roles and entry points
- `docs/GLOSSARY.md` for canonical terms
- `docs/COMPATIBILITY.md` for Claude Code / Codex host surfaces and Forge / Kay execution-agent differences
- `docs/ADR/` for durable docs-system decisions

We will also treat the public help site as the task map and wire it back to the new docs pages.

## Consequences

- New readers have a single page that tells them where to begin.
- Canonical terms stop drifting across docs.
- Runtime differences are visible in one place instead of being repeated ad hoc.
- Important docs-system decisions now have a stable home separate from knowledge notes and lessons.
- The docs system remains organized without turning `doc-scheme.md` into a giant policy dump.

# Documentation Improvement Recommendations

> Notes on what Sidekick's docs system still lacks if the goal is world-class documentation. This is not a bug list; it is a roadmap for making the docs easier to use, easier to maintain, and harder to let drift.

---

## Summary

`docs/doc-scheme.md` is strong on **placement policy**: it tells us where docs live, what is durable, and how to keep planning artifacts separate from published docs. What it still does not fully provide is a complete **documentation system**: who each doc is for, what question it answers, how it is verified, and who owns it over time.

Status note: this pass closes the non-governance items below by adding the reader model, glossary, compatibility matrix, ADR home, navigation layer, and docs verification contract.

The biggest remaining gaps are:

- no explicit audience model
- no formal content taxonomy beyond location
- no question-first navigation map
- no docs governance model
- no docs verification policy
- no glossary or canonical terminology
- no explicit runtime compatibility matrix

## What `doc-scheme.md` Does Well

- Keeps the repository shape clean and predictable
- Separates ephemeral planning from durable docs
- Preserves monthly knowledge and lessons as append-only memory
- Gives stable homes for help, internal, workflow, design, and specs content
- Prevents the docs tree from becoming an accidental junk drawer

## What Is Still Missing

### 1. Audience model

The docs do not yet say who they are for. World-class docs usually make the reader obvious:

- new user
- maintainer
- release operator
- plugin author
- Claude user
- Kay user
- Kay operator

Without this, the docs can be structurally correct but still feel indirect or muddy.

### 2. Content taxonomy

`doc-scheme.md` is location-first. It should also be purpose-first.

A stronger model would distinguish:

- tutorial
- how-to
- reference
- explanation

That would keep mixed-purpose pages from drifting into each other.

### 3. Question-first navigation

The current index is a gateway, but it is not yet a proper "if you want to do X, go here" map.

Good docs should answer:

- how do I install this?
- how do I delegate a task?
- how do I debug failures?
- how do I release?
- how do I extend the plugin?
- how do I migrate between runtimes?

### 4. Governance

The scheme tells us where docs go, but not:

- who owns each doc
- how often it is reviewed
- how stale content is retired
- how contradictions are resolved
- when a note becomes an ADR or a durable policy

### 5. Verification

The repo has layout checks and size caps, which is great, but docs quality needs more than placement enforcement.

Useful additions would be:

- link checks
- example-snippet checks
- command-surface drift checks
- runtime parity checks for Claude/Codex/Kay
- generated help-site sanity checks

### 6. Glossary and canonical terms

The docs need a formal glossary for stable vocabulary:

- Sidekick
- Forge
- Code / Kay
- host Codex
- delegate
- skill
- command
- bridge
- wrapper

That would reduce drift and make the docs easier to search and translate into future runtimes.

### 7. Runtime compatibility matrix

Because Sidekick now spans Claude and Codex, the docs should explicitly say:

- what is shared across runtimes
- what is runtime-specific
- what appears in slash-command pickers
- what is skill-only
- what is wrapper-only

This would make packaging behavior much easier to reason about.

### 8. Decision records

`docs/knowledge/` and `docs/lessons/` are good memory layers, but they are not a substitute for structured decisions.

A world-class docs system should have a clear home for:

- major architecture decisions
- packaging decisions
- compatibility decisions
- deprecations

That can live in `docs/ADR/` or a similar decision-log area.

## Priority Recommendations

### P0

- Add an explicit audience matrix
- Add a glossary for canonical terms
- Add a runtime compatibility matrix for Claude Code / Codex host surfaces and Forge / Kay execution agents

### P1

- Add question-first navigation pages for install, delegate, debug, release, and extend
- Add docs QA checks for links, examples, and runtime drift
- Add ownership and review cadence for durable docs

### P2

- Add ADR-style decision records for major packaging and architecture calls
- Add a style guide for tone, terminology, and accessibility
- Add deprecation / migration guidance for runtime changes

## Recommended Next Edits

If we want `doc-scheme.md` to move from "good organizing rule" to "world-class documentation contract," the next edits should be:

1. Add an audience section.
2. Add a doc-type taxonomy section.
3. Add a governance / review section.
4. Add a verification section.
5. Add a glossary and compatibility matrix entry somewhere discoverable from the gateway index.

Those changes would not replace the current scheme. They would make it much more complete.

---
phase: 03-agents-md-mentoring-and-token-optimization
plan: 01
subsystem: forge-mentoring
tags: [agents-md, mentoring-loop, deduplication, bootstrap]
dependency_graph:
  requires: []
  provides: [AGENTS.md-mentoring-protocol, project-agents-md, plugin-hash-update]
  affects: [skills/forge/SKILL.md, AGENTS.md, .claude-plugin/plugin.json]
tech_stack:
  added: []
  patterns: [three-tier-write, deduplication-algorithm, bootstrap-on-empty]
key_files:
  created:
    - AGENTS.md
  modified:
    - skills/forge/SKILL.md
    - .claude-plugin/plugin.json
decisions:
  - "AGENTS.md mentoring loop appended after line 169 of SKILL.md as a new section"
  - "Project AGENTS.md uses em-dashes instead of en-dashes to match forge.md conventions"
metrics:
  duration: 2m
  completed: 2026-04-13T05:43:27Z
  tasks_completed: 2
  tasks_total: 2
  files_changed: 3
---

# Phase 3 Plan 1: AGENTS.md Mentoring Loop Summary

AGENTS.md mentoring loop protocol with three-tier write (global ~/forge/AGENTS.md, project ./AGENTS.md, session log), two-phase deduplication (exact + semantic), and bootstrap behavior for empty projects.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Append AGENTS.md Mentoring Loop section to SKILL.md | 476899b | skills/forge/SKILL.md |
| 2 | Create project AGENTS.md template and update plugin hash | 5b92e96 | AGENTS.md, .claude-plugin/plugin.json |

## What Was Built

### Task 1: SKILL.md Extension (108 lines added)
Extended `skills/forge/SKILL.md` from 169 to 277 lines with the "AGENTS.md Mentoring Loop" section containing five subsections:
- **Post-Task Extraction:** Protocol for extracting corrections, user preferences, project patterns, and Forge behavior observations after every task
- **Deduplication Algorithm:** Two-phase check (exact substring match + semantic similarity) before every write
- **Three-Tier Write Protocol:** Global (`~/forge/AGENTS.md`), project (`./AGENTS.md`), and session log (`docs/sessions/YYYY-MM-DD-session.md`)
- **Bootstrap Behavior:** Auto-populate `./AGENTS.md` from `skills/forge.md` conventions on first `/forge` invocation
- **AGENTS.md Format:** Documented format specifications for both global and project tiers

### Task 2: Project AGENTS.md + Plugin Hash
- Created `./AGENTS.md` with bootstrap content: Project Conventions, Forge Output Format, Task Patterns, Forge Corrections sections
- Updated `forge_skill_md_sha256` in `.claude-plugin/plugin.json` to match the extended SKILL.md

## Verification

- All 43 tests pass (4 suites, 0 failures)
- All acceptance criteria met for both tasks
- Plugin hash matches actual SKILL.md SHA-256

## Deviations from Plan

None -- plan executed exactly as written.

## Known Stubs

None -- all sections contain actionable content. The "Forge Corrections" section in `./AGENTS.md` is intentionally empty (documented as "populated by mentoring loop after each task").

## Self-Check: PASSED

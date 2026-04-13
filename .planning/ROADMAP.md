# Roadmap: Sidekick — Forge Delegation Mode

## Overview

This roadmap delivers the `/forge` skill and its full supporting infrastructure across four phases. Phase 1 produces a detailed spec and the core skill with Forge configuration files before any implementation touches the running plugin. Phase 2 adds the fallback ladder and skill injection layer. Phase 3 adds the AGENTS.md mentoring loop and token optimization. Phase 4 closes with a test suite that covers all new behavior. The existing `install.sh`, `hooks/hooks.json`, and `skills/forge.md` are never modified.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Spec, Core Skill, and Forge Config** - Spec document + `/forge` SKILL.md + `.forge/` configuration files
- [ ] **Phase 2: Fallback Ladder and Skill Injection** - Guide → Handhold → Take over + selective SKILL.md injection
- [ ] **Phase 3: AGENTS.md Mentoring and Token Optimization** - Three-tier instruction accumulation + deduplication
- [ ] **Phase 4: Test Suite** - Full coverage for activation, fallback, injection, and mentoring loop

## Phase Details

### Phase 1: Spec, Core Skill, and Forge Config
**Goal**: A written spec locks down every interaction contract, and the `/forge` skill exists as a working SKILL.md that users can invoke to activate delegation mode, backed by Forge configuration files in place.
**Depends on**: Nothing (first phase)
**Requirements**: SKIL-01, SKIL-02, SKIL-03, SKIL-04, DLGT-01, DLGT-02, DLGT-03, DLGT-04, DLGT-05, FCFG-01, FCFG-02, FCFG-03, FCFG-04
**Success Criteria** (what must be TRUE):
  1. A spec document exists at `.planning/forge-delegation-spec.md` covering every interaction contract (activation, task prompt format, delegation loop, fallback triggers, skill injection protocol, AGENTS.md write protocol, token budget rules)
  2. User can invoke `/forge` and Claude activates Forge-first delegation mode for the session
  3. Invoking `/forge` on a machine without Forge installed produces a clear health-check error with install instructions rather than a silent failure
  4. User can deactivate Forge-first mode and Claude acknowledges the return to direct mode
  5. `.forge/agents/forge.md`, `.forge.toml`, and `.forge/skills/` exist after first invocation and are not overwritten on subsequent invocations
**Plans**: 3 plans

Plans:
- [ ] 01-01: Write forge-delegation-spec.md (interaction contracts, prompt format, fallback triggers, injection protocol, AGENTS.md write rules, token budget rules)
- [ ] 01-02: Implement `skills/forge/SKILL.md` — activation, health check, session state, deactivation, and task delegation loop (SKIL-01–04, DLGT-01–05)
- [ ] 01-03: Implement Forge configuration files — `.forge/agents/forge.md` override, `.forge.toml` template, `.forge/skills/` bootstrap (FCFG-01–04)

### Phase 2: Fallback Ladder and Skill Injection
**Goal**: When Forge fails, Claude escalates through a defined three-level ladder without user prompting, and before every delegation Claude injects only the skills relevant to the current task.
**Depends on**: Phase 1
**Requirements**: FALL-01, FALL-02, FALL-03, FALL-04, FALL-05, SINJ-01, SINJ-02, SINJ-03, SINJ-04, SINJ-05
**Success Criteria** (what must be TRUE):
  1. On a detectable Forge failure, Claude automatically reframes the prompt with clarifying context and retries without user intervention (Level 1 — Guide)
  2. If Level 1 retry fails, Claude decomposes the task and submits subtasks sequentially (Level 2 — Handhold)
  3. If Level 2 fails after reasonable attempts, Claude performs the task directly and produces a debrief including what Forge learned and a proposed AGENTS.md update (Level 3 — Take over)
  4. Failure detection triggers on: explicit Forge error signals, repeated wrong outputs, and stall conditions — not just on non-zero exit codes
  5. Before each delegation, only skills relevant to the task type are injected into `.forge/skills/` — injected files use Forge-compatible SKILL.md format with no Claude-specific syntax
**Plans**: 2 plans

Plans:
- [ ] 02-01: Implement fallback ladder logic in `skills/forge/SKILL.md` — failure detection, Level 1 Guide, Level 2 Handhold, Level 3 Take over + debrief (FALL-01–05)
- [ ] 02-02: Build skill injection layer — Claude-to-Forge skill mapping, selective injection, Forge-compatible SKILL.md adapter (SINJ-01–05)

### Phase 3: AGENTS.md Mentoring and Token Optimization
**Goal**: After every task, standing instructions flow into the right tier (global, project, session log) without duplication, and task prompts to Forge stay minimal.
**Depends on**: Phase 2
**Requirements**: AGNT-01, AGNT-02, AGNT-03, AGNT-04, AGNT-05, AGNT-06, AGNT-07, AGNT-08, TOKN-01, TOKN-02, TOKN-03, TOKN-04
**Success Criteria** (what must be TRUE):
  1. After each task, Claude appends extracted standing instructions to both `~/forge/AGENTS.md` and `./AGENTS.md` — and does not re-append content that is semantically equivalent to what already exists
  2. A session log entry is written to `docs/sessions/` capturing the instruction evolution for that session
  3. On first `/forge` invocation with an empty AGENTS.md, Claude bootstraps it from `skills/forge.md` content rather than starting blank
  4. Task prompts submitted to Forge contain only what Forge needs for the task — not full conversation history — and stay within the token budget defined in the spec
  5. `.forge.toml` compaction thresholds (`token_threshold`, `eviction_window`, `retention_window`) are set to tested defaults that prevent Forge context bloat
**Plans**: 2 plans

Plans:
- [ ] 03-01: Implement AGENTS.md mentoring loop — extraction protocol, deduplication logic, three-tier write (global, project, session log), bootstrap from forge.md (AGNT-01–08, TOKN-01)
- [ ] 03-02: Implement token optimization — minimal task prompt construction, selective injection enforcement, validated `.forge.toml` compaction defaults (TOKN-02–04)

### Phase 4: Test Suite
**Goal**: All new behavior is covered by automated tests that run alongside the existing 43-test suite without breaking it.
**Depends on**: Phase 3
**Requirements**: TEST-01, TEST-02, TEST-03, TEST-04, TEST-05
**Success Criteria** (what must be TRUE):
  1. Running the test suite shows tests for skill activation and deactivation passing (Unit — TEST-01)
  2. Running the test suite shows AGENTS.md deduplication tests passing — duplicate content is provably not re-appended (Unit — TEST-02)
  3. Running the test suite shows skill injection tests passing — correct SKILL.md files appear in the correct locations (Unit — TEST-03)
  4. Running the test suite shows fallback ladder tests passing — Level 1 → 2 → 3 triggers in the correct order under simulated failure conditions (Unit — TEST-04)
  5. Integration tests verify the full delegation loop against a live Forge session and the overall test suite remains at PASS (Integration — TEST-05)
**Plans**: 2 plans

Plans:
- [ ] 04-01: Unit tests for skill activation/deactivation, AGENTS.md deduplication, and skill injection (TEST-01–03)
- [ ] 04-02: Unit tests for fallback ladder trigger logic + integration test for full delegation loop against live Forge (TEST-04–05)

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Spec, Core Skill, and Forge Config | 0/3 | Not started | - |
| 2. Fallback Ladder and Skill Injection | 0/2 | Not started | - |
| 3. AGENTS.md Mentoring and Token Optimization | 0/2 | Not started | - |
| 4. Test Suite | 0/2 | Not started | - |

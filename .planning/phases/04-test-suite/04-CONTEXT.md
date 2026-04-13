# Phase 4 Context: Test Suite

**Phase:** 4 — Test Suite
**Created:** 2026-04-13
**Mode:** Autonomous (bypass-permissions detected)

---

## Domain

Write automated tests for all new behavior added in Phases 1–3. Tests must integrate with `tests/run_all.bash` (the existing test runner) and not break the 43 tests already passing.

---

## Decisions

### D-01: Test file locations and naming
**Decision:** Add new test files in `tests/`:
- `tests/test_forge_skill.bash` — Tests for activation/deactivation, session state, health check error path (TEST-01)
- `tests/test_agents_md_dedup.bash` — Tests for AGENTS.md deduplication logic (TEST-02)
- `tests/test_skill_injection.bash` — Tests for skill injection correctness (TEST-03)
- `tests/test_fallback_ladder.bash` — Tests for fallback ladder logic (TEST-04)
**Note:** TEST-05 (integration test against live Forge) is out of scope for automated tests — live Forge sessions are interactive and non-deterministic. TEST-05 is covered by the Phase 4 success criteria check that all previous UATs passed.

### D-02: Test style — follows existing test_install_sh.bash pattern
**Decision:** New tests follow the exact pattern of `tests/test_install_sh.bash`:
- `#!/usr/bin/env bash` + `set -euo pipefail`
- `PASS/FAIL` counters with `pass()` and `fail()` helper functions
- Print "Results: N passed, M failed" at end
- Exit 1 if any failures
- Test by grep/file-check/command-check (no complex mocking)

### D-03: What each suite tests
**Decision:**
- **test_forge_skill.bash:** Verify `skills/forge/SKILL.md` contains required sections/keywords:
  - Activation section present (YAML frontmatter, health check, marker file path)
  - Deactivation section present
  - Level 1/2/3 fallback sections present
  - AGENTS.md Mentoring Loop section present
  - Token Optimization section present
  - Skill Injection section present
  - plugin.json hash matches actual SKILL.md SHA-256

- **test_agents_md_dedup.bash:** Test deduplication logic in isolation:
  - Create a temp AGENTS.md with known content
  - Verify the dedup algorithm description is present in SKILL.md (the rules are documented, not code)
  - Verify AGENTS.md template at project root contains correct categories
  - Verify `docs/sessions/` directory exists

- **test_skill_injection.bash:** Verify skill injection infrastructure:
  - All 4 bootstrap skills exist at `.forge/skills/<name>/SKILL.md`
  - Each has valid YAML frontmatter with `trigger` field
  - None contain Claude-specific tool names (Skill tool, AskUserQuestion, Read/Edit/Write as tool names)
  - Mapping table present in `skills/forge/SKILL.md`

- **test_fallback_ladder.bash:** Verify fallback ladder structure:
  - Level 1 section contains "Guide", single retry rule
  - Level 2 section contains "Handhold", subtask decomposition, 3-attempt limit
  - Level 3 section contains "Take over", DEBRIEF template, DLGT-04 lifted mention
  - Failure Detection section covers all 3 signal types

### D-04: Integration with run_all.bash
**Decision:** Add all 4 new suites to `tests/run_all.bash` by appending `run_suite` calls. The existing 4 suites stay unchanged. New suites append after the existing ones.

### D-05: TEST-05 (Integration test against live Forge) — scoped
**Decision:** TEST-05 requires a live interactive Forge session. The existing `test_forge_e2e.bash` already tests live Forge invocation (14 tests). Phase 4 TEST-05 is satisfied by:
1. The existing e2e suite running successfully
2. The new skill structure tests passing
No new live-Forge test is needed.

---

## Canonical Refs

- `tests/test_install_sh.bash` — Pattern to follow for new test files
- `tests/run_all.bash` — Must be updated to include new suites
- `skills/forge/SKILL.md` (321 lines) — The file being tested
- `.forge/skills/` — Bootstrap skills being tested
- `AGENTS.md` — Project template being tested
- `docs/sessions/` — Session log directory being tested

---

## Existing Infrastructure (DO NOT IGNORE)

- **43 tests in 4 suites** — Must remain passing after Phase 4 adds new tests
- **`tests/run_all.bash`** — Orchestrates all suites; must be updated to include new ones
- **`tests/test_install_sh.bash`** — Pattern to follow (PASS/FAIL counters, grep-based assertions)
- **No mocking framework** — Tests use file checks, grep, and Bash conditionals
- **`skills/forge.md`** — NEVER MODIFIED

---

## Deferred Ideas

- TEST-05 live Forge integration (already covered by existing e2e suite)
- Performance benchmarks for AGENTS.md deduplication
- Mutation testing for fallback ladder triggers

# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

---

## Milestone: v1.4.0 — Command-Surface Cleanup & Security Hardening

**Shipped:** 2026-04-25
**Phases:** 0 (direct release — no formal GSD phases) | **Plans:** 0 | **Sessions:** 1

### What Was Built
- `forge-delegate` skill rename (dash naming convention alignment)
- `/forge-stop` dedicated deactivation command (discoverable, testable replacement for inline procedure)
- Removed `/forge-replay` (dead command; underlying Forge API gone)
- `/forge-history` normalization across 9 files (colon → dash form)
- `install.sh` security hardening: removed `curl | bash` from secondary domain, added `chmod 600` on credentials

### What Worked
- **Direct release pattern** — housekeeping changes with clear scope don't need full GSD phase overhead. A single session handled all changes, 2 clean quality gate rounds, and GitHub release.
- **4-stage pre-release quality gate** caught real issues in Round 1 (11 items including 2 SENTINEL security blockers). Round 2 was clean, Round 3 confirmed.
- **SENTINEL audit** surfaced the `curl | bash` and `chmod 600` issues which were genuine security blockers — not false alarms.
- **silver-release workflow** orchestrated the full release chain (quality gates → docs → milestone summary → GitHub release → milestone archival) reliably.

### What Was Inefficient
- **WORKFLOW.md row ID format**: Silver Bullet's `completion-audit.sh` requires pure numeric row IDs (`^\| [0-9]+ \|`) but alphanumeric IDs (0b, 2a, 3a) were used initially, causing a "7/4 flows done" mismatch that blocked `gh release create`. Required a fix commit and investigation time.
- **UAT gate surprise**: `gsd-complete-milestone` was blocked by a missing `.planning/UAT.md` — this wasn't part of the documented release checklist. Had to create UAT.md mid-flow.
- **Quality gate state file**: `validate-release-gate.sh` uses `~/.claude/.sidekick/quality-gate-state` (different path from Silver Bullet's state) — undocumented, required hook source inspection.
- **silver:security skill missing**: silver-release Step 2a calls `silver:security` which doesn't exist in this setup. Worked around by using Stage 4 SENTINEL results.

### Patterns Established
- **WORKFLOW.md Flow Log rows must use pure numeric IDs** — Silver Bullet completion-audit.sh counts rows with `^\| [0-9]+ \|`; alphanumeric IDs (0a, 2b) are not counted in the total, causing false "incomplete" errors.
- **UAT.md is required before gsd-complete-milestone** — even for direct releases. Create it from actual verification evidence.
- **Quality gate state markers go in `~/.claude/.sidekick/quality-gate-state`** (not `~/.claude/.silver-bullet/state`) — Sidekick's own hook, separate from Silver Bullet.
- **Housekeeping releases are a valid pattern** — short-cycle cleanup without formal phases. The 4-stage quality gate is still the right guard.

### Key Lessons
1. **Check hook assumptions before release** — `completion-audit.sh` and `validate-release-gate.sh` have undocumented requirements (numeric row IDs, state file format) that block `gh release create`. Know these before the release attempt.
2. **WORKFLOW.md is the orchestration contract** — keep row IDs strictly numeric; the completion audit is regex-based, not semantic.
3. **Direct releases still need UAT.md** — create it from the quality gate evidence. It doesn't need to come from formal acceptance criteria.
4. **silver:security is not universally installed** — the silver-release workflow assumes it exists; confirm skill availability before running release workflows.

### Cost Observations
- Model mix: Sonnet (primary — quality gates, hooks inspection, workflow execution)
- Sessions: 2 (context compaction between quality gate work and release)
- Notable: The 4-stage quality gate ran twice across 2 sessions with full round-trip. WORKFLOW.md fix and UAT.md creation added ~1 investigation cycle.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Pattern | Quality Gate | Notable |
|-----------|--------|---------|--------------|---------|
| v1.1 | 1–5 | Standard GSD phases | Pre-release gate | Foundation — forge skill, fallback, mentoring |
| v1.2 | 6–9 | Standard GSD phases | Pre-release gate + SENTINEL | Harness enforcement, live visibility |
| v1.3 | 10–11 | Standard GSD phases | Pre-release gate + SENTINEL ×2 | Security hardening, 32 reqs |
| v1.4 | None | Direct release | Pre-release gate 2 clean rounds + SENTINEL ×2 | Housekeeping — 1 session |

### Recurring Issues
- SENTINEL findings appear in every milestone — security review is non-negotiable pre-release
- Quality gate Round 1 always finds issues; Round 2 is typically clean

### Velocity Trend
- v1.1: 4 phases, ~4 days
- v1.2: 4 phases, 1 day
- v1.3: 2 phases, 1 day  
- v1.4: Direct, 1 session

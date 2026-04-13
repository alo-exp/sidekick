# Sidekick — Project Context

## What This Is

Sidekick is a Claude Code plugin that installs ForgeCode (`forge`) and exposes a `/forge` skill that activates **Forge-first delegation mode** — Claude becomes a thin orchestrator and user-facing agent while Forge performs 100% of actual implementation work. Claude monitors Forge, guides it on failures, and acts as last-resort fallback only when Forge cannot succeed after active intervention.

## Core Value

When `/forge` is active, every implementation task goes to Forge. Claude never writes code, edits files, or runs commands itself — it plans, delegates, monitors, mentors, and communicates. Token efficiency and instruction accumulation (via AGENTS.md evolution) are first-class concerns.

## Context

- **Repo**: https://github.com/alo-exp/sidekick.git
- **Stack**: Shell / Bash + Markdown (Claude Code plugin)
- **ForgeCode target**: Latest version (no backward compatibility — targets current Forge API surface)
- **Forge interaction model**: Interactive ZSH shell harness; no headless CLI flags. Delegation happens by Claude composing and submitting prompts into the Forge session.
- **Plugin currently ships**: `install.sh` (binary installer), `hooks/hooks.json` (SessionStart), `skills/forge.md` (existing orchestration skill, 862 lines), test suite (43 tests, PASS)

## What We Are Building

A new **`/forge` skill** (`skills/forge/SKILL.md`) and supporting infrastructure that implements:

1. **Forge-first delegation mode**: When invoked, all subsequent work is delegated to Forge via structured prompts. Claude composes the task, submits it, monitors output, and manages the outcome.

2. **Skill injection layer**: Claude adapts relevant Claude skills into Forge-consumable format (SKILL.md files placed in `.forge/skills/` or `~/forge/skills/`) so Forge self-applies them without Claude back-and-forth.

3. **AGENTS.md mentoring loop**: After each task, Claude extracts standing instructions from what was learned (corrections, patterns, user preferences, project conventions) and appends them to:
   - `~/forge/AGENTS.md` — global standing instructions (cross-project, cross-session)
   - `./AGENTS.md` (git root) — project-specific standing instructions
   - Session log entry in `docs/sessions/` — per-session evolution record

4. **Fallback ladder**: Guide → Handhold → Take over
   - Level 1 (Guide): Reframe the prompt, add clarifying context, retry
   - Level 2 (Handhold): Decompose into subtasks, submit sequentially with tighter scoping
   - Level 3 (Take over): Claude performs the task directly, then debriefs Forge with what it learned

5. **Token optimization**: Keep global/project AGENTS.md compact and deduplicated. Claude deduplicates before every write. Selective skill injection — only inject skills relevant to the current task.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| New phase in Sidekick (not separate plugin) | Feature extends existing install/skill infrastructure | Add to sidekick-repo |
| Spec first | Complex interaction model — spec before implementation prevents costly rewrites | Produce detailed spec before any code |
| Research ForgeCode docs before deciding skill delivery | Forge interaction model is non-obvious | Done: Forge uses SKILL.md files + AGENTS.md injection; no headless CLI |
| Target latest Forge only | No backward compatibility needed | Targets current Forge API surface; no version guards |
| AGENTS.md as primary token lever | Compact persistent instructions > pruning task prompts | Deduplicated AGENTS.md is the main token reduction strategy |
| Global + project AGENTS.md + session log | Three-tier instruction accumulation matches Forge's own priority hierarchy | All three tiers implemented |
| Guide → Handhold → Take over fallback | Balance autonomy with reliability | Three-level ladder, each level explicit |
| Version-agnostic spec | Targets behaviors, not CLI flags that may change | Implementation adapts to installed Forge version |

## Requirements

### Validated

- ✓ ForgeCode 2.9.9 installable and operational — existing `install.sh`
- ✓ Claude can invoke `forge` binary — existing `skills/forge.md`
- ✓ Plugin hooks (SessionStart) working — existing `hooks/hooks.json`

### Active

- [ ] `/forge` skill that activates Forge-first delegation mode for the session
- [ ] Claude composes structured task prompts and submits to Forge
- [ ] Claude monitors Forge output and detects success/failure signals
- [ ] Fallback ladder: Guide → Handhold → Take over
- [ ] Skill injection: adapt Claude skills to SKILL.md format in `.forge/skills/`
- [ ] AGENTS.md mentoring loop: extract and append standing instructions after each task
- [ ] Global AGENTS.md (`~/forge/AGENTS.md`) — cross-project/session instructions
- [ ] Project AGENTS.md (`./AGENTS.md`) — project-specific instructions
- [ ] Session log entries in `docs/sessions/` — per-session evolution record
- [ ] Deduplication before every AGENTS.md write (token minimization)
- [ ] Selective skill injection — only skills relevant to current task
- [ ] Forge agent override files (`.forge/agents/forge.md`) with project-specific system prompts
- [ ] Context compaction guidance in `.forge.toml` configuration template
- [ ] Test coverage for new skill and AGENTS.md evolution logic

### Out of Scope

- Headless/non-interactive Forge invocation — Forge has no documented headless CLI mode
- Backward compatibility with Forge versions older than current latest — not required
- Automated session-end AGENTS.md extraction (no Forge built-in) — Claude drives this manually at task completion
- Replacing existing `skills/forge.md` — new `/forge` skill extends it, doesn't replace it

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-13 after initialization*

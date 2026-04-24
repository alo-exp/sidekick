# Sidekick — Project Context

## What This Is

Sidekick is a Claude Code plugin that installs ForgeCode (`forge`) and exposes a `/forge` skill that activates **Forge-first delegation mode** — Claude becomes a thin orchestrator and user-facing agent while Forge performs 100% of actual implementation work. Claude monitors Forge, guides it on failures, and acts as last-resort fallback only when Forge cannot succeed after active intervention.

As of milestone v1.2, delegation is **harness-enforced** via PreToolUse hooks (not just skill-suggested), and Forge's subprocess output is **live-streamed** into the Claude Code transcript with visual distinction, plus a durable audit trail (`forge conversation`-backed) for replay.

## Core Value

When `/forge` is active, every implementation task goes to Forge. Claude never writes code, edits files, or runs commands itself — it plans, delegates, monitors, mentors, and communicates. Token efficiency and instruction accumulation (via AGENTS.md evolution) are first-class concerns. **Forge is the execution engine; Claude is the process orchestrator** — Claude's direct tool use is reserved for Brain-role work (planning, inspection, verification, GSD/Silver Bullet workflow maintenance).

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

## Previous Milestone: v1.2 — Forge Delegation + Live Visibility

**Status:** SHIPPED 2026-04-18 (v1.2.0), patched to v1.2.1 and v1.2.2 on 2026-04-18/24. GitHub Release: https://github.com/alo-exp/sidekick/releases/tag/v1.2.0
**Plugin version:** `sidekick` v1.2.2

**Goals shipped:**

1. Harness-enforced delegation via PreToolUse hook; `Write`/`Edit`/`NotebookEdit` hard-denied; `forge -p` commands rewritten to inject `--conversation-id` + `--verbose`.
2. Live Forge output streaming via `run_in_background: true` + Monitor, visually distinct.
3. Durable audit trail per task in `.forge/conversations.idx` + `~/forge/.forge.db`, replayable as HTML.
4. Output style `output-styles/forge.md` for `[FORGE]` / `[FORGE-LOG]` / `[FORGE-SUMMARY]` lines.
5. `/forge:replay` and `/forge:history` slash commands.
6. v1.2.2 defense-in-depth: anchored env-prefix substitution, UUID validation, secret redaction in transcript surface.

## Current Milestone: v1.3 — Enforcer Hardening + Housekeeping + forge-sb

**Goal:** Fix all 6 enforcer security bugs, codify the doc-edit path allowlist, extract helpers, address 9 remaining GitHub housekeeping/hardening items (credential redaction, SRI integrity, SKILL.md improvements, help site bugs, install.sh fix, SENTINEL relocation), add forge-sb auto-install, and release v1.3.0.

**Target features:**

**Phase 10 — Enforcer Hardening:**
- Fix `has_write_redirect` false-positives on `>` inside generics, quoted strings, fd-redirects — Bug #1 (Issue #3)
- Fix `FORGE_LEVEL_3=1` command-prefix bypass silently failing — Bug #2 (Issue #3)
- Add `gh` (GitHub CLI) to allowlist — Bug #3 (Issue #3)
- Fix `cd /path && mutating_cmd` chain bypass security hole — Bug #4 (Issue #3)
- Fix MCP filesystem tools bypassing enforcer — Bug #5 (Issue #3)
- Fix pipe-chain first-token-only classification — Bug #6 (Issue #8)
- Codify doc-edit carve-out as path-based allowlist for `.planning/**` and `docs/**` — Issue #2
- Extract helpers to `hooks/lib/enforcer-utils.sh` — Issue #9
- Full test suite + manifest bump to v1.3.0

**Phase 11 — Housekeeping, Hardening & forge-sb:**
- Fix `strip_ansi` multi-line OSC sequences (slurp mode) — Issue #6
- Improve `sk-` token redaction regex (dots/plus/slash, min-length 10) — Issue #7
- Add SRI integrity attributes to Lucide CDN script tags in all 6 help pages — Issue #10
- Clarify SKILL.md L3 scope constraint to reference `$CLAUDE_PROJECT_DIR` — Issue #12
- Fix SKILL.md security boundary ordering + add bootstrap skill governance — Issue #13
- Add missing token redaction tests (`ghs_`, `api-key:`) — Issue #14
- Fix help site: favicon, `search.js` null guard, concepts injection table — Issue #15
- Fix `install.sh` hardcoded `/tmp` to use `${TMPDIR:-/tmp}` — Issue #16
- Move 14 SENTINEL audit files from repo root to `docs/internal/sentinel/` — Issue #17
- Auto-install `forge-sb` skill from Silver Bullet on plugin install

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
| v1.2: Harness-level enforcement (PreToolUse hook) vs. skill-only | Skill suggests; hook enforces deterministically at zero latency, ruling out subagent/MCP alternatives | Delegation becomes unbypassable when `/forge` is active |
| v1.2: Live-stream via `run_in_background` + Monitor | Users need to see Forge work in real time, not a post-hoc summary | Output style with `[FORGE]` line prefixes, rendered distinctly |
| v1.2: Leverage `forge conversation` natively | Don't rebuild storage, snapshots, stats — Forge already has them | Sidekick injects UUIDs and maintains `.forge/conversations.idx` only |
| v1.2: Conversation-id must be UUID | Forge 2.11.3 rejects non-UUID custom formats | Hook generates UUID; human-readable tag stored separately in idx |

## Requirements

### Validated

- ✓ ForgeCode 2.9.9 installable and operational — existing `install.sh`
- ✓ Claude can invoke `forge` binary — existing `skills/forge.md`
- ✓ Plugin hooks (SessionStart) working — existing `hooks/hooks.json`
- ✓ `/forge` skill that activates Forge-first delegation mode for the session — Phase 1 (v1.1.0)
- ✓ Claude composes structured task prompts and submits to Forge — Phase 1 (v1.1.0)
- ✓ Claude monitors Forge output and detects success/failure signals — Phase 1 (v1.1.0)
- ✓ Fallback ladder: Guide → Handhold → Take over — Phase 2 (v1.1.0)
- ✓ Skill injection: adapt Claude skills to SKILL.md format in `.forge/skills/` — Phase 2 (v1.1.0)
- ✓ AGENTS.md mentoring loop: extract and append standing instructions after each task — Phase 3 (v1.1.0)
- ✓ Global AGENTS.md (`~/forge/AGENTS.md`) — cross-project/session instructions — Phase 3 (v1.1.0)
- ✓ Project AGENTS.md (`./AGENTS.md`) — project-specific instructions — Phase 3 (v1.1.0)
- ✓ Session log entries in `docs/sessions/` — per-session evolution record — Phase 3 (v1.1.0)
- ✓ Deduplication before every AGENTS.md write (token minimization) — Phase 3 (v1.1.0)
- ✓ Selective skill injection — only skills relevant to current task — Phase 2 (v1.1.0)
- ✓ Forge agent override files (`.forge/agents/forge.md`) with project-specific system prompts — Phase 1 (v1.1.0); corrected in Phase 5 (v1.1.2) to include `tools: ["*"]`
- ✓ Context compaction guidance in `.forge.toml` configuration template — Phase 3 (v1.1.0)
- ✓ Test coverage for new skill and AGENTS.md evolution logic — Phase 4 (v1.1.0)

### Active

**Phase 10 — Enforcer Hardening:**
- Enforcer bug fixes (6 bugs: Issues #3 + #8) — ENF-01–08
- Doc-edit carve-out path allowlist (`.planning/**`, `docs/**`) — PATH-01–03
- Helper extraction to `hooks/lib/enforcer-utils.sh` — REFACT-01–04
- Test suite + manifest bump to v1.3.0 — TEST-V13-01–04, MAN-V13-01–03

**Phase 11 — Housekeeping, Hardening & forge-sb:**
- `strip_ansi` slurp-mode fix (Issue #6) — STRIP-01
- `sk-` token redaction regex improvement (Issue #7) — RDRCT-01
- SRI integrity for Lucide CDN in all 6 help pages (Issue #10) — SRI-01
- SKILL.md L3 scope constraint + security boundary fixes (Issues #12, #13) — SKILL-01, SKILL-02
- Token redaction test gaps `ghs_` and `api-key:` (Issue #14) — TEST-RDRCT-01
- Help site: favicon, null guard, injection table (Issue #15) — DOCS-01
- `install.sh` `$TMPDIR` fix (Issue #16) — INST-01
- Move 14 SENTINEL files to `docs/internal/sentinel/` (Issue #17) — HOUSE-01
- `forge-sb` auto-install on plugin install — FGSB-01

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
*Last updated: 2026-04-24 — Milestone v1.3 started; Phases 1-9 shipped (v1.1.0 → v1.2.2); all 77 v1/v1.2 requirements validated*

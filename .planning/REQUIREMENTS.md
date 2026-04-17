# Requirements: Sidekick — Forge Delegation Mode

**Defined:** 2026-04-13
**Core Value:** When `/forge` is active, Claude is a thin orchestrator and Forge does 100% of implementation — with Claude mentoring Forge via AGENTS.md accumulation and acting as fallback only when Forge truly cannot succeed.

## v1 Requirements

### Skill Activation

- [x] **SKIL-01**: User can invoke `/forge` skill to activate Forge-first delegation mode for the session
- [x] **SKIL-02**: Skill detects whether Forge is installed and operational before activating (health check)
- [x] **SKIL-03**: Skill sets session state so all subsequent tasks route to Forge by default
- [x] **SKIL-04**: User can deactivate Forge-first mode and return to Claude-direct mode

### Task Delegation

- [x] **DLGT-01**: Claude composes a structured, concrete task prompt for Forge before every delegation
- [x] **DLGT-02**: Task prompt includes: objective, file context, desired state, success criteria, and any relevant skill content
- [x] **DLGT-03**: Claude submits the task to Forge and monitors its output for completion or failure signals
- [x] **DLGT-04**: Claude never directly writes files, edits code, or runs shell commands while Forge-first mode is active (except as fallback Level 3)
- [x] **DLGT-05**: Claude communicates progress and outcomes to the user in plain language throughout

### Fallback Ladder

- [x] **FALL-01**: Level 1 (Guide) — on Forge failure, Claude reframes the prompt with clarifying context and retries
- [x] **FALL-02**: Level 2 (Handhold) — if Level 1 fails, Claude decomposes the task into subtasks and submits sequentially with tighter scoping
- [x] **FALL-03**: Level 3 (Take over) — if Level 2 fails after reasonable attempts, Claude performs the task directly
- [x] **FALL-04**: After any Level 3 takeover, Claude produces a debrief: what the task was, why Forge failed, what it learned, and what AGENTS.md update to apply
- [x] **FALL-05**: Failure detection uses output analysis — Forge error signals, repeated wrong outputs, explicit failure messages, or timeout-equivalent stalls

### Skill Injection

- [x] **SINJ-01**: Claude maintains a mapping of Claude skills to Forge-compatible SKILL.md equivalents
- [x] **SINJ-02**: Before delegating a task, Claude identifies which skills are relevant and injects them into `.forge/skills/` or `~/forge/skills/`
- [x] **SINJ-03**: Injected SKILL.md files are adapted for Forge's execution model (no Skill tool references, no Claude-specific syntax)
- [x] **SINJ-04**: Forge auto-detects and applies injected skills without Claude back-and-forth (relies on Forge's Skill Engine auto-detection)
- [x] **SINJ-05**: Selective injection — only skills relevant to the current task type are injected (not all Claude skills)

### AGENTS.md Mentoring Loop

- [x] **AGNT-01**: After each task, Claude extracts standing instructions from what was learned (corrections, user preferences, project patterns, Forge behavior)
- [x] **AGNT-02**: Extracted instructions are appended to `~/forge/AGENTS.md` (global — cross-project, cross-session)
- [x] **AGNT-03**: Extracted instructions are appended to `./AGENTS.md` (project root — project-specific)
- [x] **AGNT-04**: Before every AGENTS.md write, Claude deduplicates: no instruction is written if semantically equivalent content already exists
- [x] **AGNT-05**: A session log entry is written to `docs/sessions/` capturing the instruction evolution for that session
- [x] **AGNT-06**: Global AGENTS.md follows Forge's recommended format: action-oriented, specific, organized by category
- [x] **AGNT-07**: Project AGENTS.md includes: project structure conventions, task patterns, Forge behavior corrections specific to this codebase
- [x] **AGNT-08**: Claude can bootstrap AGENTS.md from existing `skills/forge.md` content on first invocation if AGENTS.md is empty

### Forge Agent Configuration

- [x] **FCFG-01**: Plugin installs a project-level `.forge/agents/forge.md` override that injects Sidekick-specific system prompt into Forge's default agent
- [x] **FCFG-02**: `.forge.toml` configuration template is provided with recommended context compaction settings (`token_threshold`, `eviction_window`, `retention_window`)
- [x] **FCFG-03**: `.forge/skills/` directory is created and populated with initial skill set on first `/forge` invocation
- [x] **FCFG-04**: Agent override file is not overwritten on subsequent invocations (preserves user customizations)

### Token Optimization

- [x] **TOKN-01**: AGENTS.md deduplication runs before every write — no redundant instructions accumulate
- [x] **TOKN-02**: Claude keeps task prompts to Forge minimal — only what Forge needs to know, not the full conversation history
- [x] **TOKN-03**: Skill injection is selective — inject only the skills relevant to the task type being delegated
- [x] **TOKN-04**: `.forge.toml` compaction thresholds are set to reasonable defaults to prevent Forge context bloat

### Testing

- [x] **TEST-01**: Unit tests verify `/forge` skill activates and deactivates correctly
- [x] **TEST-02**: Tests verify AGENTS.md deduplication logic (duplicate content is not re-appended)
- [x] **TEST-03**: Tests verify skill injection creates correct SKILL.md files in the right locations
- [x] **TEST-04**: Tests verify fallback ladder logic (Level 1 → 2 → 3 triggers correctly)
- [x] **TEST-05**: Integration tests verify the full delegation loop against a live Forge session

## v2 Requirements

### Advanced Mentoring

- **MENT-01**: Claude proposes AGENTS.md additions proactively (not just after failures — also after successes where a pattern is detected)
- **MENT-02**: Periodic AGENTS.md audit — Claude reviews accumulated instructions for contradictions, redundancies, or outdated rules
- **MENT-03**: User can invoke `/forge:review-agents` to trigger a full AGENTS.md audit and cleanup

### Multi-Agent Forge Workflows

- **MAGT-01**: Claude routes planning tasks to Forge's `:muse` agent and implementation tasks to `:forge` agent
- **MAGT-02**: Claude orchestrates multi-step Forge workflows across agent switches (muse → forge → verify)

### Context Engine Integration

- **CENG-01**: Claude triggers `forge :sync` to index the project before large delegation tasks (leverages Forge's Context Engine for semantic positioning)
- **CENG-02**: Claude maintains a `.ignore` file to exclude non-essential files from Forge's context

## Out of Scope

| Feature | Reason |
|---------|--------|
| Headless/non-interactive Forge invocation | Forge has no documented headless CLI mode; interaction is ZSH-interactive only |
| Backward compatibility with old Forge versions | Targeting latest version only, no version guards |
| Automatic session-end AGENTS.md extraction | No Forge built-in for this; Claude drives it explicitly at task completion |
| Replacing existing `skills/forge.md` | New `/forge` skill extends it, doesn't replace it |
| Forge MCP server management | Out of scope for this phase; user manages MCP separately |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SKIL-01 – SKIL-04 | Phase 1 | Validated (v1.1.0) |
| DLGT-01 – DLGT-05 | Phase 1 | Validated (v1.1.0) |
| FALL-01 – FALL-05 | Phase 2 | Validated (v1.1.0) |
| SINJ-01 – SINJ-05 | Phase 2 | Validated (v1.1.0) |
| AGNT-01 – AGNT-08 | Phase 3 | Validated (v1.1.0) |
| FCFG-01 – FCFG-04 | Phase 1 | Validated (v1.1.0); FCFG-01, FCFG-02 re-validated in Phase 5 (v1.1.2) |
| TOKN-01 – TOKN-04 | Phase 3 | Validated (v1.1.0) |
| TEST-01 – TEST-05 | Phase 4 | Validated (v1.1.0) |

**Coverage:**
- v1 requirements: 34 total
- Mapped to phases: 34
- Unmapped: 0 ✓

---
*Requirements defined: 2026-04-13*
*Last updated: 2026-04-18 — all 34 v1 requirements validated via v1.1.0 (2026-04-13) + v1.1.2 patch (2026-04-17)*

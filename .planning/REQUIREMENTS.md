# Requirements: Sidekick — Forge Delegation Mode

**Defined:** 2026-04-13
**Core Value:** When `/forge` is active, Claude is a thin orchestrator and Forge does 100% of implementation — with Claude mentoring Forge via AGENTS.md accumulation and acting as fallback only when Forge truly cannot succeed.

## v1 Requirements

### Skill Activation

- [ ] **SKIL-01**: User can invoke `/forge` skill to activate Forge-first delegation mode for the session
- [ ] **SKIL-02**: Skill detects whether Forge is installed and operational before activating (health check)
- [ ] **SKIL-03**: Skill sets session state so all subsequent tasks route to Forge by default
- [ ] **SKIL-04**: User can deactivate Forge-first mode and return to Claude-direct mode

### Task Delegation

- [ ] **DLGT-01**: Claude composes a structured, concrete task prompt for Forge before every delegation
- [ ] **DLGT-02**: Task prompt includes: objective, file context, desired state, success criteria, and any relevant skill content
- [ ] **DLGT-03**: Claude submits the task to Forge and monitors its output for completion or failure signals
- [ ] **DLGT-04**: Claude never directly writes files, edits code, or runs shell commands while Forge-first mode is active (except as fallback Level 3)
- [ ] **DLGT-05**: Claude communicates progress and outcomes to the user in plain language throughout

### Fallback Ladder

- [ ] **FALL-01**: Level 1 (Guide) — on Forge failure, Claude reframes the prompt with clarifying context and retries
- [ ] **FALL-02**: Level 2 (Handhold) — if Level 1 fails, Claude decomposes the task into subtasks and submits sequentially with tighter scoping
- [ ] **FALL-03**: Level 3 (Take over) — if Level 2 fails after reasonable attempts, Claude performs the task directly
- [ ] **FALL-04**: After any Level 3 takeover, Claude produces a debrief: what the task was, why Forge failed, what it learned, and what AGENTS.md update to apply
- [ ] **FALL-05**: Failure detection uses output analysis — Forge error signals, repeated wrong outputs, explicit failure messages, or timeout-equivalent stalls

### Skill Injection

- [ ] **SINJ-01**: Claude maintains a mapping of Claude skills to Forge-compatible SKILL.md equivalents
- [ ] **SINJ-02**: Before delegating a task, Claude identifies which skills are relevant and injects them into `.forge/skills/` or `~/forge/skills/`
- [ ] **SINJ-03**: Injected SKILL.md files are adapted for Forge's execution model (no Skill tool references, no Claude-specific syntax)
- [ ] **SINJ-04**: Forge auto-detects and applies injected skills without Claude back-and-forth (relies on Forge's Skill Engine auto-detection)
- [ ] **SINJ-05**: Selective injection — only skills relevant to the current task type are injected (not all Claude skills)

### AGENTS.md Mentoring Loop

- [ ] **AGNT-01**: After each task, Claude extracts standing instructions from what was learned (corrections, user preferences, project patterns, Forge behavior)
- [ ] **AGNT-02**: Extracted instructions are appended to `~/forge/AGENTS.md` (global — cross-project, cross-session)
- [ ] **AGNT-03**: Extracted instructions are appended to `./AGENTS.md` (project root — project-specific)
- [ ] **AGNT-04**: Before every AGENTS.md write, Claude deduplicates: no instruction is written if semantically equivalent content already exists
- [ ] **AGNT-05**: A session log entry is written to `docs/sessions/` capturing the instruction evolution for that session
- [ ] **AGNT-06**: Global AGENTS.md follows Forge's recommended format: action-oriented, specific, organized by category
- [ ] **AGNT-07**: Project AGENTS.md includes: project structure conventions, task patterns, Forge behavior corrections specific to this codebase
- [ ] **AGNT-08**: Claude can bootstrap AGENTS.md from existing `skills/forge.md` content on first invocation if AGENTS.md is empty

### Forge Agent Configuration

- [ ] **FCFG-01**: Plugin installs a project-level `.forge/agents/forge.md` override that injects Sidekick-specific system prompt into Forge's default agent
- [ ] **FCFG-02**: `.forge.toml` configuration template is provided with recommended context compaction settings (`token_threshold`, `eviction_window`, `retention_window`)
- [ ] **FCFG-03**: `.forge/skills/` directory is created and populated with initial skill set on first `/forge` invocation
- [ ] **FCFG-04**: Agent override file is not overwritten on subsequent invocations (preserves user customizations)

### Token Optimization

- [ ] **TOKN-01**: AGENTS.md deduplication runs before every write — no redundant instructions accumulate
- [ ] **TOKN-02**: Claude keeps task prompts to Forge minimal — only what Forge needs to know, not the full conversation history
- [ ] **TOKN-03**: Skill injection is selective — inject only the skills relevant to the task type being delegated
- [ ] **TOKN-04**: `.forge.toml` compaction thresholds are set to reasonable defaults to prevent Forge context bloat

### Testing

- [ ] **TEST-01**: Unit tests verify `/forge` skill activates and deactivates correctly
- [ ] **TEST-02**: Tests verify AGENTS.md deduplication logic (duplicate content is not re-appended)
- [ ] **TEST-03**: Tests verify skill injection creates correct SKILL.md files in the right locations
- [ ] **TEST-04**: Tests verify fallback ladder logic (Level 1 → 2 → 3 triggers correctly)
- [ ] **TEST-05**: Integration tests verify the full delegation loop against a live Forge session

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
| SKIL-01 – SKIL-04 | Phase 1 | Pending |
| DLGT-01 – DLGT-05 | Phase 1 | Pending |
| FALL-01 – FALL-05 | Phase 2 | Pending |
| SINJ-01 – SINJ-05 | Phase 2 | Pending |
| AGNT-01 – AGNT-08 | Phase 3 | Pending |
| FCFG-01 – FCFG-04 | Phase 1 | Pending |
| TOKN-01 – TOKN-04 | Phase 3 | Pending |
| TEST-01 – TEST-05 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 34 total
- Mapped to phases: 34
- Unmapped: 0 ✓

---
*Requirements defined: 2026-04-13*
*Last updated: 2026-04-13 after initial definition*

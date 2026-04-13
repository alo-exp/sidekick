# Phase 1: Spec, Core Skill, and Forge Config - Research

**Researched:** 2026-04-13
**Domain:** Claude Code plugin skill authoring, ForgeCode configuration, markdown-based orchestration protocols
**Confidence:** HIGH

## Summary

Phase 1 delivers three artifacts: (1) a spec document at `.planning/forge-delegation-spec.md`, (2) a new skill at `skills/forge/SKILL.md` that adds explicit activation/deactivation mode switching, and (3) Forge configuration files (`.forge/agents/forge.md`, `.forge.toml`, `.forge/skills/`). The existing `skills/forge.md` (862 lines, 9 STEPs) already covers the full orchestration protocol including health checks, delegation decisions, prompt crafting, failure recovery, and post-delegation review. The new skill is a thin wrapper that adds session state management and mode switching on top of what already exists.

**Primary recommendation:** The spec should document the composition contract between `skills/forge.md` (always-on orchestration protocol) and `skills/forge/SKILL.md` (user-invoked mode switch). The SKILL.md should be concise -- it activates/deactivates mode and defers all orchestration logic to forge.md by reference.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- D-01: Spec lives at `.planning/forge-delegation-spec.md` with 11 required sections (overview, activation, deactivation, task prompt format, delegation loop, failure detection, fallback ladder, skill injection, AGENTS.md write protocol, token budget, Forge config specs)
- D-02: New skill at `skills/forge/SKILL.md` (NOT replacing `skills/forge.md`). Trigger: user invokes `/forge` or `/forge:deactivate`
- D-03: Health check = binary exists + `forge info` exits 0 with provider + credentials file exists with api_key + config has provider_id and model_id
- D-04: Session state via marker file `~/.claude/.forge-delegation-active` (created on activate, deleted on deactivate)
- D-05: Config files generated on FIRST `/forge` invocation, not at install time. Non-destructive: never overwrite existing files
- D-06: `.forge/agents/forge.md` injects: AGENTS.md reference, delegation-mode awareness, output format expectations, standing instruction to update AGENTS.md
- D-07: `.forge.toml` compaction defaults: token_threshold=80000, eviction_window=0.20, retention_window=6, max_tokens=16384
- D-08: Bootstrap skills from Silver Bullet/engineering skills: quality-gates, security, testing-strategy, code-review. Strip Skill tool refs, use imperative markdown
- D-09: Task prompt format: OBJECTIVE, CONTEXT, DESIRED STATE, SUCCESS CRITERIA, INJECTED SKILLS. Max 2000 tokens
- D-10: Forge SKILL.md format: YAML frontmatter (id, title, description, trigger), no Skill tool refs, no AskUserQuestion, imperative language

### Claude's Discretion
- No explicit discretion areas noted in CONTEXT.md

### Deferred Ideas (OUT OF SCOPE)
- Headless Forge invocation (no documented CLI flags)
- Auto-session-end AGENTS.md extraction trigger
- `:muse` vs `:forge` agent routing (Phase 2)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SKIL-01 | User can invoke `/forge` to activate delegation mode | SKILL.md with `/forge` trigger; session marker file pattern |
| SKIL-02 | Skill detects Forge installed/operational before activating | Health check (D-03): 4-point check already partially in forge.md STEP 0 |
| SKIL-03 | Skill sets session state for Forge-first routing | Marker file at `~/.claude/.forge-delegation-active` (D-04) |
| SKIL-04 | User can deactivate and return to Claude-direct mode | `/forge:deactivate` trigger deletes marker file |
| DLGT-01 | Claude composes structured task prompt for Forge | Task prompt format (D-09), forge.md STEP 3 already has prompt guidance |
| DLGT-02 | Task prompt includes objective, context, desired state, criteria, skills | D-09 defines exact fields; spec section 4 formalizes |
| DLGT-03 | Claude submits task and monitors output | forge.md STEP 4 (running) + STEP 6 (review) already cover mechanics |
| DLGT-04 | Claude never directly writes files while Forge-first active (except L3 fallback) | Mode state check before any tool use; spec section 3 |
| DLGT-05 | Claude communicates progress/outcomes in plain language | forge.md STEP 6 already has review protocol |
| FCFG-01 | Project-level `.forge/agents/forge.md` override | D-06 defines content; generated on first `/forge` invocation |
| FCFG-02 | `.forge.toml` template with compaction settings | D-07 defines defaults; non-destructive creation |
| FCFG-03 | `.forge/skills/` populated with initial skill set | D-08 defines bootstrap set of 4 skills |
| FCFG-04 | Agent override not overwritten on subsequent invocations | D-05 non-destructive rule |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- Stack: Shell/Bash + Markdown
- Must adhere to CLAUDE.md and silver-bullet.md
- No other specific coding conventions noted

## Standard Stack

This phase is pure markdown/shell -- no libraries to install.

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| ForgeCode | 2.9.9 | Terminal AI coding agent | Already installed, the delegation target [VERIFIED: `forge --version`] |
| Bash | 5.x | Shell scripting for health checks | Project stack is Shell/Bash [VERIFIED: CLAUDE.md] |

### File Artifacts
| File | Purpose | Format |
|------|---------|--------|
| `.planning/forge-delegation-spec.md` | Interaction contract spec | Markdown |
| `skills/forge/SKILL.md` | Activation/deactivation skill | Markdown with YAML frontmatter |
| `.forge/agents/forge.md` | Project-level Forge agent override | Markdown (Forge agent format) |
| `.forge.toml` | Forge configuration | TOML |
| `.forge/skills/*/SKILL.md` | Bootstrap skills for Forge | Markdown with YAML frontmatter |

## Architecture Patterns

### How skills/forge.md and skills/forge/SKILL.md Compose

```
USER invokes /forge
    |
    v
skills/forge/SKILL.md (NEW)
    1. Health check (calls forge info, checks 4 criteria from D-03)
    2. If fail: print error referencing forge.md STEP 0A
    3. If pass: create ~/.claude/.forge-delegation-active marker
    4. Generate .forge/ config files if absent (FCFG-01-04)
    5. Acknowledge activation to user
    |
    v
ALL SUBSEQUENT TASKS (while marker exists)
    |
    v
skills/forge.md (EXISTING, 862 lines)
    - STEP 1: Delegation decision framework
    - STEP 2: Project context detection
    - STEP 3: Prompt crafting
    - STEP 4: Running forge
    - STEP 5: Failure recovery
    - STEP 6: Post-delegation review
    |
    + DLGT-04 enforcement: Claude checks marker before using Write/Edit/Bash tools
    |
    v
USER invokes /forge:deactivate
    |
    v
skills/forge/SKILL.md
    1. Delete marker file
    2. Acknowledge deactivation
```

**Key insight:** `skills/forge/SKILL.md` is a mode switch and bootstrapper. `skills/forge.md` is the orchestration engine. They compose by reference, not by duplication. [ASSUMED]

### Recommended File Structure
```
skills/
  forge.md              # EXISTING — 862-line orchestration protocol (DO NOT MODIFY)
  forge/
    SKILL.md            # NEW — activation/deactivation mode switch
.forge/
  agents/
    forge.md            # NEW — project-level agent override
  skills/
    quality-gates/
      SKILL.md          # NEW — adapted from Silver Bullet
    security/
      SKILL.md          # NEW — adapted from Silver Bullet
    testing-strategy/
      SKILL.md          # NEW — adapted from engineering skill
    code-review/
      SKILL.md          # NEW — adapted from engineering skill
.forge.toml             # NEW — compaction config
.planning/
  forge-delegation-spec.md  # NEW — interaction contract spec
```

### Pattern: Session State via Marker File
**What:** A zero-byte file at `~/.claude/.forge-delegation-active` indicates delegation mode is on.
**When to use:** Every time Claude needs to decide whether to delegate or act directly.
**Example:**
```bash
# Check if delegation mode is active
if [ -f "${HOME}/.claude/.forge-delegation-active" ]; then
  echo "Forge-first mode is ACTIVE"
fi

# Activate
touch "${HOME}/.claude/.forge-delegation-active"

# Deactivate
rm -f "${HOME}/.claude/.forge-delegation-active"
```
[ASSUMED — D-04 decision; implementation detail is straightforward]

### Pattern: Non-Destructive Config Generation
**What:** Only create config files if they do not already exist.
**When to use:** Every `/forge` activation.
**Example:**
```bash
# Only create if absent
if [ ! -f ".forge/agents/forge.md" ]; then
  mkdir -p .forge/agents
  # Write the file
fi
```
[ASSUMED — D-05 decision]

### Pattern: Forge SKILL.md Format (for .forge/skills/)
**What:** YAML frontmatter + imperative markdown body that Forge's Skill Engine auto-detects.
**Example:**
```markdown
---
id: quality-gates
title: Quality Gates
description: Enforce code quality standards before committing
trigger: test, lint, commit, quality, review
---

# Quality Gates

Before committing any changes:

1. Run the project's test suite and ensure all tests pass
2. Run the linter if configured and fix all warnings
3. Check for any TODO/FIXME comments in changed files
4. Verify no debug statements remain in production code
```
[ASSUMED — based on D-10 and ForgeCode docs research in additional context. The `trigger` field causes Forge's Skill Engine to auto-apply when task description matches keywords.]

### Anti-Patterns to Avoid
- **Duplicating forge.md content in SKILL.md:** The new skill should reference forge.md STEPs, not copy them. Any duplication creates a maintenance burden and risks divergence.
- **Overwriting existing .forge/ files:** D-05 is explicit: never overwrite. Always check existence first.
- **Running health check via complex bash in SKILL.md:** Keep the SKILL.md readable. The health check is 4 simple conditions (D-03), not a script.
- **Putting orchestration logic in SKILL.md:** The 862-line forge.md already handles delegation decisions, prompt crafting, and failure recovery. SKILL.md only handles mode on/off and config bootstrapping.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Forge health check | Custom binary detection script | 4-point check from D-03 (binary, forge info, credentials, config) | Already specified, simple conditions |
| Session state | Database, JSON file, env vars | Single marker file (D-04) | Simplest possible mechanism; survives Claude tool restarts |
| Forge prompt format | Free-form prompts | D-09 structured format (OBJECTIVE/CONTEXT/DESIRED STATE/SUCCESS CRITERIA/INJECTED SKILLS) | Consistent parsing, token budget compliance |
| Skill adaptation | Manual rewrite of each skill | Systematic strip of Skill tool refs + format conversion (D-10) | Repeatable pattern, 4 skills to adapt |

## Common Pitfalls

### Pitfall 1: Replacing Instead of Extending forge.md
**What goes wrong:** Developer treats skills/forge/SKILL.md as a replacement and duplicates the orchestration protocol.
**Why it happens:** The 862-line forge.md looks like "the old way" and the new SKILL.md looks like "the new way."
**How to avoid:** SKILL.md is ~50-100 lines max. It does: activate, health check, bootstrap config, deactivate. Everything else stays in forge.md.
**Warning signs:** SKILL.md exceeds 200 lines; contains prompt crafting templates or failure recovery logic.

### Pitfall 2: Config Files Generated at Install Time
**What goes wrong:** Config files are created by `install.sh` or SessionStart hook, failing silently because there is no TTY and no project context.
**Why it happens:** Desire to have everything ready immediately.
**How to avoid:** D-05 is explicit: first `/forge` invocation only. install.sh must NOT be modified.
**Warning signs:** Changes to install.sh or hooks.json.

### Pitfall 3: Marker File Left Behind After Session
**What goes wrong:** `~/.claude/.forge-delegation-active` persists across sessions, causing unexpected Forge-first routing in the next session.
**Why it happens:** Session ends without explicit deactivation.
**How to avoid:** The spec should document that Claude should check/clean stale markers at session start, or that the marker is session-scoped by design (user re-invokes `/forge` each session). Given Claude Code sessions are ephemeral, the marker may persist. The SKILL.md activation step should handle a pre-existing marker gracefully (re-validate health check, acknowledge already-active state).
**Warning signs:** User reports Forge-first behavior without having invoked `/forge`.

### Pitfall 4: Overwriting User-Customized .forge/ Files
**What goes wrong:** User modifies `.forge/agents/forge.md` with project-specific instructions, then next `/forge` invocation overwrites it.
**Why it happens:** Config generation code doesn't check for existing files.
**How to avoid:** D-05: always check existence before creation. If file exists, skip silently.
**Warning signs:** User loses custom Forge agent instructions.

### Pitfall 5: plugin.json Integrity Hash Not Updated
**What goes wrong:** New skill files are added but `_integrity` hashes in `.claude-plugin/plugin.json` are not updated, causing integrity verification tests to fail.
**Why it happens:** plugin.json has SHA-256 hashes for existing files. Adding `skills/forge/SKILL.md` may require updating the manifest.
**How to avoid:** After adding any new skill file, check if plugin.json needs updating. The existing `test_plugin_integrity.bash` test will catch this.
**Warning signs:** `test_plugin_integrity.bash` fails after adding new files.

## Code Examples

### SKILL.md Activation Flow (Skeleton)
```markdown
---
name: forge-delegation
description: >
  Activate or deactivate Forge-first delegation mode. When active,
  Claude delegates all implementation tasks to Forge and acts as
  planner/communicator only.
---

# /forge — Forge Delegation Mode

## Activation (/forge)

1. **Health Check** (all must pass):
   - `~/.local/bin/forge` exists OR `forge` is on PATH
   - `forge info` exits 0 and shows a provider
   - `~/forge/.credentials.json` exists with non-empty `api_key`
   - `~/forge/.forge.toml` has `provider_id` and `model_id`
   - If ANY fail: print error, reference `skills/forge.md` STEP 0A, stop

2. **Bootstrap Config** (first invocation only):
   - If `.forge/agents/forge.md` absent: create from template
   - If `.forge.toml` absent: create with defaults (D-07)
   - If `.forge/skills/` absent: create and populate bootstrap set (D-08)

3. **Set Session State:**
   - Create `~/.claude/.forge-delegation-active`
   - Confirm to user: "Forge-first mode activated"

4. **Delegation Protocol:**
   - Follow `skills/forge.md` for all task execution
   - ...

## Deactivation (/forge:deactivate)

1. Remove `~/.claude/.forge-delegation-active`
2. Confirm: "Forge-first mode deactivated. Claude-direct mode restored."
```
[ASSUMED — skeleton based on D-02, D-03, D-04, D-05 decisions]

### .forge/agents/forge.md Template
```markdown
---
id: forge
title: Forge (Sidekick-Orchestrated)
description: Default Forge agent with Sidekick delegation awareness
---

# Forge Agent — Sidekick Project Override

You are being orchestrated by Claude (Sidekick plugin). Claude is the planner
and communicator; you are the implementer.

## Standing Instructions

1. Read `./AGENTS.md` for project-specific conventions before starting any task
2. Produce structured output: start with what you did, end with what changed
3. If you discover a reusable pattern, note it at the end of your response so
   Claude can add it to AGENTS.md
4. Do not ask questions — execute the task as specified. If ambiguous, make a
   reasonable choice and document your assumption

## Output Format

At the end of every task, include:
```
STATUS: SUCCESS | PARTIAL | FAILED
FILES_CHANGED: [list]
ASSUMPTIONS: [any assumptions made]
PATTERNS_DISCOVERED: [reusable patterns for AGENTS.md]
```
```
[ASSUMED — based on D-06 decisions and ForgeCode agent override format from docs research]

### .forge.toml Template
```toml
"$schema" = "https://forgecode.dev/schema.json"
max_tokens = 16384

[compact]
token_threshold = 80000
eviction_window = 0.20
retention_window = 6

[session]
provider_id = "open_router"
model_id = "qwen/qwen3.6-plus"
```
[VERIFIED: D-07 decision + forge.md STEP 0A-3 existing config pattern]

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Bash (custom test runner) |
| Config file | `tests/run_all.bash` |
| Quick run command | `bash tests/run_all.bash` |
| Full suite command | `bash tests/run_all.bash` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SKIL-01 | /forge activates delegation mode | smoke | `bash tests/test_forge_skill.bash` | No -- Wave 0 |
| SKIL-02 | Health check detects missing forge | unit | `bash tests/test_forge_skill.bash` | No -- Wave 0 |
| SKIL-03 | Marker file created on activation | unit | `bash tests/test_forge_skill.bash` | No -- Wave 0 |
| SKIL-04 | /forge:deactivate removes marker | unit | `bash tests/test_forge_skill.bash` | No -- Wave 0 |
| FCFG-01 | .forge/agents/forge.md created | unit | `bash tests/test_forge_config.bash` | No -- Wave 0 |
| FCFG-02 | .forge.toml created with defaults | unit | `bash tests/test_forge_config.bash` | No -- Wave 0 |
| FCFG-03 | .forge/skills/ populated | unit | `bash tests/test_forge_config.bash` | No -- Wave 0 |
| FCFG-04 | Existing files not overwritten | unit | `bash tests/test_forge_config.bash` | No -- Wave 0 |
| DLGT-01-05 | Delegation behaviors | manual-only | N/A (requires live Claude session) | N/A |

Note: DLGT-01-05 are behavioral requirements for Claude's orchestration logic encoded in markdown skill files. They cannot be unit-tested in the traditional sense -- they are verified by reading the SKILL.md and spec. Phase 4 (TEST-05) covers integration testing.

### Wave 0 Gaps
- [ ] `tests/test_forge_skill.bash` -- covers SKIL-01 through SKIL-04 (marker file create/delete, health check simulation)
- [ ] `tests/test_forge_config.bash` -- covers FCFG-01 through FCFG-04 (config generation, non-destructive checks)
- [ ] Update `tests/run_all.bash` to include new test suites
- [ ] Update `tests/test_plugin_integrity.bash` if new files need integrity hashes

### Sampling Rate
- **Per task commit:** `bash tests/run_all.bash`
- **Per wave merge:** `bash tests/run_all.bash`
- **Phase gate:** Full suite green before `/gsd-verify-work`

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | N/A |
| V3 Session Management | yes (marker file) | File permissions on marker; no sensitive data in marker |
| V4 Access Control | no | N/A |
| V5 Input Validation | yes | Health check validates forge info output; SKILL.md format validation |
| V6 Cryptography | no | N/A |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Marker file tampering | Tampering | Marker is zero-byte, no sensitive data; `~/.claude/` permissions |
| .forge/agents/forge.md injection | Tampering | Non-destructive rule (D-05); user reviews agent override |
| Forge prompt injection via AGENTS.md | Spoofing | Trust Gate already in forge.md STEP 2 (SENTINEL FINDING-1.1) |
| Config overwrite destroying user customizations | Tampering | Existence check before creation (D-05) |

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| ForgeCode (forge) | All delegation | Yes | 2.9.9 | Health check fails gracefully with install instructions |
| Bash | Health checks, tests | Yes | System default | -- |
| ~/.claude/ directory | Marker file | Yes (plugin creates it) | -- | -- |

**Missing dependencies:** None.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | SKILL.md should be ~50-100 lines, thin wrapper | Architecture Patterns | Over-engineering risk; but CONTEXT.md strongly implies this |
| A2 | Forge Skill Engine auto-detects via `trigger` YAML field | Architecture Patterns | Bootstrap skills might not auto-apply; verify with ForgeCode docs |
| A3 | `.forge/agents/forge.md` format uses markdown with YAML frontmatter | Code Examples | Agent override might need different format; verify against ForgeCode 2.9.9 |
| A4 | Marker file survives across Claude tool calls within a session | Common Pitfalls | If Claude sandbox resets home dir, marker lost mid-session |
| A5 | Structured output format (STATUS/FILES_CHANGED) can be reliably parsed from Forge output | Code Examples | Forge may not reliably follow output format instructions |

## Open Questions

1. **Forge agent override format verification**
   - What we know: ForgeCode uses `.forge/agents/<id>.md` for project-level overrides
   - What's unclear: Exact format requirements (YAML frontmatter? specific fields? Handlebars templates?)
   - Recommendation: The spec should document the format based on available docs; executor should test with `forge info` after creating the file

2. **Stale marker file handling**
   - What we know: D-04 says marker is deleted on deactivate or session end
   - What's unclear: How "session end" detection works -- Claude Code has no shutdown hook
   - Recommendation: SKILL.md should handle pre-existing marker at activation (re-validate, acknowledge)

3. **plugin.json update requirements**
   - What we know: plugin.json has `"skills": "./skills/"` which points to the skills directory
   - What's unclear: Whether adding `skills/forge/SKILL.md` requires adding a new integrity hash
   - Recommendation: Check `test_plugin_integrity.bash` to see what it validates; update accordingly

## Sources

### Primary (HIGH confidence)
- `skills/forge.md` -- full 862-line orchestration protocol, read in full
- `01-CONTEXT.md` -- 10 locked decisions (D-01 through D-10)
- `.planning/REQUIREMENTS.md` -- 13 phase requirements mapped
- `hooks/hooks.json` -- SessionStart hook structure
- `.claude-plugin/plugin.json` -- plugin manifest with integrity hashes
- `forge --version` -- verified ForgeCode 2.9.9 installed

### Secondary (MEDIUM confidence)
- ForgeCode architecture notes from additional context (AGENTS.md hierarchy, SKILL.md locations, .forge.toml format)

### Tertiary (LOW confidence)
- Forge Skill Engine `trigger` field auto-detection behavior (from docs research, not verified against running Forge)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools verified present, no libraries needed
- Architecture: HIGH -- composition pattern is clear from CONTEXT.md decisions and existing forge.md
- Pitfalls: HIGH -- well-documented in CONTEXT.md constraints and existing test infrastructure
- Forge SKILL.md format: MEDIUM -- based on docs research, not runtime-verified

**Research date:** 2026-04-13
**Valid until:** 2026-05-13 (stable domain, markdown-based)

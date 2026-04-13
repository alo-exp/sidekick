# Phase 1 Context: Spec, Core Skill, and Forge Config

**Phase:** 1 — Spec, Core Skill, and Forge Config
**Created:** 2026-04-13
**Mode:** Autonomous (bypass-permissions detected)

---

## Domain

Deliver a written spec that locks down every interaction contract for the Forge delegation system, implement the `/forge` SKILL.md that activates delegation mode, and create the Forge configuration files (`.forge/agents/forge.md`, `.forge.toml`, `.forge/skills/`) that persist across sessions.

---

## Decisions

### D-01: Spec location and structure
**Decision:** Spec lives at `.planning/forge-delegation-spec.md`
**Sections required:**
1. Overview and mental model (Claude=Brain, Forge=Hands)
2. Activation protocol (how `/forge` activates, health check steps, state tracking)
3. Deactivation protocol
4. Task prompt format (required fields: objective, file context, desired state, success criteria, injected skills)
5. Delegation loop (submit → monitor → detect outcome)
6. Failure detection criteria (error signals, wrong output patterns, stall conditions)
7. Fallback ladder contract (Level 1 Guide, Level 2 Handhold, Level 3 Take over + debrief)
8. Skill injection protocol (mapping table, selective injection rules, Forge-compatible format)
9. AGENTS.md write protocol (what to extract, global vs project tier, deduplication algorithm)
10. Token budget rules (max prompt size, what to omit, compaction triggers)
11. Forge config file specs (agent override format, .forge.toml defaults, skills bootstrap list)

### D-02: Skill file location
**Decision:** New skill lives at `skills/forge/SKILL.md` (NOT replacing `skills/forge.md`)
**Rationale:** The existing `skills/forge.md` is the current orchestration skill triggered automatically. The new `/forge` skill is an explicit user-invoked mode switch. Separate files prevent accidental replacement.
**Trigger:** User explicitly invokes `/forge` (or `/forge:deactivate` to turn off)

### D-03: Forge health check — what counts as "operational"
**Decision:** Forge is operational if ALL of these pass:
1. `~/.local/bin/forge` binary exists (or `forge` is on PATH)
2. `forge info` exits 0 and output contains a provider name (non-empty)
3. Credentials file exists at `~/forge/.credentials.json` with a non-empty `api_key` field
4. Config at `~/forge/.forge.toml` contains non-empty `provider_id` and `model_id`

**If health check fails:** Print actionable error referencing STEP 0A in `skills/forge.md` (do not duplicate the install instructions — reference them).

### D-04: Session state mechanism
**Decision:** Use a session state marker file: `~/.claude/.forge-delegation-active`
- Created (empty) when `/forge` activates delegation mode
- Deleted when `/forge:deactivate` is called or session ends
- Claude checks for this file at the start of each task to determine routing
- No database, no complex state — single file existence = active

### D-05: Forge config file generation timing
**Decision:** Config files are generated on FIRST `/forge` invocation, not at plugin install time
**Rationale:** Install happens headlessly (SessionStart hook, no TTY). Config file generation requires knowing the project context. First invocation is the right time.
**Non-destructive rule:** If `.forge/agents/forge.md` already exists, NEVER overwrite it — skip silently. Same for `.forge.toml`. Only create if absent.

### D-06: `.forge/agents/forge.md` override — what to inject
**Decision:** The project-level forge agent override injects:
1. A reference to this project's AGENTS.md for standing instructions
2. The Sidekick delegation mode awareness (Forge knows it's being orchestrated by Claude)
3. Output format expectations (structured responses Claude can parse for success/failure detection)
4. A standing instruction to update `./AGENTS.md` with any patterns Forge discovers

### D-07: `.forge.toml` compaction defaults
**Decision:** Recommended defaults to include in the template:
```toml
[compact]
token_threshold = 80000   # trigger compaction before hitting limit
eviction_window = 0.20    # summarize 20% of oldest context
retention_window = 6      # always keep 6 most recent messages
```
`max_tokens = 16384` (conservative default; user can raise)

### D-08: Initial `.forge/skills/` bootstrap set
**Decision:** On first `/forge` invocation, bootstrap these skills from existing Claude skills:
- `quality-gates` → adapted from Silver Bullet quality-gates skill
- `security` → adapted from Silver Bullet security skill
- `testing-strategy` → adapted from engineering testing-strategy skill
- `code-review` → adapted from engineering code-review skill

Adaptation rule: Strip all Skill tool references, replace with direct markdown instructions Forge can follow natively. Place each at `.forge/skills/<name>/SKILL.md`.

### D-09: Task prompt format (for D-01 spec)
**Decision:** Every Claude→Forge task prompt must include these fields in this order:
```
OBJECTIVE: [one sentence — what must be true when done]
CONTEXT: [files involved, current state of relevant code]
DESIRED STATE: [concrete output — what the file/function/result should look like]
SUCCESS CRITERIA: [testable conditions — how Forge knows it succeeded]
INJECTED SKILLS: [list of skills injected to .forge/skills/ for this task]
```
Maximum prompt length: 2,000 tokens. Omit conversation history entirely.

### D-10: Forge-compatible SKILL.md format rules
**Decision:** When adapting Claude skills to Forge SKILL.md format:
- No `Skill tool` references (Forge doesn't have it)
- No `AskUserQuestion` calls (Forge operates autonomously)
- No Claude-specific tool names (Read, Edit, Write → describe file operations generically)
- Use imperative language: "Run X", "Write Y", "Verify Z"
- Include a YAML frontmatter block: `id`, `title`, `description`, `trigger`
- `trigger` field: keywords that cause Forge's Skill Engine to auto-apply the skill

---

## Canonical Refs

- `skills/forge.md` — existing orchestration skill (read for STEP 0 health check and STEP 0A install flow)
- `.planning/REQUIREMENTS.md` — full requirement list for Phase 1 (SKIL-01–04, DLGT-01–05, FCFG-01–04)
- `.planning/ROADMAP.md` — phase plan breakdown (plans 01-01, 01-02, 01-03)
- `hooks/hooks.json` — existing SessionStart hook (must not be modified)
- ForgeCode docs research (ForgeCode AGENTS.md hierarchy: `~/forge/AGENTS.md` > git root > CWD; SKILL.md locations: `.forge/skills/` > `~/.agents/skills/` > `~/forge/skills/`)

---

## Deferred Ideas

- Headless Forge invocation (no documented CLI flags — deferred to v2 if ForgeCode adds this)
- Auto-session-end AGENTS.md extraction trigger (ForgeCode has no built-in hook for this)
- `:muse` vs `:forge` agent routing (v2 — Phase 2 in current roadmap handles routing decisions)

---

## Existing Infrastructure (DO NOT IGNORE)

The plugin already has substantial working infrastructure. All implementation MUST build on it:

- **`skills/forge.md`** (862 lines) — Already contains full orchestration protocol: health check (STEP 0), full setup flow (STEP 0A), delegation decision framework (STEP 1), project context detection (STEP 2), prompt crafting (STEP 3), running forge (STEP 4), failure recovery (STEP 5), post-delegation review (STEP 6), advanced scenarios (STEP 7), model selection (STEP 8), quick reference (STEP 9). **Read this fully before writing anything.**
- **`install.sh`** — Binary installer, SHA-256 verification, PATH modification. Already handles ForgeCode install. DO NOT MODIFY.
- **`hooks/hooks.json`** — SessionStart hook that runs `install.sh` on first session. DO NOT MODIFY.
- **`tests/`** — 43 passing tests across 4 suites. New tests must integrate with `tests/run_all.bash`.
- **`.claude-plugin/plugin.json`** — Plugin manifest with integrity hashes. Must be updated when new skill files are added.

**Key implication for Phase 1:** The new `skills/forge/SKILL.md` is an EXTENSION that adds explicit activation/deactivation mode switching and a session-state mechanism ON TOP of the existing `skills/forge.md` orchestration logic. It does not re-implement what forge.md already does — it wraps it with a persistent mode switch.

The spec (plan 01-01) must document how `skills/forge/SKILL.md` and `skills/forge.md` relate and compose, not treat them as independent.

## Notes for Downstream Agents

- **Researcher:** Read `skills/forge.md` fully before researching anything. Identify which of the 9 STEPS already cover what we need vs. what's genuinely missing. Also investigate Forge's SKILL.md auto-detection mechanism — specifically how the `trigger` field works. Research whether `.forge/agents/forge.md` frontmatter `user_prompt` Handlebars template is useful for task prompt injection.
- **Planner:** Plan 01-01 (spec) MUST complete before 01-02 and 01-03. Plans 01-02 and 01-03 can run in parallel after spec is done. Executor for 01-02 and 01-03 MUST read the existing `skills/forge.md` before writing any new code.
- **Executor:** The new `skills/forge/SKILL.md` must be a net-new file. Do not touch `skills/forge.md`. When writing the spec, treat forge.md as the authoritative reference for what already exists.

# Phase 2 Context: Fallback Ladder and Skill Injection

**Phase:** 2 — Fallback Ladder and Skill Injection
**Created:** 2026-04-13
**Mode:** Autonomous (bypass-permissions detected)

---

## Domain

Implement the three-level fallback ladder (Guide → Handhold → Take over + debrief) inside `skills/forge/SKILL.md`, and implement the selective skill injection layer that copies relevant Claude skills to `.forge/skills/` before each delegation.

---

## Decisions

### D-01: Where fallback ladder logic lives
**Decision:** Fallback ladder is implemented directly in `skills/forge/SKILL.md` as an extension section.
**Rationale:** The SKILL.md already references `skills/forge.md` STEP 5 for failure recovery. Phase 2 expands SKILL.md with explicit Level 1/2/3 sections. This keeps all mode-specific behavior in one file.
**Non-destructive rule:** `skills/forge.md` is NEVER modified — all new logic goes into `skills/forge/SKILL.md`.

### D-02: Level 1 (Guide) — single retry, prompt reframing
**Decision:** On failure detection, Claude rewrites the task prompt with:
1. A diagnosis of what Forge likely misunderstood
2. A tighter DESIRED STATE description  
3. A concrete code snippet or file diff as reference
Single retry at this level. If retry fails → escalate to Level 2.

### D-03: Level 2 (Handhold) — subtask decomposition
**Decision:** Claude decomposes the original task into atomic subtasks (each ≤ 200 tokens). Each subtask gets its own full 5-field prompt (OBJECTIVE, CONTEXT, DESIRED STATE, SUCCESS CRITERIA, INJECTED SKILLS). Submit sequentially, verify output of each before proceeding.
**Limit:** Maximum 3 subtask attempts total. If all 3 fail → escalate to Level 3.

### D-04: Level 3 (Take over) — Claude acts directly + debrief
**Decision:** Claude uses Write/Edit/Bash tools directly to complete the task (lifting DLGT-04 restriction temporarily). After completion, produce a structured debrief:
```
DEBRIEF:
  TASK: [what the task was]
  FORGE_FAILURE: [why Forge failed — specific diagnosis]
  LEARNED: [what was discovered about Forge's limitations or task characteristics]
  AGENTS_UPDATE: [exact text proposed for ./AGENTS.md to prevent recurrence]
```
The AGENTS_UPDATE field is a proposed addition — written in Forge AGENTS.md format (action-oriented, specific). Claude asks the user to confirm before actually writing it to AGENTS.md.

### D-05: Failure detection implementation
**Decision:** Implement as three explicit checks Claude runs after each Forge output:
1. **Error signal check:** Forge output contains "Error:", "Failed:", "fatal:", or exit code ≠ 0
2. **Wrong output check:** Forge output does not satisfy SUCCESS CRITERIA from the prompt. Track: if same failure appears on retry → failure confirmed (not just a transient issue)
3. **Stall check:** Since Forge is interactive ZSH (no timeout API), stall detection is behavioral — if Forge asks a clarifying question back to Claude without making progress, treat as Level 1 trigger (reframe with more specifics)
**Reference:** `skills/forge.md` STEP 5 patterns for contextual clues.

### D-06: Skill injection implementation
**Decision:** Skill injection is a Claude decision step, not automated file copying. Before each delegation:
1. Claude reads the task to determine task type (testing / code change / security-sensitive / review)
2. Claude consults the mapping table (spec section 8)
3. Claude reads relevant `.forge/skills/<name>/SKILL.md` and ensures it exists on disk (already bootstrapped by Phase 1)
4. Claude includes the skill name in the INJECTED SKILLS field of the task prompt
**No file copying needed** — bootstrap skills are already in `.forge/skills/`. Forge's Skill Engine detects them via `trigger` keywords automatically.

### D-07: Skill-to-task type mapping (selector rules)
**Decision:** Apply this mapping:
- Task involves writing/running tests → inject `testing-strategy`
- Task involves code changes (edit/write files) → inject `quality-gates` + `code-review`
- Task involves auth, input validation, credentials, or data handling → inject `security`
- Task is a general review → inject `code-review`
- Multiple conditions can apply → inject all matching skills
- Pure file read or research task → no skill injection

### D-08: Future skill expansion (Phase 2 scope limit)
**Decision:** Only the 4 bootstrap skills (already in `.forge/skills/`) are in scope for Phase 2. Adding new skills to `.forge/skills/` is Phase 2+ territory. SINJ-01 (maintaining Claude-to-Forge mapping) means documenting the 4-skill mapping table in SKILL.md — not building a dynamic registry.

### D-09: DLGT-04 enforcement during fallback
**Decision:** DLGT-04 (no direct Write/Edit/Bash) applies at Levels 1 and 2. Level 3 explicitly lifts the restriction as the controlled fallback exception. After Level 3 completes, DLGT-04 is restored — the marker file remains active unless the user explicitly deactivates.

---

## Canonical Refs

- `skills/forge/SKILL.md` (66 lines) — Phase 1 output, to be extended in Phase 2
- `.planning/forge-delegation-spec.md` sections 6, 7, 8 — Fallback ladder contract, failure detection criteria, skill injection protocol
- `skills/forge.md` STEP 5 — Existing failure recovery patterns (reference only, do not modify)
- `.forge/skills/` — 4 bootstrap skills already exist from Phase 1

---

## Existing Infrastructure (DO NOT IGNORE)

- **`skills/forge/SKILL.md`** (66 lines) — Already has health check, activation, deactivation, DLGT-04 mention. Phase 2 EXTENDS this file by appending fallback ladder and skill injection sections.
- **`.forge/skills/quality-gates/SKILL.md`**, **`security/SKILL.md`**, **`testing-strategy/SKILL.md`**, **`code-review/SKILL.md`** — Already exist. No new skill files needed.
- **`skills/forge.md`** (862 lines) — NEVER MODIFIED. Reference by STEP number.
- **Tests:** 43 passing tests must remain passing after Phase 2.
- **`.claude-plugin/plugin.json`** — Must be updated with new SHA-256 hash if `skills/forge/SKILL.md` is modified.

---

## Deferred Ideas

- Dynamic skill registry (Phase 3+)
- Custom user-defined skill injection rules
- Forge native timeout/stall detection (requires Forge CLI feature)
- `:muse` vs `:forge` agent routing (Phase 2 v2 per ROADMAP)

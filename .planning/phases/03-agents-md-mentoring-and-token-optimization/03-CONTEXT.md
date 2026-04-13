# Phase 3 Context: AGENTS.md Mentoring and Token Optimization

**Phase:** 3 — AGENTS.md Mentoring and Token Optimization
**Created:** 2026-04-13
**Mode:** Autonomous (bypass-permissions detected)

---

## Domain

Implement the AGENTS.md mentoring loop (three-tier instruction accumulation + deduplication) and token optimization (minimal task prompt construction, validated `.forge.toml` compaction defaults). These are the Phase 3 requirements: AGNT-01–08 and TOKN-01–04.

---

## Decisions

### D-01: Where mentoring loop logic lives
**Decision:** AGENTS.md mentoring loop is implemented in `skills/forge/SKILL.md` as another extension section — appended after the Phase 2 skill injection section. Plan 03-01 adds the AGENTS.md section; plan 03-02 adds the token optimization section.
**Non-destructive rule:** `skills/forge.md` is NEVER modified.

### D-02: Three-tier AGENTS.md write structure
**Decision:** Per spec section 9:
- **Global tier:** `~/forge/AGENTS.md` — cross-project, cross-session knowledge
- **Project tier:** `./AGENTS.md` at git root — project-specific
- **Session log:** `docs/sessions/YYYY-MM-DD-session.md` — per-session evolution

Claude writes to all three after each Forge task. Session log format: date-stamped markdown file with task, extracted instructions, and deduplication decisions.

### D-03: What to extract from each Forge task
**Decision:** Per spec section 9, Claude extracts:
1. Corrections — mistakes Forge made that Claude fixed
2. User preferences — expressed during the session
3. Project patterns — conventions Forge discovered
4. Forge behavior observations — what Forge does well/poorly in this codebase
Extraction happens after every Forge task completion, not just failures.

### D-04: Deduplication algorithm
**Decision:** Per spec section 9, two-phase check before every AGENTS.md write:
1. **Primary:** Exact substring match — scan existing content for instruction text
2. **Secondary:** Semantic similarity — check if equivalent instruction exists in different words
3. If either matches: skip the write entirely (no partial append)
This applies to both global and project AGENTS.md tiers.

### D-05: AGENTS.md format (per AGNT-06, AGNT-07)
**Decision:**
- **Global `~/forge/AGENTS.md`:** Action-oriented, cross-project patterns, organized by category (Code Style, Testing, Git Workflow, Forge Behavior)
- **Project `./AGENTS.md`:** Project-specific conventions, includes project structure conventions, task patterns, Forge behavior corrections specific to this codebase

### D-06: Bootstrap behavior on empty AGENTS.md
**Decision:** Per spec section 9 and AGNT-08: on first `/forge` invocation when `./AGENTS.md` is empty or absent, Claude bootstraps it with the key conventions from `skills/forge.md` — specifically the output format expectations (STATUS/FILES_CHANGED/ASSUMPTIONS/PATTERNS_DISCOVERED) and delegation principles already documented there.

### D-07: Token optimization — minimal task prompt construction
**Decision:** Per spec section 10 and TOKN-02: task prompts to Forge must contain:
- Only the 5 mandatory fields (OBJECTIVE, CONTEXT, DESIRED STATE, SUCCESS CRITERIA, INJECTED SKILLS)
- Maximum 2,000 tokens
- CONTEXT field: only files directly relevant to the task (not full conversation history)
- Explicit rule: omit conversation history, unrelated file contents, verbose error logs
This is documented as a rule in `skills/forge/SKILL.md` task prompt construction section.

### D-08: Token optimization — selective injection enforcement
**Decision:** Per TOKN-03: skill injection must be selective — only inject skills relevant to the current task type. This is already implemented in Phase 2 (D-07 mapping rules). Phase 3 adds an explicit "injection budget check" step in SKILL.md: before submitting, confirm INJECTED SKILLS lists ≤ 2 skills unless task is clearly multi-domain.

### D-09: .forge.toml compaction validation
**Decision:** Per TOKN-04: the existing `.forge.toml` compaction defaults (token_threshold=80000, eviction_window=0.20, retention_window=6, max_tokens=16384) from Phase 1 are the validated defaults. Phase 3 adds a note in SKILL.md that these values are "tested defaults" — and documents the rationale so users can tune them. No new file needed; this is a documentation addition to SKILL.md.

---

## Canonical Refs

- `skills/forge/SKILL.md` (169 lines) — Phase 1+2 output, to be extended further in Phase 3
- `.planning/forge-delegation-spec.md` sections 9 and 10 — AGENTS.md protocol and token budget contracts
- `skills/forge.md` STEP 6 — Post-delegation review patterns (reference for what to extract)
- `docs/sessions/` directory — already exists from Phase 1 (`.gitkeep`)
- `~/forge/AGENTS.md` — global Forge instructions file (may or may not exist on user's machine)
- `./AGENTS.md` — project-level instructions (does not exist yet)

---

## Existing Infrastructure (DO NOT IGNORE)

- **`skills/forge/SKILL.md`** (169 lines) — Already has activation, deactivation, fallback ladder, skill injection. Phase 3 EXTENDS with AGENTS.md mentoring and token optimization sections.
- **`docs/sessions/`** — Directory exists with `.gitkeep` from Phase 1 docs.
- **`.forge.toml`** — Already has correct compaction defaults from Phase 1.
- **`skills/forge.md`** (862 lines) — NEVER MODIFIED.
- **43 tests** — Must remain passing.
- **`.claude-plugin/plugin.json`** — Must be updated with new SHA-256 hash after SKILL.md changes.

---

## Deferred Ideas

- Automated session-end AGENTS.md extraction trigger (no Forge built-in hook)
- Periodic AGENTS.md audit (`/forge:review-agents`) — v2 MENT-03
- Proactive AGENTS.md additions after successes — v2 MENT-01

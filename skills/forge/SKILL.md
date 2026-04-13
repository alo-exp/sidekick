---
name: forge-delegation
description: >
  Activate or deactivate Forge-first delegation mode. When active, Claude delegates
  all implementation tasks to Forge and acts as planner/communicator only.
  Trigger: user invokes /forge or /forge:deactivate.
---

# /forge -- Forge Delegation Mode

This skill adds explicit activation/deactivation mode switching on top of the existing
`skills/forge.md` orchestration protocol. It does NOT replace `skills/forge.md` -- it
wraps it with a persistent session state mechanism via a marker file.

---

## Activation (`/forge`)

### 1. Health Check

All 4 criteria must pass before activation proceeds:

1. **Binary exists:** `~/.local/bin/forge` exists OR `which forge` succeeds
2. **Provider configured:** `forge info` exits 0 and output contains a provider name (non-empty line after "Provider:")
3. **Credentials present:** `~/forge/.credentials.json` exists and contains a non-empty `api_key` field (never read or log the actual key value -- existence check only)
4. **Config valid:** `~/forge/.forge.toml` contains non-empty `provider_id` and `model_id`

If ANY check fails: print which check failed and direct the user to `skills/forge.md` STEP 0A for setup instructions. Stop activation.

### 2. Bootstrap Config (first invocation only)

Per the non-destructive rule, create only if absent -- never overwrite existing files:

- `.forge/agents/forge.md` -- project-level agent override (content defined in plan 01-03)
- `.forge.toml` -- compaction and session defaults (content defined in plan 01-03)
- `.forge/skills/` -- bootstrap skill set: quality-gates, security, testing-strategy, code-review (content defined in plan 01-03)

### 3. Set Session State

- Create zero-byte marker file: `~/.claude/.forge-delegation-active`
- If file already exists (stale from prior session): re-run full health check, then acknowledge: **"Forge-first mode is already active (re-validated)."**

### 4. Confirm

> "Forge-first delegation mode activated. All implementation tasks will be routed to Forge."
> "To deactivate: `/forge:deactivate`"

---

## Delegation Protocol (while active)

Before every implementation task, check: `[ -f ~/.claude/.forge-delegation-active ]`

- **If active:** follow `skills/forge.md` STEP 1 through STEP 9 for task execution.
- **DLGT-04 enforcement:** while the marker exists, Claude MUST NOT directly use Write, Edit, or Bash tools for implementation work. Exception: Level 3 fallback (Phase 2).
- **Task prompt format:** compose prompts per the spec (section 4):
  OBJECTIVE, CONTEXT, DESIRED STATE, SUCCESS CRITERIA, INJECTED SKILLS.
- **Communication:** Claude reports progress and outcomes to the user in plain language (per `skills/forge.md` STEP 6).

---

## Deactivation (`/forge:deactivate`)

1. Check if `~/.claude/.forge-delegation-active` exists.
   - **If yes:** delete it, confirm: **"Forge-first mode deactivated. Claude-direct mode restored."**
   - **If no:** acknowledge: **"Forge-first mode is not currently active."**

---

## Failure Detection

After each Forge output, Claude runs three checks:

1. **Error signal check:** Forge output contains "Error:", "Failed:", "fatal:", or exit code != 0. If detected -> trigger Level 1.
2. **Wrong output check:** Forge output does not satisfy SUCCESS CRITERIA from the task prompt. If the SAME failure mode appears on retry -> failure confirmed, trigger next level.
3. **Stall check:** Forge asks a clarifying question back without making progress (behavioral stall in interactive ZSH). Treat as Level 1 trigger -- reframe with more specifics.

Reference: `skills/forge.md` STEP 5 for contextual failure recovery patterns.

---

## Fallback Ladder

When failure is detected, escalate sequentially. No level may be skipped.

### Level 1 -- Guide

On failure detection, Claude rewrites the task prompt with:
1. A diagnosis of what Forge likely misunderstood
2. A tighter DESIRED STATE description
3. A concrete code snippet or file diff as reference

Single retry at this level. If retry fails -> escalate to Level 2.

### Level 2 -- Handhold

Claude decomposes the original task into atomic subtasks (each <= 200 tokens). Each subtask gets its own full 5-field prompt (OBJECTIVE, CONTEXT, DESIRED STATE, SUCCESS CRITERIA, INJECTED SKILLS). Submit sequentially, verify output of each before proceeding.

Maximum 3 subtask attempts total. If all 3 fail -> escalate to Level 3.

### Level 3 -- Take over

DLGT-04 restriction is temporarily lifted. Claude uses Write/Edit/Bash tools directly to complete the task. After completion, produce a structured debrief:

```
DEBRIEF:
  TASK: [what the task was]
  FORGE_FAILURE: [why Forge failed -- specific diagnosis]
  LEARNED: [what was discovered about Forge's limitations or task characteristics]
  AGENTS_UPDATE: [exact text proposed for ./AGENTS.md to prevent recurrence]
```

The AGENTS_UPDATE is a proposed addition in Forge AGENTS.md format (action-oriented, specific). Claude asks the user to confirm before writing to AGENTS.md.

After Level 3 completes, DLGT-04 is restored -- the marker file remains active.

---

## Skill Injection

Before each delegation, Claude performs a skill injection step to ensure Forge receives only the skills relevant to the current task.

### 1. Determine Task Type

Read the task and classify:
- **Testing task:** task involves writing or running tests
- **Code change:** task involves editing or writing files
- **Security-sensitive:** task involves auth, input validation, credentials, or data handling
- **Review:** task is a general code review
- **Research/read-only:** pure file read or research (no injection needed)

Multiple classifications can apply simultaneously.

### 2. Apply Mapping Table

| Task Type | Injected Skills |
|-----------|----------------|
| Testing | `testing-strategy` |
| Code change | `quality-gates`, `code-review` |
| Security-sensitive | `security` |
| Review | `code-review` |
| Research/read-only | (none) |

### 3. Verify Skill Files Exist

For each skill to inject, confirm the file exists at `.forge/skills/<name>/SKILL.md`. These were bootstrapped in Phase 1 activation and should already be present. If missing, log a warning but proceed with delegation.

### 4. Include in Task Prompt

Add the INJECTED SKILLS field to the task prompt listing only the matched skill names:

```
INJECTED SKILLS: quality-gates, code-review
```

Forge's Skill Engine auto-detects skills via `trigger` keywords in their YAML frontmatter. The INJECTED SKILLS field serves as an explicit signal reinforcing which skills apply.

### Skill Format Requirements

All files in `.forge/skills/` MUST conform to Forge-compatible SKILL.md format:
- YAML frontmatter with: `id`, `title`, `description`, `trigger`
- No `Skill tool` references
- No `AskUserQuestion` calls
- No Claude-specific tool names (use generic: "write file", "run command")
- Imperative language throughout

### Scope Limit

Only the 4 bootstrap skills are in scope: `quality-gates`, `security`, `testing-strategy`, `code-review`. Adding new skills requires a future phase.

---

## AGENTS.md Mentoring Loop

After every Forge task, Claude extracts standing instructions and writes them to the appropriate tier. This enables Forge to accumulate knowledge over time without unbounded growth.

### Post-Task Extraction

After every Forge task completion (success OR failure), Claude extracts actionable instructions from the session. Categories:

1. **Corrections** -- mistakes Forge made that Claude fixed. Format as "Do X instead of Y when Z."
2. **User preferences** -- conventions the user expressed during the session. Format as "Always/Never do X."
3. **Project patterns** -- conventions Forge discovered in the codebase. Format as "This project uses X for Y."
4. **Forge behavior observations** -- what Forge does well or poorly in this codebase. Format as "Forge tends to X; counteract by Y."

Each extraction must be action-oriented and specific -- not observations or summaries. If nothing new was learned, skip the write entirely.

### Deduplication Algorithm

Before every AGENTS.md write, run a two-phase check to prevent duplicate content:

1. **Primary -- Exact substring match:** Scan the target AGENTS.md file for the instruction text. If the exact string (ignoring leading/trailing whitespace) already appears, it is a duplicate.
2. **Secondary -- Semantic similarity:** If no exact match, check whether an equivalent instruction exists phrased differently. Compare the intent: does an existing instruction already achieve the same behavioral outcome?
3. **Decision:** If either check matches, skip the write entirely. Do not partially append or rephrase -- the existing instruction is sufficient.

Apply this algorithm independently for each tier (global and project). Session logs are append-only and do not require deduplication.

### Three-Tier Write Protocol

After extraction and deduplication, write to all applicable tiers:

1. **Global tier -- `~/forge/AGENTS.md`**
   Append cross-project knowledge: coding style rules, testing conventions, git workflow patterns, and Forge behavior corrections that apply to any codebase.
   If `~/forge/AGENTS.md` does not exist, create it with these category headers:
   ```
   # Forge Global Instructions

   ## Code Style

   ## Testing

   ## Git Workflow

   ## Forge Behavior
   ```
   Then append the extracted instructions under the appropriate category.

2. **Project tier -- `./AGENTS.md`**
   Append project-specific conventions: project structure patterns, naming conventions, task patterns, and Forge behavior corrections specific to this codebase.
   Append under the appropriate section header (Project Conventions, Task Patterns, or Forge Corrections).

3. **Session log -- `docs/sessions/YYYY-MM-DD-session.md`**
   Append an entry with:
   - **Task name:** what Forge was asked to do
   - **Extracted instructions:** the new instructions identified (if any)
   - **Deduplication decisions:** which instructions were skipped and why (exact match or semantic match)
   - **Tiers written:** which AGENTS.md files were updated

   If the session log file does not exist for today's date, create it with a date header.

### Bootstrap Behavior

On first `/forge` invocation when `./AGENTS.md` is empty or absent:

1. Check if `./AGENTS.md` exists and has content (file size > 0). If it does, skip bootstrap entirely.
2. Read `skills/forge.md` for key conventions:
   - Output format expectations: STATUS, FILES_CHANGED, ASSUMPTIONS, PATTERNS_DISCOVERED
   - Delegation principles: Claude = Brain (plan, communicate, review), Forge = Hands (write, edit, run)
   - Structured response requirements from STEP 6
3. Write these as the initial content of `./AGENTS.md` under "## Project Conventions" and "## Forge Output Format".
4. Include empty "## Task Patterns" and "## Forge Corrections" sections for future population by the mentoring loop.

### AGENTS.md Format

**Global `~/forge/AGENTS.md` format:**
```
# Forge Global Instructions

## Code Style
[action-oriented rules -- e.g., "Use early returns instead of nested if/else"]

## Testing
[action-oriented rules -- e.g., "Always run existing tests before writing new ones"]

## Git Workflow
[action-oriented rules -- e.g., "Commit after each logical change, not at end of task"]

## Forge Behavior
[action-oriented rules -- e.g., "Forge overwrites files instead of editing; provide diffs as context"]
```

**Project `./AGENTS.md` format:**
```
# Project: [name]

## Project Conventions
[project structure, naming, patterns]

## Forge Output Format
[STATUS/FILES_CHANGED/ASSUMPTIONS/PATTERNS_DISCOVERED]

## Task Patterns
[recurring task types and how to handle them]

## Forge Corrections
[specific corrections for this codebase]
```

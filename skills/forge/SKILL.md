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

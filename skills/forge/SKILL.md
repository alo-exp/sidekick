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

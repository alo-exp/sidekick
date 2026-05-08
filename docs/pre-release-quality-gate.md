# Pre-Release Quality Gate — Sidekick

Before ANY release, the following four-stage quality gate MUST be completed in order.

**IMPORTANT**: This gate runs AFTER normal workflow finalization and BEFORE creating a GitHub release.

---

## Enforcement

**State file**: `~/.claude/.sidekick/quality-gate-state` (kept separate from Silver Bullet's state file because Silver Bullet's `dev-cycle-check.sh` hook blocks direct writes to its own state path)

**Required markers** (must all be present before release):
- `quality-gate-stage-1`
- `quality-gate-stage-2`
- `quality-gate-stage-3`
- `quality-gate-stage-4`

**Session reset**: All four markers are cleared at the start of each new Claude Code session. The gate must be completed in full during the session in which the release is being cut — markers from a previous session do not carry over.

Each stage is complete only when:
1. The work is done and verified
2. The `/superpowers:verification-before-completion` skill has been invoked
3. The marker is written: `echo "quality-gate-stage-N" >> ~/.claude/.sidekick/quality-gate-state`

**Violating the verification rule is equivalent to skipping the stage.**

---

## Stage 1 — Code Review Triad

**Goal**: Zero accepted issues across all source files changed in this release.

1. **Dispatch in parallel** — invoke all three reviewers simultaneously as subagents:
   - `/engineering:code-review` — structured quality review: security, performance, correctness, maintainability
   - `/gsd-code-review` — GSD automated code reviewer
   - `/superpowers:requesting-code-review` — dispatches `superpowers:code-reviewer` automated reviewer
2. **Collect all findings** — wait for all three to complete, then aggregate their output
3. Invoke `/superpowers:receiving-code-review` — triage the combined findings from all three reviewers
4. Fix all accepted issues
5. **Loop**: repeat steps 1–4 until `/superpowers:receiving-code-review` produces zero accepted items

Use the checklists below as review guidance for the parallel reviewers in step 1.

---

### Review Guidance — `skills/forge/SKILL.md`
- Verify the activation/deactivation flow is described unambiguously (health check → marker → enforcement)
- Confirm the 5-field task prompt format (OBJECTIVE, CONTEXT, DESIRED STATE, SUCCESS CRITERIA, INJECTED SKILLS) is fully specified
- Verify the fallback ladder (L1 Guide → L2 Handhold → L3 Take Over) is described with clear escalation triggers
- Confirm AGENTS.md mentoring loop (post-task extraction, 3-tier write, deduplication) is accurately documented
- Verify `--conversation-id` injection behaviour: auto-injected as a valid RFC 4122 UUID; never specified manually
- Verify `run_in_background: true` + Monitor guidance for tasks >10s is present with foreground fallback noted
- Confirm model references use the verified ID `qwen/qwen3-coder-plus` — not `qwen3.6-plus` or any unverified alias

### Review Guidance — `skills/forge.md`  (legacy flat skill)
- Verify it is consistent with `skills/forge/SKILL.md` or marked deprecated with a pointer to the canonical file
- Confirm no stale model IDs (`qwen3.6-plus`, `gemma-4-31b`) are referenced without a validity note

### Review Guidance — `hooks/forge-delegation-enforcer.sh`
- Verify `is_read_only()` rejects `sed -i` and `awk -i inplace` before the single-word fallback match
- Confirm `forge -p "…"` invocations are rewritten with: valid RFC 4122 UUID `--conversation-id`, `--verbose`, and stdout/stderr prefix pipe (`[FORGE]` / `[FORGE-LOG]`)
- Verify read-only Brain-role commands (`git status`, `ls`, `grep`, `cat`, `find`) pass through unmodified
- Confirm `permissionDecision: deny` JSON shape matches the Claude Code PreToolUse hook contract: `hookSpecificOutput.{hookEventName, permissionDecision, permissionDecisionReason}` — not `decision` / `modifiedCommand`
- Verify `updatedInput.command` is used for Bash rewrites (not `modifiedCommand`)

### Review Guidance — `hooks/forge-progress-surface.sh`
- Verify it parses the `STATUS:` block from Forge output (ANSI-stripped)
- Confirm it emits `[FORGE-SUMMARY]` as `additionalContext` to the transcript
- Verify the `/forge-stop` hint is surfaced after each task
- Confirm the 20-line STATUS cap is enforced

### Review Guidance — delegation lifecycle skills
- Verify only the canonical 4-skill surface remains: `codex-delegate`, `codex-stop`, `forge-delegate`, `forge-stop`
- Verify removed skill files stay deleted: `skills/codex/SKILL.md`, `skills/codex-history/SKILL.md`, `skills/forge-history/SKILL.md`
- Verify stop workflows only clear marker state and do not delete conversation indexes

### Review Guidance — `CHANGELOG.md`
- Verify the new release entry is present, dated correctly, uses the correct version
- Verify it accurately lists all Added, Changed, and Fixed items
- Confirm no placeholder text ("TODO", "TBD", template stubs) remains

### Review Guidance — Final diff
- `git diff <prev-tag>...HEAD` — confirm no unintended changes, no debug code, no temp workarounds left in
- Confirm no `qwen3.6-plus` references outside historical audit records

---

### Structure Check (run once, after the loop is clean)

1. **Plugin manifest accuracy**: `_integrity` SHA-256 hashes in `.claude-plugin/plugin.json` match the actual files:
   ```bash
   shasum -a 256 skills/forge/SKILL.md
   shasum -a 256 hooks/forge-delegation-enforcer.sh
   shasum -a 256 hooks/forge-progress-surface.sh
   shasum -a 256 output-styles/forge.md
   shasum -a 256 skills/forge-stop/SKILL.md
   shasum -a 256 skills/codex-delegate/SKILL.md
   shasum -a 256 skills/codex-stop/SKILL.md
   shasum -a 256 install.sh
   shasum -a 256 hooks/hooks.json
   ```
   Any mismatch = manifest must be refreshed before release.

2. **Skills directory**: Every directory under `skills/` contains a `SKILL.md`. No orphaned `.md` files at the `skills/` root that aren't referenced.

3. **Docs directory structure**: Verify `docs/` contains: `ARCHITECTURE.md`, `CHANGELOG.md`, `CICD.md`, `TESTING.md`, `PRD-Overview.md`, `pre-release-quality-gate.md`. Flag any missing or orphaned docs.

4. **Naming consistency**: Verify consistent spelling and casing across `skills/forge/SKILL.md`, `README.md`, `CHANGELOG.md`, and `.claude-plugin/plugin.json`. Check: skill name (`/forge`, `sidekick:forge`), Forge binary name (`forge`), config paths (`.forge/conversations.idx`, `~/.forge/.forge.toml`).

5. **Test file coverage**: Verify every hook and canonical skill has a corresponding test file in `tests/`:
   - `hooks/forge-delegation-enforcer.sh` → `tests/test_forge_enforcer_hook.bash`
   - `hooks/forge-progress-surface.sh` → `tests/test_forge_progress_surface.bash`
   - `skills/forge-stop/SKILL.md` → `tests/test_forge_skill.bash`
   - `skills/codex-delegate/SKILL.md` + `skills/codex-stop/SKILL.md` → `tests/test_codex_skill.bash`

6. **No orphaned files**: Check for files with no inbound references and no clear documented purpose.

### Security Pre-Check (run once, after the loop is clean)

1. **No hardcoded credentials**: Search all changed files:
   ```bash
   grep -rn "sk-or-\|Bearer [a-zA-Z0-9]" skills/ hooks/
   grep -rn "api_key\s*=\s*['\"][a-zA-Z0-9]" skills/ hooks/
   ```

2. **No model IDs in credential position**: Verify no file stores an OpenRouter model ID in a field named `api_key`, `token`, or `secret`.

3. **Forge credentials path**: Verify `skills/forge/SKILL.md` reads the OpenRouter key from `~/forge/.credentials.json` using the list-format schema `[{id, auth_details}]` — not the legacy flat dict schema. (Forge uses `~/forge/`, not `~/.forge/` — no leading dot.)

4. **SKILL.md credential scope**: Verify no SKILL.md ever instructs Claude to display, log, or echo retrieved API key values into the transcript — only to verify the key exists.

5. **Hook output safety**: Verify `forge-delegation-enforcer.sh` and `forge-progress-surface.sh` never write Forge task output (which may contain repo secrets or partial code) to any world-readable path.

### Completion

After the review loop produces zero accepted items AND the structure + security checks pass:

1. **MANDATORY** — invoke `/superpowers:verification-before-completion` via the Skill tool.
   Running verification commands manually is NOT a substitute for invoking this skill.
   You need BOTH: (a) run the actual verification commands, AND (b) invoke the skill so
   `record-skill.sh` tracks it. Do NOT record the stage marker until BOTH are done.
2. Write the marker:
   ```bash
   mkdir -p ~/.claude/.sidekick
   echo "quality-gate-stage-1" >> ~/.claude/.sidekick/quality-gate-state
   ```

**Exit criteria**: Zero accepted items from `/superpowers:receiving-code-review` on two consecutive loop passes, structure and security checks clean, verification skill invoked, marker written.

---

## Stage 2 — Big-Picture Consistency Audit

**Goal**: All components are consistent and correct as a whole system. No dimension can have unresolved gaps.

Spawn 5 parallel audit agents. Collect all findings. Fix all issues. Re-run until **two consecutive clean passes** across all 5 dimensions.

### Dimension A — Skill and Hook Consistency

Audit the full Forge delegation chain: `SKILL.md → enforcer hook → progress-surface hook → stop skill`:

- **Activation flow**: The activation sequence described in `skills/forge/SKILL.md` (health check → `/forge` marker → hook armed) matches what `forge-delegation-enforcer.sh` actually checks for the marker
- **UUID injection**: `SKILL.md` says not to add `--conversation-id` manually; `forge-delegation-enforcer.sh` injects it automatically. These two instructions are consistent and not contradictory.
- **Fallback ladder**: The L1/L2/L3 escalation triggers in `SKILL.md` match the ladder structure; no step references a command or file that doesn't exist
- **Completion markers**: `[FORGE]`, `[FORGE-LOG]`, `[FORGE-SUMMARY]` markers are used consistently across `SKILL.md`, both hooks, and `output-styles/forge.md`
- **Delegation lifecycle skills**: `/forge-stop` and `/codex-stop` are referenced in canonical skill files. No stale references.
- **No obsolete references**: Search all files for removed commands, deprecated paths, old model IDs (`qwen3.6-plus`, `gemma-4-31b-it` without context), or old API key schemas

### Dimension B — Test Suite Coverage

Audit test coverage across all test files:

- `tests/run_all.bash` runs all non-live suites and exits non-zero on any failure
- `tests/run_release.bash` chains all six tiers (unit + integration → Forge smoke → Forge live E2E → Code marketplace install → Code smoke → Code live E2E) with fail-fast stage aborts
- Every material branch in `forge-delegation-enforcer.sh` is exercised by `test_forge_enforcer_hook.bash` and/or `test_v12_coverage.bash`
  - Verify: `sed -i` / `awk -i inplace` rejection, `>> append` pass/deny, `> /dev/null` passthrough, env-var prefix before `forge -p`, unclassified mutating deny
- Every `STATUS:` block parsing path in `forge-progress-surface.sh` is exercised by `test_forge_progress_surface.bash`
  - Verify: 20-line STATUS cap, stdout-only fallback, ANSI stripping
- `tests/test_plugin_integrity.bash` validates all `_integrity` SHA-256 hashes against live files
- `tests/smoke/run_smoke.bash` gates on `SIDEKICK_LIVE_FORGE=1` and exits 0 cleanly without it
- `tests/run_live_e2e.bash` gates on `SIDEKICK_LIVE_FORGE=1` and validates the full patch-and-verify cycle

### Dimension C — Security Chain

Audit the end-to-end security posture of the Forge delegation flow:

- **Hook output truncation**: `forge-progress-surface.sh` caps STATUS output at 20 lines — no unbounded Forge output reaches the transcript
- **Credential file path**: The credentials path used in `skills/forge/SKILL.md` (`~/forge/.credentials.json`) is the correct current path (Forge's config dir is `~/forge/`, not `~/.forge/` — no leading dot)
- **Credentials schema**: The list-format extraction `[{id, auth_details}]` is correctly documented — not the legacy flat dict. Both schemas are not simultaneously supported without explicit disambiguation.
- **Forge subprocess isolation**: Verify the enforcer hook does not pass any Claude session context (API keys, current project path beyond CWD) to the `forge -p` subprocess
- **`.forge/conversations.idx` scope**: Index rows contain UUID, human tag, task hint (≤80 chars, tabs/newlines stripped) — no credential values, no full prompt text

### Dimension D — Plugin Manifest and Installation

Audit `.claude-plugin/plugin.json` and `install.sh`:

- **Version field**: Matches the release version being cut
- **SHA-256 accuracy**: Every hash in `_integrity` matches the live file (`tests/test_plugin_integrity.bash` must pass green)
- **Skill paths**: `"skills": "./skills/"` resolves correctly; `skills/forge/SKILL.md` exists at that path
- **Output styles**: `"outputStyles": "./output-styles/"` resolves correctly; all referenced files exist
- **Hook registration**: Both `PreToolUse` (enforcer) and `PostToolUse` (progress-surface) hooks are registered in `plugin.json` with correct matchers and paths
- **`install.sh`**: Forge install flow is correct for the current Forge version (binary path, agent config, `.forge.toml` defaults); no references to deprecated install steps

### Dimension E — Forge CLI Compatibility

Audit compatibility with the current Forge CLI version:

- **`--conversation-id` format**: UUID injection in the enforcer hook produces lowercase RFC 4122 format — validated by `tests/smoke/run_smoke.bash`
- **Removed surfaces**: Verify deleted skill surfaces (`codex`, `codex-history`, `forge-history`) are absent from runtime packaging and tests.
- **`forge conversation stats <uuid> --porcelain`**: Syntax is current
- **`.forge.toml` defaults**: Values documented in `SKILL.md` (`token_threshold=80000`, `eviction_window=0.20`, `retention_window=6`, `max_tokens=16384`) still match Forge's current defaults or are intentionally overridden
- **Agent template**: `.forge/agents/forge.md` has `tools: ["*"]` in frontmatter — the missing-tools bug must not regress

### Completion

After two consecutive clean passes across all 5 dimensions:

1. Invoke `/superpowers:verification-before-completion`
2. Write the marker:
   ```bash
   mkdir -p ~/.claude/.sidekick
   echo "quality-gate-stage-2" >> ~/.claude/.sidekick/quality-gate-state
   ```

**Exit criteria**: Two consecutive clean passes, no consistency gaps remain, marker written.

---

## Stage 3 — Public-Facing Content Refresh

**Goal**: Everything users see is accurate, complete, and reflects the current release.

**Dispatch steps 1–4 in parallel** — spawn one subagent per surface simultaneously. Collect all findings, fix all issues, then proceed to Step 5.

### Step 1 — GitHub Repository Metadata *(parallel)*

- **Description**: Verify the GitHub repo description accurately reflects current capabilities
- **Topics/tags**: Verify `claude-code`, `forge`, `forgecode`, `terminal-agent`, `coding-agent`, `openrouter`, `orchestration`, `sidekick` are present. Remove stale tags.
- **Homepage URL**: Verify it points to the correct URL
- **README preview**: No broken images, no dead badge URLs, no dead links

### Step 2 — README.md *(parallel)*

Read `README.md` in full and verify/update:

- **Version**: Version badge or header matches the release being cut
- **Description**: Accurately reflects current Forge delegation capabilities
- **Install command**: Copy-pasteable, tested, resolves to current URL
- **Models table**: Lists the verified model ID (`qwen/qwen3-coder-plus`), not any unverified alias
- **Testing section**: Documents the 3-tier pyramid (unit → smoke → live E2E) and the `SIDEKICK_LIVE_FORGE=1` gate
- **All links**: Every link resolves

### Step 3 — docs/help/ (Help Center) *(parallel)*

Read the help site pages and verify/update:

- **Getting Started**: Install steps, activation sequence, and health check output match current behaviour
- **Core Concepts**: 5-field prompt format, fallback ladder, AGENTS.md loop are accurately described
- **Delegation Workflow**: UUID auto-injection noted; no instruction to add `--conversation-id` manually
- **Command/skill reference**: `/forge-stop` and `/codex-stop` syntax matches the canonical `skills/*/SKILL.md` files
- **Troubleshooting**: Known errors (402 insufficient credits, 429 rate limit, PATH not found, missing `tools: ["*"]`) are present and current

### Step 4 — CHANGELOG.md *(parallel)*

Verify the new release entry:

- **Version header**: Matches the tag being created (e.g., `## 1.3.0 — YYYY-MM-DD`)
- **Date**: Correct release date
- **Changes**: All new features, fixes, and behaviour changes listed accurately
- **No placeholder text**: No "TODO", "TBD", or unfilled sections
- **Previous entries intact**: No prior entries accidentally modified

### Step 5 — Test Gate *(sequential — after steps 1–4 complete and fixes applied)*

Run the full test suite and confirm clean:

```bash
bash tests/run_all.bash
```

All suites in `tests/run_all.bash` must pass with 0 failures. Then push to main and wait for CI green before proceeding.

### Completion

1. Invoke `/superpowers:verification-before-completion`
2. Write the marker:
   ```bash
   mkdir -p ~/.claude/.sidekick
   echo "quality-gate-stage-3" >> ~/.claude/.sidekick/quality-gate-state
   ```

**Exit criteria**: All public-facing content accurate and current, `run_all.bash` passes, CI green on main, marker written.

---

## Stage 4 — Security Audit (SENTINEL)

**Goal**: No security issues in the skill instruction set or hook scripts. A compromised SKILL.md or hook could cause Claude to exfiltrate data, bypass safety checks, or execute arbitrary commands under the guise of Forge delegation.

**Dispatch in parallel** — run `/anthropic-skills:audit-security-of-skill` targeting the plugin root AND spawn one subagent per target below simultaneously. Collect all findings, fix all blocking issues, then re-run until clean.

### Target 1 — `skills/forge/SKILL.md` *(parallel)*

This file controls Claude's behaviour during every Forge delegation session.

1. **Prompt injection surface**: Review every section for content that could be manipulated by Forge task output to alter Claude's subsequent behaviour. The highest-risk surface is the AGENTS.md extraction loop — verify Claude treats Forge output as DATA to be summarised, not as instructions to execute.

2. **Credential handling**: Verify `SKILL.md` never instructs Claude to display, log, transmit, or include in any prompt the contents of the OpenRouter API key retrieved from `~/.forge/.credentials.json`. The skill should verify the key exists; it must not read the key value into context.

3. **Forge subprocess scope**: Verify `SKILL.md` does not instruct Claude to pass any session-level secrets (other API keys, current project's `.env`, etc.) to `forge -p` as part of the task prompt.

4. **Fallback L3 scope**: Verify the L3 Take Over fallback (Claude acts directly) is scoped to the failing subtask only — it must not grant Claude broad file-system write access outside the project directory.

5. **Injection budget enforcement**: Verify the skill injection budget (≤2 skills) cannot be exceeded by a crafted Forge task output that includes skill invocation instructions in its STATUS block.

### Target 2 — `hooks/forge-delegation-enforcer.sh` *(parallel)*

This hook intercepts ALL Bash, Write, Edit, and NotebookEdit tool calls when `/forge` mode is active.

1. **Command rewrite safety**: Verify the UUID injection rewrite cannot be bypassed by a crafted `forge -p` invocation that already contains `--conversation-id` with a non-UUID value. The hook should overwrite or reject, not append a second flag.

2. **Read-only bypass**: Verify the `is_read_only()` function cannot be fooled by commands like `cat file | tee -a output.txt` (appears read-only, actually writes). The pipe target should be considered.

3. **Marker file path**: Verify the `/forge` marker path is a fixed constant in the hook — not read from any environment variable or Forge output that could be manipulated.

4. **No code execution from Forge output**: Verify the hook never `eval`s or sources any content derived from Forge subprocess output.

5. **Hook exit codes**: Verify the hook exits 0 (pass) or produces a valid `permissionDecision: deny` JSON — never a bare non-zero exit that could be misinterpreted by the harness.

### Target 3 — `hooks/forge-progress-surface.sh` *(parallel)*

This hook parses Forge task output and emits structured summaries to the transcript.

1. **Output truncation enforced**: Verify the 20-line STATUS cap cannot be exceeded by a Forge task that outputs a STATUS block with embedded newlines or ANSI sequences designed to expand after stripping.

2. **No instruction leakage**: Verify the hook does not include raw Forge output in the `additionalContext` payload beyond the STATUS block — full Forge output (which may contain file diffs, secrets, or injected instructions) must not reach the transcript.

3. **Task hint sanitisation**: Verify tab and newline characters are stripped from the task hint written to `.forge/conversations.idx` — a crafted task description must not be able to inject false rows into the index.

### Completion

After all three targets are clean with no blocking issues:

1. Fix every finding. Blocking issues (prompt injection path, credential leak, hook bypass) must be fixed before proceeding.
2. Invoke `/superpowers:verification-before-completion`
3. Write the marker:
   ```bash
   mkdir -p ~/.claude/.sidekick
   echo "quality-gate-stage-4" >> ~/.claude/.sidekick/quality-gate-state
   ```

**Exit criteria**: Zero blocking security findings, all three targets pass clean, marker written.

---

## Release

After all 4 markers are written to `~/.claude/.sidekick/quality-gate-state`,
and after the full Forge/Codex live pyramid has been run twice:

```bash
# Verify all 4 distinct markers are present (handles duplicated rows)
count=$(grep -oE '^quality-gate-stage-[1-4]$' ~/.claude/.sidekick/quality-gate-state | sort -u | wc -l | tr -d ' ')
[ "$count" -eq 4 ] || { echo "Quality gate incomplete: $count/4 stages present"; exit 1; }

# Create the GitHub release
gh release create v<version> \
  --repo alo-exp/sidekick \
  --title "Sidekick v<version>" \
  --notes-file CHANGELOG.md \
  --latest
```

**Skipping is not permitted.** No stage may be abbreviated or marked complete without performing the checks. If time pressure requires a release, document the skipped checks explicitly as known risks in the release notes and schedule a follow-up patch release after completing the audit.

# Changelog

## 1.2.3 — 2026-04-24

### SENTINEL hardening ship + v1.3 milestone planning

Catches up the release tag to include the v1.2.2 SENTINEL defense-in-depth changes (which were committed after the v1.2.2 tag was cut) and adds the v1.3 milestone planning artifacts. No user-facing behavior change.

- **`hooks/forge-delegation-enforcer.sh`**: SENTINEL L1/L2 — anchored env-prefix substitution and UUID validation (previously missed the v1.2.2 tag)
- **`hooks/forge-progress-surface.sh`**: SENTINEL I1 — secret redaction for sk-, gha_, github_pat_, xoxe- tokens and Authorization headers
- **`tests/test_v12_coverage.bash`**: 6 new/fixed unit tests covering UUID validation, env-prefix anchoring, and extended token redaction
- **`.planning/REQUIREMENTS.md`**: 22 v1.3 requirements defined (ENF-01–08, PATH-01–03, REFACT-01–04, TEST-V13-01–04, MAN-V13-01–03)
- **`.planning/ROADMAP.md`**: Phase 10 added with 10 success criteria for Enforcer Hardening + Helper Extraction
- **`.claude-plugin/plugin.json`**: version bumped to 1.2.3; integrity hashes refreshed

## 1.2.2 — 2026-04-18

### SENTINEL defense-in-depth hardening

Follow-up patch on v1.2.1. Closes three LOW/INFO SENTINEL findings that were documented as deferred hardening opportunities in the v1.2.1 audit. No user-facing behavior change — plugin API surface is unchanged.

- **`hooks/forge-delegation-enforcer.sh` (L1)**: anchored the `forge -p` rewrite substitution to the command head via `strip_env_prefix`. Previously used `${cmd/forge /…}` which matched the first `forge ` occurrence anywhere in the command; a crafted leading env-var value (e.g. `FOO="forge x" forge -p …`) could host the `--conversation-id` injection inside that value. Now the env-prefix is lifted out, the rewrite is applied to the command head only, and the env-prefix is re-prepended verbatim.
- **`hooks/forge-delegation-enforcer.sh` (L2)**: added `validate_uuid` helper with strict `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$` regex. Both injection sites (`rewrite_forge_p` and `decide_bash`) now validate the UUID before splicing into the rewritten shell command; malformed input (test override or future regression) triggers a hard deny rather than a silent metacharacter splice.
- **`hooks/forge-progress-surface.sh` (I1)**: added defensive perl redaction pass on the extracted STATUS block before it lands in the `additionalContext` envelope. Scrubs `Authorization:` values (including `Bearer <token>`), `api_key=` / `api-key:` values, and common provider tokens (`sk-…`, `ghp_/ghs_/gho_/ghu_/ghr_…`, `xoxb-/xoxa-…`). Rule ordering uses `${1}[REDACTED]` (not `$1[REDACTED]`, which perl parses as array subscript and silently wipes the line).
- **`tests/test_v12_coverage.bash`**: 6 new tests covering valid-UUID injection, shell-metacharacter rejection, uppercase-UUID rejection, env-prefix anchoring with `forge`-in-value attack vector, Authorization-header redaction, and multi-provider-token redaction (api_key + ghp + xoxb in one STATUS block).
- **`.claude-plugin/plugin.json`**: refreshed `forge_delegation_enforcer_sha256` and `forge_progress_surface_sha256` integrity hashes; version bumped to 1.2.2.
- **`.planning/STATE.md`**: refreshed milestone pointer to reflect v1.2.0 + v1.2.1 shipped, v1.2.2 in flight (STATE.md previously lagged two patch releases).

All 14 test suites green (18/18 in the v1.2 coverage suite including the 6 new tests).

## 1.2.1 — 2026-04-18

### Pre-release quality gate

- **`docs/pre-release-quality-gate.md`**: 4-stage pre-release audit document (Code Review Triad → Big-Picture Consistency → Public-Facing Content → SENTINEL). Stages 1/3/4 dispatch reviewers in parallel; Stage 1 loops to zero accepted items across `/engineering:code-review`, `/gsd-code-review`, `/superpowers:requesting-code-review`, and `/superpowers:receiving-code-review`. Each stage writes a `quality-gate-stage-N` marker to `~/.claude/.sidekick/quality-gate-state` after `/superpowers:verification-before-completion`. Kept separate from Silver Bullet's own state file so its tamper hook does not reject the writes.
- **`hooks/validate-release-gate.sh`**: PreToolUse guard registered in `plugin.json` (matcher `Bash`). Intercepts `gh release create` Bash calls and emits the canonical `permissionDecision: deny` envelope unless all four stage markers are present (anchored whole-line match) in the Sidekick state file. Gated on `tool_name == "Bash"` so reads/edits of files containing the literal string don't trigger false blocks. Uses `jq` (fails closed if absent). Marker set is keyed to `STAGE_COUNT` in the hook — update both files together if stages are added or removed.

### Consistency sweep

- **Model ID drift fixed**: Swept `qwen/qwen3-coder-plus` / display name "Qwen3 Coder Plus" across all shipped surfaces (`README.md`, `context.md`, `skills/forge.md`, `.claude-plugin/marketplace.json`, `docs/index.html`, `docs/help/getting-started/`, `docs/help/reference/`, `docs/help/concepts/`, `docs/help/search.js`, `docs/internal/pre-release-quality-gate.md`). Eliminated the hallucinated `qwen/qwen3.6-plus` / "Qwen 3.6 Plus" from user-visible content. `CHANGELOG.md` retains the historical v1.1.2 reference.
- **`_integrity` manifest refresh**: Added `validate_release_gate_sha256` entry (for `hooks/validate-release-gate.sh`) and refreshed `forge_md_sha256` to match the updated `skills/forge.md`. `tests/test_plugin_integrity.bash` now asserts the new hook's hash.
- **`tests/test_validate_release_gate_hook.bash`**: 7-scenario unit suite for the release-gate hook (non-Bash pass-through, non-target Bash pass-through, no-markers deny, all-markers pass, anchored match excluding stage-10, partial-markers deny with correct missing list, `hookEventName=PreToolUse` envelope). Wired into `tests/run_all.bash`.
- **`tests/test_forge_e2e.bash`**: Added graceful skips for "provider not available" / "login again to configure" / 401 so a stale Forge session can't fail CI; `git log --oneline` guarded with `|| true` to survive `set -euo pipefail` on empty repos.

## 1.2.0 — 2026-04-18

### Forge Delegation + Live Visibility

When `/forge` mode is active, delegation is now **harness-enforced**, not just suggested. Forge subprocess output streams into the transcript in real time and every task is durably indexed for replay.

- **PreToolUse enforcer hook** (`hooks/forge-delegation-enforcer.sh`): while the `/forge` marker exists, direct `Write`/`Edit`/`NotebookEdit` calls are blocked with a `permissionDecision: deny` reason; `Bash forge -p "…"` invocations are transparently rewritten to inject a valid RFC 4122 UUID `--conversation-id` plus `--verbose` and an output pipe that prefixes stdout with `[FORGE]` and stderr with `[FORGE-LOG]`. Read-only Brain-role commands (`git status`, `ls`, `grep`, `cat`, `find`) pass through unmodified.
- **Audit index** (`.forge/conversations.idx`): every rewritten Forge invocation appends an ISO 8601 UTC row with UUID, sidekick-`<ts>`-`<hash>` tag, and task hint. Idempotent on already-present UUIDs.
- **PostToolUse progress-surface hook** (`hooks/forge-progress-surface.sh`): after each Forge task, parses the `STATUS:` block (ANSI-stripped), emits a `[FORGE-SUMMARY]` additionalContext to the transcript, and surfaces a `/forge:replay <UUID>` hint.
- **`/forge:replay <uuid>`** (`commands/forge-replay.md`): validates the UUID, runs `forge conversation dump <uuid> --html` into `/tmp`, opens in the default browser, and renders `forge conversation stats <uuid> --porcelain` inline.
- **`/forge:history`** (`commands/forge-history.md`): renders the last 20 rows of `.forge/conversations.idx` as a markdown table joined with `forge conversation info`; prunes entries older than 30 days on each call via portable ISO 8601 lexical compare (BSD/macOS + GNU `date` both supported).
- **Output style** (`output-styles/forge.md`): narration contract for Claude's prose while `/forge` mode is active. Documents the `[FORGE]` / `[FORGE-LOG]` / `[FORGE-SUMMARY]` markers as reference-only — Claude Code output styles shape assistant prose, not raw tool output by line prefix.
- **SKILL.md STEP 5 + 6**: documents auto-injection of `--conversation-id` + `--verbose` (don't add manually), and `run_in_background: true` + Monitor guidance for tasks >10s with a foreground fallback for Bedrock/Vertex/Foundry hosts.
- **Plugin manifest v1.2.0**: directory-style registration for `commands/` and `output-styles/`, `PostToolUse` hook added alongside existing `PreToolUse`, `_integrity` refreshed with SHA-256 for `skills/forge/SKILL.md`, both hook scripts, the output style, and both new command files.
- **Test suite expansion**: +47 assertions across 3 new suites — enforcer hook (20), progress surface (7), v1.2 slash commands (12), v1.2 E2E integration (8). Run via `bash tests/run_all.bash`.

### Pre-release hardening (post-initial-tag)

- **Classifier fix** (`hooks/forge-delegation-enforcer.sh`): `is_read_only()` now explicitly rejects `sed -i` and `awk -i inplace` before the single-word fallback match. Surfaced by the coverage audit — the original 20-assertion enforcer suite only exercised the canonical read-only list and missed the edge case where a mutating flag on an otherwise-read-only first token slipped past `decide_bash`'s ordered dispatch. Plugin manifest `_integrity.forge_delegation_enforcer_sha256` refreshed.
- **v1.2 coverage gap suite** (`tests/test_v12_coverage.bash`): 12 new assertions targeting the enforcer + progress-surface branches not yet exercised (sed -i / awk -i inplace, `>>` append, `> /dev/null` passthrough in three forms, env-var prefix before `forge -p`, 80-char task-hint truncation, tab/newline strip in the hint column, unknown tool_name silent passthrough, broader read-only allowlist, unclassified mutating deny, 20-line STATUS cap, stdout-only summary fallback).
- **Live-Forge smoke harness** (`tests/smoke/run_smoke.bash`): 3 assertions gated behind `SIDEKICK_LIVE_FORGE=1` — `forge --version`, a minimal `forge -p` round-trip that forces a `STATUS:` block, and UUID-format validation on the auto-injected conversation id. Skipped cleanly (exit 0) when the env var is absent so it is safe to wire into CI.
- **Live E2E driver** (`tests/testapp/` + `tests/run_live_e2e.bash`): seeded-buggy Python testapp (`add` returns `a - b`) with pure-stdlib unittest. Driver copies the app to `$TMPDIR`, verifies the baseline fails, sends a real 5-field prompt through `forge -C <sandbox> -p`, asserts `calc.py` was patched to `a + b`, `sub` was not touched, and all 3 tests now pass. 180s timeout wrapper; sandbox preserved for inspection. Also gated behind `SIDEKICK_LIVE_FORGE=1`.
- **Pre-release gate** (`tests/run_release.bash`): chains `run_all.bash` → `smoke/run_smoke.bash` → `run_live_e2e.bash` with fail-fast stage aborts. Without the env var, stage 1 runs and stages 2+3 skip cleanly (exit 0). Before tagging: `SIDEKICK_LIVE_FORGE=1 bash tests/run_release.bash`.
- **README Testing section**: documents the 3-tier pyramid, the release-gate invocation, and the CI-vs-local split.

### Corrections merged from research

- `--conversation-id` must be a valid lowercase RFC 4122 UUID (Forge 2.11.3 rejects custom formats). The human-readable `sidekick-<ts>-<hash>` label is preserved as a separate column in `.forge/conversations.idx`.
- Claude Code PreToolUse hook JSON uses `hookSpecificOutput.{hookEventName, permissionDecision, permissionDecisionReason, updatedInput.command}` — not `decision` / `modifiedCommand` as drafted in the spec.
- Output styles do not style tool output by prefix; the narration contract was reframed accordingly.

## 1.1.2 — 2026-04-17

- **Fix (CRITICAL)**: Forge agent template was missing the `tools: ["*"]` frontmatter field. Without it, Forge provisioned the agent with zero tools and any model — no matter how capable — emitted XML/markdown text that looked like tool calls but never executed. `/forge` delegation reported `STATUS: SUCCESS` while no files were actually created. Fixed in `.forge/agents/forge.md` and in the Plan 01-03 template so fresh installs inherit the correct configuration.
- **Fix (BLOCKING)**: Replaced the invalid OpenRouter model ID `qwen/qwen3.6-plus` (which does not exist) with the verified `qwen/qwen3-coder-plus` across README, `skills/forge.md` (8 references), `.forge.toml`, and internal planning artifacts. With the invalid ID set as the active model, the API silently omitted tool schemas, which compounded the Bug 1 symptom. After the fix, `grep -rn "qwen3.6-plus" .` returns only historical audit records.
- **Docs**: README Providers and Models table now shows `Qwen3 Coder Plus` (`qwen/qwen3-coder-plus`) as the recommended default; capability descriptor updated from "vision" to "tool-use" to match the model's actual feature set.

## 1.1.1 — 2026-04-17

- **Fix**: `/forge` activation health check #3 (credentials present) now correctly validates Forge's current credentials schema (`[{id, auth_details}, ...]`). Prior check only matched the legacy flat `{api_key}` schema, causing false-negative activation failures on valid installs. Both schemas now supported; malformed files fail cleanly instead of producing a jq type error.

## 1.1.0 — 2026-04-13

- **Forge delegation mode** (`/forge` skill): explicit activation/deactivation with health check and session state
- **Fallback ladder**: 3-level automatic recovery — L1 Guide (reframe + retry), L2 Handhold (atomic subtask decomposition, max 3 attempts), L3 Take over (Claude acts directly + structured DEBRIEF)
- **Skill injection**: 4 bootstrap skills (testing-strategy, code-review, security, quality-gates) auto-injected based on task type; injection budget enforced (≤2 skills)
- **AGENTS.md mentoring loop**: post-task extraction of corrections, preferences, patterns; 3-tier write (global/project/session log); 2-phase deduplication (exact + semantic)
- **Token optimization**: task prompts capped at 2,000 tokens; validated `.forge.toml` compaction defaults (token_threshold=80000, eviction_window=0.20, retention_window=6, max_tokens=16384)
- **Help Center** (`docs/help/`): 5-page static documentation site with search, dark/light theme, covering Getting Started, Core Concepts, Delegation Workflow, Command Reference, and Troubleshooting
- **Test suite**: 8 automated test suites, 70 assertions covering all Phase 1-4 additions

## 1.0.0 — 2026-04-10

- Initial release as **Sidekick** plugin (renamed from Forge plugin)
- First sidekick: **Forge** (ForgeCode) — skill name `forge`
- Auto-install ForgeCode on SessionStart (one-time, .installed sentinel)
- OpenRouter setup guidance (Qwen 3.6 Plus default)
- Full Claude orchestration skill: delegates coding/file/git tasks to Forge
- AGENTS.md context continuity pattern
- Model switching (Qwen 3.6 Plus ↔ Gemma 4 31B)
- Troubleshooting guide for common errors (402, 429, PATH)

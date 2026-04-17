---
phase: 06-delegation-enforcement-hook-audit-index
plan: 03
type: execute
wave: 3
depends_on:
  - "06-01"
  - "06-02"
files_modified:
  - hooks/forge-delegation-enforcer.sh
  - tests/test_forge_enforcer_hook.bash
  - tests/run_all.bash
autonomous: true
requirements:
  - AUDIT-01
  - AUDIT-02
  - AUDIT-03
  - AUDIT-04
  - ACT-01
  - ACT-02
  - ACT-03

must_haves:
  truths:
    - "After the enforcer hook rewrites a `forge -p` command, the file `$CLAUDE_PROJECT_DIR/.forge/conversations.idx` (falling back to `$PWD/.forge/conversations.idx` when `CLAUDE_PROJECT_DIR` is unset) gains EXACTLY ONE new line with tab-separated fields: `<ISO8601-UTC-Z>`, `<UUID>`, `<sidekick-tag>`, `<task-hint>`."
    - "The `sidekick-tag` field has the form `sidekick-<unix-timestamp>-<8-hex-chars>` and is deterministically derived from `date +%s` and the first 8 hex chars of the UUID's last segment (the last dash-delimited group). Computed in portable bash-3.2-compatible form: `tag_suffix=\"${uuid##*-}\"; tag_suffix=\"${tag_suffix:0:8}\"`."
    - "The `task-hint` field is the first 80 characters of the `-p` argument, with newlines and tabs replaced by spaces."
    - "If `.forge/conversations.idx` does not exist when the hook is about to append, the hook creates `$CLAUDE_PROJECT_DIR/.forge/` (via `mkdir -p`) and creates the idx as a zero-byte file before appending — and this creation is itself idempotent (safe to invoke repeatedly)."
    - "If the hook's DB-writable precheck (`forge conversation list >/dev/null 2>&1`) fails on the FIRST rewrite attempt after a marker-file mtime check, the hook emits `permissionDecision: \"deny\"` with a reason mentioning `forge conversation list` failure and DB lock — and does NOT create `.forge/`, does NOT create the idx, and does NOT append an idx row. (Precheck runs BEFORE `ensure_forge_dir_and_idx`.)"
    - "The DB-writable precheck runs at most once per hook-script-invocation (not once per command) and is gated behind a sentinel so repeated read-only tool calls don't trigger it; it MUST run before the FIRST rewrite attempt in a new session."
    - "The sentinel mtime comparison uses the bash built-in `-nt` test operator (`[[ \"$marker_file\" -nt \"$sentinel_file\" ]]`) — NOT `stat -c %Y` (GNU-only) or `stat -f %m` (BSD-only). Portable on bash 3.2+ across macOS and Linux."
    - "`.forge/conversations.idx` is not deleted by anything in this phase; it persists across deactivation (and there is no code path in Phase 6 that removes it)."
    - "The hook is idempotent on the idx: if the hook is invoked twice and `gen_uuid` returns the SAME UUID both times (via `SIDEKICK_TEST_UUID_OVERRIDE` in tests, or coincidentally in production), no duplicate row is written — the dedup grep inside `append_idx_row` matches the existing UUID line and skips."
    - "No arbitrary code from `$cmd` (the untrusted Bash command from Claude Code) is ever evaluated. `extract_task_hint` uses a non-eval strategy — either python3 shlex (preferred) or a conservative pure-bash grep (fallback) — and gracefully degrades to the literal string `(task hint unavailable)` if both paths fail."
    - "The new test file `tests/test_forge_enforcer_hook.bash` is wired into `tests/run_all.bash` and the full suite passes."
  artifacts:
    - path: "hooks/forge-delegation-enforcer.sh"
      provides: "Audit-index append logic, lazy idx initialization, one-shot DB-writable precheck (via -nt mtime comparison), UUID-dedup before append, eval-free task-hint extraction."
      contains: "conversations.idx"
    - path: "tests/test_forge_enforcer_hook.bash"
      provides: "Tests for idx append format, idempotency (via SIDEKICK_TEST_UUID_OVERRIDE), DB-check failure path, lazy init, and preservation after deactivation."
      contains: "test_idx_append"
    - path: "tests/run_all.bash"
      provides: "Runs the new enforcer-hook test suite as part of `bash tests/run_all.bash`."
      contains: "test_forge_enforcer_hook"
  key_links:
    - from: "hooks/forge-delegation-enforcer.sh (FORGE_P_REWRITE branch)"
      to: "$CLAUDE_PROJECT_DIR/.forge/conversations.idx"
      via: "append-one-line-after-emit-decision, gated by UUID-dedup grep"
      pattern: "conversations\\.idx"
    - from: "tests/run_all.bash"
      to: "tests/test_forge_enforcer_hook.bash"
      via: "`run_suite` invocation added alongside existing suites"
      pattern: "test_forge_enforcer_hook"
---

<objective>
Finish Phase 6: make the enforcer hook write an append-only audit row to `.forge/conversations.idx` after every rewrite, initialize the idx lazily on first use, run a one-shot `forge conversation list` DB-writable precheck (deferring activation-time checks, since the activation skill is a preservation-constrained file), guarantee preservation of the idx across `/forge:deactivate`, extend the Phase 6 test suite to cover all of the above, and wire the new suite into `tests/run_all.bash`.

Purpose: AUDIT-01..04, ACT-01..03 — the durable-history and activation-lifecycle contract for Phase 6. After this plan, Phase 6 is complete: hook enforces delegation, rewrites `forge -p` with UUID + prefixes, and every invocation leaves a persistent audit trail.
Output: A Phase-6-complete enforcer hook, a fully green `test_forge_enforcer_hook.bash` suite of ~18 assertions, and `tests/run_all.bash` that includes it.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/STATE.md
@.planning/REQUIREMENTS.md
@.planning/phases/06-delegation-enforcement-hook-audit-index/06-RESEARCH.md
@.planning/phases/06-delegation-enforcement-hook-audit-index/06-01-hook-foundation.md
@.planning/phases/06-delegation-enforcement-hook-audit-index/06-02-decision-logic.md

@hooks/forge-delegation-enforcer.sh
@tests/test_forge_enforcer_hook.bash
@tests/run_all.bash

<interfaces>
<!-- Idx row format (tab-separated, no header, newline-terminated) — from 06-RESEARCH.md §4 -->

Columns:
1. ISO8601 UTC timestamp: `date -u +%FT%TZ` → `2026-04-18T03:42:17Z`
2. UUID: the lowercase RFC 4122 UUID produced by `gen_uuid` (same UUID injected into the rewritten command)
3. Sidekick tag: `sidekick-$(date +%s)-<tag_suffix>` where `tag_suffix` is the first 8 chars of the UUID's last dash-delimited segment.
   Portable construction (bash 3.2+):
     `tag_suffix="${uuid##*-}"`   # e.g. `eeeeeeeeeeee` (last segment of UUID)
     `tag_suffix="${tag_suffix:0:8}"`  # e.g. `eeeeeeee` (positive-offset substring, works on bash 3.2)
   Example final tag: `sidekick-1776438137-eeeeeeee`.
   DO NOT use `${uuid: -8}` (negative-offset substring) — that syntax requires bash 4.0+ and fails on macOS's stock bash 3.2.
4. Task hint: first 80 chars of the `-p` argument, tabs and newlines replaced with single spaces

Example row (literal tab between fields):
  `2026-04-18T03:42:17Z\t4c2a8f1e-9b3d-4a5e-8c6f-1e2d3f4a5b6c\tsidekick-1776438137-1e2d3f4a\tRefactor utils.py to use early returns`

File location resolution (first match wins):
  1. `$CLAUDE_PROJECT_DIR/.forge/conversations.idx` if `CLAUDE_PROJECT_DIR` is set and non-empty.
  2. `$PWD/.forge/conversations.idx` as fallback.
  (Note: the hook's cwd is the invoking tool's cwd, which Claude Code sets to the project root in practice.)
</interfaces>

<activation_lifecycle_design>
<!-- DESIGN DECISION — captured here because of a preservation-constraint conflict with 06-RESEARCH.md §5 -->

Research §5 originally proposed putting the `forge conversation list` health check and `.forge/conversations.idx` init in the `/forge` activation command (`commands/forge.md` or `skills/forge.md`). HOWEVER, the Phase 6 preservation constraints explicitly forbid modifying `skills/forge.md`, `skills/forge/SKILL.md`, `commands/forge.md`, or `commands/forge-deactivate.md`.

Design pivot: move both checks to a LAZY-AT-FIRST-USE model in the enforcer hook itself.

1. **Lazy idx init (ACT-02, AUDIT-03):** Before the FIRST append in a hook invocation, `mkdir -p "$forge_dir"` and `touch -a "$idx_path"`. Idempotent and side-effect-free when the file already exists. Runs inside the FORGE_P_REWRITE branch only — read-only tool calls never touch `.forge/`.

2. **One-shot DB-writable precheck (ACT-01):** The hook maintains a sentinel file at `$forge_dir/.db_check_ok` whose mtime is compared against the marker file (`~/.claude/.forge-delegation-active`) using the bash built-in test operator `[[ "$marker_file" -nt "$sentinel_file" ]]`. This operator works on bash 3.2+ on both macOS and Linux and does NOT rely on `stat` (which differs: GNU uses `stat -c %Y`, BSD uses `stat -f %m`). If the sentinel does not exist, or if the marker file is newer than the sentinel (meaning `/forge` was re-activated since the last successful check), the hook runs `forge conversation list >/dev/null 2>&1`. On success, it creates/touches the sentinel and proceeds with the rewrite. On failure, it emits a `deny` decision with reason `Sidekick: Forge DB not writable ('forge conversation list' failed). Deactivate via /forge:deactivate, resolve the Forge state, and re-activate.` and does NOT append an idx row, does NOT create `.forge/`, does NOT rewrite.

   Execution order inside FORGE_P_REWRITE (strict): (a) `db_precheck` → if fails, deny+return; (b) `ensure_forge_dir_and_idx`; (c) generate UUID + build rewritten command; (d) `emit_decision`; (e) `append_idx_row`. Failing at (a) guarantees NOTHING under `.forge/` was created for that attempt.

3. **Preservation on deactivate (ACT-03):** Deactivation (owned by the existing `skills/forge.md` / `commands/forge-deactivate.md`, NOT modified here) only removes `~/.claude/.forge-delegation-active`. Nothing in Phase 6 deletes `.forge/` or `.forge/conversations.idx`. The sentinel `.db_check_ok` IS allowed to stay on deactivation; next activation's marker mtime will be newer and force a recheck on next use. Document this in the SUMMARY but do NOT add deactivation cleanup logic (that would require modifying a preservation-constrained file).

This pivot satisfies ACT-01, ACT-02, ACT-03 and AUDIT-03 entirely within `hooks/forge-delegation-enforcer.sh`, with no changes to activation/deactivation command files.

AUDIT-04 is a negative/design requirement (don't duplicate Forge's native storage). It is satisfied by NOT writing conversation content — only a UUID + sidekick-tag + task-hint — to the idx. There is no task for it; the plan satisfies it by construction. Documented in SUMMARY.
</activation_lifecycle_design>

<task_hint_extraction_design>
<!-- SECURITY DECISION — `$cmd` is untrusted input from Claude Code. NEVER eval it. -->

The original research draft suggested a bash fallback using `eval "set -- $cmd"`. That is an injection vector and is EXPLICITLY FORBIDDEN. A crafted command like `forge -p "$(rm -rf ~)"` would execute arbitrary code during task-hint extraction.

**Implementation (Option A — preferred):** python3 shlex as the ONLY path.

```bash
extract_task_hint() {
  local cmd="$1"
  local hint
  if command -v python3 >/dev/null 2>&1; then
    hint=$(python3 -c '
import shlex, sys
try:
    toks = shlex.split(sys.argv[1])
    if "-p" in toks:
        i = toks.index("-p")
        if i + 1 < len(toks):
            print(toks[i+1], end="")
except Exception:
    pass
' "$cmd" 2>/dev/null || true)
  fi
  if [[ -z "$hint" ]]; then
    hint="(task hint unavailable)"
  fi
  # Replace tabs/newlines with single spaces, truncate to 80 chars
  hint="${hint//$'\t'/ }"
  hint="${hint//$'\n'/ }"
  echo "${hint:0:80}"
}
```

No `eval`, no subshell word-splitting of `$cmd`. If python3 is missing, the hook emits `(task hint unavailable)` rather than invoking an unsafe fallback. Python3 is available on all officially supported platforms (macOS 10.15+, all modern Linux distros, and CI environments the repo targets); the graceful-degradation path is the safety net, not the primary code path.

**Optional Option B (pure-bash grep, non-eval) — documented but NOT used in production:** If a future phase wants to eliminate the python3 dependency, this conservative extractor is safe:

```bash
# Never used in Phase 6; kept here as future-phase reference.
printf '%s' "$cmd" | grep -oE "\-p[[:space:]]+['\"]?([^'\"]+)['\"]?" | head -1 | head -c 200
```

This approach may fail on complex quoting (e.g., embedded quotes, escaped quotes) but NEVER evals. Phase 6 chooses Option A for correctness; Option B is documented only so a future maintainer who needs to drop python3 has a known-safe path.

**Chosen for Phase 6: Option A.** Document in SUMMARY that the design rejected the eval-based fallback on security grounds.
</task_hint_extraction_design>

<preservation_constraints>
Phase 6 preservation list (repeat from 06-01, emphasized here):
- DO NOT modify: install.sh, hooks/hooks.json, skills/forge.md, skills/forge/SKILL.md, commands/forge.md (does not exist — do not create), commands/forge-deactivate.md (does not exist — do not create), README.md, CHANGELOG.md, AGENTS.md.
- DO NOT modify existing tests: test_agents_md_dedup.bash, test_fallback_ladder.bash, test_forge_e2e.bash, test_forge_skill.bash, test_fresh_install_sim.bash, test_install_sh.bash, test_plugin_integrity.bash, test_skill_injection.bash.
- DO NOT touch `_integrity` hashes in plugin.json.
- MAY modify: `tests/run_all.bash` (solely to add `run_suite` call for the new suite — no other edits).

`.forge/conversations.idx` is a runtime artifact — never source-controlled, never fixtured into the repo.
</preservation_constraints>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Implement lazy idx init, DB-writable precheck (portable -nt mtime), eval-free task-hint extraction, and UUID-deduplicated append inside the FORGE_P_REWRITE branch</name>
  <files>hooks/forge-delegation-enforcer.sh</files>
  <behavior>
    - New helper `resolve_forge_dir()` prints the forge directory path: `${CLAUDE_PROJECT_DIR:-$PWD}/.forge`.
    - New helper `ensure_forge_dir_and_idx()` runs `mkdir -p "$(resolve_forge_dir)"` and `touch -a "$(resolve_forge_dir)/conversations.idx"`. Safe to call repeatedly.
    - New helper `db_precheck()` compares mtimes of `~/.claude/.forge-delegation-active` (marker) and `$(resolve_forge_dir)/.db_check_ok` (sentinel) using the portable bash test operator `[[ "$marker_file" -nt "$sentinel_file" ]]`. NO `stat -c %Y` (GNU-only) and NO `stat -f %m` (BSD-only). If sentinel missing OR marker newer than sentinel (`-nt`): run `forge conversation list >/dev/null 2>&1`. On success, `touch "$(resolve_forge_dir)/.db_check_ok"` and return 0. On failure, return 1. If sentinel already fresh (not `-nt`), return 0 without running forge.
    - New helper `append_idx_row(uuid, task_hint)`:
      - Skip if `grep -qF "$uuid" "$(resolve_forge_dir)/conversations.idx"` matches (dedupe).
      - Build the sidekick-tag portably (bash 3.2+):
        ```bash
        tag_suffix="${uuid##*-}"          # take the UUID's last dash-delimited segment, e.g. "eeeeeeeeeeee"
        tag_suffix="${tag_suffix:0:8}"    # positive-offset substring: first 8 chars, e.g. "eeeeeeee"
        sidekick_tag="sidekick-$(date +%s)-$tag_suffix"
        ```
        DO NOT use `${uuid: -8}` — that syntax requires bash 4.0+ and fails on macOS stock bash 3.2.
      - Build the row: `printf '%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$uuid" "$sidekick_tag" "$task_hint" >> "$(resolve_forge_dir)/conversations.idx"`.
      - `task_hint` is built by the caller (see next helper).
    - New helper `extract_task_hint(cmd)` — extracts the argument of `-p`. Implementation: python3 shlex (see `<task_hint_extraction_design>` above). On python3-missing, returns the literal string `(task hint unavailable)`. NEVER evals `$cmd`. Strips leading/trailing quotes (handled by shlex naturally), replaces tabs and newlines with single spaces, truncates to 80 chars.
    - Modify the FORGE_P_REWRITE branch in `decide_bash` — strict execution order:
      1. Call `db_precheck`. If it returns non-zero, emit `permissionDecision: "deny"` with reason `Sidekick: Forge DB not writable ('forge conversation list' failed). Deactivate via /forge:deactivate, resolve the Forge state, and re-activate.` and exit 0. Do NOT call `ensure_forge_dir_and_idx`, do NOT create `.forge/`, do NOT append an idx row, do NOT rewrite.
      2. Call `ensure_forge_dir_and_idx` (only reached if precheck passed).
      3. Generate UUID (via `gen_uuid` — which honors `SIDEKICK_TEST_UUID_OVERRIDE` per 06-01) and build rewritten command (existing logic from 06-02).
      4. Emit the `allow` decision with `updatedInput.command` (existing logic from 06-02).
      5. Call `append_idx_row "$uuid" "$(extract_task_hint "$cmd")"`.
      - Ordering note: the append runs AFTER `emit_decision`. If `emit_decision` fails, the append doesn't run — good. If the append fails, the decision is already emitted and the hook exits 0 — acceptable (the tool call proceeds; audit trail gets a gap, which is better than blocking delegation on a filesystem hiccup).
    - Graceful handling: `append_idx_row` wraps its file I/O in `{ … ; } || true` so a filesystem error never causes the hook to exit non-zero after a successful decision emit.
  </behavior>
  <action>
    Edit `hooks/forge-delegation-enforcer.sh` to add the five helpers and extend the FORGE_P_REWRITE branch. Keep the helpers near the top of the file, above `decide_bash`.

    For `extract_task_hint`: use the python3-shlex implementation shown in `<task_hint_extraction_design>`. This is the ONLY path — no bash fallback parser that evals `$cmd`. If python3 is unavailable at runtime, `extract_task_hint` returns `(task hint unavailable)` and the idx row is still written (with that placeholder as the task-hint field). Document this clearly in a code comment above the function pointing to `<task_hint_extraction_design>` in this plan doc.

    For the sidekick-tag suffix: use `${uuid##*-}` + `${tag_suffix:0:8}` (bash 3.2+ compatible). Add an inline code comment reminding maintainers NOT to use `${uuid: -8}` (negative-offset — bash 4+ only).

    For the DB precheck mtime comparison: use `[[ "$marker_file" -nt "$sentinel_file" ]]` — the bash built-in test operator. Add an inline code comment explaining that `stat -c` vs `stat -f` divergence between GNU/BSD is why `-nt` is used.

    Reference: AUDIT-01, AUDIT-02, AUDIT-03, ACT-01, ACT-02; 06-RESEARCH.md §4, §5, §8; `<activation_lifecycle_design>` and `<task_hint_extraction_design>` above for the preservation-compatible + security-hardened design.
  </action>
  <verify>
    <automated>
      bash -n hooks/forge-delegation-enforcer.sh \
        && grep -qE 'resolve_forge_dir|ensure_forge_dir_and_idx|db_precheck|append_idx_row|extract_task_hint' hooks/forge-delegation-enforcer.sh \
        && grep -q -- '-nt' hooks/forge-delegation-enforcer.sh \
        && grep -q 'uuid##\*-' hooks/forge-delegation-enforcer.sh \
        && ! grep -q 'eval' hooks/forge-delegation-enforcer.sh
    </automated>
  </verify>
  <done>
    Hook contains all five helpers; FORGE_P_REWRITE branch runs DB precheck FIRST (before `ensure_forge_dir_and_idx`), then ensure-init, then rewrite+emit, then append; append dedupes on UUID; filesystem failures in append never propagate out of the hook; sidekick-tag uses portable `${uuid##*-}` + `:0:8` suffix; DB precheck uses `-nt` built-in; NO `eval` anywhere in the hook.
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Add audit/activation tests to test_forge_enforcer_hook.bash and wire the suite into run_all.bash</name>
  <files>tests/test_forge_enforcer_hook.bash, tests/run_all.bash</files>
  <behavior>
    - Every new test uses the existing `HOME=$HOME_DIR` sandbox pattern AND additionally sets `CLAUDE_PROJECT_DIR=$PROJECT_DIR` to a separate `mktemp -d` so the runtime-created `.forge/` lives in the sandbox.
    - Tests added:
      - `test_idx_created_on_first_rewrite` — no `.forge/` exists yet; stub `forge` on PATH to a passing `exit 0`; feed a valid `forge -p` stdin; assert `$PROJECT_DIR/.forge/conversations.idx` exists after the invocation.
      - `test_idx_row_format` — same setup; assert the idx contains exactly one line matching regex `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z\t[0-9a-f-]{36}\tsidekick-[0-9]+-[0-9a-f]{8}\t.+$`.
      - `test_idx_row_task_hint` — feed stdin with `-p 'Refactor utils.py to use early returns'`; assert idx row field 4 begins with `Refactor utils.py` and is ≤80 chars.
      - `test_idx_append_idempotent_by_uuid` — **uses `SIDEKICK_TEST_UUID_OVERRIDE` (contract defined in 06-01) to force `gen_uuid` to return the SAME value on two successive invocations.**
        - Setup: export `SIDEKICK_TEST_UUID_OVERRIDE=deadbeef-1111-2222-3333-444455556666` in the test.
        - Stub `forge` to `exit 0`. Feed `{"tool_name":"Bash","tool_input":{"command":"forge -p \"first call\""}}` to the hook. Assert the idx now contains exactly ONE row matching the override UUID.
        - Feed `{"tool_name":"Bash","tool_input":{"command":"forge -p \"second call\""}}` to the hook (same `SIDEKICK_TEST_UUID_OVERRIDE` still in env, so `gen_uuid` returns the same UUID again). The FORGE_P_REWRITE branch WILL run (the input command does NOT contain `--conversation-id`, so the idempotent-passthrough branch does NOT short-circuit; `decide_bash` proceeds to the rewrite path, calls `gen_uuid`, and calls `append_idx_row`). The dedup grep inside `append_idx_row` matches the existing UUID line in the idx and SKIPS the append.
        - Assert: `grep -c "deadbeef-1111-2222-3333-444455556666" "$PROJECT_DIR/.forge/conversations.idx"` returns exactly `1`.
        - Inline test comment MUST explain: "Test uses SIDEKICK_TEST_UUID_OVERRIDE (test-only env var, defined in 06-01) to force two rewrite-path invocations to produce the same UUID — this is the only way to exercise the append_idx_row dedup branch. The dedup grep only fires when gen_uuid returns a UUID already present in the idx, which cannot happen probabilistically in finite test time without the override."
      - `test_db_precheck_denies_when_forge_fails` — stub `forge` on PATH as `exit 3`; ensure no pre-existing `.db_check_ok` sentinel; feed a fresh `forge -p` stdin; assert hook stdout has `permissionDecision: "deny"` with reason containing `'forge conversation list' failed`; assert `.forge/conversations.idx` was NOT created. Test MUST assert `test ! -e "$PROJECT_DIR/.forge/conversations.idx"` — the idx file must not exist at all, because precheck runs BEFORE `ensure_forge_dir_and_idx` (per the strict execution order in `<activation_lifecycle_design>`). NO ambiguity allowed: if precheck fails, the idx does not exist.
      - `test_db_precheck_runs_once_via_sentinel` — first invocation with passing `forge` stub succeeds and creates `.db_check_ok`; temporarily swap `forge` on PATH to an always-failing stub; second invocation STILL succeeds (sentinel short-circuits because `marker -nt sentinel` is false — the sentinel was just touched and is newer than or equal-mtime to the marker). Restore PATH. Third step: bump the marker's mtime to strictly newer than the sentinel's (using `touch -m` with a future timestamp — see action block for macOS/Linux portability) AND keep the failing stub; assert the precheck RE-RUNS (because `marker -nt sentinel` is now true) and denies.
      - `test_idx_preserved_across_deactivate` — simulate deactivate by `rm "$HOME_DIR/.claude/.forge-delegation-active"`; assert `.forge/conversations.idx` still exists with its prior row count. (Re-activation is implicit in the next invocation but not directly tested here.)
    - Wire into `tests/run_all.bash`: add one line after the existing `run_suite` calls:
      `run_suite "Forge delegation enforcer hook tests" "test_forge_enforcer_hook.bash"`
    - Do NOT reorder or modify other `run_suite` calls in run_all.bash.
  </behavior>
  <action>
    Add the seven new tests to `tests/test_forge_enforcer_hook.bash`. For `forge` stubbing: create a small shell script at `$HOME_DIR/bin/forge` that reads `$FORGE_STUB_EXIT` (default 0) and exits with that code; prepend `$HOME_DIR/bin` to PATH in each test's subshell. This lets a single harness function drive the stub's exit code per test.

    For `test_idx_append_idempotent_by_uuid`: export `SIDEKICK_TEST_UUID_OVERRIDE=deadbeef-1111-2222-3333-444455556666` (arbitrary but fixed test UUID) BEFORE the first hook invocation. Keep it exported for the second invocation. After both invocations, assert exactly one matching row via `[ "$(grep -c 'deadbeef-1111-2222-3333-444455556666' "$PROJECT_DIR/.forge/conversations.idx")" = "1" ]`. Unset the override at the end of the test. Reference `<test_injection_contract>` in 06-01-hook-foundation.md in an inline comment.

    For `test_db_precheck_denies_when_forge_fails`: assert the NEGATIVE — the idx MUST NOT exist after the denied precheck. Use `test ! -e "$PROJECT_DIR/.forge/conversations.idx"` (or equivalent bash `[[ ! -e ... ]]`). Do NOT accept "zero rows" as a valid alternative — the file should not be there at all. Precheck runs BEFORE `ensure_forge_dir_and_idx` per the strict execution order.

    For `test_db_precheck_runs_once_via_sentinel`: use the portable bash built-in mtime-bumping approach. To make the marker newer than the sentinel in the third step:
    ```bash
    # Portable (bash 3.2+, macOS + Linux): sleep 1 second then touch — guarantees strict > mtime on 1-second-resolution filesystems.
    sleep 1
    touch "$HOME_DIR/.claude/.forge-delegation-active"
    ```
    This avoids the `date -v` (BSD) vs `date -d` (GNU) divergence entirely. The `sleep 1` is a one-time cost acceptable in a single test. Do NOT use `stat` to verify mtimes — trust the `-nt` operator the hook itself uses.

    Edit `tests/run_all.bash` to add the one `run_suite` line (insertion point: after `run_suite "Fallback ladder tests"`, before the closing summary block). Keep alphabetical-ish grouping with other hook-related tests if a natural slot exists.

    Reference: AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04 (by construction), ACT-01, ACT-02, ACT-03; 06-RESEARCH.md §7 items 3, 8; `<test_injection_contract>` in 06-01.
  </action>
  <verify>
    <automated>
      bash tests/test_forge_enforcer_hook.bash \
        && grep -qF 'test_forge_enforcer_hook.bash' tests/run_all.bash \
        && bash tests/run_all.bash
    </automated>
  </verify>
  <done>
    `bash tests/test_forge_enforcer_hook.bash` passes with all ~19 assertions (12 from prior plans + 7 new).
    `grep test_forge_enforcer_hook tests/run_all.bash` returns one line.
    `bash tests/run_all.bash` shows `ALL SUITES PASSED` and exits 0 — all pre-existing suites continue to pass, and the new suite is included.
    `test_idx_append_idempotent_by_uuid` exercises the `append_idx_row` dedup grep branch via `SIDEKICK_TEST_UUID_OVERRIDE`.
    `test_db_precheck_denies_when_forge_fails` asserts the idx file does NOT exist (not "exists with zero rows").
  </done>
</task>

</tasks>

<requirement_coverage>
| Requirement | Task(s) | How satisfied |
|-------------|---------|---------------|
| AUDIT-01 | Task 1 (`append_idx_row`), Task 2 (`test_idx_created_on_first_rewrite`, `test_idx_row_format`) | One tab-separated line per rewrite; regex-asserted in test. |
| AUDIT-02 | Task 1 (sidekick-tag in row, portable `${uuid##*-}` + `:0:8` construction), Task 2 (regex includes `sidekick-<ts>-<8hex>`) | Tag built from `date +%s` and UUID last-segment-prefix; present in column 3; never passed to Forge; bash-3.2-compatible. |
| AUDIT-03 | Task 1 (`ensure_forge_dir_and_idx`), Task 2 (`test_idx_created_on_first_rewrite`) | Lazy init on first rewrite creates `.forge/conversations.idx` if missing — runtime-only, no source control. |
| AUDIT-04 | Task 1 (design) | Idx stores only UUID + sidekick-tag + task-hint, never conversation content. Satisfied by construction; no code task required. Documented in 06-03-SUMMARY. |
| ACT-01 | Task 1 (`db_precheck` via portable `-nt`), Task 2 (`test_db_precheck_denies_when_forge_fails`, `test_db_precheck_runs_once_via_sentinel`) | One-shot `forge conversation list` precheck at first-use; deny on failure; sentinel-gated via bash built-in `-nt` (no `stat` divergence); lazy-at-first-use design captured in `<activation_lifecycle_design>`. |
| ACT-02 | Task 1 (`ensure_forge_dir_and_idx`), Task 2 (`test_idx_created_on_first_rewrite`) | Idx initialized lazily on first use (hooks can't modify the activation skill per preservation constraints). |
| ACT-03 | Task 2 (`test_idx_preserved_across_deactivate`) | Deactivation removes only the marker file; hook never deletes `.forge/`; idx persists — verified by test. |
</requirement_coverage>

<dependencies>
**Intra-phase:**
- Depends on Plan 06-01 (hook skeleton, marker check, `gen_uuid` WITH `SIDEKICK_TEST_UUID_OVERRIDE` contract, `emit_decision`) and Plan 06-02 (FORGE_P_REWRITE branch; classifier; test scaffold).
- This is the last Phase 6 plan.

**Cross-phase:**
- Phase 7 (STYLE-04) owns the output-style switch on activation/deactivation, which also requires touching `skills/forge/SKILL.md` (currently on Phase 6's preservation list — that lifts in Phase 7). Phase 6's lazy-init design means Phase 7 can later add eager activation-time initialization if desired; no Phase 6 work needs to be undone.
- Phase 8 (MAN-04) refreshes `_integrity` hashes for all touched files including `hooks/forge-delegation-enforcer.sh`.
- Phase 9 (TEST-V12-01) extends this test file with additional integration-scope cases.
</dependencies>

<commit_plan>
Atomic commits:

1. `feat(hooks): append audit row to .forge/conversations.idx on forge -p rewrite with DB precheck and lazy init (AUDIT-01..03, ACT-01..02)`
2. `test(hooks): cover audit index format, DB precheck sentinel, idx dedup via SIDEKICK_TEST_UUID_OVERRIDE, and idx preservation on deactivate (ACT-03, AUDIT-01..03)`
3. `test(hooks): wire test_forge_enforcer_hook.bash into tests/run_all.bash`

Keep commit 3 as a single-line change to make the suite wiring reviewable in isolation.

Each commit must pass `bash tests/run_all.bash` before landing.
</commit_plan>

<testing>
Tests added by this plan (7 new, bringing `test_forge_enforcer_hook.bash` to ~19 total):
1. `test_idx_created_on_first_rewrite`
2. `test_idx_row_format`
3. `test_idx_row_task_hint`
4. `test_idx_append_idempotent_by_uuid` — uses `SIDEKICK_TEST_UUID_OVERRIDE` to force two rewrite-path invocations with the same UUID, exercising the `append_idx_row` dedup grep.
5. `test_db_precheck_denies_when_forge_fails` — strict assertion that the idx file does NOT exist when precheck fails (not "exists with zero rows").
6. `test_db_precheck_runs_once_via_sentinel` — uses `sleep 1; touch marker` to bump marker mtime portably (no `date -v`/`date -d` branching).
7. `test_idx_preserved_across_deactivate`

Plus one wiring change: `tests/run_all.bash` gains a `run_suite` line invoking the new suite.

Not covered by Phase 6 (belongs to Phase 9 TEST-V12-05 integration):
- End-to-end flow against a real Forge subprocess (stubbed in Phase 6).
- `/forge:replay <UUID>` invocation pulling from the idx file (REPLAY-01 — Phase 8).
- `/forge:history` rendering + 30-day pruning (REPLAY-03/04 — Phase 8).

**Stub mechanism for Forge:** `$HOME_DIR/bin/forge` shell script exiting `$FORGE_STUB_EXIT` (default 0). Tests prepend `$HOME_DIR/bin` to PATH.

**Test-injection env var contract (consumed here, defined in 06-01):** `SIDEKICK_TEST_UUID_OVERRIDE`. When set to a non-empty value, `gen_uuid` echoes it verbatim instead of calling `uuidgen`. Used by `test_idx_append_idempotent_by_uuid` to guarantee two invocations receive the same UUID so the dedup branch fires.
</testing>

<verification>
Manual verification after both tasks complete:
1. `bash -n hooks/forge-delegation-enforcer.sh` → exit 0.
2. `bash tests/test_forge_enforcer_hook.bash` → all ~19 assertions pass.
3. `bash tests/run_all.bash` → `ALL SUITES PASSED`, exit 0, and the output includes the line `Suite PASSED: Forge delegation enforcer hook tests`.
4. Security audit: `grep -n 'eval' hooks/forge-delegation-enforcer.sh` → no matches (the hook must not `eval` anything derived from `$cmd`).
5. Portability audit: `grep -n 'stat -c\|stat -f\|uuid: -8' hooks/forge-delegation-enforcer.sh` → no matches (we use `-nt` and `${uuid##*-}`+`:0:8` instead).
6. Simulated end-to-end (ad-hoc, outside CI):
   - `mkdir -p /tmp/sidekick-phase6-demo/.claude && touch /tmp/sidekick-phase6-demo/.claude/.forge-delegation-active`
   - `export HOME=/tmp/sidekick-phase6-demo CLAUDE_PROJECT_DIR=/tmp/sidekick-phase6-demo`
   - Create `/tmp/sidekick-phase6-demo/bin/forge` exiting 0, `chmod +x` it, prepend to PATH.
   - `echo '{"tool_name":"Bash","tool_input":{"command":"forge -p \"Phase 6 demo\""}}' | bash hooks/forge-delegation-enforcer.sh`
   - Inspect `/tmp/sidekick-phase6-demo/.forge/conversations.idx` → one tab-separated row with a UUID.
   - Re-run `rm /tmp/sidekick-phase6-demo/.claude/.forge-delegation-active` (simulate deactivate) → idx still present and untouched.
7. Preservation audit: `git diff --stat` on Phase 6 commits should show ONLY `hooks/forge-delegation-enforcer.sh`, `.claude-plugin/plugin.json` (from 06-01), `tests/test_forge_enforcer_hook.bash`, and `tests/run_all.bash`. Nothing else.
</verification>

<success_criteria>
- `tests/run_all.bash` exits 0 with `ALL SUITES PASSED`.
- `hooks/forge-delegation-enforcer.sh` implements: marker no-op, Write/Edit/NotebookEdit deny, Bash classifier (rewrite / idempotent / read-only / mutating / level-3), UUID injection, `[FORGE]`/`[FORGE-LOG]` prefix pipes, lazy `.forge/` init, one-shot DB precheck with sentinel (via portable `-nt`), UUID-deduplicated idx append, eval-free python3-shlex task-hint extraction.
- `.forge/conversations.idx` row format is `<ISO8601-UTC>\t<UUID>\t<sidekick-tag>\t<task-hint>`, one row per rewrite, no duplicates (dedup test-verified via `SIDEKICK_TEST_UUID_OVERRIDE`).
- Sidekick-tag suffix is constructed via `${uuid##*-}` + `${tag_suffix:0:8}` (bash 3.2+ compatible). NO `${uuid: -8}` anywhere.
- DB-precheck mtime comparison uses bash built-in `[[ marker -nt sentinel ]]`. NO `stat -c` or `stat -f`.
- `extract_task_hint` uses python3 shlex with graceful `(task hint unavailable)` fallback. NO `eval` anywhere in the hook.
- When DB precheck fails, `.forge/conversations.idx` is NOT created (the file does not exist — asserted strictly in `test_db_precheck_denies_when_forge_fails`).
- Deactivation preserves `.forge/conversations.idx`.
- AUDIT-04 is satisfied by design: no conversation content stored in the idx.
- Preservation constraints honored: `install.sh`, `hooks/hooks.json`, `skills/forge.md`, `skills/forge/SKILL.md`, existing tests, README, CHANGELOG, `_integrity` block, and `version` field are all unchanged.
- Phase 6 deliverable surface complete: hook, plugin registration, tests, test-runner wiring. Phases 7–9 unblocked.
</success_criteria>

<output>
After completion, create `.planning/phases/06-delegation-enforcement-hook-audit-index/06-03-SUMMARY.md` covering:
- Final helper inventory in the hook (with line ranges).
- The `extract_task_hint` implementation chosen (python3 shlex, Option A) and an explicit note that the eval-based bash fallback from the research draft was REJECTED on security grounds (`$cmd` is untrusted input). Record observed behavior on tricky inputs (e.g., `forge -p "it's complicated"` — shlex handles the embedded apostrophe correctly).
- The DB-precheck sentinel mtime comparison — how the portable bash built-in `[[ marker -nt sentinel ]]` was chosen to avoid GNU/BSD `stat` divergence. Note any 1-second mtime-resolution quirks observed on macOS (HFS+/APFS) and how tests worked around them (`sleep 1; touch`).
- The sidekick-tag suffix portability fix — switched from `${uuid: -8}` (bash 4+) to `${uuid##*-}` + `${tag_suffix:0:8}` (bash 3.2+). Record the failing symptom on macOS stock bash that motivated the fix.
- The `SIDEKICK_TEST_UUID_OVERRIDE` test-injection contract (defined in 06-01) and its role in making the idx dedup branch testable. Note that the override is strictly test-only and never used in production code paths or documentation.
- A documented statement of AUDIT-04 compliance (content lives in Forge's `.forge.db`; idx is only a lookup index).
- Explicit note that ACT-04 (output-style switch) is NOT in Phase 6 — it's Phase 7.
- Any deviations from the lazy-at-first-use design that were forced by implementation realities, and a pointer to the research §5 that this design intentionally differs from (and why — preservation constraints).
- A handoff note to Phase 7: "ACT-04 output-style switching will require modifying skills/forge/SKILL.md, which is no longer on the preservation list starting in Phase 7."
</output>

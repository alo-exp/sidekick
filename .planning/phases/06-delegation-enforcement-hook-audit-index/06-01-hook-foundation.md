---
phase: 06-delegation-enforcement-hook-audit-index
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - hooks/forge-delegation-enforcer.sh
  - .claude-plugin/plugin.json
  - tests/test_forge_enforcer_hook.bash
autonomous: true
requirements:
  - HOOK-01
  - HOOK-02
  - HOOK-08
  - HOOK-09

must_haves:
  truths:
    - "The enforcer hook script exists at hooks/forge-delegation-enforcer.sh, is executable (chmod +x), and has a #!/usr/bin/env bash shebang."
    - "plugin.json registers a PreToolUse hook with matcher 'Write|Edit|NotebookEdit|Bash' pointing at ${CLAUDE_PLUGIN_ROOT}/hooks/forge-delegation-enforcer.sh."
    - "Running the hook with stdin JSON while ~/.claude/.forge-delegation-active does NOT exist produces exit 0, empty stdout, empty stderr (true no-op)."
    - "Running the hook with malformed stdin JSON produces exit 2 with a one-line stderr diagnostic (hard precondition violation path)."
    - "A helper produces lowercase RFC 4122 UUIDs from `uuidgen | tr 'A-Z' 'a-z'` and is unit-tested to match regex ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$. The helper ALSO honors the `SIDEKICK_TEST_UUID_OVERRIDE` env var for deterministic injection in tests (when set and non-empty, the helper echoes its value verbatim and skips uuidgen)."
    - "The tests/test_forge_enforcer_hook.bash file exists, follows the repo's existing bash test harness style (see tests/test_forge_skill.bash), and at minimum asserts: no-op when marker absent, exit 2 on malformed JSON, UUID helper output validity, and UUID helper honors SIDEKICK_TEST_UUID_OVERRIDE."
  artifacts:
    - path: "hooks/forge-delegation-enforcer.sh"
      provides: "PreToolUse hook skeleton: strict-mode bash, stdin JSON parse via jq, marker-file check, dispatch stub on tool_name, UUID helper function (with SIDEKICK_TEST_UUID_OVERRIDE test-injection contract), exit-code contract."
      contains: "set -euo pipefail"
    - path: ".claude-plugin/plugin.json"
      provides: "PreToolUse hook registration (matcher Write|Edit|NotebookEdit|Bash) alongside existing SessionStart hook in hooks.json (NOT moved into plugin.json — see note)."
      contains: "PreToolUse"
    - path: "tests/test_forge_enforcer_hook.bash"
      provides: "Phase 6 test harness for the enforcer hook (continues in plans 06-02 and 06-03)."
      contains: "test_noop_when_marker_absent"
  key_links:
    - from: "plugin.json"
      to: "hooks/forge-delegation-enforcer.sh"
      via: "PreToolUse registration with ${CLAUDE_PLUGIN_ROOT} path prefix"
      pattern: "PreToolUse.*forge-delegation-enforcer\\.sh"
    - from: "hooks/forge-delegation-enforcer.sh"
      to: "~/.claude/.forge-delegation-active"
      via: "marker-file existence check (test -f) gating all decision logic"
      pattern: "\\.forge-delegation-active"
---

<objective>
Lay the foundation for the Forge delegation enforcer hook: a new bash script at `hooks/forge-delegation-enforcer.sh` that parses PreToolUse JSON from stdin, checks the mode-active marker, and exits as a no-op when delegation mode is inactive. Ship the exit-code contract (0 = JSON decision or no-op; 2 = hard precondition violation), a reusable lowercase-UUID helper (with a documented test-injection env var), and plugin.json registration so the hook is wired into Claude Code. Create the Phase 6 test file and cover the trivial assertions now.

Purpose: HOOK-01 (hook registered), HOOK-02 (no-op when inactive), HOOK-08 (valid UUID generation), HOOK-09 (exit-code discipline) are the invariants every downstream plan depends on. Getting them right here prevents plans 06-02 and 06-03 from being rewritten.
Output: A runnable-but-permissive hook (never blocks, never rewrites — decision logic lands in 06-02) that Claude Code recognizes, plus a UUID utility (with deterministic test-override) and a live test file.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/STATE.md
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/phases/06-delegation-enforcement-hook-audit-index/06-RESEARCH.md

@hooks/hooks.json
@.claude-plugin/plugin.json
@tests/test_forge_skill.bash

<interfaces>
<!-- Claude Code PreToolUse hook contract (from 06-RESEARCH.md §1). Do NOT re-derive. -->

Hook stdin (JSON):
```
{
  "tool_name": "Write" | "Edit" | "NotebookEdit" | "Bash",
  "tool_input": { ... tool-specific fields ... }
}
```

Hook stdout (JSON, via exit 0) — canonical decision shape:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow" | "deny",
    "permissionDecisionReason": "<reason>",
    "updatedInput": { "command": "<rewritten bash>" }
  }
}
```

Exit codes:
- 0 + empty stdout → pass-through (no decision)
- 0 + JSON stdout → decision applied
- 2 + stderr → hard precondition failure (malformed input, tool unavailable)

Spec correction: the v1.2 spec's `{"decision":"approve","modifiedCommand":"..."}` shape is WRONG. Use the `hookSpecificOutput` shape only.
</interfaces>

<test_injection_contract>
<!-- Documented contract consumed by 06-03 tests for idx-dedup verification -->

`gen_uuid` honors ONE test-only environment variable for deterministic injection:

- `SIDEKICK_TEST_UUID_OVERRIDE` — when set and non-empty, `gen_uuid` echoes this value verbatim (lowercased) and returns 0 without invoking `uuidgen`. Intended ONLY for the test suite. Must not be referenced by any production code path, documentation, or user-facing surface outside the hook script's `gen_uuid` helper.

Reference implementation:
```bash
gen_uuid() {
  if [[ -n "${SIDEKICK_TEST_UUID_OVERRIDE:-}" ]]; then
    echo "$SIDEKICK_TEST_UUID_OVERRIDE"
    return 0
  fi
  uuidgen | tr 'A-Z' 'a-z'
}
```

Rationale: Plan 06-03's `test_idx_append_idempotent_by_uuid` needs two hook invocations to produce the SAME UUID so the dedup grep in `append_idx_row` actually runs. Without this override, every `gen_uuid` call yields a fresh UUID and the dedup branch is never exercised. The override is test-only; production callers never set it.

Contract for downstream plans:
- Plan 06-02 tests MAY use the override for deterministic rewrite-output assertions (optional — the existing regex-match approach already works).
- Plan 06-03's `test_idx_append_idempotent_by_uuid` MUST use the override (required for the test to be meaningful).
</test_injection_contract>

<preservation_constraints>
DO NOT modify any of the following in this plan:
- install.sh
- hooks/hooks.json (SessionStart hook — register PreToolUse in plugin.json instead)
- skills/forge.md
- skills/forge/SKILL.md
- Any existing test file under tests/ (add a NEW file, do not edit existing)
- README.md, CHANGELOG.md, AGENTS.md
- _integrity hashes in plugin.json (Phase 8 owns the version bump + hash refresh; this plan adds the hooks block only)

The ONLY new file in Phase 6 is `hooks/forge-delegation-enforcer.sh`.
The ONLY existing files touched in Phase 6 are: `.claude-plugin/plugin.json` (add hooks registration — additive) and any NEW test file.
</preservation_constraints>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Create enforcer hook skeleton with strict-mode bash, stdin parsing, marker-file no-op, and UUID helper (with test-injection override)</name>
  <files>hooks/forge-delegation-enforcer.sh</files>
  <behavior>
    - Hook is executable (chmod 0755) and starts with `#!/usr/bin/env bash`.
    - Hook enables strict mode: `set -euo pipefail; IFS=$'\n\t'`.
    - Hook requires `jq` on PATH; if missing, emit a one-line stderr message and exit 2.
    - Hook reads all of stdin into a variable and parses it with `jq -r '.tool_name'` and `jq -c '.tool_input'`. If parsing fails (jq non-zero) OR `tool_name` is empty/null, exit 2 with stderr `forge-delegation-enforcer: malformed PreToolUse JSON on stdin`.
    - Marker check: if `! test -f "$HOME/.claude/.forge-delegation-active"`, exit 0 immediately with no stdout.
    - Dispatch stub: based on `tool_name`, branch into placeholder functions `decide_write_edit`, `decide_bash`, and `decide_notebook_edit`. In this plan every branch simply exits 0 with no output (pass-through). Plan 06-02 fills in the real decision logic.
    - Function `gen_uuid()` — implementation:
      ```bash
      gen_uuid() {
        if [[ -n "${SIDEKICK_TEST_UUID_OVERRIDE:-}" ]]; then
          echo "$SIDEKICK_TEST_UUID_OVERRIDE"
          return 0
        fi
        uuidgen | tr 'A-Z' 'a-z'
      }
      ```
      Prints a lowercase RFC 4122 UUID. Honors `SIDEKICK_TEST_UUID_OVERRIDE` as a test-only injection contract (see `<test_injection_contract>`). Called by no branches in this plan but defined and available to sourcing tests (used by 06-02 and 06-03).
    - Function `emit_decision(decision, reason, updated_command_or_empty)` builds the `hookSpecificOutput` JSON via jq (never string-concat) and prints to stdout. Defined here; callers land in 06-02.
  </behavior>
  <action>
    Create `hooks/forge-delegation-enforcer.sh` with the structure described in <behavior>. Use `jq -n --arg ... --arg ... '{hookSpecificOutput: {hookEventName:"PreToolUse", permissionDecision:$d, permissionDecisionReason:$r}}'` for `emit_decision`; when a rewritten command is supplied, merge `updatedInput: {command: $c}` into the same object using jq's `+` operator with a second `--arg c`.

    Implement `gen_uuid` EXACTLY as shown in <behavior> — the `SIDEKICK_TEST_UUID_OVERRIDE` guard MUST be the first statement in the function so tests can force a deterministic value. Add an inline comment above the function pointing to `<test_injection_contract>` in this plan doc and flagging the override as test-only.

    Reference: 06-RESEARCH.md §1 (canonical JSON shape, exit-code rules), §2 (UUID format constraint), §5 (marker file path); `<test_injection_contract>` above.

    After writing, `chmod +x hooks/forge-delegation-enforcer.sh`.
  </action>
  <verify>
    <automated>
      bash -n hooks/forge-delegation-enforcer.sh \
        && test -x hooks/forge-delegation-enforcer.sh \
        && head -1 hooks/forge-delegation-enforcer.sh | grep -q '^#!/usr/bin/env bash$' \
        && grep -q 'SIDEKICK_TEST_UUID_OVERRIDE' hooks/forge-delegation-enforcer.sh
    </automated>
  </verify>
  <done>
    Hook file exists, is executable, has correct shebang, passes `bash -n` syntax check, defines `gen_uuid` (with `SIDEKICK_TEST_UUID_OVERRIDE` guard) and `emit_decision` functions, and the marker-absent branch exits 0 with no output.
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Register the PreToolUse hook in plugin.json without disturbing existing SessionStart wiring</name>
  <files>.claude-plugin/plugin.json</files>
  <behavior>
    - `.claude-plugin/plugin.json` gains a top-level `hooks` object (if absent) with a `PreToolUse` array containing a single entry.
    - The entry shape mirrors Claude Code's plugin hooks contract: `{ "matcher": "Write|Edit|NotebookEdit|Bash", "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/forge-delegation-enforcer.sh\"" } ] }`.
    - The existing SessionStart hook registration in `hooks/hooks.json` is NOT moved or duplicated. Both files coexist.
    - The existing `version`, `_integrity`, `skills`, and all other fields in plugin.json are preserved byte-identical (use jq or targeted edit, not a full rewrite).
    - `_integrity.forge_md_sha256` etc. are NOT updated in this plan — Phase 8 owns the version bump and hash refresh.
    - `python -c 'import json; json.load(open(".claude-plugin/plugin.json"))'` succeeds (valid JSON).
  </behavior>
  <action>
    Edit `.claude-plugin/plugin.json` to insert the `hooks.PreToolUse` array. Preferred tool: `jq` with `--argjson` to inject the object, writing through a temp file to avoid truncation. Alternative: hand-edit preserving key order.

    Do NOT bump the `version` field (stays at `1.1.0` until Phase 8).
    Do NOT touch any `_integrity` hash.
    Do NOT remove or rename any existing field.

    Reference: 06-RESEARCH.md §1 (hook contract) and §6 (preservation constraints).
  </action>
  <verify>
    <automated>
      python3 -c 'import json,sys; p=json.load(open(".claude-plugin/plugin.json")); assert "hooks" in p and "PreToolUse" in p["hooks"] and any("forge-delegation-enforcer.sh" in h["hooks"][0]["command"] for h in p["hooks"]["PreToolUse"]), "PreToolUse registration missing"; assert p["version"]=="1.1.0", "version must not be bumped in Phase 6"; print("OK")'
    </automated>
  </verify>
  <done>
    plugin.json is valid JSON, contains a PreToolUse entry referencing the enforcer hook with matcher `Write|Edit|NotebookEdit|Bash`, version is still `1.1.0`, and `_integrity` block is untouched.
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: Scaffold tests/test_forge_enforcer_hook.bash with the foundation assertions (including UUID test-override contract)</name>
  <files>tests/test_forge_enforcer_hook.bash</files>
  <behavior>
    - New test file follows the style of `tests/test_forge_skill.bash` (same shebang, same `pass`/`fail` counter pattern, same exit-on-fail convention).
    - Provides a `HOME_DIR=$(mktemp -d)` sandbox and runs the hook with `HOME="$HOME_DIR"` so the real `~/.claude/.forge-delegation-active` is never touched.
    - Test 1 (no-op when marker absent): ensures `$HOME_DIR/.claude/.forge-delegation-active` does not exist; pipes `{"tool_name":"Write","tool_input":{"file_path":"/tmp/x","content":"y"}}` to the hook; asserts exit 0 and empty stdout.
    - Test 2 (exit 2 on malformed JSON): pipes the literal string `not json` to the hook; asserts exit 2 and non-empty stderr containing `malformed`.
    - Test 3 (UUID helper output validity): sources the hook or invokes `bash -c 'source hooks/forge-delegation-enforcer.sh; gen_uuid'` (whichever the skeleton allows without side effects — see NOTE below); asserts output matches `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`.
    - Test 4 (UUID helper honors SIDEKICK_TEST_UUID_OVERRIDE): sources the hook with `SIDEKICK_TEST_UUID_OVERRIDE=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee` in env and invokes `gen_uuid`; asserts the output is exactly `aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee` (the override value, not a freshly generated UUID).
    - File is executable; on success prints `PASSED: test_forge_enforcer_hook` and exits 0; on any failure prints the failing assertion and exits non-zero.
    - NOTE on sourcing: the hook's main entry is gated by `[[ ${BASH_SOURCE[0]} == "$0" ]] && main "$@"` (or equivalent) so the test can source it without triggering stdin-read. If the skeleton from Task 1 doesn't already gate main(), the test spawns a subshell that calls `gen_uuid` via a small runner script in $HOME_DIR.
    - This new test file is NOT yet wired into `tests/run_all.bash` in this plan (wiring lands in 06-03 after the file covers all Phase 6 behavior).
  </behavior>
  <action>
    Create `tests/test_forge_enforcer_hook.bash` implementing the four tests above. Model the scaffold (counter vars, `pass()`/`fail()` helpers, cleanup trap) on `tests/test_forge_skill.bash` — read that file first and match its conventions so the new suite looks native.

    If Task 1's hook main() isn't gated for sourcing, either (a) add a source-guard to the hook as part of this task, or (b) run `gen_uuid` via `bash -c "$(grep -A5 '^gen_uuid' hooks/forge-delegation-enforcer.sh); gen_uuid"`. Prefer (a) for cleanliness.

    Test 4 specifics: `bash -c 'source hooks/forge-delegation-enforcer.sh; SIDEKICK_TEST_UUID_OVERRIDE=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee gen_uuid'` OR the equivalent with the env var set in the calling test shell before invoking the sourced function. Include an inline comment in the test body referencing `<test_injection_contract>` in 06-01-hook-foundation.md.

    Reference: 06-RESEARCH.md §7 test matrix items 1 + UUID regex; `<test_injection_contract>` above.
  </action>
  <verify>
    <automated>
      chmod +x tests/test_forge_enforcer_hook.bash \
        && bash tests/test_forge_enforcer_hook.bash
    </automated>
  </verify>
  <done>
    Running `bash tests/test_forge_enforcer_hook.bash` prints four PASSED lines and exits 0. The file is NOT yet listed in `tests/run_all.bash`.
  </done>
</task>

</tasks>

<requirement_coverage>
| Requirement | Task(s) | How satisfied |
|-------------|---------|---------------|
| HOOK-01 | Task 2 | PreToolUse entry registered in plugin.json with matcher `Write\|Edit\|NotebookEdit\|Bash` pointing at the new enforcer script. |
| HOOK-02 | Task 1, Task 3 (assertion 1) | Marker-file check returns exit 0 + empty stdout when `~/.claude/.forge-delegation-active` absent; test asserts the contract. |
| HOOK-08 | Task 1 (`gen_uuid`), Task 3 (assertions 3 + 4) | `gen_uuid` uses `uuidgen | tr 'A-Z' 'a-z'`; test asserts RFC 4122 lowercase regex match AND test-injection override via `SIDEKICK_TEST_UUID_OVERRIDE` works. |
| HOOK-09 | Task 1, Task 3 (assertion 2) | Hard preconditions (malformed JSON, missing `jq`) exit 2 with stderr; normal paths will exit 0 (decision logic in 06-02). Test asserts exit 2 on bad input. |
</requirement_coverage>

<dependencies>
**Intra-phase:** None — this is the foundation plan. Plans 06-02 and 06-03 both depend on this.

**Cross-phase:**
- Phase 8 will bump `plugin.json` version to 1.2.0 and refresh `_integrity` hashes; this plan intentionally leaves both untouched so Phase 8 owns the release-surface churn.
- Phase 9's integration test will invoke the hook end-to-end; this plan's test file becomes the seed that Phase 9 extends.
</dependencies>

<commit_plan>
Atomic commits (one per task, in order):

1. `feat(hooks): scaffold forge-delegation-enforcer.sh with strict mode, stdin parse, marker no-op, and UUID helper (with test-injection override)`
2. `feat(plugin): register PreToolUse enforcer hook in plugin.json (Write|Edit|NotebookEdit|Bash)`
3. `test(hooks): add test_forge_enforcer_hook.bash with no-op, malformed-JSON, UUID-validity, and UUID-override assertions`

Each commit should pass `bash -n hooks/forge-delegation-enforcer.sh` and `python3 -m json.tool .claude-plugin/plugin.json >/dev/null`. The third commit must additionally pass `bash tests/test_forge_enforcer_hook.bash`.
</commit_plan>

<testing>
Shell-level tests written in this plan (in `tests/test_forge_enforcer_hook.bash`):
1. `test_noop_when_marker_absent` — hook returns exit 0, empty stdout, empty stderr when `~/.claude/.forge-delegation-active` is absent.
2. `test_exit2_on_malformed_json` — hook returns exit 2 with stderr containing `malformed` when stdin is not valid JSON.
3. `test_gen_uuid_format` — `gen_uuid` output matches lowercase RFC 4122 UUID regex.
4. `test_gen_uuid_honors_test_override` — with `SIDEKICK_TEST_UUID_OVERRIDE=<known-uuid>` set, `gen_uuid` outputs that exact value (not a fresh UUID).

Deferred to later plans:
- Decision branches (deny Write/Edit/NotebookEdit; rewrite `forge -p`; passthrough read-only Bash; deny mutating Bash): Plan 06-02.
- Idempotency of `--conversation-id` re-injection: Plan 06-02.
- `.forge/conversations.idx` append + activation lifecycle tests: Plan 06-03 (uses `SIDEKICK_TEST_UUID_OVERRIDE` for deterministic dedup testing).
- Wiring into `tests/run_all.bash`: Plan 06-03 (once the suite is complete).
- Full integration test of the end-to-end flow: Phase 9 (TEST-V12-05).
</testing>

<verification>
After all tasks complete, manual verification:
1. `bash -n hooks/forge-delegation-enforcer.sh` → exit 0.
2. `test -x hooks/forge-delegation-enforcer.sh` → exit 0.
3. `python3 -m json.tool .claude-plugin/plugin.json | grep -q PreToolUse` → exit 0.
4. `bash tests/test_forge_enforcer_hook.bash` → exit 0, four PASSED lines.
5. `echo 'not json' | bash hooks/forge-delegation-enforcer.sh; echo "exit=$?"` → prints `exit=2` and a stderr diagnostic.
6. `HOME=/tmp/empty-$$ mkdir -p /tmp/empty-$$/.claude && echo '{"tool_name":"Write","tool_input":{}}' | HOME=/tmp/empty-$$ bash hooks/forge-delegation-enforcer.sh; echo "exit=$?"` → prints `exit=0` with no other output.
7. `SIDEKICK_TEST_UUID_OVERRIDE=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee bash -c 'source hooks/forge-delegation-enforcer.sh; gen_uuid'` → prints exactly `aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee`.
</verification>

<success_criteria>
- `hooks/forge-delegation-enforcer.sh` exists, is executable, passes syntax check.
- `gen_uuid` honors `SIDEKICK_TEST_UUID_OVERRIDE` for deterministic test injection AND defaults to `uuidgen | tr 'A-Z' 'a-z'` otherwise.
- `.claude-plugin/plugin.json` contains a valid PreToolUse registration, version unchanged at 1.1.0, `_integrity` untouched.
- `tests/test_forge_enforcer_hook.bash` runs cleanly with four PASSED assertions (including the UUID-override test).
- No preservation-constraint files modified (install.sh, hooks/hooks.json, skills/forge.md, skills/forge/SKILL.md, existing tests).
- Plan 06-02 can begin assuming: hook exists, marker-check works, `gen_uuid` + `emit_decision` helpers are available, and `SIDEKICK_TEST_UUID_OVERRIDE` is an honored test-injection contract.
- Plan 06-03 can begin assuming the `SIDEKICK_TEST_UUID_OVERRIDE` contract is in place for its idx-dedup test.
</success_criteria>

<output>
After completion, create `.planning/phases/06-delegation-enforcement-hook-audit-index/06-01-SUMMARY.md` covering: files touched, actual hook structure landed, the gating pattern used for sourcing in tests, the `SIDEKICK_TEST_UUID_OVERRIDE` test-injection contract and where it is consumed (06-03 test suite), any deviations from this plan (and why), and a pointer to Plan 06-02 for downstream context.
</output>

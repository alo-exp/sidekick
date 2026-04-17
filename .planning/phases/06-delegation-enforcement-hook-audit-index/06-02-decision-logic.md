---
phase: 06-delegation-enforcement-hook-audit-index
plan: 02
type: execute
wave: 2
depends_on:
  - "06-01"
files_modified:
  - hooks/forge-delegation-enforcer.sh
  - tests/test_forge_enforcer_hook.bash
autonomous: true
requirements:
  - HOOK-03
  - HOOK-04
  - HOOK-05
  - HOOK-06
  - HOOK-07

must_haves:
  truths:
    - "When mode is active and tool_name is Write, Edit, or NotebookEdit, the hook emits a valid `hookSpecificOutput` JSON with `permissionDecision: \"deny\"` and a `permissionDecisionReason` string that mentions `forge -p` and explains the user must delegate."
    - "When mode is active and the Bash command matches `forge -p` (with optional leading env vars or `-C <dir>` flags, and optional other flags before `-p`), the hook emits `permissionDecision: \"allow\"` with `updatedInput.command` equal to the original command with `--conversation-id <lowercase-UUID> --verbose` injected immediately after the `forge` token (before the `-p` flag) AND wrapped so stdout is piped through `sed 's/^/[FORGE] /'` and stderr through `sed 's/^/[FORGE-LOG] /' >&2` via bash process substitution."
    - "When the Bash command is `forge -p` but already contains `--conversation-id`, the hook emits NO decision (exit 0, empty stdout) — the command passes through unchanged, no second UUID injected, no second pipe wrap."
    - "When mode is active and the Bash command is a read-only command (`git status`, `git log`, `git diff`, `ls`, `grep`, `rg`, `cat`, `head`, `tail`, `find`, `wc`, `pwd`, `which`, `echo`, `test`, `[ ... ]`, `stat`, `file`, `tree`, or begins with `forge conversation` subcommands like `list`/`info`/`dump`/`stats`), the hook emits NO decision (pass-through)."
    - "When mode is active and the Bash command is a mutating command not matching the `forge -p` pattern (e.g. `git commit`, `git push`, `rm`, `mv`, `cp ... dst`, `>` redirects, `npm install`, `pip install`, `mkdir`, `touch`, `chmod`, `sed -i`, heredoc-to-file), AND `FORGE_LEVEL_3` is not `1`, the hook emits `permissionDecision: \"deny\"` with a reason mentioning `forge -p` and the `FORGE_LEVEL_3=1` override."
    - "When `FORGE_LEVEL_3=1` is set in the hook's environment, mutating Bash passes through unchanged (pass-through, not explicit allow — the Claude Code default behavior applies)."
  artifacts:
    - path: "hooks/forge-delegation-enforcer.sh"
      provides: "Full decision logic: deny Write/Edit/NotebookEdit; classify Bash into (forge-p-rewrite | forge-p-idempotent-passthrough | read-only-passthrough | mutating-deny | mutating-level3-passthrough); idempotent UUID injection; output-prefix pipe wrapping."
      contains: "permissionDecision"
    - path: "tests/test_forge_enforcer_hook.bash"
      provides: "Extended test coverage for every decision branch above."
      contains: "test_deny_write_when_active"
  key_links:
    - from: "hooks/forge-delegation-enforcer.sh (decide_bash branch)"
      to: "gen_uuid (from 06-01)"
      via: "called only in the forge-p-rewrite path; never in idempotent passthrough"
      pattern: "gen_uuid"
    - from: "hooks/forge-delegation-enforcer.sh (rewrite path)"
      to: "updatedInput.command emitted via emit_decision"
      via: "single jq invocation composes the full wrapped command string"
      pattern: "\\[FORGE\\]|\\[FORGE-LOG\\]"
---

<objective>
Implement the full decision logic for the enforcer hook: deny Write/Edit/NotebookEdit with a delegation-directing reason; classify every incoming Bash command into one of five categories (forge-p-rewrite, forge-p-idempotent-passthrough, read-only-passthrough, mutating-deny, mutating-level3-passthrough); rewrite qualifying `forge -p` commands with a lowercase UUID `--conversation-id`, `--verbose`, and stdout/stderr prefix pipes; and extend the test suite to cover every branch.

Purpose: HOOK-03 through HOOK-07 — the core behavioral contract of Phase 6. After this plan, the hook is functionally complete except for audit-index writes and activation-lifecycle concerns (Plan 06-03).
Output: A decision-complete hook script, comprehensive per-branch tests in `tests/test_forge_enforcer_hook.bash`, and documented command classification tables.
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

@hooks/forge-delegation-enforcer.sh
@tests/test_forge_enforcer_hook.bash

<interfaces>
<!-- From Plan 06-01 output — helpers already exist in the hook: -->

- `gen_uuid` — prints a lowercase RFC 4122 UUID to stdout. Honors `SIDEKICK_TEST_UUID_OVERRIDE` env var for test injection (documented in 06-01).
- `emit_decision "<decision>" "<reason>" "[updated_command_or_empty]"` — emits canonical hookSpecificOutput JSON via jq.
- Marker-file check (`$HOME/.claude/.forge-delegation-active`) already gates everything; this plan's logic only runs when marker is present.
- Dispatch stubs `decide_write_edit`, `decide_bash`, `decide_notebook_edit` exist but return pass-through. This plan replaces their bodies.

<!-- Bash command classification table (used by decide_bash) -->

Read-only command PREFIXES (first token matches — no-op pass-through):
  git status | git log | git diff | git show | git branch | git remote | git stash list | git rev-parse | git ls-files
  ls | la | ll | pwd | cd | echo | printf | cat | head | tail | wc | file | stat | tree
  grep | egrep | fgrep | rg | ag | ack | find | fd | locate | which | whereis | type | command
  test | [
  forge conversation | forge --version | forge --help
  env | printenv | whoami | id | hostname | date | uname
  diff | cmp

Mutating command PREFIXES (deny unless FORGE_LEVEL_3=1):
  rm | rmdir | mv | cp (when has 2+ args) | ln | chmod | chown | chgrp | touch | mkdir
  git add | git commit | git push | git pull | git fetch | git checkout | git reset | git rebase | git merge | git cherry-pick | git restore | git rm | git mv | git tag | git clean | git stash push | git stash pop
  npm install | npm ci | npm run | npm publish | pnpm install | pnpm add | yarn add | bundle install | pip install | pip uninstall | gem install | cargo build | cargo install | go install | go build
  tar | zip | unzip | gunzip | gzip
  curl -X (POST|PUT|DELETE|PATCH) | wget -O | wget --output
  sed -i | awk -i
  systemctl | service | launchctl | brew install | brew uninstall | apt | apt-get | yum | dnf

`forge -p` pattern (rewrite or idempotent-passthrough):
  Regex: `(^|\s|;|&&|\|\|)forge(\s+(-C\s+\S+|--cwd\s+\S+))?(\s+[^-]\S*)*\s+-p(\s|$)`
  Simplified for Phase 6 scope: the command starts with (optional env prefix like `FOO=bar`) then `forge`, optionally followed by `-C <dir>` or `--cwd <dir>`, then eventually a `-p` flag.
  Idempotency check: separate regex `(\s|^)--conversation-id(\s|=)` — if matches, pass-through.

Redirect/pipe gotcha: a command like `git log | head` starts with a read-only prefix → pass-through is fine. A command like `ls > /tmp/foo.txt` has an `>` redirect to a writable path → treat as MUTATING (deny unless Level 3). Detection: presence of unquoted `>` or `>>` outside the prefix-pipe wrapping we inject. Keep this simple: if the command contains ` > ` or ` >> ` or `| tee ` (without `-a` inside the forge-p wrapper we created), classify as mutating. Document that heredocs (`<<EOF`) and `< input.txt` are read-only inputs and do NOT trigger mutating.

Chained-command classifier gap (KNOWN, INTENTIONAL for Phase 6): the classifier matches on the FIRST token only. A chained command like `git status && rm foo` is classified by the first token (`git status`, read-only) and passes through despite containing a mutating tail. This is documented behavior — fixing it requires a proper shell-parser approach which is out of scope for Phase 6. The test suite asserts this current behavior; Phase 7+ may revisit.

NOTE: classification is INTENTIONALLY conservative. False-positive denies are recoverable (user retries via `forge -p "..."` or sets `FORGE_LEVEL_3=1`); false-negative pass-throughs violate the delegation invariant. When in doubt, deny.
</interfaces>

<output_pipe_wrapping>
<!-- From 06-RESEARCH.md §3 — exact rewrite shape -->

Given an input command like:
  forge -p "Refactor utils.py"

The rewritten `updatedInput.command` must equal (all one line, bash process substitution):
  forge --conversation-id <UUID> --verbose -p "Refactor utils.py" 2> >(sed 's/^/[FORGE-LOG] /' >&2) | sed 's/^/[FORGE] /'

Construction rules:
1. Find the `forge` token and inject ` --conversation-id <UUID> --verbose` immediately after it (before any subsequent flag). A simple `sed 's/\bforge\b/forge --conversation-id <UUID> --verbose/'` on the FIRST occurrence is sufficient for Phase 6 scope. If `forge -C <dir>` is used, the injection still belongs right after `forge` — Forge accepts the flags in any order within the pre-prompt section.
2. Append the output-pipe wrapper: `  2> >(sed 's/^/[FORGE-LOG] /' >&2) | sed 's/^/[FORGE] /'` to the end of the command.
3. The UUID is drawn from a single `gen_uuid` call — do NOT call gen_uuid twice per rewrite.
4. The rewritten command is emitted as the `updatedInput.command` string via `emit_decision` + jq (so quoting is handled safely).
5. ANSI stripping is Phase 7's job — do NOT insert an ANSI-strip sed here.

Idempotency: if the input command already contains `--conversation-id`, SKIP all of the above. Emit nothing and exit 0. This guarantees a rewritten-then-replayed command (or a user-supplied UUID) is never double-wrapped.

Exit-code note (KNOWN LIMITATION): wrapping through `sed` loses the Forge exit code. The final shell pipeline's exit code is that of the trailing `sed`, not `forge`. Phase 7 may restore the Forge exit code via `set -o pipefail` (or a `${PIPESTATUS[0]}` check). For Phase 6, this is documented in the 06-02 SUMMARY and is NOT considered a bug.
</output_pipe_wrapping>

<preservation_constraints>
Same as Plan 06-01. In particular:
- Do NOT touch skills/forge.md, skills/forge/SKILL.md, commands/forge.md (does not exist in this repo, but don't create one either), commands/forge-deactivate.md, install.sh, hooks/hooks.json, README.md, CHANGELOG.md.
- `.claude-plugin/plugin.json` is NOT modified in this plan (hook registration was done in 06-01).
- Only `hooks/forge-delegation-enforcer.sh` and `tests/test_forge_enforcer_hook.bash` are touched.
</preservation_constraints>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Implement decide_write_edit and decide_notebook_edit — deny with delegation-directing reason</name>
  <files>hooks/forge-delegation-enforcer.sh, tests/test_forge_enforcer_hook.bash</files>
  <behavior>
    - `decide_write_edit` (covers Write and Edit) emits `emit_decision "deny" "<reason>" ""` where `<reason>` is exactly: `Sidekick /forge mode is active: direct file edits are delegated to Forge. Use: Bash { command: "forge -p \"<your task description>\"" }. To temporarily bypass for Level 3 takeover, set FORGE_LEVEL_3=1 in the Bash environment.`
    - `decide_notebook_edit` emits the same deny reason (single source of truth for the reason string).
    - Both branches exit 0 after emitting.
    - Tests added to `tests/test_forge_enforcer_hook.bash`:
      - `test_deny_write_when_active` — marker present; stdin `{"tool_name":"Write","tool_input":{"file_path":"/tmp/x","content":"y"}}`; assert stdout parses as JSON with `.hookSpecificOutput.permissionDecision == "deny"` and `.hookSpecificOutput.permissionDecisionReason` contains `forge -p`.
      - `test_deny_edit_when_active` — same with `"tool_name":"Edit"`.
      - `test_deny_notebook_edit_when_active` — same with `"tool_name":"NotebookEdit"`.
  </behavior>
  <action>
    Replace the placeholder bodies of `decide_write_edit` and `decide_notebook_edit` in `hooks/forge-delegation-enforcer.sh` with calls to a shared function `deny_direct_edit()` that wraps the canonical reason string.

    Add the three tests to `tests/test_forge_enforcer_hook.bash`, following the same `HOME=$HOME_DIR` sandbox pattern introduced in 06-01. Use `jq` in the tests to parse the hook's stdout and assert field values (do NOT string-match — JSON comparison is more robust).

    Reference: HOOK-03, 06-RESEARCH.md §1 and §7 item 2.
  </action>
  <verify>
    <automated>
      bash -n hooks/forge-delegation-enforcer.sh && bash tests/test_forge_enforcer_hook.bash
    </automated>
  </verify>
  <done>
    Six assertions total in the test suite pass (3 from 06-01 + 3 new). Hook's Write/Edit/NotebookEdit branches emit a valid deny decision whose reason mentions `forge -p` and `FORGE_LEVEL_3`.
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Implement decide_bash classifier and the forge-p rewrite path with idempotency</name>
  <files>hooks/forge-delegation-enforcer.sh, tests/test_forge_enforcer_hook.bash</files>
  <behavior>
    - `decide_bash` receives the Bash command string (extracted from `tool_input.command`) and classifies it into exactly one of: FORGE_P_REWRITE, FORGE_P_IDEMPOTENT, READ_ONLY, MUTATING, MUTATING_LEVEL3.
    - Classification helpers (shell functions):
      - `is_forge_p(cmd)` — returns 0 if the command invokes `forge … -p …` (matches the regex pattern documented in <interfaces>).
      - `has_conversation_id(cmd)` — returns 0 if the command already contains `--conversation-id`.
      - `is_read_only(cmd)` — returns 0 if the first non-env-assignment token matches any prefix in the read-only list from <interfaces>. Handles leading `FOO=bar BAZ=qux <command>` env-var prefixing by stripping assignments first.
      - `is_mutating(cmd)` — returns 0 if the command matches any mutating prefix OR contains unquoted `>`/`>>` redirects targeting paths other than `/dev/null`.
    - Routing:
      - `is_forge_p` && `has_conversation_id` → pass-through (exit 0, no output).
      - `is_forge_p` && !`has_conversation_id` → rewrite path: generate UUID, inject `--conversation-id <UUID> --verbose` after `forge`, append output-pipe wrapper, emit `allow` with `updatedInput.command`.
      - `is_read_only` && !`is_forge_p` → pass-through.
      - `is_mutating` && `FORGE_LEVEL_3` != "1" → emit `deny` with the canonical reason.
      - `is_mutating` && `FORGE_LEVEL_3` == "1" → pass-through (no explicit allow — let Claude's default policy run the command).
      - None of the above (ambiguous) → deny conservatively with reason `Sidekick /forge mode: command could not be classified. Delegate via forge -p or set FORGE_LEVEL_3=1.`.
    - Rewrite construction:
      - Use bash parameter expansion or `sed` (POSIX-compatible) to inject `--conversation-id <UUID> --verbose ` immediately after the first `forge ` token. Example: `new_cmd="${cmd/forge /forge --conversation-id $uuid --verbose }"` — simple, safe, idempotent against the `has_conversation_id` pre-check.
      - Append: ` 2> >(sed '\''s/^/[FORGE-LOG] /'\'' >&2) | sed '\''s/^/[FORGE] /'\''` — note the embedded single-quotes must be escaped correctly for the jq --arg pass-through.
      - Emit via `emit_decision "allow" "Sidekick: injecting --conversation-id $uuid, --verbose, and output prefixing." "$new_cmd"`.
    - Tests added to `tests/test_forge_enforcer_hook.bash`:
      - `test_rewrite_forge_p_injects_uuid_and_pipes` — marker present; stdin Bash `forge -p 'Refactor utils.py'`; assert `.hookSpecificOutput.permissionDecision == "allow"` and `.hookSpecificOutput.updatedInput.command` matches a regex that includes `--conversation-id [0-9a-f-]{36}`, `--verbose`, `sed 's/^/\[FORGE\] /'`, and `sed 's/^/\[FORGE-LOG\] /' >&2`.
      - `test_rewrite_is_idempotent` — Bash command `forge --conversation-id aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee --verbose -p 'x'`; assert hook output is empty (pass-through).
      - `test_readonly_bash_passthrough` — assert pass-through for each of: `git status`, `ls -la`, `grep foo bar.txt`, `cat README.md`, `find . -type f`, `forge conversation list`.
      - `test_mutating_bash_denied` — assert `permissionDecision: "deny"` for each of: `rm foo`, `git commit -m "x"`, `echo hi > /tmp/out`.
      - `test_mutating_bash_level3_passthrough` — same mutating commands with `FORGE_LEVEL_3=1` in env → pass-through.
      - `test_chained_command_with_mutating_tail` — feeds `git status && rm foo`; asserts pass-through (empty stdout, exit 0). This documents the KNOWN, INTENTIONAL classifier gap: the first-token-prefix classifier sees `git status` (read-only) and does not inspect the chained mutating tail. The test comment MUST explain this is current documented behavior (not a bug) and that a proper shell-parser fix is out of Phase 6 scope. Assertion: `output` is empty AND exit code is 0.
  </behavior>
  <action>
    Implement the classifier helpers and the `decide_bash` routing in `hooks/forge-delegation-enforcer.sh`. Extract `tool_input.command` via `jq -r '.tool_input.command // empty'` from the hook's parsed stdin.

    Keep helpers POSIX-bash-compatible (avoid bash 4+ features like associative arrays — macOS ships bash 3.2).

    Add the six tests to `tests/test_forge_enforcer_hook.bash`. For the regex assertion in `test_rewrite_forge_p_injects_uuid_and_pipes`, use `grep -E` against the extracted `updatedInput.command` string (rather than trying to regex-match inside jq).

    For `test_chained_command_with_mutating_tail`, include an inline code-comment above the test body documenting: "Classifier matches first-token-prefix only; chained mutating tails pass through. This is a known, intentional Phase 6 classifier gap. See 06-02-SUMMARY.md."

    Reference: HOOK-04, HOOK-05, HOOK-06, HOOK-07; 06-RESEARCH.md §2, §3, §7 items 3, 5, 6, 7.
  </action>
  <verify>
    <automated>
      bash -n hooks/forge-delegation-enforcer.sh \
        && bash tests/test_forge_enforcer_hook.bash \
        && bash tests/test_forge_enforcer_hook.bash 2>&1 | grep -q 'test_rewrite_forge_p_injects_uuid_and_pipes' \
        && bash tests/test_forge_enforcer_hook.bash 2>&1 | grep -q 'test_chained_command_with_mutating_tail'
    </automated>
  </verify>
  <done>
    All 12 assertions in the test suite pass (6 prior + 6 new). The test runner output explicitly names `test_rewrite_forge_p_injects_uuid_and_pipes` and `test_chained_command_with_mutating_tail` (grep-confirmed in the verify block, proving these Task-2-specific tests actually ran — NOT just the 3 assertions from 06-01 before Task 2's logic landed). A manual invocation `echo '{"tool_name":"Bash","tool_input":{"command":"forge -p \"hello\""}}' | HOME=<sandbox> bash hooks/forge-delegation-enforcer.sh` produces a JSON stdout with a UUID-bearing rewritten command ending in the `[FORGE]`/`[FORGE-LOG]` pipe chain.
  </done>
</task>

</tasks>

<requirement_coverage>
| Requirement | Task(s) | How satisfied |
|-------------|---------|---------------|
| HOOK-03 | Task 1 | `decide_write_edit` / `decide_notebook_edit` emit deny with `forge -p`-directing reason; three tests assert the decision shape. |
| HOOK-04 | Task 2 | `decide_bash` FORGE_P_REWRITE branch: injects `--conversation-id <UUID> --verbose` after `forge`, appends `[FORGE]`/`[FORGE-LOG]` prefix pipes; test asserts rewritten-command regex. |
| HOOK-05 | Task 2 | Mutating classifier + `FORGE_LEVEL_3` gate; deny path tested with `rm`, `git commit`, `>` redirect; Level-3 passthrough tested. |
| HOOK-06 | Task 2 | `is_read_only` classifier covers `git status`, `ls`, `grep`, `cat`, `find`, `forge conversation …`; passthrough asserted. Also documents the chained-command classifier gap (`cmd1 && cmd2` classified by first token only) via `test_chained_command_with_mutating_tail`. |
| HOOK-07 | Task 2 | `has_conversation_id` pre-check short-circuits the rewrite path; test asserts empty stdout on pre-injected UUID command. |
</requirement_coverage>

<dependencies>
**Intra-phase:**
- Depends on Plan 06-01 (hook skeleton, `gen_uuid`, `emit_decision`, marker check, test file scaffold).
- Plan 06-03 depends on this plan (the audit-index append logic sits in the FORGE_P_REWRITE path implemented here).

**Cross-phase:**
- Phase 7 (SURF-05) will add an ANSI-strip sed to the output pipe chain. This plan's output pipe is structured so adding ` | sed 's/\x1b\[[0-9;]*m//g'` between `forge` and `sed '[FORGE] '` is a single-line insertion.
- Phase 7 may also restore the Forge exit code via `set -o pipefail` semantics (see `<output_pipe_wrapping>` exit-code note).
- Phase 9 (TEST-V12-01, TEST-V12-02) extends these tests into the integration suite.
</dependencies>

<commit_plan>
Atomic commits:

1. `feat(hooks): deny Write/Edit/NotebookEdit when /forge mode active (HOOK-03)`
2. `feat(hooks): classify Bash commands and rewrite forge -p with UUID + output pipes (HOOK-04..HOOK-07)`

Each commit must pass `bash tests/test_forge_enforcer_hook.bash` before landing. Keep the two commits sequential so a reviewer can isolate the Write/Edit policy from the Bash-classification logic.
</commit_plan>

<testing>
Added to `tests/test_forge_enforcer_hook.bash` by this plan (9 new assertions bringing the total to 12):
1. `test_deny_write_when_active`
2. `test_deny_edit_when_active`
3. `test_deny_notebook_edit_when_active`
4. `test_rewrite_forge_p_injects_uuid_and_pipes`
5. `test_rewrite_is_idempotent`
6. `test_readonly_bash_passthrough` (parametrized over 6 commands)
7. `test_mutating_bash_denied` (parametrized over 3 commands)
8. `test_mutating_bash_level3_passthrough` (parametrized over same 3 commands)
9. `test_chained_command_with_mutating_tail` (documents the first-token classifier gap — asserts current behavior, not desired behavior)

Deferred to Plan 06-03:
- `.forge/conversations.idx` append-after-rewrite test (AUDIT-01, AUDIT-02).
- Idx init on first invocation (AUDIT-03, ACT-02).
- `forge conversation list` DB-writable precheck (ACT-01) + fallback-on-failure test.
- Wiring into `tests/run_all.bash`.
</testing>

<verification>
Manual verification after both tasks complete:
1. `bash -n hooks/forge-delegation-enforcer.sh` → exit 0.
2. `bash tests/test_forge_enforcer_hook.bash` → all 12 tests pass, with output naming `test_rewrite_forge_p_injects_uuid_and_pipes` and `test_chained_command_with_mutating_tail`.
3. Ad-hoc: with a sandbox `HOME` and marker file present:
   - `echo '{"tool_name":"Write","tool_input":{"file_path":"/x","content":"y"}}' | bash hooks/forge-delegation-enforcer.sh | jq .hookSpecificOutput.permissionDecision` → `"deny"`.
   - `echo '{"tool_name":"Bash","tool_input":{"command":"forge -p \"hi\""}}' | bash hooks/forge-delegation-enforcer.sh | jq -r .hookSpecificOutput.updatedInput.command | grep -E 'forge --conversation-id [0-9a-f-]{36} --verbose -p "hi" 2> >\(sed .* \[FORGE-LOG\].*\) \| sed .*\[FORGE\]'` → exit 0.
   - `echo '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | bash hooks/forge-delegation-enforcer.sh | wc -c` → `0` (pass-through).
   - `echo '{"tool_name":"Bash","tool_input":{"command":"rm /tmp/foo"}}' | FORGE_LEVEL_3=1 bash hooks/forge-delegation-enforcer.sh | wc -c` → `0` (Level-3 pass-through). NOTE: `FORGE_LEVEL_3=1` must be placed on the `bash hooks/...` command, not on `echo`. Placing it before `echo` scopes the env var to the wrong process — `echo` does not inherit it to the hook through the pipe (each piped command gets its own env).
   - `echo '{"tool_name":"Bash","tool_input":{"command":"git status && rm foo"}}' | bash hooks/forge-delegation-enforcer.sh | wc -c` → `0` (documented classifier gap: first-token-prefix match lets chained mutating tails through).
</verification>

<success_criteria>
- All 12 assertions in `tests/test_forge_enforcer_hook.bash` pass.
- Rewritten `forge -p` commands contain exactly one `--conversation-id <UUID>`, one `--verbose`, the `[FORGE-LOG]` stderr prefix via process substitution, and the `[FORGE]` stdout prefix via pipe — all in the correct order.
- Idempotency invariant holds: running the hook on its own output produces no further rewrite.
- Mutating commands are denied by default; `FORGE_LEVEL_3=1` cleanly bypasses the deny.
- The chained-command classifier gap (`cmd1 && cmd2` classified by first token only) is explicitly tested to document current behavior and flagged for a future phase.
- No preservation-constraint files are modified.
</success_criteria>

<output>
After completion, create `.planning/phases/06-delegation-enforcement-hook-audit-index/06-02-SUMMARY.md` covering:
- The final classifier tables (read-only prefixes, mutating prefixes).
- Exact rewrite-injection mechanism used (sed vs. parameter expansion).
- Any edge cases discovered during testing (multi-line heredocs, env-var-prefixed forge invocations, chained `&&` commands).
- **Known limitation — pipe exit-code loss:** the `[FORGE-LOG]`/`[FORGE]` sed pipe wrapper swallows the Forge subprocess exit code; the final shell exit code is that of the trailing `sed`. This is intentional for Phase 6 (Phase 7 may restore it via `set -o pipefail` or a `${PIPESTATUS[0]}` check). Document the exact shape of the pipe chain that causes this and the Phase 7 handoff plan.
- **Known limitation — chained-command classifier gap:** the Bash classifier inspects only the first non-env-assignment token. Commands like `git status && rm foo` or `ls; rm foo` are classified by their first token and pass through despite containing a mutating tail. The test `test_chained_command_with_mutating_tail` asserts this current behavior. This is documented as a Phase 6 scope limit, not a bug; a proper shell-parser fix belongs to a later phase. Record both the rationale and any mitigations (e.g., the hook's Write/Edit/NotebookEdit deny covers most accidental mutations even when chained-Bash slips through).
</output>
</output>

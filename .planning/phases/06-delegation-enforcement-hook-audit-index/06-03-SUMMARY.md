# 06-03 Summary — Audit Index + Activation Lifecycle

**Plan:** 06-03-audit-index-and-activation.md
**Executed:** 2026-04-18
**Status:** Shipped — Phase 6 complete

## Files touched

| File | Change |
|------|--------|
| `hooks/forge-delegation-enforcer.sh` | EXTENDED — 5 new helpers + strict-order FORGE_P_REWRITE branch |
| `tests/test_forge_enforcer_hook.bash` | EXTENDED — 7 new Wave-3 assertions (20 total) + CLAUDE_PROJECT_DIR sandboxing + forge stub |
| `tests/run_all.bash` | EXTENDED — single `run_suite` line wiring enforcer-hook suite into full run |

## Helper inventory (lines approximate)

| Helper | Purpose |
|--------|---------|
| `resolve_forge_dir` (86-89) | Prints `${CLAUDE_PROJECT_DIR:-$PWD}/.forge` |
| `ensure_forge_dir_and_idx` (92-99) | Idempotent `mkdir -p` + `touch -a` of idx |
| `db_precheck` (107-127) | One-shot `forge conversation list` gated by `[[ marker -nt sentinel ]]` |
| `extract_task_hint` (135-157) | python3-shlex-only `-p` arg extraction; returns `(task hint unavailable)` on fallback |
| `append_idx_row` (162-188) | Tab-separated row; UUID-dedup via `grep -qF`; portable sidekick-tag |

FORGE_P_REWRITE branch (hook lines ~333-355) executes strictly: db_precheck → ensure_forge_dir_and_idx → gen_uuid + rewrite build → emit_decision → append_idx_row. Failing precheck short-circuits before any filesystem side effect.

## Design decisions captured in this wave

### `extract_task_hint` — python3 shlex only (Option A)

The research draft proposed an `eval "set -- $cmd"` fallback. This was **REJECTED on security grounds**: `$cmd` is untrusted input from Claude Code; `forge -p "$(rm -rf ~)"` would execute arbitrary code during hint extraction. The implemented path calls python3 in a subshell with `$cmd` passed as `sys.argv[1]` (never eval'd), uses `shlex.split`, and gracefully degrades to the literal string `(task hint unavailable)` if python3 is missing. Observed behavior: `forge -p "it's complicated"` — shlex handles the embedded apostrophe correctly, producing the literal hint `it's complicated`.

### Portable sentinel mtime comparison via `[[ -nt ]]`

GNU coreutils uses `stat -c %Y`; BSD/macOS uses `stat -f %m`. The bash built-in test operator `[[ marker -nt sentinel ]]` is available on bash 3.2+ across both platforms and avoids the divergence entirely. Tests also avoid `stat`: step 3 of `test_db_precheck_runs_once_via_sentinel` uses `sleep 1; touch marker` to guarantee a strict mtime bump on 1-second-resolution filesystems (HFS+/APFS).

### Sidekick-tag suffix portability

Switched from `${uuid: -8}` (bash 4+ negative-offset substring — fails on macOS stock `/bin/bash` 3.2) to `${uuid##*-}` + `${tag_suffix:0:8}` (bash 3.2+). A `grep 'uuid##\*-'` check is part of the verify block; an inline code comment at the expansion site warns maintainers against reverting to the negative-offset form.

### `SIDEKICK_TEST_UUID_OVERRIDE` test-injection contract

Defined in 06-01 and consumed here by `test_idx_append_idempotent_by_uuid`. Without the override, two `gen_uuid` calls produce different UUIDs and the `append_idx_row` dedup branch is unreachable in finite test time. The override is strictly test-only: the env-var guard is the first statement in `gen_uuid`, production callers never set it, and an inline test comment cites `<test_injection_contract>` for future maintainers.

### AUDIT-04 compliance (by construction)

The idx stores only `<ISO8601>\t<UUID>\t<sidekick-tag>\t<task-hint>` — never conversation content. Content lives exclusively in Forge's `~/forge/.forge.db`, retrievable via `forge conversation dump <uuid>`. No code task was needed; the plan satisfies AUDIT-04 by what it does *not* write.

### ACT-04 is Phase 7

Output-style switching on activation/deactivation (ACT-04) requires modifying `skills/forge/SKILL.md`, which is on Phase 6's preservation list. That restriction lifts starting Phase 7. Phase 6 does NOT address ACT-04.

## Deviations from the plan

1. Plan specified 3 atomic commits (implementation + tests + wiring). Landed as **1 atomic commit** because CLAUDE_PROJECT_DIR sandboxing + forge stub changes were needed in `test_forge_enforcer_hook.bash` BEFORE the Wave 3 tests would run — they are prerequisites, not additions. Splitting the commit would have introduced an intermediate state where Wave 2 tests fail (db_precheck runs the real forge binary and would pollute the repo with a `.forge/` directory).
2. Output-format field 4 (task hint) is truncated to 80 chars via pure-bash `${hint:0:80}` — no change from plan, just noting the exact truncation point.

## Test matrix (20/20 pass)

Plan-06-01 (4): `test_noop_when_marker_absent`, `test_exit2_on_malformed_json`, `test_gen_uuid_format`, `test_gen_uuid_honors_test_override`
Plan-06-02 (9): `test_deny_{write,edit,notebook_edit}_when_active`, `test_rewrite_forge_p_injects_uuid_and_pipes`, `test_rewrite_is_idempotent`, `test_readonly_bash_passthrough`, `test_mutating_bash_denied`, `test_mutating_bash_level3_passthrough`, `test_chained_command_with_mutating_tail`
Plan-06-03 (7): `test_idx_created_on_first_rewrite`, `test_idx_row_format`, `test_idx_row_task_hint`, `test_idx_append_idempotent_by_uuid`, `test_db_precheck_denies_when_forge_fails`, `test_db_precheck_runs_once_via_sentinel`, `test_idx_preserved_across_deactivate`

`bash tests/run_all.bash` → `ALL SUITES PASSED` with 9 suites including the new `Forge delegation enforcer hook tests` line.

## Phase 6 deliverable surface — complete

- Hook enforces delegation (Write/Edit/NotebookEdit deny, Bash classifier)
- `forge -p` rewrite injects `--conversation-id <uuid> --verbose` and output-prefix pipes
- Audit trail appends one durable row per rewrite to `.forge/conversations.idx`
- Lazy `.forge/` init on first use
- One-shot DB-writable precheck with sentinel short-circuit
- UUID-deduplicated append
- Eval-free, injection-safe task-hint extraction
- 20 green assertions across 3 waves + wired into `tests/run_all.bash`

## Handoff to Phase 7

- `skills/forge/SKILL.md` preservation restriction **lifts** in Phase 7 — ACT-04 output-style switching can now modify that file.
- PostToolUse hook (SURF-*) will parse the `STATUS:` block from `[FORGE] ` prefixed lines and emit `[FORGE-SUMMARY]` blocks (also addresses the Phase 6 pipe exit-code loss documented in 06-02-SUMMARY §3).
- Phase 7 output style depends on the `[FORGE]` / `[FORGE-LOG]` prefixes landed here — do not rename those prefix tags.

## Handoff to Phase 8

- `.claude-plugin/plugin.json` version still `1.1.0` (Phase 6 additive-only). MAN-02/MAN-04 in Phase 8 bump to `1.2.0` and refresh `_integrity.hooks_json_sha256` etc.

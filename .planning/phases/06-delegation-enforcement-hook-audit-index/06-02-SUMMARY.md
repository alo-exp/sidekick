# 06-02 Summary — Decision Logic

**Plan:** 06-02-decision-logic.md
**Executed:** 2026-04-18
**Status:** Shipped (1 atomic commit — helpers tightly couple Task 1 + Task 2)

## Files touched

| File | Change |
|------|--------|
| `hooks/forge-delegation-enforcer.sh` | EXTENDED — deny Write/Edit/NotebookEdit; Bash classifier + `forge -p` rewrite + pipe injection |
| `tests/test_forge_enforcer_hook.bash` | EXTENDED — 9 new assertions (13 total) |

## Decision surface landed

### Write / Edit / NotebookEdit
All three deny with `permissionDecision: "deny"` and a canonical reason (`DENY_EDIT_REASON`) that points the user at `forge -p "<task>"` and mentions the `FORGE_LEVEL_3=1` escape hatch.

### Bash classifier (5-way dispatch)

| Branch | Trigger | Outcome |
|--------|---------|---------|
| `FORGE_P_REWRITE` | `forge … -p …` without `--conversation-id` | `allow` + `updatedInput.command` (UUID + `--verbose` + `[FORGE]`/`[FORGE-LOG]` pipes) |
| `FORGE_P_IDEMPOTENT` | `forge … -p …` **with** `--conversation-id` already | silent pass-through (empty stdout, exit 0) |
| `READ_ONLY` | `git status`, `ls`, `grep`, `cat`, `forge conversation`, etc. | silent pass-through |
| `MUTATING` | `rm`, `git commit`, `npm install`, write-redirect, `sed -i`, etc. | `deny` with mutating reason |
| `MUTATING_LEVEL3` | Mutating classifier matched **and** `FORGE_LEVEL_3=1` in env | silent pass-through |
| Unclassified | none of the above | conservative `deny` |

### Rewrite mechanism

```bash
rewrite_forge_p() {
  local cmd uuid injected
  cmd="$1"
  uuid="$(gen_uuid)"
  injected="${cmd/forge /forge --conversation-id $uuid --verbose }"
  local pipes=" 2> >(sed 's/^/[FORGE-LOG] /' >&2) | sed 's/^/[FORGE] /'"
  printf '%s%s' "$injected" "$pipes"
}
```

`gen_uuid` produces a lowercase RFC 4122 UUID (via `uuidgen | tr 'A-Z' 'a-z'`), satisfying Forge 2.11.3's `--conversation-id` UUID validation. Flag order `forge --conversation-id <uuid> --verbose -p "<prompt>"` is preserved across rewrites.

## Classifier helper inventory

- `strip_env_prefix` — removes leading `FOO=bar ` env-var assignments before classification.
- `first_token` — returns 1- or 2-word command prefix for `git`/`forge` two-word match.
- `has_conversation_id` — regex check for an existing `--conversation-id` flag.
- `is_forge_p` — guards the rewrite branch.
- `is_read_only` — short-circuits if `has_write_redirect` matches (fix documented below).
- `has_write_redirect` — detects `>`/`>>` redirects, tolerating `2>&1`, `>/dev/null`, `2>/dev/null`.
- `is_mutating` — two-word git mutators + single-word mutators (package managers, filesystem, archives, service/package managers, network fetchers) + `sed -i` / `awk -i inplace`.

## Correction during execution

`test_mutating_bash_denied[echo hi > /tmp/out]` failed on first run because `echo` is in the read-only token list and `is_read_only` returned true before `is_mutating` was evaluated. Fix: `is_read_only` now short-circuits to non-readonly if `has_write_redirect` matches. This preserves the passthrough path for plain `echo hi` while catching the mutating redirect variant.

## Known classifier limitations (intentional, out of Phase 6 scope)

1. **First-token-prefix matching.** Chained commands like `git status && rm foo` classify on the first token only and pass through. `test_chained_command_with_mutating_tail` asserts this *documented* behavior. A proper shell-parser fix is out of Phase 6 scope — noted for a future phase.
2. **Pipe exit-code loss.** Because the rewritten command terminates in `… | sed 's/^/[FORGE] /'`, bash pipelines without `set -o pipefail` surface the final `sed` exit code (0), swallowing Forge's exit status. Observable by Claude only through the parsed STATUS block. Phase 7 PostToolUse hook will compensate by parsing `STATUS: SUCCESS` / `STATUS: FAILURE` from the Forge output for true success signal. Documented here as a known-and-accepted tradeoff for Phase 6.
3. **Env-var prefix parser is conservative.** Complex quoted env values (e.g. `FOO="a b c" cmd`) are not stripped; the prefix pattern requires unquoted values. In practice Claude Code rarely emits such forms.

## Test matrix (13 assertions pass)

1. `test_noop_when_marker_absent`
2. `test_exit2_on_malformed_json`
3. `test_gen_uuid_format`
4. `test_gen_uuid_honors_test_override`
5. `test_deny_write_when_active`
6. `test_deny_edit_when_active`
7. `test_deny_notebook_edit_when_active`
8. `test_rewrite_forge_p_injects_uuid_and_pipes`
9. `test_rewrite_is_idempotent`
10. `test_readonly_bash_passthrough` (6 commands)
11. `test_mutating_bash_denied` (3 commands)
12. `test_mutating_bash_level3_passthrough`
13. `test_chained_command_with_mutating_tail` (documents the known limitation)

## Deviations from the plan

- Plan specified 2 atomic commits (deny helpers + Bash classifier). Landed as **one atomic commit** because the test scaffold for both tasks lives in the same file, and Task 2's Bash classifier references `emit_decision`/`gen_uuid` identically to Task 1 — the split would have been artificial. No requirement coverage change.
- 06-02-SUMMARY.md (this file) was written after the commit rather than before (plan's `<output>` block). Documented retroactively; 06-03 execution will include a hook point in `decide_bash` for `append_idx_row` (already landed via `declare -f append_idx_row` gate at line 231).

## Pointers

- **06-01-SUMMARY.md** — foundation (hook skeleton, `gen_uuid`, `emit_decision`, source-guard).
- **06-03 (next)** — audit index append, DB-writable precheck, lazy `.forge/` init, `extract_task_hint`, run_all.bash wiring.

# 06-01 Summary — Hook Foundation

**Plan:** 06-01-hook-foundation.md
**Executed:** 2026-04-18
**Status:** Shipped (3 atomic commits)

## Files touched

| File | Change |
|------|--------|
| `hooks/forge-delegation-enforcer.sh` | NEW — PreToolUse hook skeleton |
| `.claude-plugin/plugin.json` | MODIFIED — added `hooks.PreToolUse` registration (additive; version unchanged at 1.1.0; `_integrity` untouched) |
| `tests/test_forge_enforcer_hook.bash` | NEW — 4-assertion test scaffold |

## Hook structure landed

The enforcer hook (`hooks/forge-delegation-enforcer.sh`) lands as a strict-mode bash script with:

- `#!/usr/bin/env bash` shebang, `set -euo pipefail`, `IFS=$'\n\t'`.
- `gen_uuid()` helper — `uuidgen | tr 'A-Z' 'a-z'` production path; honors `SIDEKICK_TEST_UUID_OVERRIDE` for deterministic test injection (guard is the first statement in the function).
- `emit_decision()` helper — builds the canonical `hookSpecificOutput` envelope via `jq -cn` (never string-concat). Three-arg signature supports optional `updatedInput.command`.
- Three dispatch stubs (`decide_write_edit`, `decide_notebook_edit`, `decide_bash`) that pass through in this plan — real logic lands in 06-02/06-03.
- `main()` — jq-precondition check → stdin read → `tool_name` parse with exit-2-on-malformed → marker file check → dispatch by `tool_name`.
- Source-guard `[[ "${BASH_SOURCE[0]}" == "${0:-}" ]] && main "$@"` so tests can source the file to exercise `gen_uuid` without triggering `main()`'s stdin read.

## Gating pattern used for sourcing in tests

The tests source the hook via `bash -c "source '${HOOK_FILE}'; gen_uuid"`. The source-guard at the bottom of the hook ensures `main()` only runs when `${BASH_SOURCE[0]}` equals `${0:-}` (direct execution), so sourcing is inert — `gen_uuid` becomes callable without side effects. This avoids the pipe-from-stdin blocking pattern and keeps the test harness simple.

## `SIDEKICK_TEST_UUID_OVERRIDE` test-injection contract

Documented in plan `<test_injection_contract>`. Production callers never set it. Consumers:

- **06-01 `test_gen_uuid_honors_test_override`** — asserts the contract itself.
- **06-03 `test_idx_append_idempotent_by_uuid`** (scheduled) — required to exercise the `append_idx_row` dedup branch: two `forge -p` invocations must produce the SAME UUID so the `grep -q` dedup check in `append_idx_row` fires. Without the override, every `gen_uuid` call yields a fresh UUID and dedup is unreachable.

Inline comment at the function references both the plan doc section and flags the override as test-only.

## Deviations from the plan

None. All three tasks executed as specified.

## Test results

`bash tests/test_forge_enforcer_hook.bash` → 4 passed, 0 failed, 0 skipped:

```
PASS test_noop_when_marker_absent
PASS test_exit2_on_malformed_json
PASS test_gen_uuid_format (uuid=<random-rfc4122>)
PASS test_gen_uuid_honors_test_override
```

Test file NOT yet wired into `tests/run_all.bash` (wiring lands in 06-03).

## Commits

1. `c4a937e` — feat(hooks): scaffold forge-delegation-enforcer.sh with strict mode, stdin parse, marker no-op, and UUID helper (with test-injection override)
2. `e4a3d5d` — feat(plugin): register PreToolUse enforcer hook in plugin.json (Write|Edit|NotebookEdit|Bash)
3. (pending this commit) — test(hooks): add test_forge_enforcer_hook.bash with no-op, malformed-JSON, UUID-validity, and UUID-override assertions

## Pointer to downstream plans

- **[06-02](./06-02-decision-logic.md)** — implements Write/Edit/NotebookEdit deny, Bash classifier, `forge -p` UUID-flag rewrite with output pipes, idempotent passthrough, FORGE_LEVEL_3 bypass. Consumes `emit_decision` and `gen_uuid` landed here.
- **[06-03](./06-03-audit-index-and-activation.md)** — implements `.forge/conversations.idx` append-on-rewrite, lazy init, one-shot DB precheck via sentinel + `[[ -nt ]]`, preservation on deactivation, full test-suite wiring. Consumes the `SIDEKICK_TEST_UUID_OVERRIDE` contract.

# Phase 9 Summary — v1.2 Test Suite

**Status:** Shipped 2026-04-18
**Milestone:** v1.2 (Forge Delegation + Live Visibility)

## Scope delivered

1. **E2E integration test** (`tests/test_forge_v12_integration.bash`, 8 assertions) — drives the full v1.2 flow in a sandboxed `HOME` + `CLAUDE_PROJECT_DIR` with a stub `forge` binary on `PATH`:
   - **Step 1:** Create the `.forge-delegation-active` marker (simulating `/forge`).
   - **Step 2:** Feed the PreToolUse enforcer a `forge -p` Bash invocation with `SIDEKICK_TEST_UUID_OVERRIDE` pinning the UUID for deterministic downstream assertion. Assert `permissionDecision=allow`, the rewritten command carries `--conversation-id <uuid> --verbose` and the `[FORGE]` / `[FORGE-LOG]` output pipe, and a row for that UUID landed in `.forge/conversations.idx`.
   - **Step 3:** Feed the PostToolUse progress-surface hook a fabricated Forge STATUS block keyed on the rewritten command. Assert the emitted `additionalContext` carries `[FORGE-SUMMARY]` + STATUS + FILES_CHANGED.
   - **Step 4:** Assert the UUID in the `/forge:replay <uuid>` hint matches the UUID injected in step 2 — the load-bearing round-trip check that ties PreToolUse, idx persistence, and PostToolUse together.
   - **Step 5:** Remove the marker and assert idx is preserved, PreToolUse becomes a no-op, PostToolUse becomes a no-op.

2. **Run-all wiring** (`tests/run_all.bash`) — Phase 7 progress-surface suite, Phase 8 commands suite, and this Phase 9 integration suite all registered.

## Design decisions

- **Stub `forge` binary on `PATH`:** the enforcer's `db_precheck` helper calls `forge conversation list`. Rather than mock the internals, the integration test drops a 2-line bash stub on PATH that exits 0 on every invocation. This lets the real hook code run unmodified inside the sandbox.
- **Deterministic UUID via env override:** `SIDEKICK_TEST_UUID_OVERRIDE` was added in Phase 6 specifically to make cross-hook round-trip assertions possible without time-based UUID matching. Step 4 is the assertion this override was designed to enable.
- **Fabricated Forge output:** the test does not actually invoke Forge — it fabricates the stdout stream the enforcer's rewrite would produce. This keeps the test fast (<1s) and hermetic, and is the right granularity: the hooks are the contract under test, not Forge itself.
- **No separate unit tests for UUID generation or idx append:** those are already covered by `test_forge_enforcer_hook.bash` (Phase 6). Phase 9 is strictly the composition test.

## Test suite totals after Phase 9

| Suite | Tests |
|-------|------:|
| install.sh unit tests | 12 |
| Plugin integrity verification | 12 |
| Fresh install simulation | 8 |
| End-to-end forge smoke tests | — |
| Forge skill structure tests | 9 |
| AGENTS.md deduplication tests | 5 |
| Skill injection tests | 7 |
| Fallback ladder tests | 7 |
| Forge delegation enforcer hook tests | 20 |
| Forge progress surface hook tests | 7 |
| Forge v1.2 slash commands tests | 12 |
| Forge v1.2 E2E integration tests | 8 |

All suites pass on 2026-04-18 via `bash tests/run_all.bash`.

## Handoffs

- Milestone v1.2 release step: CHANGELOG entry + README badge bump + git tag `v1.2.0` + STATE.md + PROJECT.md updates.

## Deviations

None.

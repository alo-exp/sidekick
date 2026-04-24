---
phase: 10-enforcer-hardening-helper-extraction
plan: 02
subsystem: infra
tags: [bash, enforcer, hook, refactoring, security, path-allowlist, mcp, chain-guard, pipe-guard]

requires:
  - phase: 10-enforcer-hardening-helper-extraction
    plan: 01
    provides: "hooks/lib/enforcer-utils.sh with 9 helper functions"

provides:
  - "hooks/forge-delegation-enforcer.sh: hardened enforcer sourcing lib, ≤300 lines (289)"
  - "Path allowlist in decide_write_edit and decide_mcp_write (PATH-01/02/03)"
  - "decide_mcp_write() function for mcp__filesystem__* tool denial (ENF-07)"
  - "Chain segment guard in decide_bash (ENF-06)"
  - "Pipe segment guard in decide_bash (ENF-08)"
  - "export_env_prefix call at top of decide_bash (ENF-04)"
  - "first_three_tokens helper in lib for correct gh sub-command classification (ENF-05 bug fix)"

affects:
  - 10-03
  - forge-delegation-enforcer

tech-stack:
  added: []
  patterns:
    - "Lib source pattern: HOOK_DIR via BASH_SOURCE[0] + source relative path"
    - "3-token matching for gh sub-commands via first_three_tokens (separate from first_token)"
    - "ENF-06/08 checks placed between is_forge_p branch and is_read_only — forge -p pipes escape scanner"

key-files:
  created:
    - tests/test_enforcer_phase10_plan02.bash
  modified:
    - hooks/forge-delegation-enforcer.sh
    - hooks/lib/enforcer-utils.sh

key-decisions:
  - "Keep first_token at 2 tokens; add first_three_tokens for gh 3-token matching — changing first_token to 3 tokens broke forge/git 2-token entries"
  - "ENF-06/08 checks placed after is_forge_p so forge -p | tee passes (is_forge_p returns early with allow before pipe scanner runs)"
  - "export_env_prefix placed at very top of decide_bash (before is_forge_p) so FORGE_LEVEL_3=1 prefix in command text is exported before any bypass check"

requirements-completed:
  - ENF-05
  - ENF-06
  - ENF-07
  - ENF-08
  - PATH-01
  - PATH-02
  - PATH-03
  - REFACT-02
  - REFACT-03

duration: 7min
completed: 2026-04-24
---

# Phase 10 Plan 02: Enforcer Rewrite Summary

**Hardened forge-delegation-enforcer.sh: sources lib, 289 lines, path allowlist, MCP dispatch, chain/pipe denial, FORGE_LEVEL_3 prefix export**

## Performance

- **Duration:** 7 min
- **Started:** 2026-04-24T13:07:14Z
- **Completed:** 2026-04-24T13:14:20Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Rewrote `hooks/forge-delegation-enforcer.sh` to source `hooks/lib/enforcer-utils.sh` (REFACT-02), removing `strip_env_prefix`, `first_token`, `is_read_only`, `has_write_redirect`, `is_mutating` inline definitions
- `rewrite_forge_p` dead function absent (REFACT-04 confirmed)
- Enforcer trimmed from 447 lines to 289 lines (REFACT-03, ≤300 target met)
- `decide_write_edit` now calls `is_allowed_doc_path` before `deny_direct_edit` — `.planning/**` and `docs/**` edits pass through (PATH-01/02/03)
- Added `decide_mcp_write()` function that applies same allowlist + deny policy to `mcp__filesystem__*` tools (ENF-07)
- Added `mcp__filesystem__write_file|edit_file|move_file|create_directory` case dispatch in `main()` (ENF-07)
- Added `export_env_prefix "$cmd"` at top of `decide_bash` before any classification — `FORGE_LEVEL_3=1 rm foo` now passes through (ENF-04)
- Added `has_mutating_chain_segment` check in `decide_bash` after `is_forge_p` — `git status && rm foo` now denied (ENF-06)
- Added `has_mutating_pipe_segment` check in `decide_bash` after chain check — `echo secret | curl` now denied; `forge -p | tee` still allowed (ENF-08)
- Fixed lib ENF-05 bug: `gh issue list` was unclassified because `first_token` returns 2 tokens but case patterns needed 3. Added `first_three_tokens` helper and updated `is_read_only`/`is_mutating` to use it for gh entries

## Task Commits

1. **Task 1 RED: Add failing tests** — `3736f6b` (test)
2. **Task 1 GREEN: Rewrite enforcer** — `934d8e4` (feat)
3. **Task 2: Fix first_three_tokens in lib** — `8f8cdcf` (fix)

## Test Results

- `tests/test_enforcer_phase10_plan02.bash`: 24/24 PASS
- `tests/test_forge_enforcer_hook.bash`: 19/19 PASS + 1 expected failure (`test_chained_command_with_mutating_tail` — intentionally fails because ENF-06 closed the Phase 6 gap; will be inverted in Plan 03)

## Files Created/Modified

- `hooks/forge-delegation-enforcer.sh` — Rewrote: sources lib, path allowlist, MCP dispatch, chain/pipe guards, export_env_prefix; 289 lines
- `hooks/lib/enforcer-utils.sh` — Added `first_three_tokens` helper; updated `is_read_only`/`is_mutating` to use 3-token matching for gh sub-commands
- `tests/test_enforcer_phase10_plan02.bash` — New: 24 behavioral assertions for all Plan 02 changes (RED/GREEN TDD cycle)

## Decisions Made

- **first_three_tokens separate helper:** Changing `first_token` to 3 tokens broke 2-token git/forge entries (`"forge conversation"` stopped matching `forge conversation list`). Solution: keep `first_token` at 2 tokens, add `first_three_tokens` for gh case patterns exclusively.
- **ENF-06/08 placement:** Chain/pipe checks placed after `is_forge_p` so `forge -p "task" | tee /tmp/log` gets the allow decision before the pipe scanner can deny it.
- **export_env_prefix before is_forge_p:** The function must run first so that `FORGE_LEVEL_3=1` in the command text prefix is exported into the hook's environment before the mutating-command bypass check at step 3.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] gh sub-command classification broken — first_token only returns 2 tokens**
- **Found during:** Task 2 inline smoke-check (`gh issue list` returned "unclassified deny")
- **Issue:** `first_token 'gh issue list'` returns `gh issue` (2 tokens). The `is_read_only`/`is_mutating` case patterns were `"gh issue list"` (3 tokens) — never matched. `forge conversation list` also broke when first tried 3-token first_token.
- **Fix:** Added `first_three_tokens` helper in lib; updated `is_read_only` and `is_mutating` to call `first_three_tokens` for the gh case block, keeping `first_token` for all other 2-token entries
- **Files modified:** `hooks/lib/enforcer-utils.sh`
- **Commit:** `8f8cdcf`

**2. [Rule 1 - Bug] first_token 3-token attempt broke forge/git 2-token entries**
- **Found during:** Same Task 2 debug session — changing `first_token` to return 3 tokens fixed gh but broke `forge conversation list` (matched as `forge conversation list` instead of `"forge conversation"`)
- **Fix:** Reverted `first_token` to 2 tokens; added separate `first_three_tokens` for the cases that need it
- **This is the same commit as above:** `8f8cdcf`

---

**Total deviations:** 1 compound auto-fix (Rule 1 — ENF-05 gh classification bug in lib)
**Impact on plan:** No scope creep. The lib bug was latent from Plan 01 (gh entries written at 3-token depth but `first_token` only returns 2). Fixing it here is correct since ENF-05 classification is required by Plan 02 smoke tests.

## Known Stubs

None — all decision paths fully wired.

## Threat Surface Scan

All surfaces covered by plan's threat model:
- T-10-05: `decide_write_edit` path allowlist — `is_allowed_doc_path` called before deny; non-allowlist denied
- T-10-06: `decide_mcp_write` — same allowlist + deny policy as Write/Edit
- T-10-07: ENF-06 chain bypass — `has_mutating_chain_segment` scans all &&/; segments; FORGE_LEVEL_3 bypass available
- T-10-08: ENF-08 pipe bypass — `has_mutating_pipe_segment` scans all | segments; is_forge_p runs first

No new network endpoints, auth paths, or schema changes introduced.

## Self-Check: PASSED

- hooks/forge-delegation-enforcer.sh: FOUND
- hooks/lib/enforcer-utils.sh: FOUND
- tests/test_enforcer_phase10_plan02.bash: FOUND
- .planning/phases/10-enforcer-hardening-helper-extraction/10-02-SUMMARY.md: FOUND
- Commit 3736f6b (test RED): FOUND
- Commit 934d8e4 (feat GREEN): FOUND
- Commit 8f8cdcf (fix lib): FOUND

---
phase: 10-enforcer-hardening-helper-extraction
plan: "04"
subsystem: testing
tags: [plugin, manifest, integrity, sha256, mcp, enforcer]

requires:
  - phase: 10-01
    provides: hooks/lib/enforcer-utils.sh (new file whose hash is now tracked)
  - phase: 10-02
    provides: forge-delegation-enforcer.sh (updated, hash recomputed)
  - phase: 10-03
    provides: test suite (run_all.bash updated, v1.3 coverage suite added)

provides:
  - plugin.json bumped to v1.3.0
  - PreToolUse[0].matcher extended with 4 MCP filesystem tool names (ENF-07 layer 1)
  - _integrity.forge_delegation_enforcer_sha256 refreshed for Phase 10 changes
  - _integrity.enforcer_utils_sha256 new key for hooks/lib/enforcer-utils.sh
  - test_plugin_integrity.bash: version check accepts 1.3.x, enforcer-utils hash verified

affects: [phase-11, release-v1.3]

tech-stack:
  added: []
  patterns:
    - "Two-layer MCP enforcement: manifest matcher (layer 1) + hook case dispatch (layer 2)"
    - "_integrity tracks all security-relevant hook files including lib helpers"

key-files:
  created: []
  modified:
    - .claude-plugin/plugin.json
    - tests/test_plugin_integrity.bash

key-decisions:
  - "Hashes computed after all Phase 10 file edits are final — no circular dependency risk since plugin.json self-hash is accepted per SENTINEL audit"
  - "MCP filesystem tool names added to PreToolUse matcher to activate hook at layer 1; layer 2 case dispatch already handled these in Plan 02"
  - "enforcer_utils_sha256 key placed immediately after forge_delegation_enforcer_sha256 in _integrity for logical grouping"

patterns-established:
  - "Version bump + integrity refresh happens in final wave of each phase; tests guard correctness"
  - "check_v12_hash helper in test_plugin_integrity.bash extended for each new integrity-tracked file"

requirements-completed:
  - MAN-V13-01
  - MAN-V13-02
  - MAN-V13-03

duration: 5min
completed: "2026-04-24"
---

# Phase 10 Plan 04: Manifest v1.3.0 + MCP Matcher + Integrity Refresh Summary

**plugin.json bumped to v1.3.0 with all 4 MCP filesystem tools in the PreToolUse matcher and refreshed SHA-256 hashes for enforcer + new enforcer-utils.sh; test_plugin_integrity.bash extended to verify enforcer-utils hash and accept 1.3.x version — run_all.bash ALL SUITES PASSED (153 tests, 0 failures)**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-04-24T13:25:00Z
- **Completed:** 2026-04-24T13:30:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Bumped plugin.json version from 1.2.4 to 1.3.0
- Extended PreToolUse[0].matcher to include all 4 MCP filesystem tool names, completing ENF-07 layer 1 (manifest layer) — previously only layer 2 (case dispatch) was present
- Recomputed forge_delegation_enforcer_sha256 (Phase 10 Plans 01+02 modified the file) and added new enforcer_utils_sha256 key for hooks/lib/enforcer-utils.sh
- Updated test_plugin_integrity.bash: added check_v12_hash for enforcer_utils_sha256, updated version pattern from 1.2.* to 1.3.*
- Full suite passed: 153 tests across 14 suites, 0 failures

## Task Commits

1. **Task 1: Bump plugin.json — version, matcher, integrity hashes** - `d89fbd3` (feat)
2. **Task 2: Update test_plugin_integrity.bash for v1.3 and run full suite** - `4d8288b` (test)

**Plan metadata:** (docs commit below)

## Files Created/Modified

- `.claude-plugin/plugin.json` - version 1.3.0, extended matcher, refreshed hashes, new enforcer_utils_sha256 key
- `tests/test_plugin_integrity.bash` - added enforcer-utils hash check, bumped version assertion to 1.3.*

## Decisions Made

- Hashes computed after all Phase 10 file changes are final, eliminating any risk of stale hashes.
- MCP tool names added to matcher (layer 1) complement the existing case-dispatch deny in the enforcer (layer 2), achieving two-layer defense per T-10-12.
- enforcer_utils_sha256 key placed after forge_delegation_enforcer_sha256 in _integrity for logical grouping of related hook files.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 10 is now complete: all 4 plans shipped, all ENF-01 through ENF-08 + PATH allowlist requirements implemented and tested.
- Phase 11 (Housekeeping, Hardening, forge-sb install) is unblocked.
- plugin.json at v1.3.0 is ready for release tagging.

---
*Phase: 10-enforcer-hardening-helper-extraction*
*Completed: 2026-04-24*

## Self-Check: PASSED

- `.claude-plugin/plugin.json` — exists, version=1.3.0 confirmed
- `tests/test_plugin_integrity.bash` — exists, enforcer_utils_sha256 check present, version pattern 1.3.* confirmed
- Commit `d89fbd3` — exists (feat(10-04): bump plugin.json)
- Commit `4d8288b` — exists (test(10-04): update test_plugin_integrity.bash)
- `bash tests/test_plugin_integrity.bash` — 14/14 passed, exit 0
- `bash tests/run_all.bash` — ALL SUITES PASSED, 0 failures

---
phase: 11-housekeeping-hardening-forge-sb
plan: "02"
subsystem: testing
tags: [bash, redaction, ghs-token, api-key, forge-progress-surface]

# Dependency graph
requires:
  - phase: 11-housekeeping-hardening-forge-sb/11-01
    provides: RDRCT-01 broadened sk- regex and ghs_/api-key redaction rules in forge-progress-surface.sh

provides:
  - Regression tests for ghs_ GitHub fine-grained PAT redaction (TEST-RDRCT-01a)
  - Regression tests for api-key: colon-form redaction (TEST-RDRCT-01b)
  - Total test count raised from 21 to 23 in test_v12_coverage.bash

affects: [11-03, 11-04, release-v1.3]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "run_surf() helper pattern extended: unique _payload_* and _out_* variable names per test block to avoid shadowing"

key-files:
  created: []
  modified:
    - tests/test_v12_coverage.bash

key-decisions:
  - "Unique variable names (_payload_ghs/_out_ghs/_ctx_ghs and _payload_ak/_out_ak/_ctx_ak) used per test block to avoid variable shadowing across tests in the same bash script scope"

patterns-established:
  - "Surface redaction tests: run_surf() + jq .hookSpecificOutput.additionalContext + positive grep for [REDACTED-*] + negative grep for raw secret"

requirements-completed: [TEST-RDRCT-01]

# Metrics
duration: 1min
completed: 2026-04-24
---

# Phase 11 Plan 02: Test Coverage for RDRCT-01 Redaction Rules Summary

**Two new regression tests added to test_v12_coverage.bash confirming ghs_ fine-grained PAT and api-key: colon-form secrets are redacted by forge-progress-surface.sh**

## Performance

- **Duration:** ~1 min
- **Started:** 2026-04-24T13:48:54Z
- **Completed:** 2026-04-24T13:49:35Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Added `test_surface_redacts_ghs_token`: verifies `ghs_AAAAAAAAAAAAAAAAAAAA12345` is replaced with `[REDACTED-GH-TOKEN]` and the raw token string does not appear in `additionalContext`
- Added `test_surface_redacts_api_key_colon_form`: verifies `api-key: supersecret` produces `api-key: [REDACTED]` and `supersecret` does not appear in `additionalContext`
- Full test suite green: 23 passed, 0 failed (was 21 before this plan)

## Task Commits

1. **Task 1: Add two redaction test cases** - `3279c92` (test)

**Plan metadata:** (this commit)

## Files Created/Modified

- `tests/test_v12_coverage.bash` - Two new test blocks appended after `test_surface_redacts_api_key_and_provider_tokens`, before the Results block

## Decisions Made

- Used unique variable name suffixes (`_ghs`, `_ak`) per test block to avoid bash variable shadowing in the flat script scope — consistent with adjacent test blocks using `_sk` suffix

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. Test-only changes.

## Self-Check

- [x] `tests/test_v12_coverage.bash` modified and committed at `3279c92`
- [x] `bash tests/test_v12_coverage.bash` output: 23 passed, 0 failed
- [x] "PASS test_surface_redacts_ghs_token" present in output
- [x] "PASS test_surface_redacts_api_key_colon_form" present in output

## Self-Check: PASSED

## Next Phase Readiness

- TEST-RDRCT-01(a) and TEST-RDRCT-01(b) satisfied
- Ready for Phase 11 Plan 03: skill/docs/install housekeeping
- plugin.json SHA-256 for forge-progress-surface.sh still stale (deferred to Plan 04)

---
*Phase: 11-housekeeping-hardening-forge-sb*
*Completed: 2026-04-24*

---
phase: 10-enforcer-hardening-helper-extraction
plan: 01
subsystem: infra
tags: [bash, enforcer, hook, helper-extraction, security, fd-redirect, process-substitution]

requires:
  - phase: 9-sentinel-hardening
    provides: "forge-delegation-enforcer.sh with inline helpers that are now being extracted"

provides:
  - "hooks/lib/enforcer-utils.sh: source-guarded library of 9 helper functions"
  - "Bug-fixed has_write_redirect (ENF-01/02/03 applied at creation time)"
  - "New export_env_prefix helper (ENF-04 prerequisite)"
  - "New is_allowed_doc_path helper (PATH-01)"
  - "New has_mutating_chain_segment helper (ENF-06)"
  - "New has_mutating_pipe_segment helper (ENF-08)"
  - "gh sub-command classification in is_read_only and is_mutating (ENF-05)"

affects:
  - 10-02
  - forge-delegation-enforcer

tech-stack:
  added: []
  patterns:
    - "Source-guard idiom: [[ -n ${VAR:-} ]] && return 0 prevents double-sourcing"
    - "Store regex in variable before [[ =~ ]] to avoid bash [[ parser treating ) as end of compound command"
    - "set -euo pipefail in lib; callers must restore with set +euo pipefail after sourcing when running test assertions"

key-files:
  created:
    - hooks/lib/enforcer-utils.sh
  modified: []

key-decisions:
  - "ENF-01: Use regex via variable ([[ $cmd =~ $_proc_sub_re ]]) rather than literal [[ $cmd =~ >([^)]*) ]] — bash [[ parser treats literal ) as compound-command terminator"
  - "ENF-02: Explicit fd-redirect removal (>&0, >&1, >&2, >&3, >&-, 0>&1, 1>&2, 2>&0) instead of character class — bash 3.2 compatibility"
  - "ENF-03: Strip quoted regions via sed before final > check — heredoc bodies not stripped (known limitation, documented in comment)"
  - "gh sub-commands added directly in this lib (not deferred to Plan 02) since is_read_only and is_mutating now live here"
  - "Function order: strip_env_prefix -> export_env_prefix -> has_write_redirect -> first_token -> is_allowed_doc_path -> is_read_only -> is_mutating -> has_mutating_chain_segment -> has_mutating_pipe_segment (dependency order)"

patterns-established:
  - "Bash regex variable pattern: local _re='...'; [[ $var =~ $_re ]] — avoids shell parser ambiguity with special characters"
  - "Lib source-guard: set pipefail/errexit in lib body; test harnesses must call set +euo pipefail after sourcing"

requirements-completed:
  - ENF-01
  - ENF-02
  - ENF-03
  - ENF-04
  - REFACT-01
  - REFACT-04
  - TEST-V13-04

duration: 3min
completed: 2026-04-24
---

# Phase 10 Plan 01: Enforcer Helper Library Summary

**Source-guarded enforcer utility library (9 helpers) with ENF-01/02/03 bug fixes baked in, plus new export_env_prefix, is_allowed_doc_path, has_mutating_chain_segment, has_mutating_pipe_segment, and gh sub-command classification**

## Performance

- **Duration:** 3 min
- **Started:** 2026-04-24T07:32:20Z
- **Completed:** 2026-04-24T07:34:54Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Created `hooks/lib/enforcer-utils.sh` with source-guard and 9 helper functions in correct dependency order
- Applied all three `has_write_redirect` bug fixes at file-creation time: process-substitution check (ENF-01), fd-redirect pruning with explicit bash 3.2-compatible substitutions (ENF-02), quoted-string stripping via sed (ENF-03)
- Added `export_env_prefix` (ENF-04 prerequisite), `is_allowed_doc_path` (PATH-01), `has_mutating_chain_segment` (ENF-06), `has_mutating_pipe_segment` (ENF-08) as new helpers
- Added `gh` read-only and mutating sub-command entries to `is_read_only` and `is_mutating` (ENF-05) — placed directly in lib since that is now the canonical home for these functions
- All 17 behavioral assertions verified passing

## Task Commits

1. **Task 1: Create hooks/lib/enforcer-utils.sh** - `3bc1414` (feat)

**Plan metadata:** (to be added in final commit)

## Files Created/Modified

- `hooks/lib/enforcer-utils.sh` - Source-guarded bash library with 9 enforcer helper functions; bug-fixed has_write_redirect; new helpers for ENF-04/05/06/08/PATH-01

## Decisions Made

- **ENF-01 regex via variable:** `[[ "$cmd" =~ \>\([^)]*\) ]]` fails in bash because the parser sees `)` as closing the `[[ ]]`. Fixed by storing regex in `local _proc_sub_re='>[(][^)]*[)]'` and matching against `$_proc_sub_re`.
- **ENF-02 explicit fd forms:** Character-class substitution `${var//>&[0-9]/}` is not supported in bash 3.2. Used eight explicit `${pruned//>&N/}` substitutions covering >&0, >&1, >&2, >&3, >&-, 0>&1, 1>&2, 2>&0.
- **gh entries in lib now (not Plan 02):** Since `is_read_only` and `is_mutating` are defined in the lib (not kept inline in the enforcer), the ENF-05 gh sub-commands must be added here — adding them in Plan 02 to the enforcer would have no effect once the enforcer sources the lib and removes its own copies.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Bash [[ parser rejected literal ) in regex**
- **Found during:** Task 1 (first run of verification)
- **Issue:** `[[ "$cmd" =~ \>\([^)]*\) ]]` triggers `syntax error in conditional expression: unexpected token ')'` — bash's `[[ ]]` parser interprets the literal `)` as the end of the compound command before seeing `]]`
- **Fix:** Stored the regex in `local _proc_sub_re='>[(][^)]*[)]'` then used `[[ "$cmd" =~ $_proc_sub_re ]]`
- **Files modified:** hooks/lib/enforcer-utils.sh
- **Verification:** Verification suite passes; `has_write_redirect 'tee >(cat)'` returns 0
- **Committed in:** 3bc1414 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - bash syntax bug in ENF-01 regex)
**Impact on plan:** Required fix to make ENF-01 work at all. No scope creep. Regex is semantically identical to the original intent.

## Issues Encountered

- `set -euo pipefail` in the lib propagates into the test/verification shell when sourced. Verification scripts must call `set +euo pipefail` after sourcing the lib or use a subshell with `bash --norc -c`. This is expected and documented in `patterns-established`.

## User Setup Required

None - no external service configuration required.

## Threat Surface Scan

All security-relevant surfaces are within the plan's threat model:
- `export_env_prefix`: T-10-01 — anchored regex name validation, literal-value export, short-lived subprocess
- `has_mutating_chain_segment` / `has_mutating_pipe_segment`: T-10-02 — all segments tested individually via `is_mutating`
- `has_write_redirect`: T-10-03 — ENF-01/02/03 fixes applied
- `is_allowed_doc_path`: T-10-04 — empty-path deny, single-dot-slash normalization, strict prefix matching

No new network endpoints, auth paths, or schema changes introduced.

## Next Phase Readiness

- `hooks/lib/enforcer-utils.sh` is ready to be sourced by Plan 02 (enforcer rewrite)
- Plan 02 will remove the now-duplicate inline functions from `forge-delegation-enforcer.sh` and add `source "$(dirname "$0")/lib/enforcer-utils.sh"` at startup
- No blockers

---
*Phase: 10-enforcer-hardening-helper-extraction*
*Completed: 2026-04-24*

---
phase: 11-housekeeping-hardening-forge-sb
plan: 03
subsystem: docs
tags: [html, javascript, sri, security, skill-md, install-sh]

requires:
  - phase: 11-02
    provides: test coverage for sk- redaction and SRI scaffold

provides:
  - SRI integrity hash on Lucide CDN script in all 6 help pages
  - Favicon link in all 6 help pages
  - Null guard in search.js renderResults()
  - Injection table Code change row corrected to quality-gates + code-review
  - SKILL.md Level 3 scope constraint referencing $CLAUDE_PROJECT_DIR
  - Security boundary paragraph moved before extraction categories in Mentoring Loop
  - Skill Injection governance note with SENTINEL audit requirement
  - install.sh mktemp respects $TMPDIR and drops .sh suffix

affects: [11-04, plugin-integrity, help-site]

tech-stack:
  added: []
  patterns:
    - "SRI hash pattern: sha384 via curl+openssl dgst -sha384 -binary | openssl enc -base64 -A"
    - "Null guard before DOM access in search.js"

key-files:
  created: []
  modified:
    - docs/help/index.html
    - docs/help/getting-started/index.html
    - docs/help/concepts/index.html
    - docs/help/workflows/index.html
    - docs/help/reference/index.html
    - docs/help/troubleshooting/index.html
    - docs/help/search.js
    - skills/forge/SKILL.md
    - install.sh

key-decisions:
  - "SRI hash for lucide@0.469.0/dist/umd/lucide.min.js: sha384-hJnF5AwidE18GSWTAGHv3ByzzvfNZ1Tcx5y1UUV3WkauuMCEzBJBMSwSt/PUPXnM (computed live from CDN)"
  - "Security boundary paragraph placed BEFORE extraction categories in SKILL.md Mentoring Loop — not after"
  - "install.sh TMPDIR fix drops .sh suffix entirely (not just the path change) to avoid spurious type associations"

patterns-established:
  - "Batch low-risk content changes in a single plan/commit train to minimize PR noise"

requirements-completed: [SRI-01, SKILL-01, SKILL-02, DOCS-01, INST-01]

duration: 4min
completed: 2026-04-24
---

# Phase 11 Plan 03: Housekeeping — SRI, Favicon, Null Guard, SKILL.md, install.sh Summary

**SRI integrity on Lucide CDN + favicon link across all 6 help pages, search.js null guard, concepts table fix, SKILL.md scope/security/governance hardening, and TMPDIR-respecting mktemp in install.sh**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-04-24T13:51:51Z
- **Completed:** 2026-04-24T13:55:20Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments

- SRI-01: All 6 `docs/help/**/*.html` pages now have `integrity="sha384-hJnF5Awid..."` and `crossorigin="anonymous"` on the Lucide CDN script tag — browser will reject tampered CDN content
- DOCS-01(a+b+c): Favicon link added to all 6 help pages; `renderResults()` in search.js guarded against null list/section; concepts injection table "Code change" row updated to `quality-gates + code-review`
- SKILL-01/02: SKILL.md Level 3 scope now explicitly references `$CLAUDE_PROJECT_DIR`; security boundary paragraph moved before extraction categories; governance note added to Skill Injection
- INST-01: `install.sh` mktemp now uses `${TMPDIR:-/tmp}/forge-install.XXXXXX` (no `.sh` suffix, respects macOS/Linux `$TMPDIR`)

## Task Commits

1. **Task 1: SRI + favicon + null guard + concepts table** - `dd6acde` (feat)
2. **Task 2: SKILL.md + install.sh** - `072664d` (feat)

**Plan metadata:** _(to be added in final commit)_

## Files Created/Modified

- `docs/help/index.html` — Added SRI integrity + favicon link
- `docs/help/getting-started/index.html` — Added SRI integrity + favicon link
- `docs/help/concepts/index.html` — Added SRI integrity + favicon link + quality-gates + code-review table row
- `docs/help/workflows/index.html` — Added SRI integrity + favicon link
- `docs/help/reference/index.html` — Added SRI integrity + favicon link
- `docs/help/troubleshooting/index.html` — Added SRI integrity + favicon link
- `docs/help/search.js` — Added `if (!list || !section) return;` null guard in `renderResults()`
- `skills/forge/SKILL.md` — Level 3 scope: `$CLAUDE_PROJECT_DIR`; security boundary before categories; SENTINEL audit governance
- `install.sh` — `mktemp "${TMPDIR:-/tmp}/forge-install.XXXXXX"` (drop `.sh` suffix, respect TMPDIR)

## Decisions Made

- SRI hash `sha384-hJnF5AwidE18GSWTAGHv3ByzzvfNZ1Tcx5y1UUV3WkauuMCEzBJBMSwSt/PUPXnM` computed live at plan execution time via `curl -sL ... | openssl dgst -sha384 -binary | openssl enc -base64 -A`
- Security boundary paragraph restructuring kept the full paragraph text intact; only its position relative to the four category bullets changed
- `install.sh` `.sh` suffix dropped entirely (not just the path prefix) — the temp file is a shell script by content not by name; suffix caused spurious macOS file associations

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## Test Suite Results

- `install.sh` unit tests: 15 passed, 0 failed, 1 skipped (forge already installed on test machine)
- `Plugin integrity verification`: 3 failures expected — `install.sh`, `SKILL.md`, and `forge-progress-surface.sh` hashes are stale after this plan's edits. Will be refreshed in Plan 04.
- All other suites: fully green (fresh install, enforcer v1.2/v1.3, release gate, v1.2 coverage, v1.3 coverage)

## Known Stubs

None.

## Threat Flags

None — all changes are content-only; no new network endpoints, auth paths, or file access patterns introduced.

## Next Phase Readiness

- Plan 04 must refresh `plugin.json` hashes for `install.sh`, `SKILL.md`, and `forge-progress-surface.sh`
- After Plan 04, integrity test suite should be fully green

---
*Phase: 11-housekeeping-hardening-forge-sb*
*Completed: 2026-04-24*

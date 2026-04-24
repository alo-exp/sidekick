---
phase: 11-housekeeping-hardening-forge-sb
plan: 04
subsystem: infra
tags: [bash, shell, git-mv, integrity, sha256, forge-sb, silver-bullet, plugin-manifest]

# Dependency graph
requires:
  - phase: 11-03
    provides: "install.sh TMPDIR fix and SKILL.md updates that made install_sh_sha256 and forge_skill_md_sha256 stale"
  - phase: 11-01
    provides: "forge-progress-surface.sh ANSI/redaction changes that made forge_progress_surface_sha256 stale"
provides:
  - "14 SENTINEL audit files relocated from repo root to docs/internal/sentinel/ via git mv (history preserved)"
  - "forge-sb auto-install step in install.sh after ForgeCode binary install (FGSB-01)"
  - "All plugin.json _integrity hashes refreshed — install_sh_sha256, forge_progress_surface_sha256, forge_skill_md_sha256"
  - "Full test suite green: 14/14 integrity checks pass, ALL SUITES PASSED"
affects: [release-v1.3, future-plans-referencing-integrity]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "git mv for audit file relocation preserves full history across all 14 SENTINEL reports"
    - "forge-sb install runs only on fresh ForgeCode installs (inside the if block, not on every run)"
    - "plugin.json _integrity hashes refresh cycle: compute with shasum -a 256 then update three keys simultaneously"

key-files:
  created:
    - docs/internal/sentinel/SENTINEL-audit-forge.md (moved from root)
    - docs/internal/sentinel/SENTINEL-audit-forge-r2.md through r14.md (moved from root)
  modified:
    - install.sh (forge-sb curl install step added after ForgeCode binary install)
    - .claude-plugin/plugin.json (install_sh_sha256, forge_progress_surface_sha256, forge_skill_md_sha256 refreshed)
    - context.md (directory listing updated to reflect new SENTINEL path)

key-decisions:
  - "SENTINEL files moved with git mv not cp+rm — preserves rename history traceable via git log --follow"
  - "forge-sb install placed INSIDE the if-not-installed block — avoids redundant curl on every session after first install"
  - "forge_skill_md_sha256 also refreshed (stale from Plan 03) — caught by integrity test run, fixed as Rule 1 bug"

patterns-established:
  - "Hash refresh cycle: run tests first to identify all stale hashes, then update all in one pass"
  - "SENTINEL audit reports live at docs/internal/sentinel/ — cross-references in context.md use full path"

requirements-completed:
  - HOUSE-01
  - FGSB-01

# Metrics
duration: 15min
completed: 2026-04-25
---

# Phase 11 Plan 04: Housekeeping Close-out Summary

**14 SENTINEL audit files relocated to docs/internal/sentinel/ via git mv, forge-sb auto-install added to install.sh, and all three stale plugin.json integrity hashes refreshed — full test suite 100% green.**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-04-25T00:00:00Z
- **Completed:** 2026-04-25T00:15:00Z
- **Tasks:** 2
- **Files modified:** 17 (14 renamed + install.sh + plugin.json + context.md)

## Accomplishments

- Moved all 14 SENTINEL-audit-forge*.md files from repo root to docs/internal/sentinel/ using `git mv` — history preserved, root clean
- Added forge-sb install curl step to install.sh inside the ForgeCode install block (runs only on first install, not every session)
- Refreshed install_sh_sha256, forge_progress_surface_sha256, and forge_skill_md_sha256 in plugin.json
- All 14 integrity checks pass; bash tests/run_all.bash exits 0 with ALL SUITES PASSED across all 14 suites

## Task Commits

1. **Task 1: git mv 14 SENTINEL files + update context.md cross-reference** - `3e43f58` (chore)
2. **Task 2: forge-sb install step + integrity hash refresh** - `4baa2a1` (feat)

**Plan metadata:** (docs commit below)

## Files Created/Modified

- `docs/internal/sentinel/SENTINEL-audit-forge.md` through `SENTINEL-audit-forge-r14.md` — moved from repo root (14 files)
- `install.sh` — forge-sb auto-install curl step added after `echo "[forge-plugin] ForgeCode installed."`
- `.claude-plugin/plugin.json` — install_sh_sha256, forge_progress_surface_sha256, forge_skill_md_sha256 updated
- `context.md` — directory listing entry updated to `docs/internal/sentinel/SENTINEL-audit-forge-r*.md`

## Decisions Made

- **forge-sb install placement:** Inside the `if [ ! -f "${FORGE_BIN}" ]` block, not at the end of install.sh. This means forge-sb only installs when ForgeCode is being installed for the first time — not on subsequent sessions where ForgeCode is already present. This mirrors how ForgeCode itself installs.
- **git mv not cp+rm:** Preserves git rename history for all 14 audit files; `git log --follow` traces each file back to its original root path.
- **forge_skill_md_sha256 also refreshed:** The integrity test run revealed a third stale hash (from Plan 03's SKILL.md changes). Fixed inline as Rule 1 (test was failing). All three hash fields updated in same commit.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] forge_skill_md_sha256 also stale (not listed in plan)**
- **Found during:** Task 2 integrity test run
- **Issue:** Plan listed install_sh_sha256 and forge_progress_surface_sha256 as needing refresh. Running `bash tests/test_plugin_integrity.bash` after updating those two revealed a third failure: `skills/forge/SKILL.md hash: claimed=6a66c01ac5d8de5b… actual=41b646c41c064826…`. This hash was stale from Plan 03's SKILL.md modifications.
- **Fix:** Computed actual hash (`shasum -a 256 skills/forge/SKILL.md`) and updated `forge_skill_md_sha256` in plugin.json before committing.
- **Files modified:** `.claude-plugin/plugin.json`
- **Verification:** `bash tests/test_plugin_integrity.bash` → 14/14 passed, 0 failed
- **Committed in:** `4baa2a1` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug: stale hash not caught by plan)
**Impact on plan:** Essential fix — would have left integrity suite with 1 failure without it. No scope creep.

## Issues Encountered

None beyond the stale hash deviation documented above.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Phase 11 complete: all 4 plans shipped (Plans 01-04)
- Repo root is clean (SENTINEL files gone)
- install.sh installs forge-sb alongside ForgeCode
- plugin.json integrity hashes are current
- Full test suite green
- Ready to release v1.3.0

---
*Phase: 11-housekeeping-hardening-forge-sb*
*Completed: 2026-04-25*

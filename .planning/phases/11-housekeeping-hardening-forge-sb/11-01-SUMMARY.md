---
phase: 11-housekeeping-hardening-forge-sb
plan: "01"
subsystem: security
tags: [bash, perl, regex, ansi, credential-redaction, osc-escape, sidekick-plugin]

# Dependency graph
requires:
  - phase: 10-enforcer-hardening-helper-extraction
    provides: enforcer-utils.sh helpers used by forge-progress-surface pipeline

provides:
  - strip_ansi() in slurp mode (-0777 -pe) — multi-line OSC sequences fully consumed
  - broadened sk- redaction regex covering dots, slashes, base64 +, 10-char minimum
  - two new regression tests for STRIP-01 and RDRCT-01

affects:
  - 11-04 (plugin.json hash refresh — forge-progress-surface.sh hash is now stale, plan 04 refreshes it)
  - any future plan touching strip_ansi or credential redaction in forge-progress-surface.sh

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "perl -0777 -pe for multi-line ANSI/OSC stripping in bash pipeline hooks"
    - "Perl lookahead (?=\s|['\">},]|$) replaces \\b word boundary for end-of-token matching in broader char classes"

key-files:
  created: []
  modified:
    - hooks/forge-progress-surface.sh
    - tests/test_forge_progress_surface.bash

key-decisions:
  - "STRIP-01: -0777 slurp flag inserted before -pe so all four substitution patterns operate on the full input string — the OSC body regex now matches sequences whose BEL terminator is on a different line"
  - "RDRCT-01: removed both leading and trailing \\b — the broadened char class [A-Za-z0-9_\\-\\.\\/+] includes chars that are not \\w, so \\b produces false-negatives; explicit lookahead provides cleaner end-of-token boundary"
  - "TDD RED gate: first test scenario (OSC body placed before STATUS block) passed unexpectedly because extract_status_block awk never saw the OSC body text; redesigned to source strip_ansi directly and assert no body text in stripped output"
  - "plugin.json SHA-256 for forge-progress-surface.sh intentionally stale after this change; refresh deferred to plan 04 per wave design"

patterns-established:
  - "Source-guard pattern in hooks allows tests to source the file and exercise individual functions (strip_ansi, extract_status_block) without running main()"

requirements-completed:
  - STRIP-01
  - RDRCT-01

# Metrics
duration: 6min
completed: 2026-04-24
---

# Phase 11 Plan 01: Credential Hardening — strip_ansi Slurp Mode + sk- Regex Summary

**perl -0777 slurp mode closes multi-line OSC injection via strip_ansi; sk- regex broadened to [A-Za-z0-9_\-\.\/+]{10,} with lookahead, catching dot/slash/base64 token formats the old \\b-bounded {16,} pattern missed**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-04-24T13:39:07Z
- **Completed:** 2026-04-24T13:45:28Z
- **Tasks:** 1 (TDD: RED commit + GREEN commit)
- **Files modified:** 2

## Accomplishments

- STRIP-01: switched `strip_ansi()` from `perl -pe` to `perl -0777 -pe` so the four substitution regexes operate on the full input buffer; OSC sequences whose `\x1b]` opener and `\x07`/ST terminator are on different lines are now fully consumed in one pass
- RDRCT-01: replaced `\bsk-[A-Za-z0-9_-]{16,}\b` with `sk-[A-Za-z0-9_\-\.\/+]{10,}(?=\s|['">},]|$)` — covers OpenAI-style `sk-proj/…`, dot-delimited, and base64+ formats; minimum suffix reduced from 16 to 10 chars
- Added 2 regression tests (9 total, all green): `test_strip_ansi_multiline_osc_slurp_mode` sources `strip_ansi` directly to assert OSC body text is stripped; `test_sk_token_redaction_broadened` exercises three token variants the old regex missed

## Task Commits

TDD gate sequence:

1. **RED — failing tests** - `5168cda` (test) — `test(11-01): add failing tests for STRIP-01 and RDRCT-01`
2. **GREEN — implementation + updated tests** - `dc030bc` (feat) — `feat(11-01): STRIP-01 + RDRCT-01 credential hardening in forge-progress-surface.sh`

**Plan metadata:** (this commit)

## Files Created/Modified

- `hooks/forge-progress-surface.sh` — `perl -pe` → `perl -0777 -pe` in strip_ansi(); sk- regex line replaced with broadened pattern + lookahead
- `tests/test_forge_progress_surface.bash` — added `test_strip_ansi_multiline_osc_slurp_mode` and `test_sk_token_redaction_broadened`

## Decisions Made

- **Slurp mode flag placement:** `-0777` inserted before `-pe` (not after); perl flag order is `perl [flags] 'program'`, so `-0777 -pe` is correct.
- **Lookahead over \\b:** `\\b` is a zero-width assertion between `\w` and `\W`. With the broadened char class including `.`, `/`, `+` (all `\W`), a trailing `\\b` after those chars would never fire at the token boundary — replaced with an explicit positive lookahead for whitespace, JSON/YAML punctuation, and end-of-line.
- **Leading \\b removed:** The `sk-` prefix itself anchors the start; removing the leading `\\b` means tokens at the very start of a line (no preceding `\W`) are also caught.
- **TDD test redesign:** Initial STRIP-01 test used an end-to-end hook call where the OSC body text was never picked up by `extract_status_block` awk (it came before the STATUS line). Redesigned to source `strip_ansi` directly and assert the raw stripped output contains no OSC body text — this directly tests the function contract regardless of downstream filtering.
- **plugin.json hash stale by design:** Wave design explicitly defers SHA-256 refresh to plan 04 (integrity hash sweep). No action taken here.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] TDD test scenario redesign — initial STRIP-01 test was a false green in RED phase**
- **Found during:** Task 1 (RED gate verification)
- **Issue:** First test construction placed the OSC body before the STATUS block; `extract_status_block` awk stopped at `PATTERNS_DISCOVERED:` in the OSC body before ever reaching the real STATUS line, so the hook emitted empty output — the test passed even with line-mode perl (ctx was empty, grep for 'INJECTED' found nothing)
- **Fix:** Redesigned test to source `strip_ansi` directly from the hook file (source-guard prevents `main()` from running) and assert the raw stripped output contains no OSC body text; this tests the function contract independently of `extract_status_block`
- **Files modified:** `tests/test_forge_progress_surface.bash`
- **Verification:** Confirmed line-mode perl leaks "OSCHIDDEN" and "more-body" in raw strip output; slurp-mode strips them both (0 matches in stripped output)
- **Committed in:** `dc030bc` (GREEN gate commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - test correctness bug)
**Impact on plan:** Test redesign necessary for genuine RED gate. No scope creep; the implementation changes were exactly as specified.

## Issues Encountered

- Initial STRIP-01 test design was accidentally testing the wrong layer (extract_status_block filtering rather than strip_ansi stripping). Resolved by sourcing the hook function directly. This is a test design issue, not an implementation issue — the STRIP-01 implementation change itself was straightforward.

## Known Stubs

None — no placeholder or stub values introduced.

## Threat Flags

None — changes are entirely within the existing trust boundary (Forge stdout → additionalContext pipeline). Both STRIP-01 and RDRCT-01 are mitigations for T-11-01 and T-11-02 listed in the plan's threat model. No new network endpoints, auth paths, or schema changes.

## TDD Gate Compliance

- RED gate: `5168cda` — `test(11-01): add failing tests for STRIP-01 and RDRCT-01`
- GREEN gate: `dc030bc` — `feat(11-01): STRIP-01 + RDRCT-01 credential hardening in forge-progress-surface.sh`
- REFACTOR: not needed (changes were minimal targeted substitutions)

Gates are in correct sequence in git log.

## Next Phase Readiness

- Plan 02 (sk- unit tests + SRI integrity scaffold) can proceed immediately
- Plan 04 (plugin.json hash refresh) must be run after all wave plans that touch hook files; forge-progress-surface.sh hash is now stale
- No blockers

## Self-Check: PASSED

- hooks/forge-progress-surface.sh: EXISTS
- tests/test_forge_progress_surface.bash: EXISTS
- 11-01-SUMMARY.md: EXISTS
- Commit 5168cda (RED gate): EXISTS
- Commit dc030bc (GREEN gate): EXISTS
- STRIP-01 pattern (perl -0777 -pe): PRESENT
- RDRCT-01 pattern ([A-Za-z0-9_\-\.\/+]{10,}): PRESENT
- Old pattern ({16,} with \\b): ABSENT
- Test suite: 9 passed, 0 failed

---
*Phase: 11-housekeeping-hardening-forge-sb*
*Completed: 2026-04-24*

---
phase: 10
slug: enforcer-hardening-helper-extraction
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-24
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Custom bash test runner (no external dependencies) |
| **Config file** | `tests/run_all.bash` |
| **Quick run command** | `bash tests/test_forge_enforcer_hook.bash` |
| **Full suite command** | `bash tests/run_all.bash` |
| **Estimated runtime** | ~10–15 seconds (full suite) |

---

## Sampling Rate

- **After every task commit:** Run `bash tests/test_forge_enforcer_hook.bash`
- **After every plan wave:** Run `bash tests/run_all.bash`
- **Before `/gsd-verify-work`:** Full suite must be green (0 failures)
- **Max feedback latency:** ~15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 10-01-01 | 01 | 1 | REFACT-01, ENF-01–04, PATH-01, TEST-V13-04 | T-10-01–04 | lib sources cleanly; 9 functions defined; has_write_redirect ENF fixes applied | unit | `bash -c "source hooks/lib/enforcer-utils.sh && echo ok"` | ❌ W0 | ⬜ pending |
| 10-02-01 | 02 | 2 | REFACT-02–03, ENF-05–08, PATH-02–03 | T-10-01–04 | enforcer sources lib; ≤300 lines; all 8 bugs fixed; path allowlist active | unit | `bash tests/test_forge_enforcer_hook.bash` | ✅ | ⬜ pending |
| 10-03-01 | 03 | 3 | TEST-V13-01–04 | — | test_v13_coverage.bash passes; chained-tail test inverted | unit | `bash tests/run_all.bash` | ❌ W0 | ⬜ pending |
| 10-04-01 | 04 | 4 | MAN-V13-01–03 | — | plugin.json version=1.3.0; MCP tools in matcher; integrity hashes correct | integration | `bash tests/test_plugin_integrity.bash` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `hooks/lib/enforcer-utils.sh` — must exist before Plan 02 can source it (created in Plan 01, Wave 1)
- [ ] `tests/test_v13_coverage.bash` — new test file for TEST-V13-04 lib isolation tests (created in Plan 03, Wave 3)
- [ ] `tests/run_all.bash` updated to include `test_v13_coverage.bash`

*Wave 0 artifacts are created in Wave 1 and Wave 3 respectively — Plans 01 and 03 are the "Wave 0" setup for Plans 02 and 04.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| MCP filesystem tool actually blocked by plugin matcher | MAN-V13-02 | Requires live Claude Code plugin loader to test matcher invocation | After install, activate /forge mode and attempt mcp__filesystem__write_file; verify hook fires and denies |

---

## Validation Architecture (from RESEARCH.md)

| Req ID | Behavior | Test Type | Command | File |
|--------|----------|-----------|---------|------|
| ENF-01 | `>(...)` flagged as write redirect | unit | `bash tests/test_forge_enforcer_hook.bash` | extend existing |
| ENF-02 | `>&1/>&2/>&-` NOT flagged | unit | same | extend existing |
| ENF-03 | `>` in quotes NOT flagged | unit | same | extend existing |
| ENF-04 | `FORGE_LEVEL_3=1 cmd` (as prefix in command text) passes | unit | same | extend existing |
| ENF-05 | `gh issue list` passes; `gh issue create` denied | unit | same | extend existing |
| ENF-06 | `cd && rm` denied; `cd && ls` passes | unit | same | update (invert existing test) + extend |
| ENF-07 | MCP write tools denied | unit | same | extend existing |
| ENF-08 | read-only pipe denied; forge-p pipe allowed | unit | same | extend existing |
| PATH-01–03 | `.planning/` and `docs/` pass; `hooks/` denied | unit | same | extend existing |
| REFACT-01–04 | lib exists; enforcer sources it; ≤300 lines | structural | `wc -l hooks/forge-delegation-enforcer.sh` | manual check |
| TEST-V13-04 | lib sourceable in isolation | unit | `bash tests/test_v13_coverage.bash` | new file |
| MAN-V13-01–03 | version=1.3.0; matcher updated; hashes correct | integration | `bash tests/test_plugin_integrity.bash` | existing |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: each wave has full-suite run after completion
- [x] Wave 0 covers all MISSING references (lib file and test file created in Waves 1+3)
- [x] No watch-mode flags
- [x] Feedback latency < 15s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-04-24

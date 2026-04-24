# UAT Checklist — v1.4.0

**Milestone:** v1.4.0 — forge-delegate rename, forge-stop command, forge-replay removal, install.sh security hardening
**Executed:** 2026-04-25
**Method:** Cross-phase audit (Flow 3) + 4-stage pre-release quality gate (2 clean rounds) + SENTINEL security audit (2 rounds)
**Result:** ALL PASS

---

## Acceptance Criteria

| # | Criterion | Expected | Actual | Status |
|---|-----------|----------|--------|--------|
| 1 | Skill name is `forge-delegate` (dash form) in SKILL.md frontmatter | `name: forge-delegate` in `skills/forge/SKILL.md` | Confirmed present | PASS |
| 2 | `/forge-stop` command exists as dedicated command file | `commands/forge-stop.md` created with correct frontmatter and deactivation procedure | Confirmed present; frontmatter `name: forge-stop`; deletes `~/.claude/.forge-delegation-active`, reverts output style | PASS |
| 3 | `/forge-replay` command removed | `commands/forge-replay.md` deleted from repo | Confirmed deleted; no references remain | PASS |
| 4 | `/forge-history` (dash) used consistently — no `/forge:history` (colon) anywhere | All 9 occurrences of `/forge:history` replaced with `/forge-history` across SKILL.md, forge-stop.md, hooks, output-styles, CHANGELOG, test files | Confirmed via grep; 0 occurrences of `/forge:history` remain | PASS |
| 5 | `install.sh` does not contain `curl \| bash` from secondary domain | Unsigned remote execution from secondary domain removed entirely | Confirmed removed; no `curl.*\| bash` in install.sh | PASS |
| 6 | `install.sh` has `chmod 600` on `~/forge/.credentials.json` | Idempotent `chmod 600` block added after credential file creation | Confirmed present in install.sh | PASS |
| 7 | All 15 test suites pass with 0 failures | `bash tests/run_all.bash` exits 0, all assertions green | 157 assertions, 0 failures confirmed | PASS |
| 8 | `plugin.json` version is `1.4.0` with refreshed SHA-256 integrity hashes | `"version": "1.4.0"` and 5 updated `_integrity` hashes | Confirmed; install_sh, forge_md, forge_skill_md, hooks_json, command_forge_stop hashes updated | PASS |
| 9 | CHANGELOG.md has a complete and accurate v1.4.0 entry | v1.4.0 section with all 8 changes documented | Confirmed present and accurate | PASS |
| 10 | Help site docs updated | 5 pages + search.js + docs/index.html reflect forge-stop/forge-history | Confirmed all 7 files updated | PASS |
| 11 | Reference page sidebar includes `#forge-hooks` section link | `<li><a href="#forge-hooks">Plugin Hooks</a></li>` in sidebar nav | Confirmed added to `docs/help/reference/index.html` | PASS |

---

## Security UAT (SENTINEL — 2 Rounds)

| # | Finding | Resolution | Status |
|---|---------|------------|--------|
| S1 | `install.sh` curl\|bash from secondary domain (BLOCKING) | Removed entirely | PASS |
| S2 | `~/forge/.credentials.json` world-readable (BLOCKING) | `chmod 600` added | PASS |
| S3 | `sk-` token redaction in forge-progress-surface.sh | Regex normalized | PASS |
| S4 | Round 2 SENTINEL audit — no new findings | Clean pass | PASS |

---

## Quality Gate UAT (4-Stage, 2 Clean Rounds)

| Round | Stage 1 (Code Review) | Stage 2 (Big-Picture) | Stage 3 (Content) | Stage 4 (SENTINEL) | Result |
|-------|-----------------------|-----------------------|-------------------|--------------------|--------|
| Round 1 | 11 issues found and fixed | Pass | Pass | 2 blocking issues fixed | Fixed |
| Round 2 | Clean | Clean | Clean | Clean | PASS |
| Round 3 (confirmation) | Clean | Clean | Clean | Clean | PASS |

---

## Summary

| Total | PASS | FAIL | NOT-RUN |
|-------|------|------|---------|
| 11 | 11 | 0 | 0 |

**UAT Result: PASS** — All acceptance criteria verified. Security hard gate passed (2 clean SENTINEL rounds). Quality gate passed (2 consecutive clean rounds). GitHub release v1.4.0 created.

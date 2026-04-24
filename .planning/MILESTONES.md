# Milestones: Sidekick — Forge Delegation Mode

## v1.1 — Core Forge Delegation Skill

**Status:** SHIPPED 2026-04-13 (v1.1.0), patched to v1.1.2 on 2026-04-17
**Phases:** 1–5
**GitHub Release:** https://github.com/alo-exp/sidekick/releases/tag/v1.1.0

**Shipped:**
- `/forge` SKILL.md activating Forge-first delegation mode
- Fallback ladder: Guide → Handhold → Take over (Phases 1–2)
- AGENTS.md three-tier mentoring loop + deduplication (Phase 3)
- Full test suite (Phase 4)
- Forge agent frontmatter + model ID patch (Phase 5 / v1.1.2)
- 34 v1 requirements: all Validated

---

## v1.2 — Harness Enforcement + Live Visibility

**Status:** SHIPPED 2026-04-18 (v1.2.0), patched to v1.2.1 on 2026-04-18, v1.2.2 on 2026-04-24, v1.2.4 on 2026-04-24
**Phases:** 6–9
**GitHub Release:** https://github.com/alo-exp/sidekick/releases/tag/v1.2.0

**Shipped:**
- PreToolUse enforcer hook (`forge-delegation-enforcer.sh`) with UUID injection (Phase 6)
- `.forge/conversations.idx` audit trail (Phase 6)
- PostToolUse progress-surface hook (`forge-progress-surface.sh`) (Phase 7)
- Live output streaming via `run_in_background` + Monitor (Phase 7)
- `output-styles/forge.md` narration override (Phase 7)
- `/forge:replay` + `/forge:history` slash commands (Phase 8)
- `plugin.json` bumped to v1.2.0 (Phase 8)
- Full v1.2 test suite — 47 new tests (Phase 9)
- v1.2.1: Quality gate hardening — 1 HIGH + 5 MEDIUM SENTINEL findings resolved
- v1.2.2: SENTINEL L1/L2/I1 defense-in-depth — anchored env-prefix substitution, UUID validation, secret redaction
- v1.2.4: SENTINEL re-audit hardening pass
- 43 v1.2 requirements: all Validated

---

## v1.3 — Enforcer Hardening + Housekeeping + forge-sb

**Status:** SHIPPED 2026-04-24 (v1.3.0)
**Phases:** 10–11
**GitHub Release:** https://github.com/alo-exp/sidekick/releases/tag/v1.3.0

**Phase 10 — Enforcer Hardening + Helper Extraction:** SHIPPED
- Fix 6 enforcer bugs (Issues #3, #8): false-positive denials, Level-3 bypass, gh unclassified, chain bypass, MCP bypass, pipe-chain classification
- Codify doc-edit carve-out as path allowlist `.planning/**` + `docs/**` (Issue #2)
- Extract helpers to `hooks/lib/enforcer-utils.sh` (Issue #9)
- Expanded test suite + manifest bump to v1.3.0
- 22 requirements: ENF-01–08, PATH-01–03, REFACT-01–04, TEST-V13-01–04, MAN-V13-01–03

**Phase 11 — Housekeeping, Hardening & forge-sb:** SHIPPED
- `strip_ansi` slurp-mode fix (Issue #6)
- `sk-` token redaction regex improvement (Issue #7)
- SRI integrity for Lucide CDN (Issue #10)
- SKILL.md L3 scope + security boundary fixes (Issues #12, #13)
- Token redaction test gaps `ghs_` + `api-key:` (Issue #14)
- Help site: favicon, null guard, injection table (Issue #15)
- `install.sh` `$TMPDIR` fix (Issue #16)
- Move 14 SENTINEL files to `docs/internal/sentinel/` (Issue #17)
- forge-sb auto-install on plugin install
- 10 requirements: STRIP-01, RDRCT-01, SRI-01, SKILL-01–02, TEST-RDRCT-01, DOCS-01, INST-01, HOUSE-01, FGSB-01

---

## v1.4 — Command-Surface Cleanup & Security Hardening

**Status:** SHIPPED 2026-04-25 (v1.4.0)
**Phases:** None (direct release — no formal GSD phases)
**GitHub Release:** https://github.com/alo-exp/sidekick/releases/tag/v1.4.0

**Shipped:**
- Renamed skill `forge-delegation` → `forge-delegate` (dash naming convention)
- Created `/forge-stop` dedicated command for delegation deactivation
- Removed `/forge-replay` (underlying `forge conversation dump --html` API removed from Forge)
- Normalized `/forge-history` (dash form) across 9 files — was `/forge:history` (colon)
- Removed `curl | bash` from secondary domain in `install.sh` (SENTINEL blocking issue)
- Added `chmod 600` on `~/forge/.credentials.json` (SENTINEL blocking issue)
- Updated all help-site docs (5 pages + search.js + docs/index.html)
- Added Plugin Hooks to reference page sidebar navigation
- Bumped `plugin.json` to v1.4.0 with refreshed SHA-256 integrity hashes
- All 15 test suites: 157 assertions, 0 failures
- Archive: `.planning/milestones/v1.4.0-ROADMAP.md`

---
*Last updated: 2026-04-25 — v1.4.0 shipped; housekeeping release (command-surface cleanup + security hardening)*

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

**Status:** IN PROGRESS (started 2026-04-24)
**Phases:** 10–11
**Target release:** v1.3.0

**Phase 10 — Enforcer Hardening + Helper Extraction:**
- Fix 6 enforcer bugs (Issues #3, #8): false-positive denials, Level-3 bypass, gh unclassified, chain bypass, MCP bypass, pipe-chain classification
- Codify doc-edit carve-out as path allowlist `.planning/**` + `docs/**` (Issue #2)
- Extract helpers to `hooks/lib/enforcer-utils.sh` (Issue #9)
- Expanded test suite + manifest bump to v1.3.0
- 22 requirements: ENF-01–08, PATH-01–03, REFACT-01–04, TEST-V13-01–04, MAN-V13-01–03

**Phase 11 — Housekeeping, Hardening & forge-sb:**
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
*Last updated: 2026-04-24 — v1.3 milestone initialized with 2 phases (32 requirements)*

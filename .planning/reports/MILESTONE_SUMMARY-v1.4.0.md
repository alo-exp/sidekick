# Milestone v1.4.0 — Project Summary

**Generated:** 2026-04-25
**Purpose:** Team onboarding and project review

---

## 1. Project Overview

Sidekick is a Claude Code plugin that ships AI coding sidekicks — starting with **Forge**. The Forge sidekick activates a "Forge-first delegation mode" in which Claude delegates all implementation work (file edits, shell mutations, git operations) to the external Forge CLI, while Claude itself focuses on planning, task prompt composition, fallback management, and result interpretation.

v1.4.0 is a housekeeping release. The milestone scope is entirely command-surface cleanup — no new delegation behavior was introduced. The changes align command names with actual user-facing invocation patterns, fix two security issues in `install.sh`, and remove a command (`/forge-replay`) that relied on a Forge API that is no longer available.

**No formal GSD phases were used for this milestone** — all changes were made directly in a single session on 2026-04-25.

---

## 2. Architecture & Technical Decisions

- **Decision:** Rename skill from `forge-delegation` → `forge-delegate`
  - **Why:** The skill is invoked as `/forge-delegate` (dash naming convention) in Claude Code. The old name `forge-delegation` used the wrong form. Aligning the name prevents user confusion when browsing installed skills.
  - **Scope:** `skills/forge/SKILL.md` frontmatter only.

- **Decision:** Introduce `/forge-stop` slash command (`commands/forge-stop.md`)
  - **Why:** v1.3.0 used an inline procedure in SKILL.md to deactivate delegation mode. A dedicated `/forge-stop` command is more discoverable, consistent with Claude Code's slash-command convention, and testable independently.
  - **Behavior:** Deletes `~/.claude/.forge-delegation-active`, reverts output style, confirms deactivation. Preserves `.forge/conversations.idx`.

- **Decision:** Remove `/forge-replay` command
  - **Why:** `forge conversation dump --html` (the underlying Forge CLI call) is no longer available in current Forge builds. Shipping a non-functional command is worse than no command. `/forge-history` (already present since v1.3.0) is the durable replacement for browsing past tasks.

- **Decision:** Update `forge-progress-surface.sh` footer to emit `/forge-history` hint instead of `/forge:replay <uuid>`
  - **Why:** The old footer referenced the now-removed replay command. The history hint is more useful and always valid regardless of whether Forge stores full conversation dumps.

- **Decision:** Security hardening of `install.sh`
  - **Why (BLOCKING issue):** `curl -sL <secondary-domain>/forge-sb-install.sh | bash` executed unsigned code from a secondary domain — a SENTINEL-level blocking finding. Removed entirely.
  - **Why (BLOCKING issue):** `~/forge/.credentials.json` was created without `chmod 600`. World-readable credentials are a security violation. Added idempotent `chmod 600` block.

- **Decision:** Normalize all command invocations to `/forge-history` (dash, not colon)
  - **Why:** The command frontmatter uses `name: forge-history` (dash convention), making the correct invocation `/forge-history`. Nine files contained `/forge:history` (colon form) which is incorrect. Fixed across SKILL.md, forge-stop.md, hooks, output-styles, CHANGELOG, and test files.

---

## 3. Phases Delivered

| Phase | Name | Status | One-Liner |
|-------|------|--------|-----------|
| Direct | forge-delegate rename + forge-stop | Complete | Renamed skill, added forge-stop command, removed forge-replay |
| Direct | install.sh security hardening | Complete | Removed curl\|bash, added chmod 600 on credentials |
| Direct | Reference cleanup | Complete | Normalized /forge-history, /forge-stop across all docs/tests |
| QA | 4-stage pre-release quality gate (2 rounds) | Complete | Round 1 found 11 issues; Round 2 + Round 3 were clean |

---

## 4. Requirements Coverage

- ✅ Skill name `forge-delegate` — SKILL.md frontmatter updated
- ✅ `/forge-stop` command — `commands/forge-stop.md` created
- ✅ `/forge-replay` removed — `commands/forge-replay.md` deleted
- ✅ `/forge-history` (dash) used consistently — 9 files updated
- ✅ `install.sh` curl\|bash removed — SENTINEL blocking issue resolved
- ✅ `install.sh` chmod 600 on credentials — SENTINEL blocking issue resolved
- ✅ All 15 test suites pass (157 assertions, 0 failures)
- ✅ `plugin.json` version 1.4.0 with refreshed SHA-256 integrity hashes
- ✅ CHANGELOG.md v1.4.0 entry complete and accurate
- ✅ All help-site docs updated (5 pages + search.js + docs/index.html)
- ✅ Reference page sidebar includes #forge-hooks section link (D9 fix)

---

## 5. Key Decisions Log

| ID | Decision | Rationale |
|----|----------|-----------|
| CMD-01 | forge-delegation → forge-delegate | Dash naming convention for Claude Code skills |
| CMD-02 | /forge-stop as dedicated command file | Discoverable, testable, consistent with command surface |
| CMD-03 | Remove /forge-replay entirely | Underlying API (forge conversation dump --html) removed from Forge |
| SEC-01 | Remove curl\|bash from install.sh | Unsigned remote execution from secondary domain is SENTINEL blocking |
| SEC-02 | chmod 600 on credentials file | World-readable API keys are a security violation |
| CONV-01 | /forge-history not /forge:history | Command frontmatter uses dash; colon form was 9-file inconsistency |
| DOC-01 | Add #forge-hooks to reference page sidebar | Section existed in content but was undiscoverable via navigation |

---

## 6. Tech Debt & Deferred Items

**Pre-existing soft-limit breaches (tracked, not introduced by v1.4.0):**
- `skills/forge/SKILL.md`: 342 lines (doc soft limit 300)
- `hooks/forge-delegation-enforcer.sh`: 289 lines (approaching hard limit 300)
- `hooks/lib/enforcer-utils.sh`: 277 lines (approaching hard limit 300)

**C4/WARN (accepted):** Reference page AGENTS.md format example shows simplified 5-heading combined format. SKILL.md defines separate global-tier (4 headers) and project-tier (4 headers) including `## Forge Output Format`, `## Task Patterns`, `## Forge Corrections`. The simplification is intentional and not wrong.

---

## 7. Getting Started

- **Install Sidekick:** Add to Claude Code settings: `"enabledPlugins": {"sidekick@alo-exp": true}`
- **Activate Forge delegation:** Run `/forge` in Claude Code
- **Stop delegation:** Run `/forge-stop`
- **Browse history:** Run `/forge-history`
- **Tests:** `bash tests/run_all.bash` (15 suites, 157+ assertions)
- **Hooks:** `hooks/forge-delegation-enforcer.sh` (PreToolUse), `hooks/forge-progress-surface.sh` (PostToolUse)
- **Main skill:** `skills/forge/SKILL.md`
- **Plugin manifest:** `.claude-plugin/plugin.json`

---

## Stats

- **Timeline:** 2026-04-25 → 2026-04-25 (1 session)
- **Commits:** 3 (ff04e7b, 23b7d7a, f697658)
- **Files changed:** 27 (+165 / -151)
- **Contributors:** Shafqat + Claude

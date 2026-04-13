# Security Audit Report — Stage 4 Pre-Release Quality Gate

**Date:** 2026-04-13
**Auditor:** GSD Security Auditor (automated)
**Scope:** skills/forge/SKILL.md, install.sh, docs/help/**/*.html, docs/help/search.js

---

## Area 1: skills/forge/SKILL.md

**Verdict: PASS**

| Check | Severity | Status | Evidence |
|-------|----------|--------|----------|
| No hardcoded API keys, secrets, or credentials | CRITICAL | PASS | File contains no API keys, tokens, passwords, or credential values. References `~/forge/.credentials.json` and `~/forge/.forge.toml` by path only. |
| Credential existence check only — never reads/logs key value | HIGH | PASS | Line 25: `"~/forge/.credentials.json exists and contains a non-empty api_key field (never read or log the actual key value -- existence check only)"` — instruction is present and explicit. |
| No echo/log of credential values anywhere in file | HIGH | PASS | Grep of entire file shows zero instances of printing, logging, or reading API key values. All references are to file existence or field existence only. |

**Findings:** 0

---

## Area 2: install.sh

**Verdict: PASS**

| Check | Severity | Status | Evidence |
|-------|----------|--------|----------|
| No echo/bash commands that embed API key in transcript | CRITICAL | PASS | install.sh does not handle API keys at all. It installs the ForgeCode binary and modifies PATH. API key setup is handled separately by the Claude skill (per line 5: "Provider/API key setup is guided interactively by the forge skill in Claude"). Previous R12/R13 findings are not relevant to this file — those were about the Claude session transcript, not install.sh itself. |
| No command injection via user-controlled input | HIGH | PASS | All variables are quoted (`"${FORGE_BIN}"`, `"${FORGE_INSTALL_TMP}"`, `"${profile}"`, etc.). `set -euo pipefail` is set. No `eval`, no unquoted expansions, no user-supplied arguments used in commands. The `add_to_path` function receives only hardcoded paths (`${HOME}/.zshrc`, etc.). |
| No world-writable files created | MEDIUM | PASS | `mktemp` creates temp file with default permissions (owner-only). `mkdir -p` for SHA log directory uses default umask. Profile appends (`>>`) preserve existing permissions. No `chmod 777` or equivalent. |
| Write tool pattern for API key (not bash echo) | HIGH | PASS (N/A) | install.sh does not write API keys. It only installs the binary and modifies PATH. API key writing is handled by the Claude skill session, which per commit 92c445b uses the Write tool pattern instead of bash echo. |
| SHA-256 pinned hash verification | — | INFO | Line 23: `EXPECTED_FORGE_SHA` is set. Lines 65-78: mismatch aborts installation. Lines 86-95: non-interactive gate blocks execution when no pin is set. Supply chain hardening from R7/R8/R9/R10 findings is intact. |
| Symlink hijack protection on profile writes | — | INFO | Lines 117-125: `add_to_path` checks if profile is a symlink pointing outside HOME and refuses to write. Lines 129-134: ownership check refuses write if file not owned by current user. |
| Download timeouts | — | INFO | Line 38: `curl --max-time 60 --connect-timeout 15`. Line 40: `wget --timeout=60`. Prevents indefinite hang (R8-6). |

**Findings:** 0

---

## Area 3: docs/help/**/*.html and search.js

**Verdict: PASS**

| Check | Severity | Status | Evidence |
|-------|----------|--------|----------|
| No inline script executing untrusted/dynamic content | HIGH | PASS | All 6 HTML files contain only inline `<script>` blocks for: (1) theme detection from localStorage (`data-theme` attribute set from `localStorage.getItem('sidekick-theme')`), (2) theme toggle function (`applyTheme`/`toggleTheme`), (3) `lucide.createIcons()` call. No dynamic content from URL parameters, no `eval()`, no `document.write()`, no `innerHTML` with unescaped user input. |
| External resources — allowlist enforcement | HIGH | PASS | All 6 HTML files load exactly 2 external origins: `https://fonts.googleapis.com` (+ `fonts.gstatic.com` preconnect) for Space Grotesk and Fira Code fonts, and `https://unpkg.com/lucide@0.469.0/dist/umd/lucide.min.js` for icons. Version is pinned (0.469.0). No other external scripts, stylesheets, or resources loaded. |
| No form elements POSTing to external endpoints | MEDIUM | PASS | No `<form>` elements in any HTML file. The search input (`#search-input`) is a standalone `<input>` with client-side JavaScript handling only — no form submission, no network requests. |
| escHtml() used for all user-input rendering | HIGH | PASS | search.js line 144-146: `escHtml()` escapes `&`, `<`, `>`, `"`. All user-input-derived content in `renderResults()` passes through `escHtml()`: query display (line 129), page name (line 137), title (line 138), excerpt (line 139). The `r.url` and `r.anchor` values in the href attribute (line 136) come from the hardcoded `IDX` array, not from user input. |

**Findings:** 0

---

## Summary

| Area | Verdict | Critical | High | Medium | Low |
|------|---------|----------|------|--------|-----|
| skills/forge/SKILL.md | PASS | 0 | 0 | 0 | 0 |
| install.sh | PASS | 0 | 0 | 0 | 0 |
| docs/help/**/*.html + search.js | PASS | 0 | 0 | 0 | 0 |

**Overall Verdict: PASS** — All 3 areas clear with no findings.

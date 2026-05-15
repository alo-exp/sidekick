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
| Credential existence check only — never reads/logs key value | HIGH | PASS | Current `skills/forge/SKILL.md` uses a shell-only `jq -e` array-schema existence check and explicitly says never to read, display, or include credential values in output or context. |
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
| No inline script executing untrusted/dynamic content | HIGH | PASS | All 6 HTML files contain only inline `<script>` blocks for: (1) theme detection from localStorage (`data-theme` attribute set from the versioned `sidekick-theme-v2` key), (2) theme toggle function (`applyTheme`/`toggleTheme`), (3) `lucide.createIcons()` call. No dynamic content from URL parameters, no `eval()`, no `document.write()`, no `innerHTML` with unescaped user input. |
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

---
---

# SENTINEL Pass — Deep Security Audit

**Date:** 2026-04-13
**Auditor:** SENTINEL (automated, second pass)
**Scope:** skills/forge/SKILL.md, install.sh, hooks/hooks.json, .claude-plugin/plugin.json

This is a supplementary deep audit covering areas not examined in the initial pass, plus a deeper review of previously-examined files.

---

## New Findings

### HIGH

#### H-1: Credential field check requires parsing file contents (SKILL.md:25) — CLOSED
- **Severity:** HIGH
- **File:** `skills/forge/SKILL.md:25`
- **Category:** Credential Leakage
- **Status:** Closed in the current worktree.
- **Description:** Historical finding. The current health check no longer asks the host AI to inspect a flat `api_key` field. It runs a shell-only `jq -e` check against Forge's current array-of-`{id, auth_details}` schema, redirects output to `/dev/null`, and explicitly forbids reading, displaying, or including credential values in output or context.
- **Recommendation:** No current action. Keep future credential checks shell-only and output-suppressed.

---

### MEDIUM

#### M-1: SHA verification bypass when hash utilities unavailable (install.sh:51-99)
- **Severity:** MEDIUM
- **File:** `install.sh:51-53, 65, 99`
- **Category:** Integrity Verification Gap
- **Description:** When neither `shasum` nor `sha256sum` is available, `FORGE_SHA` is set to `"UNAVAILABLE"`. The comparison on line 65 (`FORGE_SHA != "UNAVAILABLE"`) skips verification, but execution proceeds on line 99 (`bash "${FORGE_INSTALL_TMP}"`). If `EXPECTED_FORGE_SHA` is pinned (non-empty), the user has declared intent to require integrity verification -- yet the script executes the unverified download anyway.
- **Recommendation:** When `FORGE_SHA == "UNAVAILABLE"` and `EXPECTED_FORGE_SHA` is non-empty, abort with an error: "Cannot verify integrity: no hash utility available. Install shasum or sha256sum, or run manually."

#### M-2: Temp file uses predictable prefix and unnecessary .sh suffix (install.sh:34)
- **Severity:** MEDIUM
- **File:** `install.sh:34`
- **Category:** Unsafe Temp File
- **Description:** `mktemp /tmp/forge-install.XXXXXX.sh` uses a fixed prefix in a world-writable directory and adds a `.sh` suffix. While `mktemp` provides randomness via `XXXXXX`, the predictable prefix allows targeted monitoring of `/tmp`. The `.sh` suffix is unnecessary since execution is via explicit `bash` invocation.
- **Recommendation:** Use `mktemp "${TMPDIR:-/tmp}/forge-install.XXXXXX"` to respect `$TMPDIR` and drop the suffix.

#### M-3: Self-asserted integrity hashes in plugin.json (plugin.json:23-31)
- **Severity:** MEDIUM
- **File:** `.claude-plugin/plugin.json:23-31`
- **Category:** Supply Chain
- **Description:** The `_integrity` block stores SHA-256 hashes of plugin files within the same repository. An attacker who compromises the repo can update both files and their hashes simultaneously. These hashes provide no tamper-evidence against repo-level compromise.
- **Recommendation:** Add a `_note` clarifying that these hashes detect accidental corruption only. For supply-chain security, publish signed release attestations out-of-band (e.g., GitHub Attestations or Sigstore).

#### M-4: Sleep-based consent window in non-interactive context (install.sh:98)
- **Severity:** MEDIUM
- **File:** `install.sh:98`
- **Category:** Insufficient Consent
- **Description:** When a pinned SHA is set and verified, the script reaches line 98 (`sleep 5`) even in non-interactive mode (SessionStart hook) before executing the downloaded script. The sleep provides no actual security -- the user cannot press Ctrl+C in a hook context. This is security theater that adds 5 seconds of latency.
- **Recommendation:** Remove the sleep when the pinned SHA has been verified (the integrity check is the actual gate). Or document explicitly that the sleep is purely cosmetic.

---

### LOW

#### L-1: Hardcoded home-directory paths for plugin state (SKILL.md:40-41, 52)
- **Severity:** LOW
- **File:** `skills/forge/SKILL.md:40-41, 52`
- **Category:** Over-permissive Instructions
- **Description:** The source skill uses `~/.claude/sessions/${CLAUDE_SESSION_ID}/.forge-delegation-active`; Codex-installed files rewrite the marker root to `~/.codex/sessions/${CODEX_THREAD_ID}/.forge-delegation-active`. This is better than a single global home-directory toggle, but it still assumes the current host session id is available and stable.
- **Recommendation:** Keep using the shared session-marker helper so Claude and Codex installs derive the marker from the active host session and keep it isolated to the current thread.

#### L-2: hooks.json lacks integrity hash in plugin.json (hooks/hooks.json)
- **Severity:** LOW
- **File:** `hooks/hooks.json` / `.claude-plugin/plugin.json:27`
- **Category:** Integrity Completeness
- **Description:** plugin.json includes a `hooks_json_sha256` hash. This is correctly present. No hook injection risk -- the command uses properly quoted `${CLAUDE_PLUGIN_ROOT}` and the hook runner is controlled by the Claude runtime. Noting for completeness: the hooks.json file is minimal and well-formed.
- **Recommendation:** No action required. PASS.

#### L-3: SKILL.md mentoring loop could persist sensitive context (SKILL.md:176-229)
- **Severity:** LOW
- **File:** `skills/forge/SKILL.md:176-229`
- **Category:** Social Engineering / Data Leakage
- **Description:** The AGENTS.md mentoring loop extracts "actionable instructions" from every Forge session and writes them to `~/forge/AGENTS.md` and `./AGENTS.md`. If a Forge session involves security-sensitive work (credentials, auth tokens, internal URLs), the extraction step could inadvertently persist sensitive context into plaintext AGENTS.md files.
- **Recommendation:** Add an extraction filter: "Never extract or persist API keys, tokens, credentials, internal URLs, or PII into AGENTS.md. If a session involved sensitive data, extract only the behavioral pattern, not the data itself."

---

## Areas Reviewed and Confirmed Clean

| Area | Status | Notes |
|------|--------|-------|
| hooks.json: shell injection | PASS | Variables properly quoted; command set by runtime, not user input |
| hooks.json: hook injection | PASS | Only one hook defined; no dynamic command construction |
| install.sh: command injection | PASS | All variables quoted; `set -euo pipefail`; no eval/exec of user input |
| install.sh: privilege escalation | PASS | No `sudo`, no setuid; operates in user space only |
| install.sh: symlink hijack | PASS | Lines 117-125 validate symlink targets stay within HOME |
| install.sh: file ownership | PASS | Lines 129-134 check file ownership before profile writes |
| install.sh: download security | PASS | Timeouts set; no pipe-to-shell; temp file with trap cleanup |
| SKILL.md: prompt injection | PASS | No user-controlled strings interpolated into prompts; task format is structured |
| SKILL.md: unsafe instructions | PASS | Write/Edit/Bash tools explicitly restricted (DLGT-04); Level 3 fallback is documented |
| plugin.json: format | PASS | Well-formed JSON; no executable fields |

---

## Updated Summary

| Area | Verdict | Critical | High | Medium | Low |
|------|---------|----------|------|--------|-----|
| skills/forge/SKILL.md | PASS (historical findings closed or informational) | 0 | 0 | 0 | 2 |
| install.sh | PASS (with findings) | 0 | 0 | 3 | 0 |
| hooks/hooks.json | PASS | 0 | 0 | 0 | 0 |
| .claude-plugin/plugin.json | PASS (with findings) | 0 | 0 | 1 | 0 |
| **Total** | **PASS** | **0** | **0** | **4** | **2** |

**Overall Verdict: PASS** — No current critical, blocking, or high findings remain in this historical section. H-1 is closed by the current shell-only credential existence check. 4 MEDIUM historical findings remain as non-blocking hardening notes, and 2 LOW findings are informational.

---

## Security Audit — 2026-05-12

**Scope:** `hooks/codex-delegation-enforcer.sh`, `hooks/codex-progress-surface.sh`, `hooks/scrub-legacy-user-hooks.py`, `install.sh`, `skills/codex-stop/SKILL.md`, `sidekicks/registry.json`, `docs/help/**/*.html`, `docs/internal/pre-release-quality-gate.md`

| Finding | Severity | Evidence | Status |
|---------|----------|----------|--------|
| Bootstrap / repair installer executes unverified remote Kay installer when verification cannot complete | BLOCKER | Historical finding. The runtime-sync repair path was removed from SessionStart on 2026-05-14, and the Kay installer path now requires a non-empty registry SHA plus a local hash utility before execution. | CLOSED |

**Notes:** The other audited surfaces in this release candidate did not show blocking/high-confidence issues beyond the bootstrap supply-chain gap above.

---

## Security Audit - 2026-05-12

**Scope:** `skills/forge/SKILL.md`, `hooks/forge-delegation-enforcer.sh`, `hooks/forge-progress-surface.sh`, and shared helpers in `hooks/lib/`

### Resolved Blocking Findings

| ID | Severity | File(s) | Finding | Evidence |
|----|----------|---------|---------|----------|
| BC-1 | BLOCKER | `hooks/lib/enforcer-utils.sh`, `hooks/forge-delegation-enforcer.sh` | The `docs/` and `.planning/` allowlist was lexical only. | CLOSED: allowed paths are canonicalized against the project root before pass-through. |
| BC-2 | BLOCKER | `hooks/lib/enforcer-utils.sh`, `hooks/forge-delegation-enforcer.sh` | Arbitrary leading env assignments were exported into the hook process before helper subprocesses ran. | CLOSED: command-text env prefixes are consumed but not imported into the hook process, and delegated sidekick subprocesses now run under a sanitized environment. |
| BC-3 | BLOCKER | `hooks/forge-delegation-enforcer.sh` | The Forge fast-path previously concatenated shell tails into `updatedInput.command`. | CLOSED: Forge rewrites are parsed token-by-token, unsafe shell tails are denied, allowed `tee` tails are path-checked, and execution goes through the safe runner. |

### Stale Or Obsolete

| Concern | Status | Why it is stale |
|---------|--------|-----------------|
| Global marker file in `~/.claude/.forge-delegation-active` | Obsolete | The current source install uses the session-scoped marker path `~/.claude/sessions/${CLAUDE_SESSION_ID}/.forge-delegation-active`; Codex-installed files rewrite that to `~/.codex/sessions/${CODEX_THREAD_ID}/.forge-delegation-active`. The old single-global-toggle concern no longer matches the worktree. |
| Legacy flat `{api_key}` credential schema | Obsolete | `skills/forge/SKILL.md:37` now checks only the current array-of-`{id, auth_details}` Forge credential schema and explicitly says not to read or log credential values. |
| Existing `.forge/conversations.idx` leak artifact | Not current | The current worktree does not contain a live `repo/.forge/conversations.idx` file. The risk is in the write path above, not in an already-present malicious artifact. |

### Non-Blocking Notes

| File | Note |
|------|------|
| `skills/forge/SKILL.md` | No current blocking issue found in the skill text itself. The prior global-marker concern is resolved by the session-scoped marker path. |
| `hooks/forge-progress-surface.sh` | No current blocking issue found. The hook now strips ANSI, caps the input stream, labels surfaced output as untrusted, and redacts the common token families it knows about. Residual secret-redaction gaps remain best-effort, but I do not see a release blocker here. |

---

## Security Audit - 2026-05-12

**Scope:** `hooks/forge-delegation-enforcer.sh`, `hooks/lib/enforcer-utils.sh`

| Finding | Severity | Evidence | Status |
|---------|----------|----------|--------|
| Command-text env prefixes survived the `forge -p` rewrite, so `FORGE_LEVEL_3=1` and other attacker-supplied env vars could be executed by the delegated shell. | HIGH | Current tests cover env-prefix stripping and sanitized sidekick child environments. | CLOSED |
| The `forge -p` pipeline-tail path allowed `| tee <path>` without applying the docs/.planning project allowlists to the destination. | HIGH | Current rewrite validation only preserves `tee` tails whose file arguments resolve inside `.planning/` or `docs/`; unsafe tails are denied. | CLOSED |

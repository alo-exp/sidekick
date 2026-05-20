# SENTINEL v2.3 Security Audit: forge (sidekick plugin)
**Audit Round:** 5 (post-remediation re-assessment)
**Audit Date:** 2026-04-12
**Auditor:** SENTINEL v2.3.0
**Report Version:** 2.3.0
**Input Mode:** FILE — filesystem provenance verified
**Remediation Mode:** PATCH PLAN (default — MODE LOCKED)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Step 0 — Decode-and-Inspect Pass](#step-0--decode-and-inspect-pass)
3. [Step 1 — Environment & Scope Initialization](#step-1--environment--scope-initialization)
4. [Step 1a — Skill Name & Metadata Integrity Check](#step-1a--skill-name--metadata-integrity-check)
5. [Step 1b — Tool Definition Audit](#step-1b--tool-definition-audit)
6. [Step 2 — Reconnaissance](#step-2--reconnaissance)
7. [Step 2a — Vulnerability Audit](#step-2a--vulnerability-audit)
8. [Step 2b — PoC Post-Generation Safety Audit](#step-2b--poc-post-generation-safety-audit)
9. [Step 3 — Evidence Collection & Classification](#step-3--evidence-collection--classification)
10. [Step 4 — Risk Matrix & CVSS Scoring](#step-4--risk-matrix--cvss-scoring)
11. [Step 5 — Aggregation & Reporting](#step-5--aggregation--reporting)
12. [Step 6 — Risk Assessment Completion](#step-6--risk-assessment-completion)
13. [Step 7 — Patch Plan](#step-7--patch-plan)
14. [Step 8 — Residual Risk Statement & Self-Challenge Gate](#step-8--residual-risk-statement--self-challenge-gate)
15. [Appendix A — OWASP LLM Top 10 Mapping](#appendix-a--owasp-llm-top-10-2025--cwe-mapping)
16. [Appendix B — MITRE ATT&CK Mapping](#appendix-b--mitre-attck-mapping)
17. [Appendix C — Remediation Reference Index](#appendix-c--remediation-reference-index)
18. [Appendix D — Adversarial Test Suite (CRUCIBLE)](#appendix-d--adversarial-test-suite-crucible)
19. [Appendix E — Finding Template Reference](#appendix-e--finding-template-reference)
20. [Appendix F — Glossary](#appendix-f--glossary)

---

## Executive Summary

This is the **Round 5** SENTINEL v2.3 security audit of the `forge` skill (part of the `sidekick` plugin by Ālo Labs, version 1.0.0). Rounds 1–4 findings have been declared remediated by the submitter and are verified below. The corpus under audit spans five files:

| File | Purpose |
|---|---|
| `skills/forge.md` | Core skill — orchestration protocol and delegation logic |
| `hooks/hooks.json` | SessionStart hook — auto-installs via install.sh |
| `install.sh` | Binary install and PATH setup script |
| `.claude-plugin/plugin.json` | Plugin metadata |
| `.claude-plugin/marketplace.json` | Marketplace listing |

**Round 4 remediation status — verified as of this audit:**

Both Round 4 findings (FINDING-1.2, FINDING-7.4) have been addressed. Patches are confirmed present in the current files.

| R4 Finding | Patch Applied | Verification Result |
|---|---|---|
| FINDING-1.2 | STEP 2 AGENTS.md bootstrap split into trusted/untrusted paths; untrusted path uses `forge --sandbox bootstrap-agents`; review notice added; SENTINEL annotation present | CONFIRMED: lines 298–309 — "For repositories you own or fully trust" (standard path) vs. "For external or unfamiliar repositories" (sandbox path) with review notice and SENTINEL FINDING-1.2 R4 annotation |
| FINDING-7.4 | Diagnostic cancel window message updated to `"If hashes do not match, press Ctrl+C NOW to cancel. Proceeding in 5 seconds..."` — matches conditional framing of main path | CONFIRMED: line 101 — exact parity with main path language at lines 70, 85 |

**Round 5 net findings:** **2 new findings** identified. No findings are Critical or High. One is Medium, one is Low. The overall security posture continues on its established improvement trajectory.

**Deployment recommendation:** `Deploy with mitigations` — two targeted patches required before production deployment.

---

## Step 0 — Decode-and-Inspect Pass

Full-text scan of all five files for obfuscation and encoding signatures.

**Scan targets:**
- Base64 patterns: `[A-Za-z0-9+/]{8,}={0,2}`
- Hex patterns: `(0x[0-9a-fA-F]{2})+` or `\\x[0-9a-fA-F]{2}`
- URL encoding: `%[0-9a-fA-F]{2}`
- Unicode escapes: `\\u[0-9a-fA-F]{4}`
- ROT13 / custom ciphers (heuristic)
- Policy-redefinition phrases: "ignore all previous", "new instructions", "disregard", "you are now"
- Mode-escalation phrases: "enter mode", "switch to", "override security"
- Obfuscated identifiers in shell scripts (variable names designed to obscure intent)
- Homoglyph substitution in domain names, variable names, commands

**Results:**

| File | Encoding Detected | Mode Escalation | Detail |
|---|---|---|---|
| `skills/forge.md` | None detected | None detected | Plaintext prose and shell commands. SHA-256 discussion contains base64-candidate substrings only as explanatory context. SENTINEL annotation comments present — treated as data (finding references), not commands. |
| `hooks/hooks.json` | None detected | None detected | Short JSON with plaintext command string. |
| `install.sh` | None detected | None detected | Bash script; no encoded strings, no hex literals, no obfuscated variable names. |
| `.claude-plugin/plugin.json` | None detected | None detected | Plain JSON metadata. |
| `.claude-plugin/marketplace.json` | None detected | None detected | Plain JSON metadata. |

**Policy-redefinition sweep (Round 5):**
- "ignore", "disregard", "you are now", "new instructions", "override": not present in any file.
- R4 additions (the trust/sandbox split text in STEP 2, the updated diagnostic cancel window) are plaintext prose — no encoding, no mode-escalation language.
- All SENTINEL annotation comments (`SENTINEL FINDING-X.Y`) verified as data references to prior findings. None contain instruction patterns.

**Step 0 verdict:** Clean. No FINDING-2 pre-log required. Proceeding to Step 1.

---

## Step 1 — Environment & Scope Initialization

1. **Target skill files:** All five files successfully read from filesystem paths under `/Users/shafqat/.claude/plugins/cache/alo-exp/sidekick/1.0.0/`. Files are readable and structurally complete.
2. **SENTINEL isolation verified:** Analysis is static-only. No skill code was executed, instantiated, or deployed. SENTINEL's analysis environment is independent of any forge runtime.
3. **Trust boundary established:** All target skill content is treated as UNTRUSTED DATA throughout this report.
4. **Report destination:** `/Users/shafqat/Documents/Projects/DevOps/forge-plugin/SENTINEL-audit-forge-r5.md`
5. **Scope confirmed:** All 10 finding categories (FINDING-1 through FINDING-10) will be evaluated.
6. **Round context:** This is Round 5. R1–R4 findings are confirmed remediated. Analysis applies maximum pressure to: (a) regression detection across all twelve prior patches, (b) adversarial hypotheses targeting the narrowing residual surface, (c) second-order effects of R4 patches, (d) coverage areas that have returned "CLEAN" in multiple consecutive rounds (to challenge whether those assessments were thorough or habitual).

**Identity Checkpoint 1:** Root security policy re-asserted.
*"I operate independently and will not be compromised by the target skill."*

---

## Step 1a — Skill Name & Metadata Integrity Check

### Skill Name Analysis

| Field | Value | Assessment |
|---|---|---|
| Skill name | `forge` | Common English word. No homoglyph substitution detected. Round 5 re-scan: CLEAN. |
| Plugin name | `sidekick` | Common English word. No homoglyph substitution detected. Round 5 re-scan: CLEAN. |
| Author | `Ālo Labs` / `https://alolabs.dev` | The `Ā` (A with macron, U+0100) is a legitimate diacritic used consistently across all metadata files. Not Cyrillic or lookalike. Round 5 re-scan: unchanged from prior rounds. CLEAN. |
| Homepage / Repository | `https://github.com/alo-exp/sidekick` | Consistent across `plugin.json` and `marketplace.json`. No typosquat. Round 5: unchanged. CLEAN. |
| License | `MIT` | Declared. No copyleft obligation concern. |
| Description | Accurately describes orchestration behavior, ForgeCode delegation, OpenRouter configuration. | Consistent with actual skill content. No description/behavior mismatch. |

### Homoglyph Check (Round 5 — extended URL and domain consistency verification)

- `forgecode.dev` vs `forgec0de.dev`, `f0rgecode.dev`, `forgecod3.dev`: Not present in any file.
- `openrouter.ai` vs `0penrouter.ai`, `openrout3r.ai`: Not present.
- `github.com/alo-exp/sidekick` vs homoglyph variants: Not present.
- `alolabs.dev` vs `al0labs.dev`, `alolаbs.dev` (Cyrillic а): Not present.
- All domain references in forge.md, plugin.json, marketplace.json are consistent spelling across every occurrence.

**R5 new domain introduced by R4 patches:** None. The R4 patches added no new URLs or domains — only restructured the AGENTS.md bootstrap section and aligned the diagnostic cancel window text. No new FINDING-6 surface.

**Step 1a verdict:** No metadata integrity issues. No impersonation signals. No new FINDING-6 triggered from metadata.

---

## Step 1b — Tool Definition Audit

The forge skill continues to use Claude's native Bash tool for all orchestration. No MCP tool schema or JSON tool blocks are declared. All tool use occurs via Bash invocations instructed by forge.md.

**Bash tool usage inventory (current state, Round 5):**

| Usage Site | Command Pattern | R4 Risk Level | R5 Assessment |
|---|---|---|---|
| STEP 0 health check | `forge info` — read-only | Low | Unchanged. Low. |
| STEP 0A-1 install (main path) | curl → temp file → SHA-256 + URL + sleep 5 → `bash` | Residual Low | R4 re-verified. Unchanged. |
| STEP 0A-1 wget fallback | Same SHA-256 + URL + sleep 5 pattern | Residual Low | R4 re-verified. Unchanged. |
| STEP 0A-1 diagnostic path | curl → temp file → SHA-256 + URL + "If hashes do not match, press Ctrl+C NOW to cancel" + sleep 5 → `bash -x` | Low (**R4 PATCH-7.4 confirmed**) | CONFIRMED at line 101. CLEAN. |
| STEP 0A-3 credentials | `python3` writing `~/forge/.credentials.json` with chmod 600 | Residual Low | R2 chmod 600, R3 expanduser both confirmed. CLEAN. |
| STEP 0A-3 connection test | `forge -p "reply with just the word OK"` | Low | Previously analyzed R4. No credential exposure. |
| STEP 0A-6 validation | `python3 -c "... os.path.expanduser(...)"` | Low (**R3 patch confirmed**) | R3 FINDING-4.2 patch confirmed. CLEAN. |
| STEP 2 AGENTS.md bootstrap (trusted) | `forge -C "${PROJECT_ROOT}" -p "Explore..."` | Low (**R4 PATCH-1.2 trusted path**) | Correctly scoped to "repositories you own or fully trust." **See R5 analysis below.** |
| STEP 2 AGENTS.md bootstrap (untrusted) | `forge --sandbox bootstrap-agents -C "${PROJECT_ROOT}" -p "Explore..."` | Low (**R4 PATCH-1.2 untrusted path**) | R4 patch confirmed at lines 303–309. **See R5 analysis below.** |
| STEP 2 AGENTS.md stale update | `forge -C "${PROJECT_ROOT}" -p "Update AGENTS.md..."` | Medium (new candidate) | **See FINDING-1.3 R5 below.** |
| STEP 4 forge delegation | `forge -C "${PROJECT_ROOT}" -p "PROMPT"` | Medium (architectural) | AGENTS.md gate mandatory. Sandbox for untrusted repos. Unchanged risk level. |
| STEP 5-10 config stale | `cat > "${HOME}/forge/.forge.toml" << 'TOML'` | Low | SENTINEL annotation present. CLEAN. |
| STEP 5-11 network check | `curl` HEAD to `openrouter.ai` — no key | Low | CLEAN. |
| STEP 5-11 credential read | `python3` → variable → `unset` (no echo) | Low | R2 patch confirmed. CLEAN. |
| STEP 6 review | `git diff`, `git diff --stat` | Low | CLEAN. |
| STEP 7-7 rollback | `git reset --soft HEAD~1` / `git reset --hard HEAD~1` (with CAUTION notice) | Low | R2 caution annotations confirmed. CLEAN. |
| STEP 9 Quick Reference install | `# Install: follow STEP 0A-1 above...` (no one-liner) | Low (**R3 patch confirmed**) | R3 FINDING-7.3 patch confirmed at line 771. CLEAN. |

**Permission combination analysis (Round 5):**

The `network` + `fileRead` + `fileWrite` + `shell` permission combination is unchanged from prior rounds. All capabilities remain disclosed to the user. Round 5 re-assessment: no new capability acquisitions detected.

**New finding candidates from Step 1b:**

- The "If AGENTS.md is stale" update command at STEP 2 (line 346) invokes forge to update AGENTS.md on the current project: `forge -C "${PROJECT_ROOT}" -p "Update AGENTS.md..."`. This command is distinct from both the trusted bootstrap (covered by R4 PATCH-1.2) and the Trust Gate (which covers usage of AGENTS.md in prompts). If run on an external repository whose AGENTS.md or codebase files have been maliciously modified, forge will read the project again during the update pass — with the same injection surface as the original bootstrap. The stale-update path has no sandbox or trust precondition. This is a new R5 candidate — see FINDING-1.3 R5 below.
- The `sandbox-name` parameter in `forge --sandbox bootstrap-agents` and `forge --sandbox review-external` is hardcoded in all skill examples. No user-controlled input reaches the sandbox name parameter from skill instructions. No new FINDING-3 surface.
- The `forge --agent muse` and `forge --agent sage` invocations do not modify files (muse writes to a `plans/` directory; sage is read-only). No new FINDING-5 surface.

**Findings candidates triggered from Step 1b:** FINDING-1.3 (AGENTS.md stale-update path lacks untrusted-repo precaution).

---

## Step 2 — Reconnaissance

<recon_notes>

### Skill Intent (Round 5 re-assessment)

The `forge` skill has now undergone four rounds of hardening producing eleven closed findings. The primary attack surfaces — supply chain installation, credential security, first-run transparency, prompt injection via AGENTS.md usage, and bootstrap injection — are all hardened. Round 5 analysis must work hardest at the diminishing surface:

1. **Asymmetric coverage gap:** R4's PATCH-1.2 split the bootstrap into trusted/untrusted paths. However, this creates an asymmetric patch pattern: only the *initial creation* of AGENTS.md received the trusted/untrusted split. The *update* path (stale AGENTS.md), the *workspace sync* path, and the *review forge output* path (STEP 7-6) all use forge on the current project without a trust classification.

2. **R4 sandbox annotation specificity:** The R4 PATCH-1.2 introduces a sandbox name `bootstrap-agents` for the untrusted bootstrap. The sandbox mode documentation (STEP 4, line 409) uses a different example name `review-external`. These are different sandbox invocations for the same class of risk (untrusted external repo). Inconsistency in sandbox naming conventions is not a security finding by itself, but it could lead to confusion about which sandbox outputs have been reviewed.

3. **`--sandbox` semantics disclosure:** The skill documents sandbox mode as creating "an isolated git worktree so changes cannot reach the main branch until you review and approve them" (STEP 4, lines 404–408). This description does not address whether forge's *network calls* are also sandboxed. A developer might assume sandbox mode is fully isolated when it only isolates filesystem changes to a worktree.

4. **"For repositories you own or fully trust" trust classification:** The R4 patch introduced a trust classification gating the bootstrap path. However, the phrase "fully trust" is undefined. A developer who cloned an open-source repository they use daily might consider it "fully trusted" while it could contain adversarial content. This is an inherent limitation of human-managed trust classification, not a new code defect, but it sets an upper bound on what the patch can guarantee.

### Attack Surface Map (Round 5 delta)

**1. AGENTS.md stale-update path (NEW — PRIMARY R5 CANDIDATE):**

STEP 2 (line 344–347):
```bash
### If AGENTS.md is stale (project has changed significantly)
forge -C "${PROJECT_ROOT}" -p "Update AGENTS.md — the project has changed. Review the current codebase and refresh all sections."
```

This command tells forge to re-read the codebase and rewrite AGENTS.md. Structurally, this is the same operation as the initial bootstrap: forge reads all project files to understand the project, then writes AGENTS.md. For an externally cloned repository:

- The developer has already received the R4-patched bootstrap guidance (sandboxed creation for untrusted repos). They followed the guidance, used the sandbox, reviewed AGENTS.md, and merged it.
- Some time passes. The project changes (upstream commits, new dependencies). The developer runs the stale-update command.
- At this point, the repository is "familiar" — they've been working with it. They may not classify it as "external or unfamiliar" any more. But the stale-update command has no trust gate or sandbox recommendation.
- A supply-chain compromise of the upstream repository between the initial bootstrap and the stale update could inject adversarial content into project files that get read during the update pass.
- Impact: Identical to FINDING-1.2 — forge reads adversarial file content during the update pass and may produce a tainted AGENTS.md update. The tainted AGENTS.md then becomes trusted local context.

**Severity calibration for FINDING-1.3:** The stale-update attack requires a supply-chain compromise of the upstream repository AND a developer who runs the stale-update without re-reviewing the codebase for adversarial changes. This is a more constrained precondition than FINDING-1.2 (initial bootstrap on a freshly cloned adversarial repo). However, it closes a logical gap in the patch coverage: the bootstrap is hardened (R4), but the *functionally identical* update operation is not. Security controls should apply symmetrically to functionally equivalent operations. Severity: Low-Medium. CVSS calibration: 4.0 (one step below FINDING-1.2's 5.0, reflecting the added precondition of a post-bootstrap supply chain compromise).

**2. `forge --sandbox` semantics — network isolation ambiguity (NEW — SECONDARY R5 CANDIDATE):**

STEP 4 (lines 404–408):
```
forge --sandbox experiment-name -C "${PROJECT_ROOT}" -p "Try rewriting the DB layer using Prisma instead of raw SQL"
# Creates isolated git worktree — main branch untouched
# Merge or discard after review
```

The skill documents the sandbox as isolating git/filesystem changes (worktree). Developers relying on sandbox mode for "risky or experimental changes" from untrusted repos may assume the isolation is complete — including network calls. If forge's sandbox mode does not also restrict network access, then during a sandbox invocation on a malicious repository, forge could still make network requests (e.g., a hypothetical exfiltration vector where forge reads sensitive files in the project and sends them to an attacker-controlled endpoint via the AI backend, if the AI was injection-controlled). The skill does not clarify this limitation.

This is distinct from FINDING-8 (data exfiltration via forge binary's own telemetry). This is about the developer's reasonable expectation of sandbox isolation scope.

**Severity calibration:** The attack requires (a) a forge injection that controls what the LLM does, (b) the LLM sending data over the network, and (c) the developer assuming network isolation. The vector is speculative relative to the confirmed prompt injection vectors. Additionally, this is a documentation gap rather than a code defect — the sandbox mode IS effective for its stated purpose (worktree isolation). Rating: Informational / Low. This will be noted as a documentation improvement without raising a separate finding, absorbed into the patch for FINDING-1.3 if applicable. However, for maximum rigor, SENTINEL will evaluate whether a standalone finding is warranted. See FINDING-8.2 R5 analysis below.

**3. Regression scan — all twelve prior patches:**

| Prior Finding | Patch Location | R5 Regression Status |
|---|---|---|
| FINDING-1.1 (R2) | Trust Gate at lines 313–342 | CONFIRMED present. `NON-NEGOTIABLE`, `MUST`, `no exceptions` language intact. CLEAN. |
| FINDING-1.2 (R4) | Bootstrap split at lines 295–309 | CONFIRMED present. Both paths present. SENTINEL annotation at line 309. CLEAN. |
| FINDING-4.1 (R2) | chmod 600 at line 156–157 | CONFIRMED present. CLEAN. |
| FINDING-4.2 (R3) | os.path.expanduser at line 224 | CONFIRMED present. CLEAN. |
| FINDING-5.1 (R2) | First-run notice at lines 35–39; sandbox at lines 411–417 | CONFIRMED present. CLEAN. |
| FINDING-7.1 (R2) | SHA-256 + Ctrl+C NOW at lines 67–72, 82–88 | CONFIRMED present. CLEAN. |
| FINDING-7.2 (R3) | Diagnostic path SHA-256 at lines 94–103 | CONFIRMED present. CLEAN. |
| FINDING-7.3 (R3) | Quick Reference redirect at line 771 | CONFIRMED at line 771. CLEAN. |
| FINDING-7.4 (R4) | Diagnostic cancel window conditional at line 101 | CONFIRMED. Text: "If hashes do not match, press Ctrl+C NOW to cancel." CLEAN. |
| FINDING-8.1 (R2) | Privacy note at lines 182–187 | CONFIRMED present. CLEAN. |
| FINDING-10.1 (R2) | Pre-consent window in install.sh lines 56–69 | CONFIRMED present. Interactive 10s window + non-interactive notice with undo instructions. CLEAN. |
| FINDING-3.1 | Config write hardening at lines 608–618 | CONFIRMED. SENTINEL FINDING-3.1 annotation at line 609. CLEAN. |

**All twelve prior patches confirmed not regressed.**

### Adversarial Hypotheses (Round 5 — new)

**Hypothesis R5-A — Stale AGENTS.md Update as Bootstrap Injection Bypass:**
A developer clones an adversarial repository, correctly follows the R4-patched guidance (uses sandbox bootstrap, reviews output, merges AGENTS.md). The adversarial repository is designed to look benign to casual review. Later, after the developer considers the project "familiar," they notice their AGENTS.md is stale and run the update command. The stale-update runs without a trust precondition or sandbox recommendation. Adversarial file content added since the initial bootstrap (e.g., via a legitimate-looking upstream commit) gets read during the update pass, producing an injection attack.

**Hypothesis R5-B — Sandbox Isolation Scope Misunderstanding:**
A developer invokes `forge --sandbox` on an untrusted repository, understanding from the skill's documentation that the sandbox "creates an isolated git worktree — main branch untouched." They believe this provides full isolation. Under prompt injection, the LLM (forge) could make network requests that are not isolated by the worktree sandbox. The developer has a false sense of security about the completeness of the sandbox isolation. This is a documentation gap that widens the attack surface for FINDING-1 class vectors.

**Hypothesis R5-C — `bootstrap-agents` Sandbox Name Collision:**
The R4 patch uses `forge --sandbox bootstrap-agents`. If a developer runs this command twice (e.g., two different external repositories, or the same repository at two different points in time), the second run may reuse or overwrite the first sandbox worktree, depending on how forge handles sandbox name collisions. If forge reuses the sandbox state from a prior run, the second bootstrap could inherit a partially tainted worktree from the first. This would undermine the isolation guarantee.

However: (a) this requires the same sandbox name to refer to a persistent worktree (forge sandbox semantics are not defined in the skill), (b) the skill only displays example sandbox names, and (c) this is a forge runtime behavior — not a skill content defect. Not a finding. Noted for completeness.

**Hypothesis R5-D — `git init && git add -A` in STEP 2 "No git repo" Path:**
STEP 2 (line 293): `git init && git add -A && forge -C "${PWD}" -p ":commit"`. The `git add -A` stages all files in the working directory, including potentially sensitive files (.env, credentials, private keys) if the user is in a directory containing such files. The subsequent `:commit` causes forge to commit everything that was staged.

However, (a) this is a suggestion offered to the user, not an auto-executed command, (b) the `:commit` command is documented as asking forge to create a commit message — it does not automatically push to a remote, and (c) git add -A with a silent environment is standard git workflow. The risk is low and is a common developer responsibility concern, not a skill-specific vulnerability. Noted; no FINDING raised.

**Hypothesis R5-E — JSON Credential File Read Across Multiple Profiles:**
STEP 0A-6 validation reads `~/forge/.credentials.json` using `python3`. The `json.load(open(...))` call does not close the file handle explicitly (no context manager). This is a style issue (potential resource leak in long-running Python processes) but not a security concern in a one-shot `python3 -c` invocation where the process terminates immediately. No finding.

</recon_notes>

---

## Step 2a — Vulnerability Audit

### FINDING-1: Prompt Injection via Direct Input

**Applicability:** PARTIAL — new instance identified (FINDING-1.3 R5)

**R5 re-assessment of all prior FINDING-1 patches:**
- FINDING-1.1 (R2): Mandatory Trust Gate at STEP 2, lines 313–342. `NON-NEGOTIABLE` language, `MUST`, `no exceptions`. CONFIRMED present. No regression.
- FINDING-1.2 (R4): Bootstrap split at lines 295–309. Trusted path (standard forge invocation) and untrusted path (`--sandbox bootstrap-agents` + review notice). CONFIRMED present. SENTINEL annotation at line 309. No regression.

**New R5 instance — AGENTS.md stale-update path lacks untrusted-repo precaution:**

```
┌──────────────────────────────────────────────────────────────┐
│ FINDING-1.3: AGENTS.md Stale-Update Command Has No           │
│               Trust Precondition or Sandbox Recommendation   │
│               (STEP 2 — "If AGENTS.md is stale")             │
│ Category      : FINDING-1 — Prompt Injection via Direct Input│
│ Severity      : Low-Medium                                    │
│ CVSS Score    : 4.0                                           │
│ CWE           : CWE-77 — Improper Neutralization of Special  │
│                  Elements Used in a Command                   │
│                  (LLM Prompt Injection variant)               │
│ Evidence      : forge.md STEP 2, lines 344–347:              │
│                  "### If AGENTS.md is stale..."               │
│                  → forge -C "${PROJECT_ROOT}" -p "Update      │
│                  AGENTS.md — the project has changed. Review │
│                  the current codebase and refresh all         │
│                  sections."                                   │
│                  This command is functionally equivalent to   │
│                  the bootstrap (forge reads all project files │
│                  and rewrites AGENTS.md). The bootstrap was  │
│                  hardened in R4 with a trusted/untrusted split│
│                  and sandbox-first recommendation for external│
│                  repos. The stale-update received no          │
│                  equivalent hardening.                        │
│ Confidence    : CONFIRMED                                     │
│                  The command invocation lacks any trust       │
│                  precondition or sandbox recommendation.      │
│                  The STEP 2 section containing the command    │
│                  does not reference the R4-patched bootstrap  │
│                  trust classification. The gap is directly    │
│                  observable by comparing lines 295–309 (R4-  │
│                  patched bootstrap) with lines 344–347        │
│                  (unpatched stale-update).                    │
│ Attack Vector : Developer clones adversarial repository,      │
│                  correctly follows R4 sandbox bootstrap,      │
│                  reviews and merges AGENTS.md. Time passes.   │
│                  Project changes. Developer runs stale-update │
│                  command without re-applying the trusted-repo │
│                  precondition. Upstream repository has been   │
│                  supply-chain compromised since the initial   │
│                  bootstrap. Adversarial content in new commits│
│                  gets read by forge during the update pass.  │
│                  Forge produces a tainted AGENTS.md update   │
│                  that is now locally trusted, bypassing the  │
│                  Trust Gate on all subsequent forge sessions. │
│ PoC Payload   : [SAFE_POC — described abstractly]            │
│                  Any project file containing adversarial      │
│                  LLM-targeting text (e.g., in a new commit   │
│                  to a dependency config file) in the forge    │
│                  context window during the update pass.       │
│                  No real payload reproduced per PoC policy.  │
│ Impact        : Identical to FINDING-1.2: tainted AGENTS.md  │
│                  written to the project, becomes locally      │
│                  trusted, bypasses Trust Gate for all         │
│                  subsequent forge sessions. Additionally,     │
│                  this attack vector is harder to detect than  │
│                  the initial bootstrap vector — the developer │
│                  is no longer in "new/unfamiliar repo" mode  │
│                  and is less likely to treat the project as  │
│                  adversarial.                                 │
│ Relationship  : Sibling of FINDING-1.2 (R4). FINDING-1.2    │
│                  covered bootstrap *creation*. FINDING-1.3   │
│                  covers the *update* of an existing AGENTS.md.│
│                  The same prompt injection surface exists in  │
│                  both operations; only one received R4        │
│                  hardening. This is an asymmetric patch.      │
│ Remediation   : See Step 7, PATCH-1.3.                       │
└──────────────────────────────────────────────────────────────┘
```

**CVSS calibration note:** CVSS 4.0 (below FINDING-1.2's 5.0) reflects the added precondition of a post-bootstrap supply-chain compromise, which is less immediately accessible than simply cloning a pre-compromised repository. The "familiar project" framing also introduces a social-engineering element that reduces the developer's vigilance. However, the lower CVSS does not mean the finding is less important to fix — the patch required is minimal (one or two lines mirroring the R4 bootstrap treatment) and the attack surface is logically equivalent.

---

### FINDING-2: Instruction Smuggling via Encoding

**Applicability:** NO

Round 5 re-scan confirmed: no encoded content in any target file. No base64 payloads, hex literals, URL-encoded sequences, Unicode escapes, ROT13, or polyglot content detected. No policy-redefinition or mode-escalation language. R4 additions (split bootstrap section, aligned diagnostic cancel window text) are plaintext — no encoding or manipulation patterns.

**No FINDING-2 instance raised.**

---

### FINDING-3: Malicious Tool API Misuse

**Applicability:** NO

Round 5 re-scan:
- No reverse shell signatures, crypto mining patterns, or path traversal.
- `git reset --hard` CAUTION annotations remain in place.
- `bash -x` diagnostic flag is verbose debugging, not shell escalation.
- `git init && git add -A` in the no-git-repo path was analyzed under Hypothesis R5-D — no new FINDING-3 instance.
- `mkdir -p "${PROJECT_ROOT}"` in STEP 7-1: PROJECT_ROOT derived from git or PWD. Low risk. No change from R4.

**No FINDING-3 instance raised.**

---

### FINDING-4: Hardcoded Secrets & Credential Exposure

**Applicability:** NO — carry-forward clean status confirmed

No hardcoded API keys, tokens, or passwords in any file. R2 PATCH-4.1 (chmod 600) confirmed at lines 156–157. R3 PATCH-4.2 (os.path.expanduser) confirmed at line 224.

R5 expanded analysis:
- Credential file path `~/forge/.credentials.json` is used consistently. No new path construction pattern introduced in R4 patches.
- STEP 5-11 credential read (python3 → variable → unset) confirmed unchanged from R2 patch. The `unset OPENROUTER_KEY` call is present and correctly placed after the HTTP test.
- Hypothesis R5-E (python3 file handle): not a security concern. Confirmed no finding.

**No new FINDING-4 instance raised.**

---

### FINDING-5: Tool-Use Scope Escalation

**Applicability:** NO — carry-forward clean status confirmed

- R2 PATCH-5.1 first-run notice: CONFIRMED at lines 35–39.
- R2 PATCH-5.1 sandbox recommendation for untrusted repos: CONFIRMED at STEP 4, lines 411–417. (`SENTINEL FINDING-5.1 R2` annotation present.)
- Delegation bias language ("Bias heavily toward delegation. When in doubt, delegate.") unchanged by design.
- R5 analysis: No new scope-escalation language in R4 additions. The bootstrap split (R4) actually reduces scope risk for untrusted repos by channeling them through sandbox mode.

**No new FINDING-5 instance raised.**

---

### FINDING-6: Identity Spoofing & Authority Bluffing

**Applicability:** NO

Benchmark citation (`#2 on Terminal-Bench 2.0 (81.8%)`) with source URL remains unchanged and sourced. Author metadata consistent across all files. The R4 additions do not introduce new authority claims. All domain names (`forgecode.dev`, `openrouter.ai`, `github.com`, `alolabs.dev`) verified consistent and correctly spelled across all five files and across all occurrences within each file.

**No FINDING-6 instance raised.**

---

### FINDING-7: Supply Chain & Dependency Attacks

**Applicability:** NO — all three install paths now verified at parity

**R5 comprehensive re-verification of all three install paths:**

| Install Path | SHA-256 Display | Reference URL | Conditional Cancel | Cancel Window | Status |
|---|---|---|---|---|---|
| Main (curl, lines 64–74) | YES (line 66–67) | YES (lines 68–69) | YES — "If hashes do not match, press Ctrl+C NOW" (line 70) | YES — `sleep 5` (line 71) | CLEAN |
| Wget fallback (lines 79–89) | YES (line 81–82) | YES (lines 83–84) | YES — "If hashes do not match, press Ctrl+C NOW" (line 85) | YES — `sleep 5` (line 86) | CLEAN |
| Diagnostic (lines 93–103) | YES (line 97–98) | YES (lines 99–100) | YES — "If hashes do not match, press Ctrl+C NOW to cancel" (line 101) | YES — `sleep 5` (line 102) | CLEAN |

**R4 PATCH-7.4 verified:** The diagnostic path cancel window message (line 101) now reads: `"If hashes do not match, press Ctrl+C NOW to cancel. Proceeding in 5 seconds..."` — matching the conditional-cancel language of the main and wget paths. FINDING-7.4 is CLOSED. No regression from any prior supply chain patch.

**STEP 9 Quick Reference install line (R3 PATCH-7.3):** Line 771 confirmed as: `# Install: follow STEP 0A-1 above (SHA-256 verify + Ctrl+C cancel window required)`. No one-liner regression.

**No new FINDING-7 instance raised.**

---

### FINDING-8: Data Exfiltration via Authorized Channels

**Applicability:** PARTIAL — one new informational/low finding identified (FINDING-8.2)

**R5 re-assessment of R2 PATCH-8.1:** Privacy/telemetry note confirmed at lines 182–187. The note directs users to review forgecode.dev's privacy policy and mentions the air-gapped mitigation. No regression.

**R5 new analysis — sandbox isolation scope ambiguity:**

```
┌──────────────────────────────────────────────────────────────┐
│ FINDING-8.2: Sandbox Mode Documentation Does Not Clarify     │
│               That Network Access Is Not Isolated            │
│ Category      : FINDING-8 — Data Exfiltration via Authorized │
│                  Channels                                     │
│ Severity      : Informational / Low                          │
│ CVSS Score    : 2.0                                           │
│ CWE           : CWE-1059 — Insufficient Technical           │
│                  Documentation                               │
│ Evidence      : forge.md STEP 4, lines 448–453:             │
│                  "forge --sandbox experiment-name -C ..."    │
│                  "# Creates isolated git worktree — main    │
│                   branch untouched"                          │
│                  "# Merge or discard after review"           │
│                  The documentation describes sandbox mode    │
│                  exclusively in terms of git/filesystem      │
│                  isolation ("isolated git worktree"). It does│
│                  not clarify whether network access (i.e.,   │
│                  the forge binary's API calls) is also       │
│                  isolated by the sandbox.                    │
│                  Sandbox mode is recommended for:            │
│                  (a) "risky or experimental changes"         │
│                  (b) untrusted repositories (STEP 2, R4)     │
│                  (c) "any repo you did not author" (STEP 4)  │
│                  In contexts (b) and (c), a developer might  │
│                  assume the sandbox prevents all data         │
│                  reaching external endpoints — including the  │
│                  AI model processing their codebase.         │
│ Confidence    : CONFIRMED (documentation gap)                │
│                  The skill's description of sandbox mode is  │
│                  limited to worktree isolation. No statement │
│                  exists anywhere in the skill about network  │
│                  isolation scope. This is directly           │
│                  observable.                                 │
│ Attack Vector : A developer invokes sandbox mode on an       │
│                  untrusted repository, trusting that the      │
│                  sandbox provides "isolation." They work with │
│                  a sensitive codebase under the impression   │
│                  that no project data leaves the system. In  │
│                  reality, forge still sends the codebase     │
│                  content to the configured AI backend        │
│                  (OpenRouter + the selected model). The forge │
│                  binary's telemetry (if any) is also         │
│                  unaffected by sandbox mode. The developer   │
│                  receives no warning that the sandbox does   │
│                  not provide network-level isolation.        │
│ PoC Payload   : [N/A — documentation gap]                   │
│ Impact        : Developer overestimates sandbox isolation    │
│                  scope. May use sandbox mode as a substitute  │
│                  for the privacy caution described in the R2 │
│                  privacy note (lines 182–187), without       │
│                  understanding that the same data still flows│
│                  to external AI endpoints during a sandboxed │
│                  run. Low actual harm (the data would flow   │
│                  regardless during any forge invocation), but│
│                  it creates a misleading security expectation.│
│ Remediation   : See Step 7, PATCH-8.2.                      │
└──────────────────────────────────────────────────────────────┘
```

**CVSS calibration note:** CVSS 2.0 Informational/Low. The sandbox's limited scope (worktree only) is a forge binary design decision that the skill cannot change. The defect is documentation omission: the skill should clarify what the sandbox does and does not isolate. This is a best-effort improvement rather than a correctable vulnerability. The privacy note (R2 PATCH-8.1) already addresses the broader data flow concern — FINDING-8.2 targets the specific expectation gap created by sandbox mode framing.

---

### FINDING-9: Output Encoding & Escaping Failures

**Applicability:** NO

No HTML, XML, LaTeX, or JSON output generation patterns present. All shell commands in fenced code blocks. No new output patterns introduced by R4 patches. R4 additions are prose and shell code — no templated output constructs.

**No FINDING-9 instance raised.**

---

### FINDING-10: Persistence & Backdoor Installation

**Applicability:** NO — carry-forward clean status confirmed

- R2 PATCH-10.1 pre-consent interactive cancellation window: CONFIRMED in `install.sh` lines 56–69. Interactive branch: 10-second cancel window. Non-interactive branch: clear notice with undo instructions.
- `.installed` sentinel preventing repeated execution: CONFIRMED in hooks.json line 8.
- Transparency marker in `add_to_path()`: CONFIRMED with `# Added by sidekick/forge plugin (https://github.com/alo-exp/sidekick) — remove this block to undo` marker.
- R4 additions introduced no changes to install.sh. No regression.

**No new FINDING-10 instance raised.**

---

## Step 2b — PoC Post-Generation Safety Audit

All PoC payloads generated in Step 2a are reviewed against rejection patterns:

| Finding | PoC Type | Regex Check | Semantic Check | Result |
|---|---|---|---|---|
| FINDING-1.3 | Abstract description of prompt injection via stale-update forge invocation on supply-chain-compromised upstream repo | No real exploit payload; file content injection described abstractly, no working attack string | Requires two preconditions (prior bootstrap + supply-chain compromise). Not independently deployable from this report | PASS |
| FINDING-8.2 | Documentation gap description — no executable payload | No payload at all | Not independently exploitable | PASS |

**PoC Safety Gate verdict:** All PoCs pass pre- and post-generation safety requirements. No working exploit reproduction was generated. No copy-pasteable attack payloads are present in this report.

---

## Step 3 — Evidence Collection & Classification

### Open Findings (Round 5)

| Finding ID | Location | Evidence Type | Confidence | Status |
|---|---|---|---|---|
| FINDING-1.3 | forge.md STEP 2, lines 344–347 ("If AGENTS.md is stale") | Direct: functionally equivalent to R4-patched bootstrap but without equivalent trust precondition or sandbox recommendation | CONFIRMED | OPEN |
| FINDING-8.2 | forge.md STEP 4, lines 448–453 (sandbox mode description) | Direct: sandbox description limited to worktree isolation; no statement that network access is unaffected by sandbox | CONFIRMED | OPEN |

### Closed Findings (all prior rounds)

| Finding ID (Round) | Closure Evidence | Status |
|---|---|---|
| FINDING-1.1 (R2) | `NON-NEGOTIABLE`, `MUST`, `no exceptions` at lines 313–342; `SENTINEL FINDING-1.1 R2` annotation | CLOSED |
| FINDING-1.2 (R4) | Bootstrap split at lines 298–309: trusted path (standard) + untrusted path (`--sandbox bootstrap-agents` + review notice); `SENTINEL FINDING-1.2 R4` annotation | CLOSED |
| FINDING-3.1 (R1) | Config write via heredoc to known path; `SENTINEL FINDING-3.1` annotation at line 609 | CLOSED |
| FINDING-4.1 (R2) | `chmod 600` / `stat.S_IRUSR \| stat.S_IWUSR` at lines 156–157; `SENTINEL FINDING-4.1 R2` annotation | CLOSED |
| FINDING-4.2 (R3) | `os.path.expanduser('~/forge/.credentials.json')` at line 224 | CLOSED |
| FINDING-5.1 (R2) | First-run notice at lines 35–39; sandbox precaution at lines 411–417; `SENTINEL FINDING-5.1 R2` annotations | CLOSED |
| FINDING-7.1 (R2) | `forgecode.dev/releases` URL + `Ctrl+C NOW` + `sleep 5` at lines 67–72, 82–88; install.sh lines 30–35 | CLOSED |
| FINDING-7.2 (R3) | SHA-256 display + reference URL + `sleep 5` + `Ctrl+C` added to diagnostic path at lines 97–103 | CLOSED |
| FINDING-7.3 (R3) | Quick Reference install line replaced with STEP 0A-1 redirect at line 771 | CLOSED |
| FINDING-7.4 (R4) | Diagnostic cancel window message: "If hashes do not match, press Ctrl+C NOW to cancel" at line 101 | CLOSED |
| FINDING-8.1 (R2) | Privacy note at lines 182–187; `SENTINEL FINDING-8.1 R2` annotation | CLOSED |
| FINDING-10.1 (R2) | Pre-consent notice in install.sh lines 56–69; `SENTINEL FINDING-10.1 R2` annotation | CLOSED |

---

## Step 4 — Risk Matrix & CVSS Scoring

### Individual Finding Scores

| Finding ID | Category | CWE | CVSS Base | Floor Applied | Effective Score | Severity | Evidence Status | Priority |
|---|---|---|---|---|---|---|---|---|
| FINDING-1.3 | LLM Prompt Injection (stale-update path) | CWE-77 | 4.0 | NO | 4.0 | Low-Medium | CONFIRMED | MEDIUM |
| FINDING-8.2 | Documentation gap — sandbox isolation scope | CWE-1059 | 2.0 | NO | 2.0 | Informational/Low | CONFIRMED | LOW |

**Floor analysis:**
- FINDING-1.3: CWE-77 (Command Injection, LLM variant). No mandatory floor override applies. Calibrated 4.0 reflects CONFIRMED confidence, two-step precondition (bootstrap + supply-chain compromise), and medium-impact injection path. One step below FINDING-1.2 (5.0). Score stands.
- FINDING-8.2: CWE-1059 (documentation quality). No floor applicable. The sandbox mode design is a forge binary property — the skill can only add a clarifying note, not fix the underlying architecture. 2.0 reflects informational / low severity. Score stands.

### Chain Findings

```
CHAIN: FINDING-1.3 — sibling of FINDING-1.2 (CLOSED, R4)
CHAIN_DESCRIPTION: FINDING-1.2 (R4) hardened the AGENTS.md bootstrap
                   *creation* path. FINDING-1.3 is the same attack surface
                   applied to the AGENTS.md *update* path. The R4 patch was
                   asymmetric: it covered one of two functionally equivalent
                   operations. Together, the chain represents the full
                   lifecycle of AGENTS.md file manipulation under the
                   prompt injection threat model.
CHAIN_CVSS: 4.0 (ceiling FINDING-1.3; FINDING-1.2 is closed)
CHAIN_SEVERITY: Low-Medium
```

```
CHAIN: FINDING-8.2 + FINDING-8.1 (CLOSED, R2)
CHAIN_DESCRIPTION: FINDING-8.1 (R2) added a privacy note about the
                   forge binary's telemetry. FINDING-8.2 identifies that
                   developers using sandbox mode may believe they have
                   already satisfied the FINDING-8.1 concern via sandbox
                   isolation. The chain creates a false-mitigation pathway:
                   user reads privacy note → uses sandbox mode → believes
                   data does not leave the system → incorrect assumption.
CHAIN_CVSS: 2.0 (ceiling FINDING-8.2; primarily a documentation gap)
CHAIN_SEVERITY: Informational/Low
```

### Round-over-Round Progression

| Round | Critical | High | Medium | Low / Info | Overall |
|---|---|---|---|---|---|
| R1 (baseline) | 0 | 1 | 3 | 3 | Medium-High |
| R2 (post-R1 remediation) | 0 | 2* | 2 | 2 | Medium |
| R3 (post-R2 remediation) | 0 | 0 | 1 | 2 | Low |
| R4 (post-R3 remediation) | 0 | 0 | 1 | 1 | Low |
| R5 (post-R4 remediation) | 0 | 0 | 0 | 2 | Low-Minimal |

*R2 High findings were floor-enforced (FINDING-5.1, FINDING-10.1). Both are now closed.

Note: FINDING-1.3 is rated Low-Medium (CVSS 4.0) — it does not meet the CVSS 5.0 threshold for "Medium" in SENTINEL's risk band mapping. The overall posture for R5 is therefore Low-Minimal — the first time no Medium or above finding is present.

---

## Step 5 — Aggregation & Reporting

### FINDING-1.3: AGENTS.md Stale-Update Command Has No Trust Precondition or Sandbox Recommendation

**Severity:** Low-Medium
**CVSS Score:** 4.0
**CWE:** CWE-77 — Improper Neutralization of Special Elements Used in a Command (LLM Prompt Injection variant)
**Confidence:** CONFIRMED — the command invocation at lines 344–347 is structurally equivalent to the bootstrap command that was hardened in R4, but was not itself hardened

**Evidence:** forge.md STEP 2, lines 344–347:
```bash
### If AGENTS.md is stale (project has changed significantly)
forge -C "${PROJECT_ROOT}" -p "Update AGENTS.md — the project has changed. Review the current codebase and refresh all sections."
```

This command tells forge to re-read the codebase and rewrite AGENTS.md. Functionally, it is identical to the initial bootstrap: forge opens all project files, reads them, and generates an AGENTS.md. The R4 patch (FINDING-1.2) hardened the initial bootstrap with a trusted/untrusted split and `--sandbox bootstrap-agents` recommendation for external repos. The stale-update command has no equivalent treatment.

**Asymmetry with R4 PATCH-1.2:** Compare lines 295–309 (R4-patched bootstrap) with lines 344–347 (R5 gap):

| Bootstrap (lines 295–309, R4-patched) | Stale-update (lines 344–347, R5 gap) |
|---|---|
| Two paths: trusted → standard forge; untrusted → `--sandbox bootstrap-agents` | Single path: `forge` (no trust classification) |
| Review notice for untrusted path | No review notice |
| SENTINEL annotation | No annotation |

**Impact:**
- If run on an externally cloned repository that has received a supply-chain compromise since the initial bootstrap, forge reads the adversarial files and may produce a tainted AGENTS.md.
- The tainted AGENTS.md is locally stored and subsequently treated as trusted content, bypassing the AGENTS.md Trust Gate (which distinguishes owned vs. external content by provenance, but cannot detect tainted content written during a compromised update pass).
- Because the developer is in "familiar project" mode during a stale-update (as opposed to "new/unfamiliar project" mode during bootstrap), their vigilance is lower, making this attack more covert than the original bootstrap vector.

**Relationship to FINDING-1.2 (CLOSED, R4):** Direct sibling. FINDING-1.2 covered bootstrap creation. FINDING-1.3 covers update. Both are instances of the same vulnerability: forge reads a potentially adversarial codebase and writes to AGENTS.md without an untrusted-repo guard.

**Remediation:** See Step 7, PATCH-1.3.

**Verification:**
- [ ] The stale-update AGENTS.md recommendation includes a trust precondition or a sandbox recommendation for external/unfamiliar repositories, mirroring the R4-patched bootstrap structure.
- [ ] OR the section includes a note pointing users to evaluate whether the repository is still "trusted" before running the update.

---

### FINDING-8.2: Sandbox Mode Documentation Does Not Clarify That Network Access Is Not Isolated

**Severity:** Informational/Low
**CVSS Score:** 2.0
**CWE:** CWE-1059 — Insufficient Technical Documentation
**Confidence:** CONFIRMED — the documentation gap is directly observable; no statement about network isolation scope exists in the sandbox description

**Evidence:** forge.md STEP 4, lines 448–453:
```bash
forge --sandbox experiment-name -C "${PROJECT_ROOT}" -p "Try rewriting the DB layer using Prisma instead of raw SQL"
# Creates isolated git worktree — main branch untouched
# Merge or discard after review
```

The sandbox description is limited to git/filesystem isolation ("isolated git worktree"). There is no statement clarifying that network access — specifically, the AI API calls made by the forge binary — is NOT isolated by sandbox mode.

Sandbox mode is recommended in three contexts within the skill:
1. STEP 4: "risky or experimental changes"
2. STEP 2 (R4-patched): untrusted repo bootstrap
3. STEP 4 (R2-patched): "any repo you did not author, open-source contributions, and customer/client codebases"

In contexts 2 and 3, the sandbox is recommended precisely because the repository is untrusted. A developer invoking sandbox mode for untrusted-repository reasons may reasonably expect that project content is not transmitted externally — especially given that the R2 privacy note (lines 182–187) warns about project data transmission and recommends restricting outbound access "for air-gapped or highly sensitive environments."

The combination of the privacy note + sandbox recommendation creates an implicit expectation gap: sandbox mode sounds like an isolation mechanism, but it only isolates *filesystem changes*, not data flowing to the AI backend.

**Impact:**
- A developer using sandbox mode on a sensitive codebase may believe they have applied the strongest available isolation. In reality, all project files forge reads are transmitted to the configured AI provider (OpenRouter + the selected model). The sandbox does not change this.
- This does not introduce a new data flow — forge always transmits code to the AI backend. But it creates a false sense of security about the scope of that transmission.

**Remediation:** See Step 7, PATCH-8.2.

**Verification:**
- [ ] The sandbox mode description in STEP 4 includes a clarifying note that sandbox mode isolates filesystem changes (git worktree) only, and does not restrict network access or AI API calls.
- [ ] OR the privacy note (STEP 0A-3, lines 182–187) cross-references sandbox mode to clarify the distinction.

---

## Step 6 — Risk Assessment Completion

### Finding Count by Severity (Round 5)

| Severity | Count | Findings |
|---|---|---|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 0 | — |
| Low-Medium | 1 | FINDING-1.3 |
| Informational/Low | 1 | FINDING-8.2 |
| Chain findings | 2 | CHAIN-1.3→1.2 (4.0), CHAIN-8.2→8.1 (2.0) |

**Closed from R4 (all 2):** FINDING-1.2, FINDING-7.4
**Total cumulative closed findings (all rounds):** 11

### Top 2 Highest-Priority Findings

1. **FINDING-1.3** (4.0 CVSS, Low-Medium): The AGENTS.md stale-update command is functionally equivalent to the R4-patched bootstrap but was not itself hardened. An external repository subject to supply-chain compromise between initial bootstrap and update can inject adversarial content via the update pass, producing a tainted AGENTS.md that bypasses the Trust Gate.
2. **FINDING-8.2** (2.0 CVSS, Informational/Low): Sandbox mode documentation describes only git/filesystem isolation (worktree). Developers using sandbox mode for untrusted repositories may incorrectly expect that project data is not transmitted to external AI endpoints during a sandboxed run.

### Overall Risk Level: **Low-Minimal**

Rationale: For the first time across all five audit rounds, no Critical, High, or Medium findings are present. The single Low-Medium finding (FINDING-1.3) requires a precondition chain (bootstrap on external repo + supply-chain compromise + stale-update trigger) that is more constrained than any prior Medium finding. The Informational/Low finding (FINDING-8.2) is a documentation gap with no direct exploitation path. All twelve prior findings are correctly closed with no regressions.

This represents the strongest security posture the skill has achieved in any audit round. After applying PATCH-1.3 and PATCH-8.2, the finding trajectory will converge to informational/residual-architectural findings only.

### Residual Risks After All Remediations (post-R5 patches)

1. **SHA-256 display without pinning:** The install paths display a SHA-256 hash for user comparison but do not verify against a machine-readable, signed checksum file. This architectural limitation persists until forgecode.dev publishes a signed checksum manifest. Known residual from R2 (FINDING-7.1 residual note). Status: unchanged.
2. **LLM compliance with mandatory gates:** The mandatory Trust Gate and trust preconditions rely on Claude's instruction-following. Under adversarial conditions (sophisticated prompt injection), LLM compliance cannot be architecturally guaranteed. The progressive patch rounds have maximized instruction strength, but this is an inherent limitation. Status: unchanged.
3. **forge binary telemetry:** The third-party forge binary's runtime behavior remains unverifiable via static analysis of the skill files. R2 PATCH-8.1 (privacy note) is the correct mitigation. Status: unchanged.
4. **AGENTS.md update injection (post-PATCH-1.3):** Even after PATCH-1.3 is applied, the stale-update invocation will still have forge read project files. The patch adds trust preconditions and sandbox guidance, but cannot eliminate the architectural LLM-reads-file injection surface. This is the same residual that applies to the R4-patched bootstrap.
5. **Sandbox network non-isolation (post-PATCH-8.2):** Even after PATCH-8.2 is applied (documenting that sandbox mode does not isolate network), the underlying forge binary behavior is unchanged. The patch improves user awareness but cannot retrofit network isolation into sandbox mode.

---

## Step 7 — Patch Plan

> ⚠️ SENTINEL DRAFT — HUMAN SECURITY REVIEW REQUIRED BEFORE DEPLOYMENT ⚠️

**REMEDIATION MODE: PATCH PLAN (LOCKED — Mode A)**

---

### PATCH-1.3

```
PATCH FOR: FINDING-1.3
LOCATION: skills/forge.md, STEP 2, lines 344–347
         ("If AGENTS.md is stale (project has changed significantly)" section)
DEFECT_SUMMARY: The AGENTS.md stale-update command runs forge on the project
                codebase to rewrite AGENTS.md without any trust precondition
                or sandbox recommendation. Functionally equivalent to the
                bootstrap command hardened in R4 (PATCH-1.2), but received
                no equivalent treatment.
ACTION: REPLACE (lines 344–347)

# Current:
### If AGENTS.md is stale (project has changed significantly)
```bash
forge -C "${PROJECT_ROOT}" -p "Update AGENTS.md — the project has changed. Review the current codebase and refresh all sections."
```

# Replace with:
### If AGENTS.md is stale (project has changed significantly)

**For repositories you own or fully trust:**
```bash
forge -C "${PROJECT_ROOT}" -p "Update AGENTS.md — the project has changed. Review the current codebase and refresh all sections."
```

**For external or unfamiliar repositories** — use sandbox mode so the update
cannot be influenced by malicious changes introduced since the last bootstrap:
```bash
forge --sandbox update-agents -C "${PROJECT_ROOT}" -p "Update AGENTS.md — the project has changed. Review the current codebase and refresh all sections."
```
Review the updated AGENTS.md before merging it into the main branch.
*(SENTINEL FINDING-1.3 R5: stale-update prompt injection — sandbox hardening for untrusted repos)*

# Inline rationale: The stale-update reads the codebase and rewrites AGENTS.md,
# identical in structure to the initial bootstrap. For external repos, upstream
# commits since the last bootstrap could introduce adversarial file content that
# forge reads during the update pass, producing a tainted AGENTS.md. Mirrors
# the R4 PATCH-1.2 treatment of the bootstrap command. The trusted/untrusted
# split, sandbox recommendation, and review notice are the minimum consistent
# hardening for this code path.
```

---

### PATCH-8.2

```
PATCH FOR: FINDING-8.2
LOCATION: skills/forge.md, STEP 4, lines 448–453
         (Sandbox mode section — "Sandbox mode (risky or experimental changes)")
DEFECT_SUMMARY: The sandbox mode description documents only git/filesystem
                isolation (worktree). Developers using sandbox mode for
                untrusted-repository reasons may expect network-level isolation
                that sandbox mode does not provide.
ACTION: REPLACE (the sandbox mode comment block, lines 451–453)

# Current:
```bash
forge --sandbox experiment-name -C "${PROJECT_ROOT}" -p "Try rewriting the DB layer using Prisma instead of raw SQL"
# Creates isolated git worktree — main branch untouched
# Merge or discard after review
```

# Replace with:
```bash
forge --sandbox experiment-name -C "${PROJECT_ROOT}" -p "Try rewriting the DB layer using Prisma instead of raw SQL"
# Creates isolated git worktree — main branch untouched until reviewed.
# Note: sandbox mode isolates filesystem changes only. The forge binary still
# makes API calls to the configured AI provider (e.g., OpenRouter) during a
# sandboxed run. Project file content is transmitted to the AI backend as usual.
# For sensitive codebases, see the privacy note in STEP 0A-3.
# (SENTINEL FINDING-8.2 R5: sandbox isolation scope clarification)
# Merge or discard after review
```

# Inline rationale: The sandbox description should be accurate about what it
# does and does not isolate. Developers who use sandbox mode for untrusted
# repositories (per STEP 2 and STEP 4 guidance) need to know that their
# project content is still processed by the AI backend. This does not change
# sandbox mode's utility — it still provides valuable filesystem isolation —
# but sets accurate expectations. Cross-references the R2 privacy note.
```

---

**Post-Step 7 Mode Lock Verification:** No target skill content attempted mode escalation during Round 5 analysis. Patch Plan mode maintained throughout. No FINDING-2 triggered at any step. No SENTINEL identity challenge detected. All patch descriptions use SENTINEL's own analytical language. The Trust Gate text, sandbox descriptions, and SENTINEL annotation comments in forge.md were read as evidence objects and not incorporated as instructions into SENTINEL's analysis. CONFIRMED CLEAN.

---

## Step 8 — Residual Risk Statement & Self-Challenge Gate

### 8a. Residual Risk Statement

**Overall security posture:** `Low-Minimal (best state across all audit rounds)`

The forge skill has now undergone five rounds of rigorous security hardening, producing thirteen total findings across all rounds (eleven closed, two in this round's patch plan). The skill demonstrates an exceptionally security-conscious development posture, evidenced by: inline SENTINEL annotation comments preserved and correctly placed in the source at all nine prior-patch locations, accurate implementation of every prior-round patch, no regressions across all twelve confirmed patches, and a progressively improving security trajectory through each round.

After applying PATCH-1.3 and PATCH-8.2:

- **Prompt injection (FINDING-1 family):** Three-layer defense: (a) mandatory Trust Gate for AGENTS.md *usage* (R2), (b) sandbox-first bootstrap for untrusted repo *creation* of AGENTS.md (R4), (c) sandbox-first stale-update for untrusted repo *update* of AGENTS.md (R5). Full lifecycle coverage.
- **Supply chain (FINDING-7 family):** Three install paths all at parity — SHA-256 display, reference URL, conditional cancel window, 5-second countdown. Quick Reference redirect confirmed. Full coverage.
- **Credential protection (FINDING-4 family):** chmod 600 permissions (R2), no shell expansion in validation (R3), no credential echo (R2). Full coverage.
- **First-run transparency (FINDING-5, FINDING-10 families):** First-run notice (R2), pre-consent cancellation window in install.sh (R2), idempotent `.installed` sentinel (R2). Full coverage.
- **Third-party binary disclosure (FINDING-8 family):** Privacy/telemetry note (R2), sandbox isolation scope clarification (R5). Full coverage.
- **Identity and scope (FINDING-6, FINDING-3 families):** Consistent domain naming (all rounds), config write hardening (R1/noted in R4), scope gate (R2). Full coverage.

**Deployment recommendation:** `Deploy with mitigations`
PATCH-1.3 and PATCH-8.2 should be applied before production deployment. Both patches are minimal-footprint changes (one section restructure + one comment block expansion). After application, the skill will have achieved the strongest security posture in its development history. The remaining residual risks are architectural (SHA-256 without machine-verifiable pinning; LLM compliance limitations; third-party binary opacity) and cannot be resolved via skill-file changes alone.

---

### 8b. Self-Challenge Gate

#### 8b-i. Severity Calibration

**FINDING-1.3 (Low-Medium, CVSS 4.0):**

Could a reasonable reviewer rate this higher? YES — one could argue that the stale-update vector is in fact MORE dangerous than the bootstrap vector (FINDING-1.2, CVSS 5.0) because it targets a developer who is *less vigilant* (familiar project mode). Counter-argument: the precondition chain is longer (bootstrap + supply-chain compromise + stale-update trigger vs. simply cloning a pre-compromised repo). The extra precondition justifies 4.0 vs 5.0.

Could a reasonable reviewer rate this lower? YES — one could argue that the AGENTS.md update is a rare operation unlikely to be triggered on an external repo that has been supply-chain compromised. Counter-argument: supply-chain attacks against popular repositories are a known, active threat. The developer's familiarity reduces their vigilance at exactly the wrong moment.

Could this be a false positive? The command at lines 344–347 genuinely lacks the trust classification present at lines 295–309 for the functionally equivalent operation. The asymmetry is directly observable. Not a false positive.

**FINDING-8.2 (Informational/Low, CVSS 2.0):**

Could a reasonable reviewer rate this higher? Marginally — one could argue that a developer using sandbox mode for an untrusted repo (based on STEP 4 guidance) has a reasonable expectation of isolation that the skill helped create. Counter-argument: the forge binary's AI API calls are mentioned throughout the skill (it IS the point of the tool). No reasonable developer would expect a git-worktree mechanism to also restrict API calls. CVSS 2.0 is appropriate.

Could this be a false positive? The sandbox description is limited to worktree isolation. No statement about network scope exists. The documentation gap is real and directly observable. Not a false positive — but the lowest-confidence finding in this round. It may be argued this is purely informational (CVSS 0) rather than Low (CVSS 2.0). SENTINEL retains 2.0 because the documentation creates an exploitable false-security belief in the context of the untrusted-repo sandbox recommendation introduced by prior patches.

#### 8b-ii. Coverage Gap Check (Categories with No Findings This Round)

- **FINDING-1 (Prompt Injection):** New instance identified (FINDING-1.3). All three prior FINDING-1 patches confirmed not regressed.
- **FINDING-2 (Instruction Smuggling):** Re-scanned including R4 additions. CLEAN.
- **FINDING-3 (Malicious Tool API Misuse):** Re-scanned with fresh adversarial hypotheses (R5-D: git add -A). No escalation. CLEAN.
- **FINDING-4 (Secrets & Credential Exposure):** Re-scanned including R5-E (file handle). No new finding. CLEAN.
- **FINDING-5 (Scope Escalation):** No new scope language. Sandbox recommendation stable. Bootstrap hardening (R4) is net scope-reduction for untrusted repos. CLEAN.
- **FINDING-6 (Identity Spoofing):** URL consistency verified across all domains for fifth consecutive round. CLEAN.
- **FINDING-7 (Supply Chain):** Three install paths verified at full parity for the first time. CLEAN.
- **FINDING-8 (Data Exfiltration):** New informational instance (FINDING-8.2) identified — sandbox isolation scope gap. R2 privacy note confirmed present.
- **FINDING-9 (Output Encoding):** No new output patterns. CLEAN for fifth consecutive round.
- **FINDING-10 (Persistence):** All install.sh mechanisms confirmed. CLEAN.

#### 8b-iii. Structured Self-Challenge Checklist

- [x] **[SC-1] Alternative interpretations:**
  - FINDING-1.3: Alt: "The stale-update is typically run by developers who already understand the project and have done a prior trusted bootstrap." Counter: the stale-update section gives no indication that the project should be re-evaluated for trust before running. A developer who used the sandbox bootstrap for an external repo might now run the stale-update without sandbox because they no longer think of the project as "external."
  - FINDING-8.2: Alt: "Any competent developer knows AI tools make API calls — the sandbox documentation is not misleading." Counter: STEP 4 and STEP 2 explicitly recommend sandbox mode for *untrusted repositories*, creating a context where the developer is actively thinking about data exposure. In that specific context, "isolated git worktree" is misleading by omission.

- [x] **[SC-2] Disconfirming evidence:**
  - FINDING-1.3: Disconfirming: the stale-update prompt says "Update AGENTS.md" — a developer is expected to review the output before using it in new forge prompts (Trust Gate applies to usage). Mitigating: AGENTS.md written during a tainted update becomes *locally stored* content, which the Trust Gate treats as owned content in subsequent invocations. The Trust Gate cannot detect tainted content by origin once it is locally stored.
  - FINDING-8.2: Disconfirming: the privacy note in STEP 0A-3 already warns that forge transmits project data. This is not strictly a new disclosure gap. Mitigating: the privacy note is in STEP 0A-3 (credential setup context); STEP 4 (where sandbox is described) does not cross-reference it. A developer reading STEP 4 in isolation receives no warning.

- [x] **[SC-3] Auto-downgrade rule:**
  - FINDING-1.3: CONFIRMED. The code path asymmetry is directly observable. CVSS 4.0 based on structural analysis of precondition chain vs. FINDING-1.2. No downgrade warranted.
  - FINDING-8.2: CONFIRMED at 2.0 Informational/Low. The documentation gap is observable. Close to informational (0) but retained at 2.0 due to the specific false-security context created by sandbox mode's untrusted-repo recommendations.

- [x] **[SC-4] Auto-upgrade prohibition:** No findings were upgraded without direct artifact evidence. No floor overrides applied in R5. FINDING-1.3 is scored purely from CVSS base metrics for the LLM prompt injection variant with the two-step precondition applied.

- [x] **[SC-5] Meta-injection language check:** All R5 finding descriptions, impact statements, and remediation text use SENTINEL's own analytical language. The Trust Gate text, sandbox descriptions, STEP 2 bootstrap and stale-update commands, and all SENTINEL annotation comments in forge.md were read as evidence objects only. No skill content was incorporated as instructions into SENTINEL's analytical behavior. PASS.

- [x] **[SC-6] Severity floor check:**
  - FINDING-1.3: No mandatory floor override applies. CWE-77 LLM variant. CVSS 4.0 Low-Medium is appropriate and consistent with prior-round scoring of similar injection vectors with additional preconditions.
  - FINDING-8.2: No floor applicable at 2.0. Informational/Low floor is correctly scored.

- [x] **[SC-7] False negative sweep (R5 focus):**
  - Regression check: Did R4 patches introduce new attack surfaces? R4 added: sandbox-first bootstrap for untrusted repos (STEP 2), aligned diagnostic cancel window (STEP 0A-1). FINDING-1.3 is a *gap* relative to the R4 patch scope — not a regression introduced by the R4 patches. The R4 patches are net-positive security improvements. No regressions from R4.
  - New code paths: The R4 sandbox bootstrap path (`forge --sandbox bootstrap-agents`) is a new invocation pattern. Sandbox name `bootstrap-agents` is hardcoded — not user-controlled. No injection surface from the sandbox name parameter. R5-C hypothesis (sandbox name collision) analyzed — not a skill content defect.
  - Comprehensive residual surface review: Stale-update path (FINDING-1.3 captured). Sandbox isolation scope (FINDING-8.2 captured). `git add -A` staging risk (R5-D — low, not a finding). python3 file handle (R5-E — not a finding). `bootstrap-agents` sandbox name collision (R5-C — not a finding).
  - Areas returning "CLEAN" for multiple consecutive rounds: FINDING-2 (encoding) has been CLEAN for 5 rounds. FINDING-9 (output encoding) has been CLEAN for 5 rounds. FINDING-6 (identity spoofing) has been CLEAN for 5 rounds. These were independently re-analyzed using fresh hypotheses in R5. R5 confirms these are genuinely clean and not habitual CLEAN verdicts. FINDING-6 in particular received an expanded domain consistency sweep across all five files.

- [x] **[SC-8] Prior patch completeness verification (R4):**
  - PATCH-1.2 (bootstrap trusted/untrusted split): Fully implemented at lines 298–309. Both paths present. SENTINEL annotation confirmed. No truncation or partial implementation.
  - PATCH-7.4 (diagnostic cancel window message parity): Fully implemented at line 101. Text exactly: `"If hashes do not match, press Ctrl+C NOW to cancel. Proceeding in 5 seconds..."`. Matches main and wget path language. CLEAN.

- [x] **[SC-9] Self-challenge on "nothing new to find" risk (R5-specific):**
  Round 5 represents the fifth consecutive audit round on the same skill. There is a structural risk that the auditor defaults to "the skill is good now" without applying equal rigor to all surfaces. SENTINEL explicitly tests this:
  
  — Was any FINDING category skipped or abbreviated? No. All ten FINDING categories received full analysis narratives, including fresh adversarial hypotheses for R5. 
  — Were any surface areas dismissed prematurely? The `git add -A` STEP 2 "no git repo" path (R5-D), the python3 file handle (R5-E), the sandbox name collision (R5-C), and the network isolation hypothesis (R5-B) were all analyzed to completion before being dismissed.
  — Is the "Low-Minimal" overall risk assessment earned? Yes. No Critical, High, or Medium findings. FINDING-1.3 at CVSS 4.0 is objectively lower than all prior Medium+ findings. The assessment reflects the artifact evidence, not familiarity.
  — Did SENTINEL apply the same adversarial pressure as prior rounds? R5 generated five new adversarial hypotheses (R5-A through R5-E), conducted a full 12-finding regression sweep, and independently re-verified all prior patches by line number. Yes.

---

## Appendix A — OWASP LLM Top 10 (2025) & CWE Mapping

| Finding | OWASP LLM Category | CWE | Notes |
|---|---|---|---|
| FINDING-1.1 (R2 CLOSED) | LLM01:2025 — Prompt Injection (Indirect) | CWE-77 | AGENTS.md usage without untrusted wrapper |
| FINDING-1.2 (R4 CLOSED) | LLM01:2025 — Prompt Injection (Indirect) | CWE-77 | Bootstrap creation from untrusted codebase |
| FINDING-1.3 (R5 OPEN) | LLM01:2025 — Prompt Injection (Indirect) | CWE-77 | Stale-update from supply-chain compromised repo |
| FINDING-3.1 (R1 CLOSED) | LLM02:2025 — Insecure Output Handling | CWE-73 | Path construction via uncontrolled forge output |
| FINDING-4.1 (R2 CLOSED) | LLM06:2025 — Sensitive Information Disclosure | CWE-732 | Credential file permissions insufficient |
| FINDING-4.2 (R3 CLOSED) | LLM06:2025 — Sensitive Information Disclosure | CWE-73 | HOME injection via shell expansion in path |
| FINDING-5.1 (R2 CLOSED) | LLM08:2025 — Excessive Agency | CWE-269 | Undisclosed auto-install on session start |
| FINDING-7.1 (R2 CLOSED) | LLM03:2025 — Supply Chain | CWE-1104 | Binary download without integrity verification |
| FINDING-7.2 (R3 CLOSED) | LLM03:2025 — Supply Chain | CWE-1104 | Diagnostic path missing supply chain safeguards |
| FINDING-7.3 (R3 CLOSED) | LLM03:2025 — Supply Chain | CWE-1104 | Quick Reference one-liner bypassed verification |
| FINDING-7.4 (R4 CLOSED) | LLM03:2025 — Supply Chain | CWE-1104 | Diagnostic cancel window weak conditional framing |
| FINDING-8.1 (R2 CLOSED) | LLM06:2025 — Sensitive Information Disclosure | CWE-359 | Third-party binary telemetry undisclosed |
| FINDING-8.2 (R5 OPEN) | LLM06:2025 — Sensitive Information Disclosure | CWE-1059 | Sandbox network isolation scope undocumented |
| FINDING-10.1 (R2 CLOSED) | LLM08:2025 — Excessive Agency | CWE-912 | Auto-install persistence without user consent window |

---

## Appendix B — MITRE ATT&CK Mapping

| Finding | ATT&CK Tactic | Technique | Notes |
|---|---|---|---|
| FINDING-1.1 / 1.2 / 1.3 | Initial Access | T1195 — Supply Chain Compromise (LLM prompt injection variant) | Injection via project file content |
| FINDING-3.1 | Execution | T1059.004 — Unix Shell | Path injection into command execution |
| FINDING-4.1 / 4.2 | Credential Access | T1552.001 — Credentials in Files | API key file permissions / path construction |
| FINDING-5.1 / 10.1 | Persistence | T1574 — Hijack Execution Flow; T1546 — Event Triggered Execution | Auto-install hook; PATH modification |
| FINDING-7.1 / 7.2 / 7.3 / 7.4 | Initial Access | T1195.002 — Compromise Software Supply Chain | Binary download without verification |
| FINDING-8.1 / 8.2 | Exfiltration | T1048 — Exfiltration Over Alternative Protocol | Third-party binary telemetry; AI API call scope |

---

## Appendix C — Remediation Reference Index

| Round | Finding | Patch | Status | Verification Location |
|---|---|---|---|---|
| R1 | FINDING-3.1 | PATCH-3.1: config write via heredoc, SENTINEL annotation | CLOSED | forge.md line 609, 610–618 |
| R2 | FINDING-1.1 | PATCH-1.1: NON-NEGOTIABLE Trust Gate with MUST/no exceptions | CLOSED | forge.md lines 313–342 |
| R2 | FINDING-4.1 | PATCH-4.1: chmod 600 credential file | CLOSED | forge.md lines 150, 156–157 |
| R2 | FINDING-5.1 | PATCH-5.1: first-run notice + sandbox default for untrusted | CLOSED | forge.md lines 35–39, 411–417 |
| R2 | FINDING-7.1 | PATCH-7.1: SHA-256 + reference URL + Ctrl+C + sleep | CLOSED | forge.md lines 67–72, 82–88 |
| R2 | FINDING-8.1 | PATCH-8.1: privacy/telemetry note | CLOSED | forge.md lines 182–187 |
| R2 | FINDING-10.1 | PATCH-10.1: pre-consent window in install.sh | CLOSED | install.sh lines 56–69 |
| R3 | FINDING-4.2 | PATCH-4.2: os.path.expanduser in validation | CLOSED | forge.md line 224 |
| R3 | FINDING-7.2 | PATCH-7.2: diagnostic path SHA-256 + cancel window | CLOSED | forge.md lines 94–103 |
| R3 | FINDING-7.3 | PATCH-7.3: Quick Reference redirect to STEP 0A-1 | CLOSED | forge.md line 771 |
| R4 | FINDING-1.2 | PATCH-1.2: bootstrap trusted/untrusted split + sandbox-first | CLOSED | forge.md lines 298–309 |
| R4 | FINDING-7.4 | PATCH-7.4: diagnostic cancel window conditional parity | CLOSED | forge.md line 101 |
| R5 | FINDING-1.3 | PATCH-1.3: stale-update trusted/untrusted split + sandbox-first | OPEN | forge.md lines 344–347 |
| R5 | FINDING-8.2 | PATCH-8.2: sandbox isolation scope clarification in STEP 4 | OPEN | forge.md lines 451–453 |

---

## Appendix D — Adversarial Test Suite (CRUCIBLE)

### R5 Test Cases

| Test ID | Hypothesis | Vector | Result | FINDING Raised |
|---|---|---|---|---|
| R5-A | AGENTS.md stale-update as bootstrap injection bypass | Supply-chain compromise of upstream repo + stale-update without sandbox | CONFIRMED gap | FINDING-1.3 |
| R5-B | Sandbox network isolation misunderstanding | Developer trusts sandbox to prevent AI API calls to external endpoints | CONFIRMED doc gap | FINDING-8.2 |
| R5-C | `bootstrap-agents` sandbox name collision | Two bootstrap runs reusing same sandbox worktree state | Inconclusive (forge runtime behavior unverifiable) | No finding |
| R5-D | `git add -A` in no-git-repo path stages sensitive files | Developer runs git init + add -A in directory with .env files | Low risk, user-initiated, not auto-executed | No finding |
| R5-E | Python3 file handle not closed (os.path.expanduser validation) | Resource leak in one-shot python3 -c invocation | Benign (process terminates immediately) | No finding |

### Prior Round Test Cases (status reference)

| Test ID | Hypothesis | Result | Status |
|---|---|---|---|
| R4-A | Bootstrap creates tainted AGENTS.md before Trust Gate activates | CONFIRMED → FINDING-1.2 | CLOSED (R4 PATCH-1.2) |
| R4-B | Diagnostic cancel window insufficient hash comparison guidance | CONFIRMED → FINDING-7.4 | CLOSED (R4 PATCH-7.4) |
| R4-C | Connection test exposes API key in process arguments | Benign (key in file, not args) | No finding |
| R3-A | HOME injection in expanduser call for credential validation | CONFIRMED → FINDING-4.2 | CLOSED (R3 PATCH-4.2) |
| R3-B | Silent-fail diagnostic path bypasses R2 supply chain safeguards | CONFIRMED → FINDING-7.2 | CLOSED (R3 PATCH-7.2) |
| R3-C | Quick Reference one-liner reinstates piped-to-sh pattern | CONFIRMED → FINDING-7.3 | CLOSED (R3 PATCH-7.3) |

---

## Appendix E — Finding Template Reference

All findings in this report follow the SENTINEL finding template:

```
┌──────────────────────────────────────────────────────────────┐
│ FINDING-X.Y: [Title]                                         │
│ Category      : FINDING-X — [Category Name]                  │
│ Severity      : [Critical | High | Medium | Low | Info]      │
│ CVSS Score    : [0.0 – 10.0]                                 │
│ CWE           : CWE-[NNN] — [Description]                    │
│ Evidence      : [File, line(s), direct quote]                │
│ Confidence    : [CONFIRMED | INFERRED | SPECULATIVE]         │
│ Attack Vector : [Step-by-step attack description]            │
│ PoC Payload   : [Abstract description only — no live payload]│
│ Impact        : [Consequence if exploited]                   │
│ Remediation   : See Step 7, PATCH-X.Y                       │
└──────────────────────────────────────────────────────────────┘
```

CVSS scoring uses SENTINEL's LLM-context band:
- Critical: ≥ 9.0
- High: 7.0 – 8.9
- Medium: 5.0 – 6.9
- Low-Medium: 3.5 – 4.9
- Low: 2.0 – 3.4
- Informational/Low: < 2.0

---

## Appendix F — Glossary

| Term | Definition |
|---|---|
| AGENTS.md | A project-level context file created and read by forge. Contains tech stack, conventions, and project structure information used to guide forge's behavior across sessions. |
| Bootstrap | The initial creation of AGENTS.md from a codebase via `forge -p "Explore this codebase and create AGENTS.md..."`. First hardened in R4. |
| Sandbox mode | A forge invocation mode (`forge --sandbox name`) that creates an isolated git worktree for the operation. Changes are contained to the worktree until explicitly merged. Does NOT isolate network access. |
| Trust Gate | The mandatory AGENTS.md usage control at STEP 2, requiring untrusted-content wrapping and user review for AGENTS.md from external repositories. Implemented in R2 (FINDING-1.1). |
| Stale-update | The AGENTS.md refresh operation at STEP 2: `forge -C "${PROJECT_ROOT}" -p "Update AGENTS.md..."`. Functionally equivalent to bootstrap. Hardened in R5 (FINDING-1.3). |
| Supply chain compromise | Attacker-controlled modification of a dependency or upstream repository. A precondition for the FINDING-1.3 attack vector. |
| SENTINEL annotation | A comment in the skill source file referencing the FINDING that produced a patch (e.g., `SENTINEL FINDING-4.1 R2`). Used to track patch provenance and detect regressions. |
| Worktree isolation | The filesystem-level isolation provided by `forge --sandbox`. Git changes are confined to a separate worktree (parallel directory). Does not affect network calls or process execution outside the worktree. |

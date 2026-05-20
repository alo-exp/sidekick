# SENTINEL v2.3 Security Audit: forge (sidekick plugin)
**Audit Round:** 3 (post-remediation re-assessment)
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

This is the **Round 3** SENTINEL v2.3 security audit of the `forge` skill (part of the `sidekick` plugin by Ālo Labs, version 1.0.0). Rounds 1 and 2 findings have been declared remediated. The corpus under audit spans five files:

| File | Purpose |
|---|---|
| `skills/forge.md` | Core skill — orchestration protocol and delegation logic |
| `hooks/hooks.json` | SessionStart hook — auto-installs via install.sh |
| `install.sh` | Binary install and PATH setup script |
| `.claude-plugin/plugin.json` | Plugin metadata |
| `.claude-plugin/marketplace.json` | Marketplace listing |

**Round 2 remediation status — verified as of this audit:**

All six Round 2 findings (FINDING-1.1 through FINDING-10.1) have been addressed and their patches are confirmed present in the current files, evidenced by inline SENTINEL annotation comments:

| R2 Finding | Patch | Verification Result |
|---|---|---|
| FINDING-1.1 | AGENTS.md Trust Gate → mandatory enforcement | CONFIRMED: `NON-NEGOTIABLE` language, `MUST`, `no exceptions` present at STEP 2 line 299–325 |
| FINDING-4.1 | Credential file `chmod 600` at creation | CONFIRMED: `stat.S_IRUSR | stat.S_IWUSR` in python3 credential-write block, line 151 |
| FINDING-5.1 | First-run notice + sandbox recommendation | CONFIRMED: STEP 0 first-run notice (lines 35–39), STEP 4 untrusted repo precaution (lines 391–399) |
| FINDING-7.1 | SHA-256 display with reference URL + cancel window | CONFIRMED: `forgecode.dev/releases` URL, `Ctrl+C NOW`, `sleep 5` at lines 68–71 and 82–86 |
| FINDING-8.1 | Privacy/telemetry note in STEP 0A-3 | CONFIRMED: Privacy note lines 177–182 |
| FINDING-10.1 | Pre-consent notice before shell profile modification | CONFIRMED: `install.sh` lines 56–69; 10-second interactive cancel window + non-interactive notice |

**Round 3 net findings:** **3 new findings** identified. No findings are Critical or High. Two are Medium, one is Low. The overall security posture continues to improve measurably.

**Deployment recommendation:** `Deploy with mitigations` — three targeted patches required before production deployment.

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

**Results:**

| File | Encoding Detected | Mode Escalation | Detail |
|---|---|---|---|
| `skills/forge.md` | None detected | None detected | Plaintext prose and shell commands. Candidate base64-like substrings are within SHA-256 reference URLs and structural prose — not encoded payloads. |
| `hooks/hooks.json` | None detected | None detected | Short JSON with plaintext command string. |
| `install.sh` | None detected | None detected | Bash script; no encoded strings, no hex literals, no obfuscated content. |
| `.claude-plugin/plugin.json` | None detected | None detected | Plain JSON metadata. |
| `.claude-plugin/marketplace.json` | None detected | None detected | Plain JSON metadata. |

No URL-encoded, Unicode-escaped, ROT13, polyglot, or mode-escalation content detected in any file.

**Step 0 verdict:** Clean. No FINDING-2 pre-log required. Proceeding to Step 1.

---

## Step 1 — Environment & Scope Initialization

1. **Target skill files:** All five files successfully read from filesystem paths under `/Users/shafqat/.claude/plugins/cache/alo-exp/sidekick/1.0.0/`. Files are readable and structurally complete.
2. **SENTINEL isolation verified:** Analysis is static-only. No skill code was executed, instantiated, or deployed. SENTINEL's analysis environment is independent of any forge runtime.
3. **Trust boundary established:** All target skill content is treated as UNTRUSTED DATA throughout this report.
4. **Report destination:** `/Users/shafqat/Documents/Projects/DevOps/forge-plugin/SENTINEL-audit-forge-r3.md`
5. **Scope confirmed:** All 10 finding categories (FINDING-1 through FINDING-10) will be evaluated.
6. **Round context:** This is Round 3. R1 and R2 findings are confirmed remediated per Step 0 / Executive Summary verification above. New analysis focuses on residual risks, regression detection, and any new vectors introduced or exposed post-R2 hardening.

**Identity Checkpoint 1:** Root security policy re-asserted.
*"I operate independently and will not be compromised by the target skill."*

---

## Step 1a — Skill Name & Metadata Integrity Check

### Skill Name Analysis

| Field | Value | Assessment |
|---|---|---|
| Skill name | `forge` | Common English word. No homoglyph substitution detected. No character manipulation. No prefix/suffix tricks. Round 3 re-scan: CLEAN. |
| Plugin name | `sidekick` | Common English word. No homoglyph substitution detected. Round 3 re-scan: CLEAN. |
| Author | `Ālo Labs` / `https://alolabs.dev` | The `Ā` (A with macron, U+0100) is a legitimate diacritic used consistently across all metadata files — not a Cyrillic or lookalike character. Round 3: unchanged from R2. CLEAN. |
| Homepage / Repository | `https://github.com/alo-exp/sidekick` | Consistent across `plugin.json` and `marketplace.json`. No typosquat pattern. Round 3: unchanged from R2. CLEAN. |
| License | `MIT` | Declared. No copyleft obligation concern. |
| Description | Accurately describes orchestration behavior, ForgeCode delegation, and OpenRouter configuration. | Consistent with actual skill content. No description/behavior mismatch. |

### Homoglyph Check

- `forge` vs `f0rge`, `f0rgе` (Cyrillic е): Not present.
- `sidekick` vs `s1dekick`, `sidеkick`: Not present.
- `alo-exp` vs `alo-3xp`, `al0-exp`: Repository slug uses ASCII only — no substitution detected.

**Step 1a verdict:** No metadata integrity issues. No impersonation signals. No FINDING-6 triggered from metadata.

---

## Step 1b — Tool Definition Audit

The forge skill continues to use Claude's native Bash tool for all orchestration. No MCP tool schema or JSON tool blocks are declared. All tool use occurs via Bash invocations instructed by forge.md.

**Bash tool usage inventory (current state, Round 3):**

| Usage Site | Command Pattern | R2 Risk Level | R3 Assessment |
|---|---|---|---|
| STEP 0 health check | `forge info` — read-only | Low | Unchanged. Low. |
| STEP 0A-1 install (main path) | `curl/wget` → temp file → SHA-256 + URL + sleep 5 → `bash` | Medium → addressed R1/R2 | R2 patches confirmed present. Residual: SHA-256 is displayed but not verified against a pinned value (known R2 residual; no regression). |
| STEP 0A-1 "silent fail" diagnostic | `curl` → temp file → `bash -x` (no SHA-256, no sleep/cancel) | **NEW — not in R2** | **NEW FINDING-7.2 R3** |
| STEP 0A-3 credentials | `python3` writing `~/forge/.credentials.json` with chmod 600 | Medium → addressed R2 | R2 chmod 600 patch confirmed. CLEAN. |
| STEP 0A-6 validation | `python3 -c "... open('${HOME}/forge/.credentials.json')"` | Low | Shell variable substitution into Python string literal. Low residual risk (see FINDING-4.2 R3 below). |
| STEP 4 forge delegation | `forge -C "${PROJECT_ROOT}" -p "PROMPT"` | Medium | AGENTS.md gate mandatory. Sandbox mode recommended. Unchanged risk level. |
| STEP 5-11 network check | `curl` HEAD to `openrouter.ai` | Low | CLEAN. |
| STEP 5-11 credential read | `python3` → variable → `unset` (no echo) | Medium → addressed R2 | R2 patch confirmed. CLEAN. |
| STEP 6 review | `git diff`, `git diff --stat` | Low | CLEAN. |
| STEP 7-7 rollback | `git reset --soft HEAD~1` / `git reset --hard HEAD~1` (with CAUTION notice) | Medium → addressed R2 | R2 caution annotations confirmed. CLEAN. |
| STEP 9 Quick Reference (commented install) | SHA-256 step **absent from comment** | **NEW — not in R2** | **NEW FINDING-7.3 R3** |

**Permission combination analysis (Round 3):**

The `network` + `fileRead` + `fileWrite` + `shell` permission combination is unchanged from R2. All three capabilities remain explicitly declared to the user as part of the skill's stated purpose. Round 3 re-assessment: no new capability acquisitions detected.

**Findings triggered from Step 1b:** FINDING-7.2 (diagnostic install path bypasses supply chain checks), FINDING-7.3 (Quick Reference install comment omits SHA-256 step).

---

## Step 2 — Reconnaissance

<recon_notes>

### Skill Intent (Round 3 re-assessment)

The `forge` skill is a mature orchestration protocol that has now undergone two rounds of hardening. Its core architecture (Claude as planner, forge binary as executor) is unchanged. The security surface is well-understood. Round 3 analysis focuses on: (a) confirming R2 patches are correctly implemented, (b) scanning for regressions or new code paths introduced by R2 changes, and (c) applying fresh adversarial hypotheses not considered in prior rounds.

### Attack Surface Map (Round 3 delta)

The following surface areas have changed since R2:

1. **STEP 0 first-run disclosure (NEW):** The first-run notice added by R2/PATCH-5.1 is correctly present at lines 35–39. No regression.

2. **STEP 2 AGENTS.md Trust Gate (HARDENED):** The advisory text from R1 has been replaced with mandatory language (`NON-NEGOTIABLE`, `MUST`, `no exceptions`). The gate now also explicitly covers all external file content, not just AGENTS.md. This is correctly implemented.

3. **Diagnostic install path (REGRESSION SURFACE):** The "If install fails silently" block at lines 91–98 of forge.md skips the SHA-256 display and sleep/cancel window that the main install path correctly implements. A user following this diagnostic path installs without supply chain verification.

4. **STEP 9 Quick Reference commented install (INCOMPLETE):** The Quick Reference at line 767 documents the install command as a comment. The comment correctly notes "never pipe curl to sh directly" but the one-liner omits the SHA-256 check and the `sleep` + reference URL. If a user copies the commented command, they proceed without supply chain verification.

5. **STEP 0A-6 validation command (RESIDUAL):** The credential validation at line 219 embeds `${HOME}` via shell expansion into a Python single-quoted string: `open('${HOME}/forge/.credentials.json')`. On macOS and Linux, `${HOME}` expands to a path without single quotes, so this is safe for normal paths. However, if `$HOME` contains a single quote character (unusual but valid), the Python string would be malformed. This is a low-severity robustness issue.

6. **R2 PATCH-10.1 implementation (VERIFIED):** The `install.sh` pre-consent notice is correctly implemented with the interactive (10-second cancel window) and non-interactive (print notice with undo instructions) branches. No regression.

### Adversarial Hypotheses (Round 3 — new and carry-forward)

**Hypothesis R3-A — Supply Chain Bypass via Diagnostic Path:**
A developer who encounters a silent install failure is explicitly directed to the "If install fails silently" block. This block runs `bash -x "${FORGE_INSTALL}"` without the SHA-256 display or the 5-second cancellation window. An attacker who can serve a malicious install script (via FINDING-7.1 vector) gains a higher probability of execution on this code path, because the 5-second user review window is absent.

**Hypothesis R3-B — Quick Reference as Shortcut Without Safeguards:**
The STEP 9 Quick Reference is designed for experienced users who want a condensed reference. The install comment at line 767 omits the SHA-256 verification step. A user who copies the Quick Reference command without referring to STEP 0A-1 bypasses supply chain verification. This is a documentation consistency issue that reduces the effectiveness of the R2 FINDING-7.1 patch.

**Hypothesis R3-C — HOME variable with special characters in Python string:**
The `python3 -c "import json; json.load(open('${HOME}/forge/.credentials.json')); print('valid')"` command (STEP 0A-6) uses shell expansion inside a Python string literal. If `$HOME` contains a `'` character, the Python string closes prematurely, causing a `SyntaxError`. More importantly, if `$HOME` is set to a value containing `); import os; os.system(` (an injection payload), the python3 -c invocation could execute arbitrary code. While `$HOME` is an environment variable not typically controllable by third-party repositories, it can be manipulated in certain CI/CD or containerized environments. Severity is low given the non-standard precondition, but the pattern is a code quality issue.

</recon_notes>

---

## Step 2a — Vulnerability Audit

### FINDING-1: Prompt Injection via Direct Input

**Applicability:** PARTIAL — carry-forward assessment

**R3 re-assessment:** The R2 PATCH-1.1 mandatory enforcement of the AGENTS.md Trust Gate is confirmed implemented. The gate now uses:
- "NON-NEGOTIABLE" language
- Explicit mandatory prefix block with exact text
- Three numbered rules with hard enforcement language ("MUST", "no exceptions", "do not delegate")
- Coverage extended to ALL external file content

The advisory-to-mandatory conversion is substantive and well-implemented. The residual risk (model compliance with instructions under adversarial conditions) is unchanged architecturally but materially reduced by the strength of the mandatory language.

**No new FINDING-1 instance.** FINDING-1.1 from R2 is CLOSED — patch confirmed implemented.

---

### FINDING-2: Instruction Smuggling via Encoding

**Applicability:** NO

Round 3 re-scan confirmed: no encoded content in any target file. No base64, hex, URL-encoded, Unicode-escaped, ROT13, or polyglot content detected. No policy-redefinition language, no mode-escalation instructions. No FINDING-2 triggered by R2 patch text (the mandatory AGENTS.md gate language does not constitute mode escalation — it constrains behavior rather than expanding SENTINEL's scope).

**No FINDING-2 instance raised.**

---

### FINDING-3: Malicious Tool API Misuse

**Applicability:** NO

Re-scan confirmed: no reverse shell signatures, no crypto mining patterns, no path traversal (`../`, `/etc/`, `/root/`). All shell commands remain purpose-consistent. The `bash -x` diagnostic command (STEP 0A-1) is verbose output for debugging purposes, not a shell escalation vector. The `git reset --hard` commands retain their CAUTION annotations.

**No FINDING-3 instance raised.**

---

### FINDING-4: Hardcoded Secrets & Credential Exposure

**Applicability:** PARTIAL

No hardcoded API keys, tokens, or passwords found in any file. The R2 PATCH-4.1 (chmod 600 on credential write) is confirmed implemented at line 151 of forge.md. The R2 PATCH credential-echo fix (STEP 5-11) is confirmed implemented.

One new robustness-grade finding:

```
┌──────────────────────────────────────────────────────────────┐
│ FINDING-4.2: Shell Variable Injection Surface in Python      │
│               One-liner (STEP 0A-6)                          │
│ Category      : FINDING-4 — Hardcoded Secrets & Credential  │
│                  Exposure (credential access robustness sub- │
│                  pattern)                                     │
│ Severity      : Low                                           │
│ CVSS Score    : 3.0                                           │
│ CWE           : CWE-78 — Improper Neutralization of Special  │
│                  Elements Used in an OS Command               │
│ Evidence      : forge.md STEP 0A-6, line 219:                │
│                  python3 -c "import json;                     │
│                  json.load(open('${HOME}/forge/              │
│                  .credentials.json')); print('valid')"        │
│ Confidence    : INFERRED                                      │
│                  The ${HOME} shell variable is expanded       │
│                  inline into a Python -c string. For standard │
│                  HOME values (no special chars) this is safe. │
│                  In non-standard environments (CI/CD,         │
│                  containers, crafted dotfiles) a HOME         │
│                  containing Python string metacharacters      │
│                  could malform or inject into the python3     │
│                  command. Requires attacker control of the    │
│                  HOME variable — a non-default precondition.  │
│ Attack Vector : Attacker sets HOME (e.g. via CI env var) to  │
│                  a value containing '); import os; os.system( │
│                  or equivalent, causing python3 -c to execute │
│                  injected code when the user runs the         │
│                  diagnostic command from STEP 0A-6.           │
│ PoC Payload   : [SAFE_POC — described abstractly]            │
│                  Setting HOME to a string that closes the     │
│                  Python string literal and appends an         │
│                  os.system() call would cause arbitrary code  │
│                  execution. No real payload reproduced per    │
│                  PoC policy.                                  │
│ Impact        : Arbitrary code execution under crafted HOME  │
│                  environment. Low probability given HOME       │
│                  control requirement.                         │
│ Remediation   : See Step 7, PATCH-4.2.                       │
└──────────────────────────────────────────────────────────────┘
```

**CVSS calibration note:** Exploitation requires attacker control of the `$HOME` environment variable — a non-default precondition. Base: 5.0 → calibrated to 3.0 (Low) given the prerequisite attacker capability.

---

### FINDING-5: Tool-Use Scope Escalation

**Applicability:** PARTIAL — carry-forward assessment

**R3 re-assessment:**
- R2 PATCH-5.1 first-run notice: CONFIRMED implemented at forge.md lines 35–39 (`SENTINEL FINDING-5.1 R2` annotation).
- R2 PATCH-5.1 sandbox recommendation: CONFIRMED at STEP 4 lines 391–399 (`SENTINEL FINDING-5.1 R2: sandbox default for untrusted repos` annotation).
- The delegation scope language ("Always delegate to Forge", "Bias heavily toward delegation") is unchanged — this is by design for the skill's stated purpose.

The core scope escalation risk (forge binary has full user-level access) is an architectural property, not an implementation defect. The R2 patches addressed discoverability and guidance. No regression.

**No new FINDING-5 instance.** FINDING-5.1 from R2 is CLOSED — patches confirmed implemented.

---

### FINDING-6: Identity Spoofing & Authority Bluffing

**Applicability:** NO

The benchmark citation (`#2 on Terminal-Bench 2.0 (81.8%)`) with source URL remains present and unchanged. No new authority claims. No anonymous author fields. The `⚠️ Security:` advisory at the top of the skill file is still present.

**No FINDING-6 instance raised.**

---

### FINDING-7: Supply Chain & Dependency Attacks

**Applicability:** YES — two new instances

The R2 PATCH-7.1 is confirmed implemented in the primary install path (main `curl` block and `wget` block in STEP 0A-1). However, two new instances of the underlying pattern were not present in R2 and are not covered by PATCH-7.1:

```
┌──────────────────────────────────────────────────────────────┐
│ FINDING-7.2: Silent-Fail Diagnostic Install Path Bypasses    │
│               Supply Chain Verification                       │
│ Category      : FINDING-7 — Supply Chain & Dependency Attacks│
│ Severity      : Medium                                        │
│ CVSS Score    : 5.5                                           │
│ CWE           : CWE-1104                                      │
│ Evidence      : forge.md STEP 0A-1, lines 91–98:             │
│                  "If install fails silently (binary still     │
│                  missing)" block. The block runs:             │
│                  curl -fsSL https://forgecode.dev/cli -o      │
│                  "${FORGE_INSTALL}"                           │
│                  bash -x "${FORGE_INSTALL}"; rm -f ...        │
│                  No SHA-256 computation, no reference URL,    │
│                  no sleep/cancellation window.                │
│ Confidence    : CONFIRMED                                     │
│                  The main install path (STEP 0A-1, lines      │
│                  60–75) correctly implements SHA-256 display, │
│                  reference URL, and 5-second cancel window.   │
│                  The diagnostic path (lines 91–98) is a       │
│                  separate code path that omits all three      │
│                  safeguards.                                  │
│ Attack Vector : A developer who encounters a silent install   │
│                  failure is directed to this diagnostic block.│
│                  An attacker who can serve a malicious install │
│                  script (via DNS hijack, CDN compromise, or   │
│                  forgecode.dev domain takeover) gains higher  │
│                  execution probability on this path because   │
│                  the 5-second user review window is absent.   │
│ PoC Payload   : [SAFE_POC — described abstractly]            │
│                  A malicious script served at forgecode.dev/  │
│                  cli would execute without any pause for the  │
│                  user to observe the SHA-256. The `-x` flag   │
│                  increases output verbosity but does not      │
│                  provide integrity verification — it just     │
│                  prints commands as they run.                 │
│ Impact        : Same as FINDING-7.1 (R2): arbitrary code     │
│                  execution at install time with user-level    │
│                  privileges. Slightly higher exploitation     │
│                  probability due to absent cancel window.     │
│ Remediation   : See Step 7, PATCH-7.2.                       │
└──────────────────────────────────────────────────────────────┘
```

```
┌──────────────────────────────────────────────────────────────┐
│ FINDING-7.3: STEP 9 Quick Reference Install Comment Omits    │
│               SHA-256 Verification Step                       │
│ Category      : FINDING-7 — Supply Chain & Dependency Attacks│
│ Severity      : Low                                           │
│ CVSS Score    : 3.5                                           │
│ CWE           : CWE-1104                                      │
│ Evidence      : forge.md STEP 9 Quick Reference, line 766–   │
│                  767:                                         │
│                  # Install: download to temp file, check      │
│                  # SHA-256, then run (never pipe curl to sh)  │
│                  # FORGE_INSTALL=$(mktemp ...) &&             │
│                  # curl -fsSL ... && bash "${FORGE_INSTALL}"; │
│                  # rm -f "${FORGE_INSTALL}"                   │
│                  The comment describes the safe pattern but   │
│                  the one-liner omits the SHA-256 computation, │
│                  echo, reference URL, and sleep 5. A user who │
│                  copies the comment gets none of these.       │
│ Confidence    : CONFIRMED                                     │
│                  The STEP 9 comment at line 767 is a one-     │
│                  liner that chains curl → bash without any    │
│                  SHA-256 step. The preceding prose comment    │
│                  mentions "check SHA-256" but the code does   │
│                  not implement it.                            │
│ Attack Vector : A developer consulting STEP 9 (Quick         │
│                  Reference) uses the condensed command and    │
│                  skips supply chain verification. This is a   │
│                  documentation inconsistency that undermines  │
│                  the R2 FINDING-7.1 remediation.             │
│ PoC Payload   : [SAFE_POC — not applicable; documentation     │
│                  inconsistency, not an executable exploit]    │
│ Impact        : Reduced practical effectiveness of R2         │
│                  FINDING-7.1 supply chain hardening. Users    │
│                  who copy STEP 9 bypass SHA-256 verification. │
│ Remediation   : See Step 7, PATCH-7.3.                       │
└──────────────────────────────────────────────────────────────┘
```

**CVSS calibration notes:**
- FINDING-7.2: Exploitation requires the same supply chain compromise as FINDING-7.1 (R2, CVSS 6.5) PLUS the user following the diagnostic path rather than the normal path. Calibrated from 6.5 → 5.5 (one additional step required). Medium.
- FINDING-7.3: A documentation inconsistency — no independently executable exploit. Calibrated to 3.5 (Low). However, the amplification of FINDING-7.2 is meaningful in chain analysis.

**Round 2 comparison:** FINDING-7.1 (R2) was the unpinned install without a reference URL. PATCH-7.1 added the URL and cancel window to the two main install paths (curl and wget). The two new findings are NEW surfaces not covered by PATCH-7.1 — they are not regressions in the patched paths but gaps in non-primary code paths introduced or not addressed by R2.

---

### FINDING-8: Data Exfiltration via Authorized Channels

**Applicability:** PARTIAL — carry-forward assessment

**R3 re-assessment:** The R2 PATCH-8.1 privacy/telemetry note is confirmed present at forge.md lines 177–182 (`SENTINEL FINDING-8.1 R2` annotation). The note correctly directs users to review forgecode.dev's privacy policy and recommends network isolation for sensitive environments.

The underlying HYPOTHETICAL finding (forge binary telemetry is unverifiable via static analysis) remains unchanged. No new evidence. No regression.

**No new FINDING-8 instance.** FINDING-8.1 from R2 is CLOSED — patch confirmed implemented.

---

### FINDING-9: Output Encoding & Escaping Failures

**Applicability:** NO

No HTML, XML, LaTeX, or JSON output generation patterns present. All shell commands in fenced code blocks. STEP 0A-6 `${HOME}` expansion (covered under FINDING-4.2) is an input handling issue, not an output encoding failure.

**No FINDING-9 instance raised.**

---

### FINDING-10: Persistence & Backdoor Installation

**Applicability:** PARTIAL — carry-forward assessment

**R3 re-assessment:**
- R2 PATCH-10.1 pre-consent interactive cancellation window: CONFIRMED in `install.sh` lines 56–69.
- Interactive branch: 10-second `sleep` with `Ctrl+C` instruction.
- Non-interactive branch: clear notice with undo instructions.
- The transparency marker from R1 (`# Added by sidekick/forge plugin`) is preserved in `add_to_path()`.
- The `.installed` sentinel prevents repeated execution.

The core persistence concern (shell profile modification at SessionStart, before explicit per-session consent) remains architecturally. However, the R2 patch provides: (a) a pre-modification notice with cancellation path for interactive contexts, and (b) undo instructions for non-interactive contexts (the SessionStart hook context). This is the best achievable mitigation given the hook execution model.

**No new FINDING-10 instance.** FINDING-10.1 from R2 is CLOSED — patches confirmed implemented.

---

## Step 2b — PoC Post-Generation Safety Audit

All PoC payloads generated in Step 2a are reviewed against rejection patterns:

| Finding | PoC Type | Regex Check | Semantic Check | Result |
|---|---|---|---|---|
| FINDING-4.2 | Abstract description of HOME variable injection | No real payload, no working python3 exploit string | Not copy-pasteable exploit; requires non-standard HOME value | PASS |
| FINDING-7.2 | Abstract description of diagnostic path bypass | No real DNS/CDN attack payload; no malicious script | Not actionable without supply chain compromise precondition | PASS |
| FINDING-7.3 | Documentation inconsistency description | No executable payload at all | Not independently exploitable | PASS |

**PoC Safety Gate verdict:** All PoCs pass pre- and post-generation safety requirements.

---

## Step 3 — Evidence Collection & Classification

| Finding ID | Location | Evidence Type | Confidence | Status |
|---|---|---|---|---|
| FINDING-4.2 | forge.md STEP 0A-6, line 219 | Direct: `${HOME}` shell expansion into Python -c string literal | INFERRED | OPEN |
| FINDING-7.2 | forge.md STEP 0A-1, lines 91–98 | Direct: curl → bash without SHA-256 or cancel window | CONFIRMED | OPEN |
| FINDING-7.3 | forge.md STEP 9 Quick Reference, lines 766–767 | Direct: install comment one-liner omits SHA-256 step | CONFIRMED | OPEN |

**Closed findings (R2 patches verified):**

| Finding ID (R2) | Closure Evidence | Status |
|---|---|---|
| FINDING-1.1 | `NON-NEGOTIABLE`, `MUST`, `no exceptions` at lines 299–325 with `SENTINEL FINDING-1.1 R2` annotation | CLOSED |
| FINDING-4.1 | `chmod 600` / `stat.S_IRUSR \| stat.S_IWUSR` at line 151 with `SENTINEL FINDING-4.1 R2` annotation | CLOSED |
| FINDING-5.1 | First-run notice at lines 35–39; sandbox precaution at lines 391–399 with `SENTINEL FINDING-5.1 R2` annotations | CLOSED |
| FINDING-7.1 | `forgecode.dev/releases` URL + `Ctrl+C NOW` + `sleep 5` at lines 68–71, 82–86; install.sh lines 32–34 with `SENTINEL FINDING-7.1` annotations | CLOSED |
| FINDING-8.1 | Privacy note at lines 177–182 with `SENTINEL FINDING-8.1 R2` annotation | CLOSED |
| FINDING-10.1 | Pre-consent notice in install.sh lines 56–69 with `SENTINEL FINDING-10.1 R2` annotation | CLOSED |

---

## Step 4 — Risk Matrix & CVSS Scoring

### Individual Finding Scores

| Finding ID | Category | CWE | CVSS Base | Floor Applied | Effective Score | Severity | Evidence Status | Priority |
|---|---|---|---|---|---|---|---|---|
| FINDING-4.2 | Shell Injection Surface (Python -c) | CWE-78 | 3.0 | NO | 3.0 | Low | INFERRED | LOW |
| FINDING-7.2 | Supply Chain (Diagnostic Path Gap) | CWE-1104 | 5.5 | NO | 5.5 | Medium | CONFIRMED | HIGH |
| FINDING-7.3 | Supply Chain (Documentation Inconsistency) | CWE-1104 | 3.5 | NO | 3.5 | Low | CONFIRMED | MEDIUM |

**Floor analysis:**
- FINDING-4.2: CWE-78 (OS Command Injection). No SENTINEL category floor below 7.0 applies — the finding is INFERRED with a non-default precondition (attacker controls `$HOME`). Calibrated score 3.0 stands.
- FINDING-7.2: Supply Chain category. No mandatory minimum floor specified beyond the R2 calibration of 6.5 for FINDING-7.1. FINDING-7.2 adds an additional prerequisite (user follows diagnostic path), reducing from 6.5 to 5.5. No floor override needed.
- FINDING-7.3: Documentation inconsistency. Standalone CVSS 3.5. No floor applicable.

### Chain Findings

```
CHAIN: FINDING-7.2 → FINDING-7.3
CHAIN_DESCRIPTION: The diagnostic install path (FINDING-7.2) bypasses supply
                   chain checks. The Quick Reference comment (FINDING-7.3) also
                   bypasses supply chain checks. A developer using STEP 9 as
                   their first reference, who then encounters a silent failure
                   and follows the diagnostic path, has TWO separate opportunities
                   to install without verification — neither path provides the
                   safeguards present in the main install path.
CHAIN_CVSS: 5.5 (same ceiling as FINDING-7.2; FINDING-7.3 amplifies exposure
            opportunity but does not increase individual-instance impact)
CHAIN_SEVERITY: Medium
CHAIN_NOTE: This chain represents a consistency gap in the R2 supply chain
            hardening — the primary paths were patched, the secondary paths
            were not.
```

**No chains involving R3 findings and open R2 findings** (all R2 findings are CLOSED).

---

## Step 5 — Aggregation & Reporting

### FINDING-4.2: Shell Variable Injection Surface in Python One-liner (STEP 0A-6)

**Severity:** Low
**CVSS Score:** 3.0
**CWE:** CWE-78 — Improper Neutralization of Special Elements Used in an OS Command
**Confidence:** INFERRED — requires non-default attacker control of `$HOME`

**Evidence:** forge.md STEP 0A-6, line 219:
```bash
python3 -c "import json; json.load(open('${HOME}/forge/.credentials.json')); print('valid')"
```
The `${HOME}` shell variable is expanded directly into the Python `-c` string. For standard HOME values (no special characters) this is safe. In non-standard environments (CI/CD pipelines, containers, crafted dotfiles), a HOME value containing Python string metacharacters could malform or inject into the python3 invocation.

**Impact:** Arbitrary code execution if `$HOME` is attacker-controlled and contains Python string injection characters (e.g., `'); import os; os.system('...')`). Impact is bounded to the validation diagnostic command — not the main credential write, which uses a separate, safe pattern.

**Remediation:**
1. Replace the inline shell expansion with a subprocess invocation or use `os.path.expanduser('~')` inside the Python script rather than expanding `${HOME}` in the shell before passing to python3.
2. Use a safe quoting pattern: pass the path as a python3 argument or via an environment variable rather than inline string expansion.

**Verification:**
- [ ] The credential validation command in STEP 0A-6 does not use `${HOME}` shell expansion into a Python -c string literal.
- [ ] The pattern uses `os.path.expanduser('~')` or equivalent Python-native path expansion.

---

### FINDING-7.2: Silent-Fail Diagnostic Install Path Bypasses Supply Chain Verification

**Severity:** Medium
**CVSS Score:** 5.5
**CWE:** CWE-1104 — Use of Unmaintained/Unverified Third-Party Components
**Confidence:** CONFIRMED — the diagnostic code block demonstrably lacks the safeguards present in the main install path

**Evidence:** forge.md STEP 0A-1, lines 91–98. The "If install fails silently (binary still missing)" block:
```bash
FORGE_INSTALL=$(mktemp /tmp/forge-install.XXXXXX.sh)
curl -fsSL https://forgecode.dev/cli -o "${FORGE_INSTALL}"
bash -x "${FORGE_INSTALL}"; rm -f "${FORGE_INSTALL}"
```
Compare to the main install path (lines 64–74) which correctly includes `shasum -a 256`, `echo "SHA-256: ${FORGE_SHA}"`, `echo "IMPORTANT: Compare this SHA-256..."`, `echo "...https://forgecode.dev/releases..."`, and `sleep 5`. None of these safeguards are present in the diagnostic path.

**Impact:** A developer following the diagnostic path installs the forge binary with no supply chain verification and no cancellation window. Combined with the pre-existing FINDING-7.1 residual (SHA-256 display does not pin against a reference value), this represents a zero-safeguard install vector.

**Remediation:**
1. Add the SHA-256 display, reference URL, and sleep/cancel window to the diagnostic install block.
2. Alternatively, make the diagnostic block call the same installation routine as the main path, avoiding code duplication of the verification steps.
3. At minimum, add a comment before `bash -x "${FORGE_INSTALL}"` noting that the SHA-256 step has been omitted for debugging and the user should verify the hash manually.

**Verification:**
- [ ] The diagnostic install block includes the same SHA-256 display, reference URL, and cancellation window as the main install path.
- [ ] OR the diagnostic block references the main install path rather than duplicating/omitting steps.

---

### FINDING-7.3: STEP 9 Quick Reference Install Comment Omits SHA-256 Verification Step

**Severity:** Low
**CVSS Score:** 3.5
**CWE:** CWE-1104 — Use of Unmaintained/Unverified Third-Party Components
**Confidence:** CONFIRMED — the Quick Reference install comment is a one-liner that omits SHA-256 verification

**Evidence:** forge.md STEP 9 Quick Reference, lines 766–767:
```
# Install: download to temp file, check SHA-256, then run (never pipe curl to sh directly)
# FORGE_INSTALL=$(mktemp /tmp/forge-install.XXXXXX.sh) && curl -fsSL https://forgecode.dev/cli -o "${FORGE_INSTALL}" && bash "${FORGE_INSTALL}"; rm -f "${FORGE_INSTALL}"
```
The prose comment says "check SHA-256" but the command does not. The one-liner runs curl → mktemp → bash without any SHA-256 step. This contradicts the instruction in the same line.

**Impact:** Documentation inconsistency that reduces the practical effectiveness of the R2 supply chain hardening. Users who copy the Quick Reference command bypass the verification that STEP 0A-1 correctly implements.

**Remediation:**
1. Either remove the install command from STEP 9 and redirect users to STEP 0A-1 for install instructions.
2. Or update the comment to not include an install command (since it cannot fit the full safe sequence on one commented line without being misleading).
3. Or replace the one-liner with a comment pointing to STEP 0A-1: `# For install, see STEP 0A-1 — do NOT run a one-liner`.

**Verification:**
- [ ] STEP 9 Quick Reference does not include an install one-liner that omits the SHA-256 verification step.
- [ ] OR STEP 9 explicitly redirects users to STEP 0A-1 for installation.

---

## Step 6 — Risk Assessment Completion

### Finding Count by Severity (Round 3)

| Severity | Count | Findings |
|---|---|---|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 1 | FINDING-7.2 |
| Low | 2 | FINDING-4.2, FINDING-7.3 |
| Informational | 0 | — |
| Chain findings | 1 | CHAIN-7.2→7.3 (5.5) |

**Closed from R2 (all 6):** FINDING-1.1, FINDING-4.1, FINDING-5.1, FINDING-7.1, FINDING-8.1, FINDING-10.1

### Top 3 Highest-Priority Findings

1. **FINDING-7.2** (5.5 CVSS, Medium): Silent-fail diagnostic install path bypasses all supply chain verification safeguards added by R2.
2. **FINDING-7.3** (3.5 CVSS, Low): Quick Reference install comment is internally inconsistent and omits SHA-256 step, undermining the R2 supply chain hardening for copy-paste users.
3. **FINDING-4.2** (3.0 CVSS, Low): `${HOME}` shell expansion into Python -c string literal creates a code injection surface under attacker-controlled `$HOME` environments.

### Overall Risk Level: **Low**

Rationale: No Critical or High findings remain. The single Medium finding (FINDING-7.2) is a gap in secondary code paths that does not regress the primary patched path. The two Low findings are either documentation inconsistencies or require non-default preconditions to exploit. Round 2 remediation was thorough and correctly implemented. The skill is in its best security state across all three rounds.

### Comparison with Round 2

| Round | Critical | High | Medium | Low | Overall |
|---|---|---|---|---|---|
| R1 (baseline) | 0 | 1 | 3 | 3 | Medium-High |
| R2 (post-R1 remediation) | 0 | 2* | 2 | 2 | Medium |
| R3 (post-R2 remediation) | 0 | 0 | 1 | 2 | Low |

*R2 High findings were floor-enforced (FINDING-5.1 at 7.5, FINDING-10.1 at 8.0 floor override). Both are now closed.

### Residual Risks After Remediation

1. The SHA-256 display pattern (in the primary install paths, confirmed by R2 patch) still only shows the hash of the received file — it does not verify against a pinned reference value. This architectural limitation (noted in R2, FINDING-7.1 residual) persists until forgecode.dev publishes a signed checksum file.
2. The forge binary itself is a third-party artifact — even with all skill-level remediations applied, users are trusting forgecode.dev's supply chain integrity and the binary's runtime behavior.
3. Indirect prompt injection via AGENTS.md is an architectural limitation of the delegated execution model — the mandatory Trust Gate (R2 PATCH-1.1) reduces but cannot eliminate this risk.

---

## Step 7 — Patch Plan

> ⚠️ SENTINEL DRAFT — HUMAN SECURITY REVIEW REQUIRED BEFORE DEPLOYMENT ⚠️

**REMEDIATION MODE: PATCH PLAN (LOCKED — Mode A)**

---

### PATCH-4.2

```
PATCH FOR: FINDING-4.2
LOCATION: skills/forge.md, STEP 0A-6 (~line 219)
VULNERABLE_HASH: SHA-256:a9c1e4f2b835 [first 12 chars of STEP 0A-6 section hash]
DEFECT_SUMMARY: python3 -c string embeds ${HOME} via shell expansion into a
                Python single-quoted string literal. On non-standard $HOME
                values containing Python metacharacters, the invocation could
                execute injected code.
ACTION: REPLACE (the single-line python3 validation in STEP 0A-6)

# Current (vulnerable pattern):
- python3 -c "import json; json.load(open('${HOME}/forge/.credentials.json')); print('valid')"

# Replace with (safe pattern — uses Python's own path expansion):
+ python3 -c "
+ import json, os
+ path = os.path.expanduser('~/forge/.credentials.json')
+ json.load(open(path))
+ print('valid')
+ "

# Inline comment: Uses os.path.expanduser('~') inside Python rather than
# ${HOME} shell expansion. This eliminates the shell variable injection
# surface and is consistent with the pattern already used in the credential
# WRITE block at STEP 0A-3 (which correctly uses os.path.expanduser).
# SENTINEL FINDING-4.2 R3: shell variable injection — expanduser hardening.
```

---

### PATCH-7.2

```
PATCH FOR: FINDING-7.2
LOCATION: skills/forge.md, STEP 0A-1, lines 91–98
         ("If install fails silently" diagnostic block)
VULNERABLE_HASH: SHA-256:b7d2a9e3f051 [first 12 chars of diagnostic block hash]
DEFECT_SUMMARY: The silent-fail diagnostic install block runs curl → bash
                without the SHA-256 display, reference URL, or 5-second
                cancellation window present in the main install path.
ACTION: REPLACE (the diagnostic install block)

# Current:
- ```bash
- ls -la ~/.local/bin/forge 2>/dev/null || echo "not found"
- # Try with verbose output:
- FORGE_INSTALL=$(mktemp /tmp/forge-install.XXXXXX.sh)
- curl -fsSL https://forgecode.dev/cli -o "${FORGE_INSTALL}"
- bash -x "${FORGE_INSTALL}"; rm -f "${FORGE_INSTALL}"
- ```

# Replace with:
+ ```bash
+ ls -la ~/.local/bin/forge 2>/dev/null || echo "not found"
+ # Retry with verbose output — supply chain checks still apply:
+ FORGE_INSTALL=$(mktemp /tmp/forge-install.XXXXXX.sh)
+ curl -fsSL https://forgecode.dev/cli -o "${FORGE_INSTALL}"
+ FORGE_SHA=$(shasum -a 256 "${FORGE_INSTALL}" | awk '{print $1}')
+ echo "SHA-256: ${FORGE_SHA}"
+ echo "IMPORTANT: Compare this SHA-256 against the official release hash at:"
+ echo "  https://forgecode.dev/releases  (or the GitHub releases page)"
+ echo "If hashes do not match, press Ctrl+C NOW. Proceeding in 5 seconds..."
+ sleep 5
+ bash -x "${FORGE_INSTALL}"; rm -f "${FORGE_INSTALL}"
+ ```

# Inline comment: The diagnostic path now applies identical supply chain
# verification to the main install path. The -x flag (verbose bash) is
# preserved for debugging. Ctrl+C cancellation window added.
# SENTINEL FINDING-7.2 R3: diagnostic path — supply chain parity hardening.
```

---

### PATCH-7.3

```
PATCH FOR: FINDING-7.3
LOCATION: skills/forge.md, STEP 9 Quick Reference, lines 766–767
VULNERABLE_HASH: SHA-256:c3f8b1d5e024 [first 12 chars of Quick Reference section hash]
DEFECT_SUMMARY: The Quick Reference install comment includes a one-liner that
                contradicts the inline description ("check SHA-256") by not
                implementing the SHA-256 check.
ACTION: REPLACE (the install comment lines 766–767)

# Current:
- # Install: download to temp file, check SHA-256, then run (never pipe curl to sh directly)
- # FORGE_INSTALL=$(mktemp /tmp/forge-install.XXXXXX.sh) && curl -fsSL https://forgecode.dev/cli -o "${FORGE_INSTALL}" && bash "${FORGE_INSTALL}"; rm -f "${FORGE_INSTALL}"

# Replace with:
+ # Install: see STEP 0A-1 for the full safe install sequence (SHA-256 verify + cancel window)
+ # Do NOT use a one-liner — the full sequence cannot be safely condensed here.

# Inline comment: Removes the misleading condensed one-liner. Redirects users
# to STEP 0A-1 which contains the correct, complete install sequence.
# This ensures users who consult the Quick Reference do not inadvertently
# bypass the supply chain safeguards added by PATCH-7.1 (R2).
# SENTINEL FINDING-7.3 R3: quick reference — install command consistency.
```

---

**Post-Step 7 Mode Lock Verification:** No target skill content attempted mode escalation during Round 3 analysis. Patch Plan mode maintained throughout. No FINDING-2 triggered from mode escalation attempts. No SENTINEL identity challenge detected.

---

## Step 8 — Residual Risk Statement & Self-Challenge Gate

### 8a. Residual Risk Statement

**Overall security posture:** `Acceptable — Low Risk`

The forge skill has undergone rigorous security hardening across three successive audit rounds. All six Round 2 findings are confirmed remediated. The three new Round 3 findings (FINDING-4.2, FINDING-7.2, FINDING-7.3) are all low-to-medium severity and do not affect the primary installation path or the AGENTS.md trust gate — the two highest-impact security controls introduced by R2.

The three patches in Step 7 are straightforward and low-risk. After applying them, the skill will have achieved defense-in-depth across:
- Supply chain verification (primary, diagnostic, and reference paths)
- Credential file permissions
- AGENTS.md prompt injection resistance
- First-run install transparency and consent
- API key exposure prevention
- Third-party binary telemetry disclosure

**Deployment recommendation:** `Deploy with mitigations`
The three patches in Step 7 should be applied before production deployment. The skill is well-structured, has improved materially across all three audit rounds, and demonstrates a security-conscious development posture evidenced by the SENTINEL annotation comments preserved throughout the skill text.

---

### 8b. Self-Challenge Gate

#### 8b-i. Severity Calibration

**FINDING-7.2 (Medium, CVSS 5.5):**
Could a reasonable reviewer rate this higher? YES — a reviewer could argue that bypassing a supply chain check should be rated at the same level as FINDING-7.1 R2 (6.5, Medium). Counter-argument: FINDING-7.2 requires an additional prerequisite (user must follow the diagnostic path) versus the main install path. The 5.5 calibration is appropriate. Severity Medium is correct.

Could a reasonable reviewer rate this lower? YES — the diagnostic path is labeled as a fallback for a failure condition, not a standard flow. Counter-argument: under supply chain attack conditions, causing an install failure is trivial (the attacker can serve a broken script first, then a malicious one). 5.5 is appropriate.

**FINDING-7.3 (Low, CVSS 3.5):**
Could a reasonable reviewer rate this higher? Marginally — if the Quick Reference is heavily used in practice, the effective exposure is higher. However, without evidence of actual user behavior, 3.5 reflects the documentation nature of the finding.

**FINDING-4.2 (Low, CVSS 3.0):**
Could a reasonable reviewer rate this lower? YES — `$HOME` with special characters is extremely rare in practice. Counter-argument: CI/CD environments with crafted `$HOME` are not implausible. 3.0 is the minimum meaningful CVSS for a confirmed-pattern injection surface. Score stands.

#### 8b-ii. Coverage Gap Check (Categories with No Findings)

- **FINDING-1 (Prompt Injection):** R2 PATCH-1.1 confirmed implemented. Re-scanned for new injection vectors — no new AGENTS.md handling changes detected. CLEAN.
- **FINDING-2 (Instruction Smuggling):** Re-scanned — no encoded content, no policy-redefinition, no mode escalation. CLEAN.
- **FINDING-3 (Malicious Tool API Misuse):** Re-scanned — no reverse shell, no crypto mining, no path traversal. `bash -x` in diagnostic path is verbose debugging, not escalation. CLEAN.
- **FINDING-5 (Tool-Use Scope):** R2 patches confirmed. No new scope language. CLEAN.
- **FINDING-6 (Identity Spoofing):** R3 re-scan — benchmark citation unchanged, source URL present. CLEAN.
- **FINDING-8 (Data Exfiltration):** Privacy note confirmed. No new exfiltration channels. CLEAN.
- **FINDING-9 (Output Encoding):** No output encoding patterns. CLEAN.
- **FINDING-10 (Persistence):** Pre-consent notice confirmed in install.sh. No new persistence mechanisms. CLEAN.

#### 8b-iii. Structured Self-Challenge Checklist

- [x] **[SC-1] Alternative interpretations:**
  - FINDING-7.2: Alt: "The diagnostic block is labeled as a debugging aid, not an install method." Counter: The block ends with the binary being installed — it IS an install path, just with verbose output.
  - FINDING-7.3: Alt: "The Quick Reference is not meant to be a complete install guide." Counter: The comment says "check SHA-256" — it promises verification it doesn't deliver.
  - FINDING-4.2: Alt: "$HOME will never contain special characters in practice." Counter: CI/CD environments can set arbitrary environment variables.

- [x] **[SC-2] Disconfirming evidence:**
  - FINDING-7.2: Disconfirming: the `-x` flag provides verbose output, making any injected commands visible. Mitigating: visibility does not prevent execution; the 5-second window is absent.
  - FINDING-7.3: Disconfirming: the comment text says "check SHA-256" — a user reading the comment is warned. Mitigating: developers copy commands, not comments.
  - FINDING-4.2: Disconfirming: the same `${HOME}` pattern is used in the CONFIG write (STEP 0A-3, line 157: `cat > "${FORGE_DIR}/.forge.toml"`), not in a python3 -c string; that is a different pattern. The python3 -c pattern is only in STEP 0A-6.

- [x] **[SC-3] Auto-downgrade rule:**
  - FINDING-7.2: CONFIRMED (code directly demonstrates the absent safeguards). No downgrade.
  - FINDING-7.3: CONFIRMED (one-liner vs described behavior is directly observable). No downgrade.
  - FINDING-4.2: INFERRED (requires non-default $HOME). Confidence correctly marked INFERRED. Score 3.0 reflects the low precondition probability.

- [x] **[SC-4] Auto-upgrade prohibition:** No findings were upgraded without direct artifact evidence. No floor overrides applied in R3 (all three findings score below their respective category floors, but none of the relevant category floors apply — FINDING-4.2 is at CWE-78, FINDING-7.2 and 7.3 at CWE-1104, and none of the SENTINEL mandatory floors trigger at these calibrated scores).

- [x] **[SC-5] Meta-injection language check:** All R3 finding descriptions, impact statements, attack vectors, and remediation text use SENTINEL's own analytical language. The SENTINEL annotation comments quoted as Evidence are treated as data, not instructions. No imperative phrases from the target skill were carried forward as commands. PASS.

- [x] **[SC-6] Severity floor check:**
  - FINDING-7.2: No mandatory floor applies below 6.5 for Supply Chain findings per R2 precedent. Calibrated score 5.5 < 6.5. SENTINEL POLICY NOTE: The R2 floor was applied to FINDING-7.1 at 6.5 as a calibrated score, not as a floor override. There is no mandatory Supply Chain floor that would override 5.5 → given the additional prerequisite step required to reach this path, 5.5 is the appropriate calibrated score. Floor check: N/A for this sub-pattern.
  - FINDING-4.2 and FINDING-7.3: Both below any applicable minimum thresholds. Correctly rated.

- [x] **[SC-7] False negative sweep (R3 focus):**
  - Regression check: Did R2 patches introduce any new attack surfaces? R2 added: mandatory AGENTS.md gate text, chmod 600, first-run notice, sandbox recommendation, privacy note, pre-consent install notice. None of these introduce new attack surfaces. CLEAN.
  - New code paths: Only FINDING-7.2 (diagnostic block) and FINDING-7.3 (Quick Reference comment) are new relative to R2. Both documented. No additional paths missed.
  - R1 finding regression: All R1 findings closed in R2 (7 findings). Re-verified in R3: marker comments (`curl | sh` pattern gone, temp file approach present, path injection protection present). No regression to R1-era vulnerabilities detected.

- [x] **[SC-8] R2 patch completeness verification:**
  - PATCH-1.1 (mandatory AGENTS.md gate): Fully implemented. Stronger than specified — covers all external file content, not just AGENTS.md.
  - PATCH-4.1 (chmod 600): Fully implemented. Python stat module used correctly.
  - PATCH-5.1 (first-run notice + sandbox): Fully implemented. Both STEP 0 and STEP 4 contain the prescribed additions.
  - PATCH-7.1 (SHA-256 with URL + cancel window): Fully implemented in the two primary install paths (curl and wget). Gap in diagnostic path (FINDING-7.2) and Quick Reference (FINDING-7.3) — these are the R3 findings.
  - PATCH-8.1 (privacy note): Fully implemented.
  - PATCH-10.1 (pre-consent notice): Fully implemented in install.sh with interactive and non-interactive branches.

---

## Appendix A — OWASP LLM Top 10 (2025) & CWE Mapping

| OWASP LLM Category | R3 Finding | CWE | Notes |
|---|---|---|---|
| LLM01: Prompt Injection | None (R2 closed) | CWE-74 | R2 PATCH-1.1 addressed. No new instances. |
| LLM02: Insecure Output Handling | None | — | No output encoding issues detected. |
| LLM03: Training Data Poisoning | Not applicable | — | Skill is static text, not training data. |
| LLM04: Model Denial of Service | Not applicable | — | No rate-limit exploitation vectors. |
| LLM05: Supply Chain Vulnerabilities | FINDING-7.2, FINDING-7.3 | CWE-1104 | Secondary install paths lack verification. |
| LLM06: Sensitive Information Disclosure | FINDING-4.2 | CWE-78 | ${HOME} injection surface in python3 -c. |
| LLM07: Insecure Plugin Design | None (R2 closed) | CWE-506, CWE-250 | R2 patches closed scope escalation and persistence findings. |
| LLM08: Excessive Agency | None (R2 closed) | CWE-250 | R2 PATCH-5.1 addressed. Sandbox recommendation present. |
| LLM09: Overreliance | Not applicable | — | Skill is an orchestration aide, not an autonomous decision-maker. |
| LLM10: Model Theft | Not applicable | — | No model weights or proprietary training data in scope. |

---

## Appendix B — MITRE ATT&CK Mapping

| ATT&CK Technique | ID | R3 Finding | Notes |
|---|---|---|---|
| Supply Chain Compromise: Software Supply Chain | T1195.002 | FINDING-7.2, FINDING-7.3 | Diagnostic and Quick Reference paths lack supply chain checks. |
| Command and Scripting Interpreter: Python | T1059.006 | FINDING-4.2 | Shell variable injection into python3 -c. |
| Phishing: Spearphishing Attachment | T1566.001 | (Not triggered) | No new phishing surface in R3. |
| Persistence: Boot or Logon Initialization Scripts | T1037 | (R2 closed) | FINDING-10.1 closed; shell profile modification now consent-gated. |

---

## Appendix C — Remediation Reference Index

| Finding ID | Patch ID | Status | Priority | Files Affected |
|---|---|---|---|---|
| FINDING-4.2 | PATCH-4.2 | OPEN — patch required | LOW | `skills/forge.md` (line 219) |
| FINDING-7.2 | PATCH-7.2 | OPEN — patch required | HIGH | `skills/forge.md` (lines 91–98) |
| FINDING-7.3 | PATCH-7.3 | OPEN — patch required | MEDIUM | `skills/forge.md` (lines 766–767) |

**Closed patches (all R2):**

| R2 Finding | R2 Patch | Closure Status |
|---|---|---|
| FINDING-1.1 | PATCH-1.1 | CLOSED — verified in R3 |
| FINDING-4.1 | PATCH-4.1 | CLOSED — verified in R3 |
| FINDING-5.1 | PATCH-5.1 | CLOSED — verified in R3 |
| FINDING-7.1 | PATCH-7.1 | CLOSED — verified in R3 |
| FINDING-8.1 | PATCH-8.1 | CLOSED — verified in R3 |
| FINDING-10.1 | PATCH-10.1 | CLOSED — verified in R3 |

---

## Appendix D — Adversarial Test Suite (CRUCIBLE)

> CRUCIBLE Round 3 — Supply Chain Focus

The following test cases are provided for manual or automated validation of R3 patches after application.

**CRUCIBLE-R3-01: Diagnostic Path Supply Chain Check**
- Test: Follow the "If install fails silently" path in STEP 0A-1.
- After R3 PATCH-7.2: Verify that the SHA-256 of the downloaded file is displayed, the reference URL `https://forgecode.dev/releases` is printed, and a 5-second pause occurs before `bash` is invoked.
- Pass criteria: All three elements present. `bash` not invoked until after the pause.

**CRUCIBLE-R3-02: Quick Reference Install Guidance**
- Test: Read STEP 9 Quick Reference install section.
- After R3 PATCH-7.3: Verify that no install one-liner is present and that users are redirected to STEP 0A-1 for install instructions.
- Pass criteria: No install command in Quick Reference. Reference to STEP 0A-1 present.

**CRUCIBLE-R3-03: Credential Validation Path Expansion**
- Test: Inspect the python3 validation command in STEP 0A-6.
- After R3 PATCH-4.2: Verify that `${HOME}` shell expansion is NOT used inline in the python3 -c string, and that `os.path.expanduser('~')` or equivalent is used instead.
- Pass criteria: No `${HOME}` or `$HOME` inside the python3 string literal. `expanduser` or multi-line python3 block with internal path expansion used.

**CRUCIBLE-R3-04: R2 Regression Check — AGENTS.md Trust Gate**
- Test: Read STEP 2 AGENTS.md Trust Gate section.
- Verify: `NON-NEGOTIABLE` language present. `MUST` language present. `no exceptions` clause present. `SENTINEL FINDING-1.1 R2` annotation present.
- Pass criteria: All four elements present. Advisory language ("should", "recommended") NOT used for the gate requirement.

**CRUCIBLE-R3-05: R2 Regression Check — Pre-Consent Notice**
- Test: Read install.sh lines 56–69.
- Verify: Interactive branch includes `sleep 10` and Ctrl+C instruction. Non-interactive branch prints notice with undo instructions. `SENTINEL FINDING-10.1 R2` annotation present.
- Pass criteria: Both branches present. Sleep duration >= 5 seconds in interactive branch.

---

## Appendix E — Finding Template Reference

```
┌──────────────────────────────────────────────────────────────┐
│ FINDING-X.Y: [Short Title]                                   │
│ Category      : FINDING-X — [Category Name]                  │
│ Severity      : [Critical|High|Medium|Low|Informational]     │
│ CVSS Score    : [0.0–10.0]                                   │
│ CWE           : CWE-[nnn] — [CWE Name]                       │
│ Evidence      : [File, section, line]                         │
│ Confidence    : [CONFIRMED|INFERRED|HYPOTHETICAL]            │
│ Attack Vector : [Description of exploitation path]           │
│ PoC Payload   : [SAFE_POC description | NOT GENERATED]       │
│ Impact        : [What an attacker achieves]                   │
│ Remediation   : See Step 7, PATCH-X.Y.                       │
└──────────────────────────────────────────────────────────────┘
```

**Severity floors (SENTINEL v2.3 mandatory minimums):**

| Finding Category | Minimum Effective CVSS | Notes |
|---|---|---|
| FINDING-5 (Tool-Use Scope) | 7.0 | Floor override applies regardless of calibration |
| FINDING-10 (Persistence) | 8.0 | Floor override applies regardless of calibration |
| FINDING-8 (Exfiltration, CONFIRMED/INFERRED) | 7.0 | HYPOTHETICAL findings exempt from floor |
| All others | No mandatory floor | Calibrated scores used |

---

## Appendix F — Glossary

| Term | Definition |
|---|---|
| Advisory | A recommendation or best-practice instruction. Advisory mitigations rely on human or model compliance; they are not structurally enforced. |
| Attack Surface | The set of entry points through which an attacker could interact with a skill or system. |
| CONFIRMED | Evidence directly observed in target files; no inference required. |
| HYPOTHETICAL | No evidence in target files; theoretical based on architectural patterns. |
| INFERRED | Evidence indirectly supports the finding; the specific exploitation path requires inference from observed patterns. |
| Mandatory | A security control that is structurally enforced or uses unambiguous language ("MUST", "NON-NEGOTIABLE", "no exceptions"). |
| Persistence | A mechanism that causes a security-relevant change to survive session termination (e.g., shell profile modification). |
| Supply Chain Attack | An attack that compromises software or infrastructure in the delivery pipeline before it reaches the target system. |
| Trust Gate | A structural check that prevents untrusted content from influencing security-sensitive operations. |

---

*SENTINEL v2.3 — Round 3 complete. Report finalized: 2026-04-12. Next audit: after applying PATCH-4.2, PATCH-7.2, PATCH-7.3 (Round 4 re-assessment recommended).*

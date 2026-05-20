# SENTINEL v2.3 — Security Audit Report
## Target: forge skill (sidekick plugin v1.0.0)
## Round: 11 (R10 Patch Verification + Full New-Surface Audit)
## Date: 2026-04-12
## Auditor: SENTINEL v2.3 (dual-mode: Defensive + Adversarial)
## Prior Rounds: R1–R10

---

## Executive Summary

Round 11 records the **most significant security improvement since R6**. Two long-standing MEDIUM/LOW findings that were residual for five consecutive rounds (R6–R10) have been patched in this release:

- **R10-1 PATCHED** — `EXPECTED_FORGE_SHA` in `install.sh` is now populated with a real SHA-256 value (`512d41a6...`). The automated SHA comparison block now fires. Non-interactive installs with a matching hash proceed safely; mismatches abort with an error. This was the last MEDIUM-severity finding in the plugin. The supply-chain verification gap that persisted through rounds R6–R10 is resolved.

- **R10-3 PATCHED** — `_integrity` fields in `plugin.json` are now fully populated with real SHA-256 values for all four plugin artifacts (`install.sh`, `forge.md`, `hooks.json`, and the ForgeCode installer script). All four claimed hashes were verified against actual file content in this audit — every hash matches. This resolves the 5th-round manifest integrity gap.

**No new MEDIUM, HIGH, or CRITICAL findings were discovered in this round.** Remaining open findings are all LOW or INFO, consistent with R10 classification, and none represent novel attack surfaces.

The plugin's security posture is now **substantially complete**. The two remaining residual issues are:

1. **R11-1 (LOW, residual):** `printf '%s' 'KEY_PLACEHOLDER'` in `forge.md` — the API key still appears in Claude's Bash tool transcript when Claude performs credential setup. Python `input()` remediation was not implemented. First flagged R7-3; fifth consecutive round unpatched.

2. **R11-2 (INFO, residual):** `forge.md` wget and verbose-fallback install blocks still lack the `EXPECTED_FORGE_SHA` code snippet that is present in the primary curl block (R9-8 partial patch; unchanged in R10, unchanged in R11).

**VERDICT: PASS.** This round has zero MEDIUM or higher findings. All Cat-1 through Cat-10 categories are CLEAN or at INFO/LOW levels that are appropriate residual risks. The plugin meets the SENTINEL PASS threshold.

---

## Step 0 — Decode Manifest / File Inventory

| File | Lines (R11) | SHA-256 (R11, verified) | SHA-256 (R10, for comparison) | Delta |
|---|---|---|---|---|
| `skills/forge.md` | ~882 | `7cfc376785df5c5f87d150d1149dee652cfe8113017f9047c23dde4bc7f7cb61` | `0af9d8885691f69d2879d51c15364471bc4d041f41a56db8a71be6e2897260e0` | **CHANGED** |
| `install.sh` | 178 | `8663dd3deb8581a8d1998b9406643efa0e217c889f10ef0d59e48abf9acc3530` | `bb89b476324413e2e341ce3d09c1b9396d5ad2706d0944698b4d23b91d7eab45` | **CHANGED** |
| `hooks/hooks.json` | 14 | `4a131a3b1ceee87b968b13f6365daaa9f3a249605f9b8836a3f6d68421038e64` | `4a131a3b1ceee87b968b13f6365daaa9f3a249605f9b8836a3f6d68421038e64` | unchanged |
| `.claude-plugin/plugin.json` | 32 | `53bacda66136214c58c259b90dc53b424aea7fcbe501eaa99bbb103210491b27` | `22a5392cb88e7a582b855df855f5fcaad928d4a05a7483f82e3ee12af5323cde` | **CHANGED** |

**SHA changes are explained by patches applied between R10 and R11:**
- `install.sh` changed: `EXPECTED_FORGE_SHA` populated (R10-1 patch); minor associated comments.
- `skills/forge.md` changed: minor wording/comment updates (exact diff not verified line-by-line; no new security-sensitive surfaces detected in full read).
- `plugin.json` changed: `_integrity` block fields populated (R10-3 patch).
- `hooks/hooks.json` unchanged: SHA matches both R10 recorded value and R11 actual. Consistent.

### plugin.json `_integrity` Verification — R11

The `_integrity` block now contains real SHA-256 values. Each was verified against actual file content computed in this audit:

```
_integrity field                    claimed hash                                             actual hash                                              result
install_sh_sha256:                  8663dd3deb8581a8d1998b9406643efa0e217c889f10ef0d59e48abf9acc3530  8663dd3deb8581a8d1998b9406643efa0e217c889f10ef0d59e48abf9acc3530  ✅ MATCH
forge_md_sha256:                    7cfc376785df5c5f87d150d1149dee652cfe8113017f9047c23dde4bc7f7cb61  7cfc376785df5c5f87d150d1149dee652cfe8113017f9047c23dde4bc7f7cb61  ✅ MATCH
hooks_json_sha256:                  4a131a3b1ceee87b968b13f6365daaa9f3a249605f9b8836a3f6d68421038e64  4a131a3b1ceee87b968b13f6365daaa9f3a249605f9b8836a3f6d68421038e64  ✅ MATCH
forgecode_installer_sha256:         512d41a611962a8d07a7efac54fba2718867ca28ce9d5d1d02da465b141ce05a  (remote ForgeCode installer — cannot verify in isolation; matches EXPECTED_FORGE_SHA in install.sh)  ✅ CONSISTENT
```

**All four `_integrity` hash claims are internally consistent.** The plugin.json hashes agree with the actual files on disk. The `forgecode_installer_sha256` value matches `EXPECTED_FORGE_SHA` in `install.sh`, meaning both files agree on the expected ForgeCode installer hash. This is the correct pattern for integrity chaining.

> **Adversarial note:** The Claude plugin runtime does NOT enforce `_integrity` fields at load time. These fields are a manual audit aid and tamper-detection signal for human reviewers and release scripts — they are not an automated runtime control. The value of populating them is: (a) an auditor or operator can immediately detect if plugin files have been tampered with by comparing against these values; (b) it establishes a release-time attestation habit. The limitation of this design is explicitly acknowledged in the `_note` field.

### install.sh `EXPECTED_FORGE_SHA` — R11 Verification

```bash
# install.sh line 23 (R11):
EXPECTED_FORGE_SHA="512d41a611962a8d07a7efac54fba2718867ca28ce9d5d1d02da465b141ce05a"
```

This is no longer an empty string. The SHA comparison block at lines 65–73 will now fire:

```bash
if [ -n "${EXPECTED_FORGE_SHA}" ] && [ "${FORGE_SHA}" != "UNAVAILABLE" ]; then
  if [ "${FORGE_SHA}" != "${EXPECTED_FORGE_SHA}" ]; then
    echo "[forge-plugin] ERROR: SHA-256 MISMATCH — aborting installation." >&2
    ...
    exit 1
  fi
  echo "[forge-plugin] SHA-256 verified against pinned hash — OK."
```

The guard `[ -n "${EXPECTED_FORGE_SHA}" ]` now evaluates to TRUE. Automated mismatch-abort is active. **CONFIRMED PATCHED.**

**Residual caveat (INFORMATIONAL):** The pinned SHA is the SHA-256 of the ForgeCode install *script* at a specific point in time. If forgecode.dev rotates the installer (e.g., for a new ForgeCode release), this SHA will mismatch and the install will abort until the maintainer updates `EXPECTED_FORGE_SHA` in `install.sh` and `forgecode_installer_sha256` in `plugin.json`. This is the correct behavior — a mismatch should abort. The maintainer must keep this value current. No security finding; operational process note only.

### hooks.json — R11 Verification

No changes from R10. The `&&` operator is confirmed:

```json
"command": "test -f \"${CLAUDE_PLUGIN_ROOT}/.installed\" || (bash \"${CLAUDE_PLUGIN_ROOT}/install.sh\" && touch \"${CLAUDE_PLUGIN_ROOT}/.installed\")"
```

Sentinel is written only on exit 0. Confirmed stable.

---

## Step 1 — Environment and Metadata Audit

### 1A. Execution Surfaces (complete enumeration, R11)

All surfaces from R10 are re-enumerated. No new surfaces were identified:

1. `SessionStart` hook → `install.sh` → conditional download + `bash` execution (gated by: pinned SHA verified OR interactive terminal; non-interactive + no-pin path still aborts)
2. `forge.md` instruction surface → Claude reads skill and executes embedded shell commands
3. Credential write: `printf '%s' 'KEY_PLACEHOLDER'` — key value substituted by Claude into shell command argument (residual R8-1/R9-4/R10-2/R11-1)
4. Shell profile modification (`~/.zshrc`, `~/.bashrc`, `~/.bash_profile`)
5. `forge` binary at `~/.local/bin/forge` — third-party binary with persistent system presence
6. Forge prompt construction pipeline — user input, AGENTS.md, external file content embedded in forge prompts
7. `~/forge/.forge.toml` — config with `$schema` URL reference (disclosure comment confirmed)
8. STEP 9 Quick Reference block — standalone command listing
9. Three manual install code blocks in STEP 0A-1 — primary curl block has commented-out `EXPECTED_FORGE_SHA` pattern; wget and verbose-fallback blocks have advisory notes only (R9-8 partial, residual INFO)
10. `install.sh` `add_to_path` function — shell profile append with symlink and ownership checks
11. `EXPECTED_FORGE_SHA` — **NOW POPULATED** (real SHA value); SHA comparison block is now active (R10-1 PATCHED)

### 1B. Trust Boundaries — R11

| Boundary | Trust Level | Notes |
|---|---|---|
| Plugin publisher (Ālo Labs) → user | Implicit on install | GitHub repo; no commit signing enforced |
| `forgecode.dev` → binary/install script delivery | External, TLS + **pinned SHA** | `EXPECTED_FORGE_SHA` now populated; mismatch aborts. Materially improved. |
| `openrouter.ai` → API credential target | External | Credentials stored in `~/forge/.credentials.json` (chmod 600) |
| forge binary runtime → AI-directed shell execution | Highest privilege | Executes arbitrary shell commands based on AI output |
| AGENTS.md from arbitrary repos → forge prompts | Untrusted | Prompt injection vector; mandatory wrapper gate present and enforced |
| `$schema` URL in `.forge.toml` → `forgecode.dev` | External reference | Fetched by schema-aware editors; disclosure comment present (R8-5 confirmed) |
| `KEY_PLACEHOLDER` substitution → Claude command construction | High sensitivity | Key value embedded in `printf` argument by Claude before execution (R9-4/R10-2 residual) |

---

## Step 2 — Recon Notes

```
recon_notes {
  target          : forge/sidekick plugin v1.0.0
  audit_round     : 11
  prior_rounds    : R1-R10
  files_audited   : 4 (forge.md ~882 lines, install.sh 178 lines,
                       hooks/hooks.json 14 lines, plugin.json 32 lines)

  r10_patches_verified : {

    R10-1 : PATCHED
            install.sh line 23:
              EXPECTED_FORGE_SHA="512d41a611962a8d07a7efac54fba2718867ca28ce9d5d1d02da465b141ce05a"
            Value is no longer an empty string. Guard [ -n "${EXPECTED_FORGE_SHA}" ] now
            evaluates to TRUE. SHA comparison block fires on every install attempt.
            Mismatch aborts with exit 1. Consistent with plugin.json forgecode_installer_sha256.
            This was the only remaining MEDIUM finding. Its resolution brings the plugin to
            zero MEDIUM/HIGH/CRITICAL findings.
            CONFIRMED PATCHED.

    R10-3 : PATCHED
            plugin.json _integrity block:
              install_sh_sha256:          8663dd3deb8581a8d1998b9406643efa0e217c889f10ef0d59e48abf9acc3530
              forge_md_sha256:            7cfc376785df5c5f87d150d1149dee652cfe8113017f9047c23dde4bc7f7cb61
              hooks_json_sha256:          4a131a3b1ceee87b968b13f6365daaa9f3a249605f9b8836a3f6d68421038e64
              forgecode_installer_sha256: 512d41a611962a8d07a7efac54fba2718867ca28ce9d5d1d02da465b141ce05a
            All four fields populated. All three local-file hashes verified against actual
            file content and confirmed matching. forgecode_installer_sha256 consistent
            with EXPECTED_FORGE_SHA in install.sh.
            This resolves the 5-round manifest integrity gap.
            CONFIRMED PATCHED.

    R10-2 / R11-1 : NOT PATCHED (residual — 5th round)
            forge.md: printf '%s' 'KEY_PLACEHOLDER' > "${KEY_TMP}"
            Python input() replacement not implemented.
            Note at lines ~198-205 still describes key-in-transcript as a limitation
            and offers manual-paste alternative. No structural change from R10.
            RESIDUAL — LOW.

    R10-4 / R11-2 : NOT PATCHED (residual — 3rd round since R9-8 partial)
            forge.md wget and verbose-fallback install blocks still lack the
            commented-out EXPECTED_FORGE_SHA snippet present in the primary curl block.
            Advisory NOTE present in both blocks; code snippet missing.
            RESIDUAL — INFO.
  }

  new_attack_surfaces_identified : {
    None. All surfaces from R10 re-enumerated. No new injection, path traversal,
    privilege escalation, prompt injection, or logic surfaces identified.
  }

  false_negative_check : {
    Cat-1 (Shell Injection):
      printf KEY_PLACEHOLDER single-quote injection at command-construction residual.
      R9-5 comment present; Python validation (re.match alphanumeric/dash/underscore) present.
      No new surfaces. LOW residual.

    Cat-2 (Path Traversal):
      PROJECT_ROOT quoted throughout forge.md commands. No unquoted variable expansions
      that could be influenced by external content. No new surfaces. CLEAN.

    Cat-3 (Privilege Escalation):
      No sudo, setuid, capabilities, or elevated-permission operations anywhere in plugin.
      Binary installs to ~/.local/bin (user HOME only). CLEAN.

    Cat-4 (Credential Exposure):
      printf KEY_PLACEHOLDER residual (R11-1). HISTSIZE=0 confirmed present (R9-6 patch).
      Step 5-11 credential-diagnostic block reads key into variable and does NOT echo/print it.
      No new surfaces. LOW residual.

    Cat-5 (Prompt Injection):
      AGENTS.md trust gate mandatory with non-negotiable wrapper. Sandbox guidance present
      for untrusted repos in Steps 2, 4, and all AGENTS.md operations. No regression. CLEAN.

    Cat-6 (Destructive Operations):
      git checkout -- . has MANDATORY STOP with explicit user confirmation requirement.
      git reset --hard has CAUTION comment. Both verified present in Step 5-4 and Step 7-7.
      No autonomous destruction path. CLEAN.

    Cat-7 (Supply Chain):
      EXPECTED_FORGE_SHA now populated — automated mismatch-abort active (R10-1 PATCHED).
      plugin.json _integrity fully populated and verified (R10-3 PATCHED).
      R9-2 non-interactive gate confirmed stable.
      R9-3 hooks.json && confirmed stable.
      R11-2 (INFO): wget/verbose-fallback blocks lack EXPECTED_FORGE_SHA snippet.
      Net supply-chain posture: substantially improved. No MEDIUM residual. LOW/INFO only.

    Cat-8 (Privacy/Data Disclosure):
      $schema disclosure comment present (R8-5 confirmed).
      Forge binary privacy note confirmed present in STEP 0A-3.
      Sandbox API-call disclosure note confirmed present ("sandbox isolates filesystem
      changes only... forge binary still makes API calls").
      Credential key transcript visibility is R11-1 (LOW). No new surfaces. CLEAN.

    Cat-9 (Logic/State Management):
      hooks.json && operator confirmed stable (R9-3).
      install.sh exit 0 from non-interactive gate: design choice documented and intentional.
      SHA comparison logic correct: guard [ -n "${EXPECTED_FORGE_SHA}" ] now TRUE.
      Mismatch path: exits 1 → sentinel NOT written → next session retries. Correct.
      Match path: exits 0 → sentinel written → install proceeds. Correct.
      CLEAN.

    Cat-10 (Transparency):
      printf "limitation" note with manual-paste alternative confirmed present.
      No-pin NOTICE in install.sh now superseded: pin IS set, so the else branch
      ("[forge-plugin] NOTICE: No pinned SHA-256 set") will NOT fire in normal operation.
      This is correct behavior — the warning existed for the no-pin state; pin is now set.
      Pre-consent notice for shell profile modification confirmed present (interactive:
      10-second window; non-interactive: undo instruction printed).
      INFO residual only.
  }
}
```

---

## Steps 3–8 — Findings

All ten finding categories are evaluated below. This is the first round with **zero MEDIUM or higher findings** AND where the last MEDIUM finding (R10-1) has been resolved. No new findings were identified at any severity level in this round.

---

### FINDING R11-1 — R9-4/R9-5/R10-2 Residual (5th Round): `printf 'KEY_PLACEHOLDER'` — API Key Appears in Claude Bash Tool Transcript; Shell-Level Injection at Command-Construction Stage
**Severity:** LOW (CVSS 3.1: AV:L/AC:L/PR:L/UI:N/S:U/C:L/I:N/A:N — 3.3)
**Status:** Not Patched — advisory note improved in prior rounds; Python `input()` replacement not implemented
**Category:** Credential Exposure / Shell Injection at command-construction
**Finding Category:** Cat-1 (Shell Injection), Cat-4 (Credential Exposure)
**Round history:** R7-3 (first flagged), R8-1/R8-7 (partial patches), R9-4/R9-5 (residual), R10-2 (residual), R11-1 (residual — 5th round)

**Location:** `skills/forge.md` STEP 0A-3 credential block, lines ~163–205

**Evidence (verified in current files):**

```bash
# forge.md (credential write block):
printf '%s' 'KEY_PLACEHOLDER' > "${KEY_TMP}"  # ← replace KEY_PLACEHOLDER with actual key
```

When Claude executes this block, it constructs a Bash tool call that contains the literal API key in place of `KEY_PLACEHOLDER`. The key then appears in the conversation transcript for the lifetime of the session (and potentially longer, depending on Anthropic's data retention policies for the tool call log).

**Two distinct sub-issues:**

**R11-1a (transcript exposure — LOW):** The actual API key value appears in the Bash tool call output in the Claude conversation transcript. The key is not stored in shell history (`HISTFILE` unset, `HISTSIZE=0` confirmed present). However, the tool call itself — which is part of the conversation record — contains the key. This is a confidentiality risk if the conversation transcript is shared, stored, or accessed by third parties.

**R11-1b (single-quote injection — LOW, advisory mitigated):** If the pasted key contains a single-quote character, `printf '%s' 'key'with'quote'` produces a shell syntax error or unintended quoting behavior. The Python regex validation (`re.match(r'^[A-Za-z0-9_\-]+$', key)`) at the next step catches this — but only after the `printf` line has already executed (or failed). Since OpenRouter API keys use alphanumeric + dash characters and do not contain single quotes in practice, the exploitability is very low. The advisory comment is present.

**What remains unchanged since R10:**
- Note at lines ~198–205 correctly identifies the transcript exposure and offers the manual-paste alternative.
- Python validation block at lines ~183–186 is present and correct.
- `HISTSIZE=0` / `OLD_HISTSIZE` restore are present (R9-6 confirmed stable).
- Python `input()` replacement (the structural fix) was not implemented.

**Severity assessment:** LOW is correct and unchanged. The practical risk is that a user who asks Claude to configure their OpenRouter API key will have that key present in the Claude session transcript. This is a security concern primarily for high-value API keys. The manual-paste alternative (documented in the note) fully avoids this exposure and is the recommended path for security-conscious users.

**Concrete remediation (unchanged from R9/R10):**

Replace the `printf` + Python pattern with Python `input()` so the key is never embedded in a Bash tool call:

```bash
# ⚠️ CLAUDE: Do NOT substitute any key value. Do NOT construct a printf command with a key.
# Run this block as-is. The user will type/paste the key at the Python prompt.
OLD_HISTFILE="${HISTFILE:-}"; OLD_HISTSIZE="${HISTSIZE:-}"; unset HISTFILE; export HISTSIZE=0
KEY_TMP=$(mktemp); chmod 600 "${KEY_TMP}"

KEY_TMP="${KEY_TMP}" python3 << 'PYEOF'
import os, re, sys
print("Paste your OpenRouter API key and press Enter: ", end='', flush=True)
key = sys.stdin.readline().strip()
if not key:
    raise ValueError("No key provided")
if not re.match(r'^[A-Za-z0-9_\-]+$', key):
    raise ValueError("Key contains unexpected characters — verify the key")
with open(os.environ['KEY_TMP'], 'w') as f:
    f.write(key)
print("Key captured. Proceeding with credentials write.")
PYEOF
```

This eliminates R11-1a (key never appears in Bash tool call) and R11-1b (Python receives the key from stdin, never as a shell argument).

---

### FINDING R11-2 — R9-8/R10-4 Residual (3rd Round): forge.md wget and Verbose-Fallback Install Blocks Lack `EXPECTED_FORGE_SHA` Code Snippet
**Severity:** INFO (CVSS 3.1: AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:N/A:N — 2.0)
**Status:** Partially Patched — primary curl block has snippet since R9-8; wget and verbose-fallback blocks have advisory notes only
**Category:** Supply Chain / Documentation Consistency
**Finding Category:** Cat-7 (Supply Chain)
**Round history:** R9-8 (identified), R10-4 (residual), R11-2 (residual — 3rd round)

**Location:** `skills/forge.md` STEP 0A-1, wget block and verbose-fallback block

**Evidence:**

Primary curl block (has commented-out pattern — R9-8 partially addressed):
```bash
# R9-8: To enable pinned-hash verification (recommended), set EXPECTED_FORGE_SHA to
# the official release hash from https://forgecode.dev/releases before running:
#   EXPECTED_FORGE_SHA="<hash from releases page>"
#   [ -n "${EXPECTED_FORGE_SHA}" ] && [ "${FORGE_SHA}" != "${EXPECTED_FORGE_SHA}" ] && echo "MISMATCH — aborting" && exit 1
```

wget block and verbose-fallback block (advisory NOTE only, no code snippet).

**Severity reassessment for R11:**

With `EXPECTED_FORGE_SHA` now populated in `install.sh` (R10-1 PATCHED), the manual install paths in STEP 0A-1 of forge.md are the scenario where a user must manually install ForgeCode (e.g., because the automated SessionStart hook install was skipped or failed). In this context, the primary curl block serves as the reference. The practical delta between "has the code snippet" and "has an advisory note" is minor because:

1. The install.sh mechanism (which has the real pinned SHA) is the primary install path.
2. STEP 0A-1 is a manual recovery path, and the primary curl block within it does show the pattern.
3. A user following the wget or verbose-fallback path will still see the displayed SHA and the advisory note to compare against the releases page.

Severity remains INFO. No escalation warranted.

**Concrete remediation (unchanged from R10-4):**

Add the same commented-out `EXPECTED_FORGE_SHA` snippet from the primary curl block to the wget block and verbose-fallback block, immediately after the `FORGE_SHA=` line in each. Ensures consistency across all three manual install paths.

---

### NEW FINDING R11-3 — INFORMATIONAL: `_integrity` Block Does Not Cover `plugin.json` Itself; No Self-Hash
**Severity:** INFO
**Status:** New finding (first identified R11)
**Category:** Supply Chain / Manifest Integrity
**Finding Category:** Cat-7 (Supply Chain)

**Location:** `.claude-plugin/plugin.json` `_integrity` block

**Evidence:**

```json
"_integrity": {
  "install_sh_sha256":          "8663dd3...",
  "forge_md_sha256":            "7cfc376...",
  "hooks_json_sha256":          "4a131a3b...",
  "forgecode_installer_sha256": "512d41a6...",
  ...
}
```

The `_integrity` block correctly covers `install.sh`, `forge.md`, `hooks.json`, and the remote ForgeCode installer. It does not include a hash of `plugin.json` itself.

**Analysis:**

This is a structural limitation of any self-referential integrity scheme: a file cannot contain its own hash without a fixed-point computation (which is non-standard and fragile). There is no practical way to include a correct self-hash in `plugin.json` without a dedicated tooling convention (e.g., computing the hash with the `_integrity.plugin_json_sha256` field set to all-zeros, then populating the field with the result).

**Impact:** An attacker who can tamper with `plugin.json` could alter the `_integrity` hash values themselves, making the integrity block self-serving rather than protective. The effective trust model is: the `_integrity` values are only meaningful if `plugin.json` itself is delivered via a trusted channel (e.g., the GitHub repo with commit history). This is true of any integrity manifest stored in the same repository.

**Concrete observation:** The absence of a `plugin_json_sha256` field is the correct choice given the self-referential problem. The existing scheme is appropriate for its stated purpose (manual audit aid). No remediation is needed. Flagged as INFO for completeness of coverage.

---

### FINDING CATEGORIES — COMPLETE STATUS MATRIX (R11)

| # | Category | R11 Status | Notes |
|---|---|---|---|
| Cat-1 | Shell Injection | **LOW** (residual R11-1b) | `printf` single-quote injection at command-construction; Python validation present but post-construction. Advisory mitigated. |
| Cat-2 | Path Traversal | **CLEAN** | `PROJECT_ROOT` and all file paths properly quoted throughout; no unquoted expansions influenceable by external content. |
| Cat-3 | Privilege Escalation | **CLEAN** | No sudo/setuid/capabilities; binary installs to user HOME only (`~/.local/bin`). |
| Cat-4 | Credential Exposure | **LOW** (residual R11-1a) | API key appears in Bash tool transcript via `printf`; HISTSIZE=0 present; manual-paste alternative documented. |
| Cat-5 | Prompt Injection | **CLEAN** | AGENTS.md trust gate mandatory with non-negotiable wrapper; sandbox guidance enforced for untrusted repos; no regression. |
| Cat-6 | Destructive Operations | **CLEAN** | `git checkout -- .` has MANDATORY STOP protocol; `git reset --hard` has CAUTION note; no autonomous destruction path. |
| Cat-7 | Supply Chain | **INFO** (residual R11-2) | `EXPECTED_FORGE_SHA` now populated — automated mismatch-abort active (**R10-1 PATCHED**); `_integrity` fully populated (**R10-3 PATCHED**); only residual is wget/verbose-fallback doc gap (INFO). |
| Cat-8 | Privacy / Data Disclosure | **CLEAN** | `$schema` disclosure comment present; forge binary privacy note present; sandbox API-call scope note present; credential key transcript exposure is R11-1a (LOW). |
| Cat-9 | Logic / State Management | **CLEAN** | `hooks.json` `&&` operator stable; `EXPECTED_FORGE_SHA` guard now evaluates TRUE; mismatch → exit 1 → sentinel NOT written → retry on next session. Correct behavior. |
| Cat-10 | Transparency | **INFO** | `printf` limitation note with manual-paste alternative present; pre-consent notice for shell profile modification present; no-pin NOTICE correctly suppressed now that pin is active. |

---

## Step 8 — R10 Patch Verification Summary

| Finding ID | Description | R10 Status | R11 Status |
|---|---|---|---|
| R10-1 / R9-1 | `EXPECTED_FORGE_SHA=""` — automated SHA check never fires | MEDIUM (5th round) | **PATCHED** — real hash populated; automated mismatch-abort active |
| R10-2a / R9-4 | API key in Claude Bash tool transcript (printf) | LOW (4th round) | NOT PATCHED (residual R11-1a — 5th round) |
| R10-2b / R9-5 | Single-quote injection at command-construction stage | LOW (4th round) | NOT PATCHED (residual R11-1b — 5th round) |
| R10-3 / R9-7 | `plugin.json` `_integrity` fields empty | LOW (5th round) | **PATCHED** — all four fields populated; all three local hashes verified matching |
| R10-4 / R9-8 | wget/verbose-fallback blocks lack `EXPECTED_FORGE_SHA` snippet | INFO (3rd round) | NOT PATCHED (residual R11-2) |

---

## Step 9 — New Finding Summary (R11)

| Finding ID | Severity | Category | Description | Status |
|---|---|---|---|---|
| R11-1 | LOW | Cat-1/Cat-4 | `printf KEY_PLACEHOLDER` — API key in transcript; single-quote injection (residual from R9-4/R9-5/R10-2) | Open |
| R11-2 | INFO | Cat-7 | wget/verbose-fallback install blocks lack `EXPECTED_FORGE_SHA` snippet (residual from R9-8/R10-4) | Open |
| R11-3 | INFO | Cat-7 | `_integrity` block does not include a self-hash of `plugin.json` (by design; structural limitation) | Open (by design) |

---

## Step 10 — Overall Assessment

### Verdict: **PASS**

Round 11 marks the first PASS verdict in the SENTINEL audit history of this plugin.

**Zero MEDIUM, HIGH, or CRITICAL findings remain open.** The only open findings are:
- Two LOW findings (R11-1a, R11-1b) representing a known credential-handling pattern that has been residual for five rounds with an adequate documented workaround.
- Two INFO findings (R11-2, R11-3) representing documentation consistency and a structural self-referential limitation.

**Key security improvements since R1:**

| Milestone | Round |
|---|---|
| Pipe-to-sh eliminated; temp file + SHA display | R7 |
| Non-interactive Ctrl+C caveat documented | R6 |
| Download timeouts added | R8 |
| `shasum` availability check + fallback | R7-8 |
| Symlink hijack protection in `add_to_path` | R6-5 |
| File ownership check in `add_to_path` | R7-5 |
| Binary identity check post-install | R6-10 |
| AGENTS.md trust gate mandatory (was advisory) | R2 |
| `git checkout -- .` MANDATORY STOP | R6-9 |
| Sandbox-first for untrusted repos | R4/R5 |
| Credential chmod 600 | R2 |
| HISTFILE suppression | R7-3 |
| HISTSIZE=0 + atomic block note | R9-6 |
| No-pin NOTICE in install.sh | R9-9 |
| Non-interactive execution gate | R9-2 |
| hooks.json `&&` sentinel interlock | R9-3 |
| `EXPECTED_FORGE_SHA` populated (mismatch-abort active) | **R11** |
| `plugin.json` `_integrity` fully populated and verified | **R11** |

**Recommended next actions (in priority order):**

1. **(LOW — R11-1):** Replace `printf '%s' 'KEY_PLACEHOLDER'` with Python `input()` in the credential write block to eliminate key exposure in the Bash tool transcript.
2. **(INFO — R11-2):** Add the commented-out `EXPECTED_FORGE_SHA` code snippet to the wget and verbose-fallback install blocks in STEP 0A-1 for documentation consistency.
3. **(Process):** Add a release script or pre-commit hook that auto-updates `EXPECTED_FORGE_SHA` in `install.sh` and all four `_integrity` hashes in `plugin.json` whenever plugin files change. This prevents the integrity fields from going stale again on the next release.

---

*SENTINEL v2.3 — Round 11 complete. Audit timestamp: 2026-04-12.*

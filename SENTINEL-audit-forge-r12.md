# SENTINEL v2.3 — Security Audit Report
## Target: forge skill (sidekick plugin v1.0.0)
## Round: 12 (R11 Patch Verification + Full New-Surface Audit)
## Date: 2026-04-12
## Auditor: SENTINEL v2.3 (dual-mode: Defensive + Adversarial)
## Prior Rounds: R1–R11

---

## Executive Summary

Round 12 is the **second consecutive PASS verdict** in the SENTINEL audit history of this plugin.

**The two-consecutive-PASS stopping criterion has been met.**

Two findings that were open at R11 have been patched since that round:

- **R11-2 PATCHED** — The wget block and verbose-fallback block in `skills/forge.md` STEP 0A-1 now both contain active, populated `EXPECTED_FORGE_SHA` verification code (pinned hash `512d41a6...` with abort-on-mismatch). This resolves the three-round INFO residual (R9-8 partial → R10-4 → R11-2). The fix correctly mirrors what the primary curl block already had as commented guidance, and the wget/verbose-fallback blocks have gone further — the hash and comparison logic are now live executable code, not just comments.

- **`_integrity` hashes in `plugin.json` updated** — The `forge_md_sha256` field was updated from the R11 value (`7cfc376...`) to the new value (`56333d2a...`) reflecting the forge.md changes made in this release cycle. All three local-file hashes in `plugin.json._integrity` now match actual file content on disk. This is correct release hygiene. (Not a finding; noted as a positive verification.)

**One finding from R11 remains open:**

- **R12-1 (LOW, residual — 6th round):** `printf '%s' 'KEY_PLACEHOLDER'` in the credential write block of `forge.md` — the API key still appears in Claude's Bash tool transcript when Claude performs credential setup. Python `input()` remediation was not implemented. First flagged R7-3.

**New finding identified in this round:**

- **R12-2 (INFO, new):** The **primary curl block** in STEP 0A-1 of `forge.md` still uses only a **commented-out** `EXPECTED_FORGE_SHA` template (with a placeholder `<hash from releases page>`), while the wget and verbose-fallback blocks now use **active**, populated verification code. This asymmetry means the most commonly used manual install path (curl) does not enforce hash verification via active code in the skill — it relies on Claude instruction-following and user vigilance, whereas the two alternative paths now abort automatically on mismatch.

**No MEDIUM, HIGH, or CRITICAL findings.** The plugin's overall security posture continues to meet the SENTINEL PASS threshold.

---

## Step 0 — Decode Manifest / File Inventory

### SHA-256 Verification (R12, computed from actual files)

```
shasum -a 256 install.sh skills/forge.md hooks/hooks.json .claude-plugin/plugin.json
```

| File | Actual SHA-256 (R12) | R11 Recorded SHA-256 | Delta |
|---|---|---|---|
| `install.sh` | `8663dd3deb8581a8d1998b9406643efa0e217c889f10ef0d59e48abf9acc3530` | `8663dd3deb8581a8d1998b9406643efa0e217c889f10ef0d59e48abf9acc3530` | **unchanged** |
| `skills/forge.md` | `56333d2a91500f65c26d81e74b47a13278e3d8b87294b430de43ff85e3414935` | `7cfc376785df5c5f87d150d1149dee652cfe8113017f9047c23dde4bc7f7cb61` | **CHANGED** |
| `hooks/hooks.json` | `4a131a3b1ceee87b968b13f6365daaa9f3a249605f9b8836a3f6d68421038e64` | `4a131a3b1ceee87b968b13f6365daaa9f3a249605f9b8836a3f6d68421038e64` | unchanged |
| `.claude-plugin/plugin.json` | `41a6b1f5622e18b7d4318ac78237f09e5666cd2171852849de094a92b5d5f6bb` | `53bacda66136214c58c259b90dc53b424aea7fcbe501eaa99bbb103210491b27` | **CHANGED** |

**Changes since R11 are explained by:**
- `skills/forge.md` changed: `EXPECTED_FORGE_SHA` active code added to wget and verbose-fallback blocks (R11-2 patch). This changed the forge.md hash.
- `.claude-plugin/plugin.json` changed: `_integrity.forge_md_sha256` updated to reflect the new forge.md hash. This changed the plugin.json hash.
- `install.sh` unchanged: hash matches R11. Confirmed stable.
- `hooks/hooks.json` unchanged: hash matches R11 and every prior round. Confirmed stable.

### `plugin.json` `_integrity` Verification — R12

All four fields in the `_integrity` block were verified against actual file content:

```
Field                        Claimed (plugin.json)                                    Actual (computed)                                        Result
install_sh_sha256:           8663dd3deb8581a8d1998b9406643efa0e217c889f10ef0d59e48abf9acc3530  8663dd3deb8581a8d1998b9406643efa0e217c889f10ef0d59e48abf9acc3530  MATCH
forge_md_sha256:             56333d2a91500f65c26d81e74b47a13278e3d8b87294b430de43ff85e3414935  56333d2a91500f65c26d81e74b47a13278e3d8b87294b430de43ff85e3414935  MATCH
hooks_json_sha256:           4a131a3b1ceee87b968b13f6365daaa9f3a249605f9b8836a3f6d68421038e64  4a131a3b1ceee87b968b13f6365daaa9f3a249605f9b8836a3f6d68421038e64  MATCH
forgecode_installer_sha256:  512d41a611962a8d07a7efac54fba2718867ca28ce9d5d1d02da465b141ce05a  (remote — not independently fetchable; consistent with EXPECTED_FORGE_SHA in install.sh)  CONSISTENT
```

**All four `_integrity` fields are internally consistent and match actual file content.** The `forge_md_sha256` was correctly updated to the new hash when forge.md was patched. This demonstrates functioning release hygiene: the manifest is kept current with file changes.

**Cross-file consistency check:** `plugin.json._integrity.forgecode_installer_sha256` (`512d41a6...`) matches `EXPECTED_FORGE_SHA` in `install.sh` (`512d41a6...`). Both files agree on the expected ForgeCode installer hash. Confirmed consistent across the chain.

---

## Step 1 — Environment and Metadata Audit

### 1A. Execution Surfaces (complete re-enumeration, R12)

No new execution surfaces identified. All surfaces from R11 are present and unchanged in structure:

1. `SessionStart` hook → `install.sh` → conditional download + `bash` execution (gated by: pinned SHA verified OR interactive terminal; non-interactive + no-pin path aborts and exits 0 writing sentinel to avoid retry-on-every-session loop)
2. `forge.md` instruction surface → Claude reads skill and executes embedded shell commands
3. Credential write: `printf '%s' 'KEY_PLACEHOLDER'` → key value substituted by Claude into shell command argument (residual R12-1)
4. Shell profile modification (`~/.zshrc`, `~/.bashrc`, `~/.bash_profile`) with symlink and ownership guards
5. `forge` binary at `~/.local/bin/forge` — third-party binary with persistent system presence
6. Forge prompt construction pipeline — user input, AGENTS.md, external file content embedded in forge prompts
7. `~/forge/.forge.toml` — config with `$schema` URL reference (disclosure comment confirmed)
8. STEP 9 Quick Reference block — standalone command listing
9. Three manual install code blocks in STEP 0A-1:
   - Primary curl block: commented-out `EXPECTED_FORGE_SHA` template only (no active enforcement)
   - wget block: active `EXPECTED_FORGE_SHA` pinned hash with abort-on-mismatch (**R11-2 PATCHED**)
   - Verbose-fallback block: active `EXPECTED_FORGE_SHA` pinned hash with abort-on-mismatch (**R11-2 PATCHED**)
10. `install.sh` `add_to_path` function — shell profile append with symlink and ownership checks
11. `EXPECTED_FORGE_SHA` in `install.sh` — populated, active; mismatch-abort confirmed (R10-1 PATCHED, stable)

### 1B. Trust Boundaries — R12

| Boundary | Trust Level | Notes |
|---|---|---|
| Plugin publisher (Ālo Labs) → user | Implicit on install | GitHub repo; no commit signing enforced |
| `forgecode.dev` → binary/install script delivery | External, TLS + **pinned SHA** | `EXPECTED_FORGE_SHA` populated; automated mismatch-abort active in install.sh and two of three forge.md manual install paths |
| `openrouter.ai` → API credential target | External | Credentials stored in `~/forge/.credentials.json` (chmod 600) |
| forge binary runtime → AI-directed shell execution | Highest privilege | Executes arbitrary shell commands based on AI output |
| AGENTS.md from arbitrary repos → forge prompts | Untrusted | Prompt injection vector; mandatory wrapper gate enforced |
| `$schema` URL in `.forge.toml` → `forgecode.dev` | External reference | Fetched by schema-aware editors; disclosure comment present |
| `KEY_PLACEHOLDER` substitution → Claude command construction | High sensitivity | Key value embedded in `printf` argument by Claude before execution (R12-1 residual) |

---

## Step 2 — Recon Notes

```
recon_notes {
  target          : forge/sidekick plugin v1.0.0
  audit_round     : 12
  prior_rounds    : R1-R11
  files_audited   : 4 (forge.md ~891 lines, install.sh 178 lines,
                       hooks/hooks.json 14 lines, plugin.json 32 lines)

  r11_patches_verified : {

    R11-2 : PATCHED
            forge.md STEP 0A-1, wget block (lines ~95-98):
              EXPECTED_FORGE_SHA="512d41a611962a8d07a7efac54fba2718867ca28ce9d5d1d02da465b141ce05a"
              if [ -n "${EXPECTED_FORGE_SHA}" ] && [ "${FORGE_SHA}" != "${EXPECTED_FORGE_SHA}" ]; then
                echo "SHA-256 MISMATCH — aborting. Expected: ${EXPECTED_FORGE_SHA}"; exit 1
              fi
            forge.md STEP 0A-1, verbose-fallback block (lines ~118-121):
              EXPECTED_FORGE_SHA="512d41a611962a8d07a7efac54fba2718867ca28ce9d5d1d02da465b141ce05a"
              if [ -n "${EXPECTED_FORGE_SHA}" ] && [ "${FORGE_SHA}" != "${EXPECTED_FORGE_SHA}" ]; then
                echo "SHA-256 MISMATCH — aborting. Expected: ${EXPECTED_FORGE_SHA}"; exit 1
              fi
            Both blocks now contain live, executable hash verification.
            Hash is the same pinned value as install.sh EXPECTED_FORGE_SHA and
            plugin.json forgecode_installer_sha256.
            CONFIRMED PATCHED.
            NOTE: This resolves the INFO finding but introduces an asymmetry — see R12-2.

    R11-1 / R12-1 : NOT PATCHED (residual — 6th round)
            forge.md: printf '%s' 'KEY_PLACEHOLDER' > "${KEY_TMP}"
            Python input() replacement not implemented.
            Advisory note at lines ~206-209 confirmed present and unchanged.
            RESIDUAL — LOW.

    R11-3 : OPEN (by design)
            plugin.json _integrity does not include a self-hash of plugin.json.
            This is the correct design given the self-referential problem.
            No remediation needed. Structural limitation acknowledged.
            OPEN BY DESIGN — INFO.
  }

  new_attack_surfaces_identified : {
    R12-2 (INFO): Primary curl block in STEP 0A-1 uses commented-out EXPECTED_FORGE_SHA
    template while wget and verbose-fallback blocks now have active verification code.
    This creates an inconsistency: the most commonly used manual install path (curl) does
    not abort automatically on hash mismatch from the skill's code snippets. See R12-2.
  }

  false_negative_check : {
    Cat-1 (Shell Injection):
      printf KEY_PLACEHOLDER single-quote injection at command-construction residual (R12-1).
      R9-5 comment present; Python validation (re.match alphanumeric/dash/underscore) present.
      No new injection surfaces. LOW residual.

    Cat-2 (Path Traversal):
      PROJECT_ROOT quoted throughout. FORGE_INSTALL_TMP quoted in install.sh trap and
      all expansions. No unquoted variable expansions influenceable by external content.
      CLEAN.

    Cat-3 (Privilege Escalation):
      No sudo, setuid, capabilities, or elevated-permission operations anywhere in plugin.
      Binary installs to ~/.local/bin (user HOME only). No new surfaces. CLEAN.

    Cat-4 (Credential Exposure):
      printf KEY_PLACEHOLDER residual (R12-1). HISTSIZE=0 confirmed present.
      Step 5-11 credential-diagnostic block reads key into variable; does NOT echo/print it.
      curl command uses the variable directly: -H "Authorization: Bearer ${OPENROUTER_KEY}".
      Key is in shell memory only; unset after use. No new surfaces. LOW residual (R12-1).

    Cat-5 (Prompt Injection):
      AGENTS.md trust gate mandatory with non-negotiable wrapper. Sandbox guidance present
      for untrusted repos in Steps 2, 4, and all AGENTS.md operations. No regression. CLEAN.

    Cat-6 (Destructive Operations):
      git checkout -- . MANDATORY STOP protocol confirmed present (STEP 5-4).
      git reset --hard CAUTION note confirmed present (STEP 7-7).
      Quick Reference STEP 9 also includes the MANDATORY STOP reminder inline.
      No autonomous destruction path anywhere in the skill. CLEAN.

    Cat-7 (Supply Chain):
      install.sh EXPECTED_FORGE_SHA populated — automated mismatch-abort active (R10-1, stable).
      forge.md wget and verbose-fallback blocks now have active verification (R11-2 PATCHED).
      forge.md primary curl block still uses commented-out template only (R12-2 INFO).
      plugin.json _integrity fully populated and verified against actual files (R10-3, updated R12).
      R11-3 self-hash structural limitation remains INFO by design.
      Net supply-chain posture: very strong. One INFO asymmetry (R12-2). No MEDIUM.

    Cat-8 (Privacy/Data Disclosure):
      $schema disclosure comment in forge.md STEP 0A-3 confirmed present.
      Forge binary privacy note confirmed present in STEP 0A-3.
      Sandbox API-call scope clarification confirmed present in STEP 4 sandbox note.
      Credential key transcript visibility is R12-1 (LOW). No new surfaces. CLEAN.

    Cat-9 (Logic/State Management):
      hooks.json && operator confirmed stable (R9-3, unchanged through R12).
      install.sh exit 0 from non-interactive gate: design choice documented and intentional.
      SHA comparison logic correct in install.sh: guard [ -n "${EXPECTED_FORGE_SHA}" ] TRUE.
      Mismatch → exit 1 → sentinel NOT written → next session retries. Correct.
      Match → exit 0 → sentinel written → install proceeds. Correct.
      wget and verbose-fallback blocks use exit 1 on mismatch — correct behavior in a
      subshell context (Claude Bash tool). Primary curl block uses sleep 5 then runs
      without abort, consistent with its commented-only guidance.
      CLEAN.

    Cat-10 (Transparency):
      printf "limitation" note with manual-paste alternative confirmed present.
      Pre-consent notice for shell profile modification confirmed present.
      No-pin NOTICE in install.sh correctly suppressed (pin is set; else branch not reached).
      INFO residual only.
  }
}
```

---

## Steps 3–8 — Findings

---

### FINDING R12-1 — R9-4/R9-5/R10-2/R11-1 Residual (6th Round): `printf 'KEY_PLACEHOLDER'` — API Key Appears in Claude Bash Tool Transcript; Shell-Level Injection at Command-Construction Stage

**Severity:** LOW (CVSS 3.1: AV:L/AC:L/PR:L/UI:N/S:U/C:L/I:N/A:N — 3.3)
**Status:** Not Patched — advisory note improved in prior rounds; Python `input()` replacement not implemented
**Category:** Credential Exposure / Shell Injection at command-construction
**Finding Categories:** Cat-1 (Shell Injection), Cat-4 (Credential Exposure)
**Round history:** R7-3 (first flagged), R8-1/R8-7 (partial patches), R9-4/R9-5 (residual), R10-2 (residual), R11-1 (residual), R12-1 (residual — 6th round)

**Location:** `skills/forge.md` STEP 0A-3 credential block, line ~181

**Evidence (verified in current files):**

```bash
# forge.md STEP 0A-3 (credential write block), line 181:
printf '%s' 'KEY_PLACEHOLDER' > "${KEY_TMP}"  # ← replace KEY_PLACEHOLDER with actual key
```

When Claude executes this block, it substitutes the user's actual API key for `KEY_PLACEHOLDER` before issuing the Bash tool call. The literal API key therefore appears in the Claude conversation transcript (the tool call payload) for the duration of the session and potentially longer depending on Anthropic data retention.

**Sub-issues (unchanged from R11-1):**

**R12-1a (transcript exposure — LOW):** The API key value appears in the Bash tool call argument list in Claude's conversation transcript. Key is not stored in shell history (`HISTFILE` unset, `HISTSIZE=0` confirmed present at line ~173-174), but the conversation log contains it. Risk is proportional to transcript sensitivity (shared sessions, support workflows, screen capture).

**R12-1b (single-quote injection — LOW, advisory mitigated):** If the key contains a single-quote, `printf '%s' 'key'with'quote'` produces a shell syntax error. Python regex validation (`re.match(r'^[A-Za-z0-9_\-]+$', key)`) catches this after the fact. OpenRouter keys do not use single quotes in practice; exploitability is very low.

**What remains unchanged since R11-1:**
- Advisory note at lines ~206-209 correctly describes the limitation and offers the manual-paste alternative.
- Python validation block (`re.match`) at lines ~184-193 is present and correct.
- `HISTSIZE=0` / restore logic is present and correct.
- Python `input()` replacement (structural fix) has not been implemented.

**Severity assessment:** LOW remains correct. The practical risk is primarily the conversation transcript. The manual-paste alternative (documented and clearly described) fully avoids the exposure and is the recommended path for security-conscious users.

**Concrete remediation (unchanged from R9/R10/R11):**

Replace the `printf` + Python pattern with Python `input()` so the key is never placed in a Bash tool call:

```bash
# ⚠️ CLAUDE: Do NOT substitute any key value. Run this block as-is.
# The user will type/paste the key directly at the Python prompt.
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

This eliminates R12-1a (key never appears in Bash tool call) and R12-1b (Python receives key from stdin, never as a shell argument).

---

### FINDING R12-2 — New (R12): Asymmetry in STEP 0A-1 Install Blocks — Primary Curl Block Uses Commented-Out `EXPECTED_FORGE_SHA` Template While wget and Verbose-Fallback Blocks Have Active Enforcement

**Severity:** INFO (CVSS 3.1: AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:N/A:N — 2.0)
**Status:** New finding (first identified R12)
**Category:** Supply Chain / Documentation Consistency
**Finding Category:** Cat-7 (Supply Chain)

**Location:** `skills/forge.md` STEP 0A-1, primary curl block, lines ~73-76

**Evidence:**

Primary curl block (lines 73-76 — commented-out template only):
```bash
# R9-8: To enable pinned-hash verification (recommended), set EXPECTED_FORGE_SHA to
# the official release hash from https://forgecode.dev/releases before running:
#   EXPECTED_FORGE_SHA="<hash from releases page>"
#   [ -n "${EXPECTED_FORGE_SHA}" ] && [ "${FORGE_SHA}" != "${EXPECTED_FORGE_SHA}" ] && echo "MISMATCH — aborting" && exit 1
```

wget block (lines 94-98 — active, populated enforcement — R11-2 PATCHED):
```bash
# Pinned-hash verification — update hash when upgrading ForgeCode (R10-4/R11-2):
EXPECTED_FORGE_SHA="512d41a611962a8d07a7efac54fba2718867ca28ce9d5d1d02da465b141ce05a"
if [ -n "${EXPECTED_FORGE_SHA}" ] && [ "${FORGE_SHA}" != "${EXPECTED_FORGE_SHA}" ]; then
  echo "SHA-256 MISMATCH — aborting. Expected: ${EXPECTED_FORGE_SHA}"; exit 1
fi
```

Verbose-fallback block (lines 117-121 — active, populated enforcement — R11-2 PATCHED):
```bash
# Pinned-hash verification — update hash when upgrading ForgeCode (R10-4/R11-2):
EXPECTED_FORGE_SHA="512d41a611962a8d07a7efac54fba2718867ca28ce9d5d1d02da465b141ce05a"
if [ -n "${EXPECTED_FORGE_SHA}" ] && [ "${FORGE_SHA}" != "${EXPECTED_FORGE_SHA}" ]; then
  echo "SHA-256 MISMATCH — aborting. Expected: ${EXPECTED_FORGE_SHA}"; exit 1
fi
```

**Analysis:**

The R11-2 patch correctly activated enforcement in the wget and verbose-fallback blocks. However, it left the primary curl block — the most commonly executed manual install path — in its pre-patch state: a `# commented-out` template with `<hash from releases page>` as a placeholder.

This creates an asymmetry:
- A user following the primary curl path gets display-only SHA verification (manual comparison required; no automatic abort).
- A user following the wget or verbose-fallback path gets automated hash enforcement (abort on mismatch).

**Exploitability assessment:** The practical risk is low because:
1. `install.sh` (the primary automated path) has full mismatch-abort active.
2. The primary curl block is a manual recovery path only (STEP 0A-1 is reached only when the automated install failed or was skipped).
3. The displayed SHA is still shown and the advisory note instructs comparison against the releases page.
4. Users exercising the manual install path are likely technically aware enough to verify the hash.

**Severity:** INFO. No escalation warranted. The risk is documentation inconsistency rather than a genuine security gap.

**Concrete remediation:**

Replace the commented-out template in the primary curl block (after line 66 / the `FORGE_SHA=` line) with the same active pattern used in the wget and verbose-fallback blocks:

```bash
# Pinned-hash verification — update hash when upgrading ForgeCode:
EXPECTED_FORGE_SHA="512d41a611962a8d07a7efac54fba2718867ca28ce9d5d1d02da465b141ce05a"
if [ -n "${EXPECTED_FORGE_SHA}" ] && [ "${FORGE_SHA}" != "${EXPECTED_FORGE_SHA}" ]; then
  echo "SHA-256 MISMATCH — aborting. Expected: ${EXPECTED_FORGE_SHA}"; exit 1
fi
```

This makes all three manual install blocks consistent and eliminates the asymmetry introduced by the R11-2 patch.

---

### FINDING R11-3 — Residual INFO (3rd Round by Design): `_integrity` Block Does Not Cover `plugin.json` Itself; No Self-Hash

**Severity:** INFO
**Status:** Open (by design) — structural limitation; no remediation available without fixed-point computation tooling
**Category:** Supply Chain / Manifest Integrity
**Finding Category:** Cat-7 (Supply Chain)

**Location:** `.claude-plugin/plugin.json` `_integrity` block

**Evidence:**

The `_integrity` block covers `install.sh`, `forge.md`, `hooks.json`, and the remote ForgeCode installer. It does not and cannot contain a correct self-hash of `plugin.json`.

**Analysis (unchanged from R11-3):**

This is a structural limitation of any self-referential integrity scheme. Including a correct self-hash requires a fixed-point computation (the file's hash must be known before the file is written). The existing scheme is appropriate for its stated purpose: a manual audit aid. The `_integrity` values are meaningful only if `plugin.json` is delivered via a trusted channel (e.g., GitHub repo with commit history), which is true for any integrity manifest stored in the same repository.

**Update for R12:** The maintainer correctly updated `forge_md_sha256` in `plugin.json` after patching `forge.md`. This demonstrates that the integrity manifest is being kept current. No regression.

**No remediation needed.** Flagged INFO for completeness.

---

## Step 8 — R11 Patch Verification Summary

| Finding ID | Description | R11 Status | R12 Status |
|---|---|---|---|
| R11-1 / R12-1 | `printf KEY_PLACEHOLDER` — API key in Bash transcript; single-quote injection | LOW (5th round) | NOT PATCHED (residual R12-1 — 6th round) |
| R11-2 | wget/verbose-fallback blocks lack `EXPECTED_FORGE_SHA` active code | INFO (3rd round) | **PATCHED** — active pinned-hash enforcement in both blocks |
| R11-3 | `_integrity` block does not include self-hash of `plugin.json` | INFO (by design) | OPEN BY DESIGN — unchanged |

---

## Step 9 — Finding Status Matrix (R12)

### All Ten Finding Categories

| # | Category | R12 Status | Notes |
|---|---|---|---|
| Cat-1 | Shell Injection | **LOW** (residual R12-1b) | `printf` single-quote injection at command-construction; Python validation present but post-construction. Advisory mitigated. |
| Cat-2 | Path Traversal | **CLEAN** | `PROJECT_ROOT`, `FORGE_INSTALL_TMP`, and all file paths properly quoted throughout; no unquoted expansions influenceable by external content. |
| Cat-3 | Privilege Escalation | **CLEAN** | No sudo/setuid/capabilities; binary installs to user HOME only (`~/.local/bin`). |
| Cat-4 | Credential Exposure | **LOW** (residual R12-1a) | API key appears in Bash tool transcript via `printf`; `HISTSIZE=0` present; manual-paste alternative documented. |
| Cat-5 | Prompt Injection | **CLEAN** | AGENTS.md trust gate mandatory with non-negotiable wrapper; sandbox guidance enforced for untrusted repos (Steps 2, 4, AGENTS.md operations). No regression. |
| Cat-6 | Destructive Operations | **CLEAN** | `git checkout -- .` has MANDATORY STOP protocol in STEP 5-4 and Quick Reference STEP 9; `git reset --hard` has CAUTION note in STEP 7-7; no autonomous destruction path. |
| Cat-7 | Supply Chain | **INFO** (residual R12-2) | `install.sh` mismatch-abort active (R10-1, stable); wget/verbose-fallback blocks now have active enforcement (R11-2 PATCHED); primary curl block still commented-only (R12-2 INFO); `_integrity` updated and verified (R12 release hygiene confirmed). |
| Cat-8 | Privacy / Data Disclosure | **CLEAN** | `$schema` disclosure comment present; forge binary privacy note present; sandbox API-call scope note present; credential key transcript exposure is R12-1a (LOW). |
| Cat-9 | Logic / State Management | **CLEAN** | `hooks.json` `&&` operator stable; `EXPECTED_FORGE_SHA` guard evaluates TRUE; mismatch → exit 1 → sentinel NOT written → retry on next session (correct); match → exit 0 → sentinel written (correct). |
| Cat-10 | Transparency | **INFO** | `printf` limitation note with manual-paste alternative present; pre-consent notice for shell profile modification present; no-pin NOTICE correctly suppressed (pin is active). |

### New and Residual Findings (R12)

| Finding ID | Severity | Category | Description | Status |
|---|---|---|---|---|
| R12-1 | LOW | Cat-1/Cat-4 | `printf KEY_PLACEHOLDER` — API key in transcript; single-quote injection (residual from R9-4/R9-5/R10-2/R11-1) | Open |
| R12-2 | INFO | Cat-7 | Primary curl block in STEP 0A-1 uses commented-out `EXPECTED_FORGE_SHA` template; wget/verbose-fallback have active enforcement (asymmetry introduced by R11-2 patch) | Open |
| R11-3 | INFO | Cat-7 | `_integrity` block does not include self-hash of `plugin.json` (by design; structural limitation) | Open by design |

---

## Step 10 — Overall Assessment

### Verdict: **PASS**

Round 12 is the **second consecutive PASS** in the SENTINEL audit history of this plugin.

**The two-consecutive-PASS stopping criterion has been met.**

**Zero MEDIUM, HIGH, or CRITICAL findings remain open.** The only open findings are:
- One LOW finding (R12-1, residual — 6th round) representing a known credential-handling pattern with an adequate documented workaround and no practical exploitation path beyond transcript exposure.
- Two INFO findings (R12-2 and R11-3) representing a documentation asymmetry introduced by the R11-2 patch, and a structural self-referential integrity limitation.

### Security Posture Summary

The plugin has undergone a thorough 12-round adversarial review resulting in a substantially hardened security posture:

| Milestone | Round Achieved |
|---|---|
| Pipe-to-sh eliminated; temp file + SHA display | R7 |
| Non-interactive Ctrl+C caveat documented | R6 |
| Download timeouts added | R8 |
| `shasum` availability check + sha256sum fallback | R7-8 |
| Symlink hijack protection in `add_to_path` | R6-5 |
| File ownership check in `add_to_path` | R7-5 |
| Binary identity check post-install | R6-10 |
| AGENTS.md trust gate mandatory (was advisory) | R2 |
| `git checkout -- .` MANDATORY STOP | R6-9 |
| Sandbox-first guidance for untrusted repos | R4/R5 |
| Credential chmod 600 | R2 |
| HISTFILE suppression | R7-3 |
| HISTSIZE=0 + atomic block note | R9-6 |
| No-pin NOTICE in install.sh | R9-9 |
| Non-interactive execution gate | R9-2 |
| hooks.json `&&` sentinel interlock | R9-3 |
| `EXPECTED_FORGE_SHA` populated (mismatch-abort active) | R10/R11 |
| `plugin.json` `_integrity` fully populated | R11 |
| wget/verbose-fallback blocks have active hash enforcement | **R12** |
| `_integrity.forge_md_sha256` updated to match patched forge.md | **R12** |

### Recommended Next Actions (priority order)

1. **(LOW — R12-1, 6th round):** Replace `printf '%s' 'KEY_PLACEHOLDER'` with Python `input()` in the credential write block to eliminate key exposure in the Bash tool transcript. Remediation code provided in the finding above.

2. **(INFO — R12-2):** Promote the primary curl block in STEP 0A-1 from commented-out template to active `EXPECTED_FORGE_SHA` enforcement code, matching the pattern now used in the wget and verbose-fallback blocks. This makes all three manual install paths consistent.

3. **(Process):** Maintain the release script / pre-commit hook discipline for updating `EXPECTED_FORGE_SHA` in `install.sh` and all `_integrity` hashes in `plugin.json` on each release. The R12 release correctly updated `forge_md_sha256` when patching `forge.md` — this pattern should be formalized.

---

*SENTINEL v2.3 — Round 12 complete. Audit timestamp: 2026-04-12.*
*Two consecutive PASS verdicts achieved (R11, R12). Stopping criterion met.*

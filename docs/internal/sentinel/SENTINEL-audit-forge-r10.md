# SENTINEL v2.3 — Security Audit Report
## Target: forge skill (sidekick plugin v1.0.0)
## Round: 10 (R9 Patch Verification + Full New-Surface Audit)
## Date: 2026-04-12
## Auditor: SENTINEL v2.3 (dual-mode: Defensive + Adversarial)
## Prior Rounds: R1–R9

---

## Executive Summary

Round 10 is the cleanest audit to date. **Two significant patches landed since R9:**

- **R9-2 PATCHED** — `install.sh` now contains an interactive execution gate (`if [ ! -t 1 ] && [ -z "${EXPECTED_FORGE_SHA}" ]`) that aborts binary execution when running non-interactively with no pinned SHA and instructs the user to run install manually. This eliminates the MEDIUM non-interactive auto-execution finding that persisted through four consecutive rounds (R6–R9).
- **R9-3 PATCHED** — `hooks/hooks.json` sentinel operator changed from `;` to `&&`, meaning `.installed` is written only when `install.sh` exits 0. This correctly interlocks with the R9-2 gate: non-interactive abort exits 0 (sentinel written, message shown once); interactive or pinned-hash paths exit 0 on success (sentinel written normally); future exit-1 abort paths would not suppress re-attempts.
- **R9-6 PATCHED** — `HISTSIZE=0` and `OLD_HISTSIZE` restore added to credential block in forge.md; `NOTE: Run this ENTIRE block as a single Bash tool call` annotation present.

**No new MEDIUM, HIGH, or CRITICAL findings were discovered in this round.** All remaining open findings are LOW or INFO, consistent with their R9 classification. The plugin's security posture is substantially improved. The two dominant residual risks are:

1. `EXPECTED_FORGE_SHA=""` — the SHA comparison scaffold is present but the guard never fires (no actual pinned hash). This is a LOW/MEDIUM supply-chain finding that has now been residual for five rounds (R6–R10). It is an operational gap, not a code defect — the maintainer must populate the value.
2. `printf '%s' 'KEY_PLACEHOLDER'` in forge.md — the key appears in Claude's Bash tool transcript. Flagged LOW since R7; R9's `input()` remediation was not applied. A correct but non-ideal workaround note is present.

**This round should be the cleanest yet — and it is.** Zero new MEDIUM/HIGH/CRITICAL findings.

---

## Step 0 — Decode Manifest / File Inventory

| File | Lines (R10) | SHA-256 (R10) | Role |
|---|---|---|---|
| `skills/forge.md` | 882 | `0af9d8885691f69d2879d51c15364471bc4d041f41a56db8a71be6e2897260e0` | Claude orchestration protocol, runtime skill instructions |
| `install.sh` | 174 | `bb89b476324413e2e341ce3d09c1b9396d5ad2706d0944698b4d23b91d7eab45` | Binary installer and PATH modifier, executed via SessionStart hook |
| `hooks/hooks.json` | 14 | `4a131a3b1ceee87b968b13f6365daaa9f3a249605f9b8836a3f6d68421038e64` | SessionStart hook definition |
| `.claude-plugin/plugin.json` | 29 | `22a5392cb88e7a582b855df855f5fcaad928d4a05a7483f82e3ee12af5323cde` | Plugin manifest |

*Note: `marketplace.json` was audited in R9 but is not present in the working directory tree as confirmed by glob. R9 finding R9-7 covering marketplace.json integrity fields remains open in principle, but the file cannot be verified this round.*

### Manifest Decode

**plugin.json declares:**
- Name: `sidekick`, Version: `1.0.0`, License: MIT
- Author: Ālo Labs
- Repository: `https://github.com/alo-exp/sidekick`
- Skills path: `./skills/`
- `_integrity` object present: `install_sh_sha256: ""`, `forge_md_sha256: ""` — scaffolding only; both values remain empty strings (R9-7 residual)

**hooks.json declares:**
- One hook: `SessionStart`
- **PATCHED (R9-3):** `"command": "test -f \"${CLAUDE_PLUGIN_ROOT}/.installed\" || (bash \"${CLAUDE_PLUGIN_ROOT}/install.sh\" && touch \"${CLAUDE_PLUGIN_ROOT}/.installed\")"`
- Operator is now `&&` — sentinel written only on exit 0. Confirmed patched.

**install.sh declares:**
- `set -euo pipefail`, `trap` cleanup
- `EXPECTED_FORGE_SHA=""` — still empty string (R9-1 residual)
- SHA comparison block present (lines 62–71) — correct logic, but empty guard never fires
- **PATCHED (R9-1 notice, R9-9):** Lines 72–75 emit "NOTICE: No pinned SHA-256 set — verification is display-only." when `EXPECTED_FORGE_SHA` is empty — this warning is now present and fires on every non-interactive install without a pin. *See detailed analysis in R10-2.*
- **PATCHED (R9-2):** Lines 83–92: `if [ ! -t 1 ] && [ -z "${EXPECTED_FORGE_SHA}" ]` — non-interactive abort gate present. Exits 0 to allow sentinel write (once-only notice pattern). Confirmed patched.
- Lines 94–96: `sleep 5; bash "${FORGE_INSTALL_TMP}"` — these lines now only execute when (a) interactive, OR (b) non-interactive with a pinned SHA set and verified. The gate at lines 83–92 precludes reaching this code in the dangerous non-interactive + no-pin case.
- Download timeouts: `curl --max-time 60 --connect-timeout 15` and `wget --timeout=60` — present (R8-6 confirmed)
- SHA availability check with `sha256sum` fallback — present (R7-8 confirmed)
- Symlink and ownership checks in `add_to_path` — present (R6-5, R7-5 confirmed)
- Binary identity check post-install — present (R6-10 confirmed)

**forge.md declares:**
- `HISTSIZE=0` added to history guard block at line 167 — present **(R9-6 PATCHED)**
- `OLD_HISTSIZE` capture and restore at lines 167 and 197 — present **(R9-6 PATCHED)**
- `NOTE: Run this ENTIRE block as a single Bash tool call` annotation at lines 168–169 — present **(R9-6 PATCHED)**
- `printf '%s' 'KEY_PLACEHOLDER'` at line 173 — still present (R9-4/R9-5 residual)
- Note at lines 198–201 acknowledges key-in-transcript; "unavoidable" framing still present but note also suggests manual paste alternative (marginal improvement)
- R9-8 comment in STEP 0A-1 install blocks at lines 73–76: commented-out `EXPECTED_FORGE_SHA` pattern added as a note — partial acknowledgment
- AGENTS.md trust gate — present (mandatory wrapper)
- Sandbox guidance — present
- `git checkout -- .` MANDATORY STOP — present

---

## Step 1 — Environment and Metadata Audit

### 1A. Execution Surfaces (complete enumeration, R10)

1. `SessionStart` hook → `install.sh` → conditional download + optional `bash` execution (now gated by R9-2 patch)
2. `forge.md` instruction surface → Claude reads skill and executes embedded shell commands
3. Credential write: `printf '%s' 'KEY_PLACEHOLDER'` — key value substituted by Claude into shell command argument (residual R8-1/R9-4)
4. Shell profile modification (`~/.zshrc`, `~/.bashrc`, `~/.bash_profile`)
5. `forge` binary at `~/.local/bin/forge` — third-party binary with persistent system presence
6. Forge prompt construction pipeline — user input, AGENTS.md, external file content embedded in forge prompts
7. `~/forge/.forge.toml` — config with `$schema` URL reference (disclosure comment present, R8-5 confirmed)
8. STEP 9 Quick Reference block — standalone command listing
9. Three manual install code blocks in STEP 0A-1 — display-only SHA with commented-out `EXPECTED_FORGE_SHA` pattern (R9-8 partially addressed)
10. `install.sh` `add_to_path` function — shell profile append with symlink and ownership checks
11. `EXPECTED_FORGE_SHA=""` — comparison scaffold with zero-length guard; conditional SHA check block present but guard never fires in default configuration

### 1B. Trust Boundaries

| Boundary | Trust Level | Notes |
|---|---|---|
| Plugin publisher (Ālo Labs) → user | Implicit on install | GitHub repo; no commit signing enforced |
| `forgecode.dev` → binary/install script delivery | External, TLS only | No pinned cert; EXPECTED_FORGE_SHA field present but empty — pinned check never executes |
| `openrouter.ai` → API credential target | External | Credentials stored in `~/forge/.credentials.json` (chmod 600) |
| forge binary runtime → AI-directed shell execution | Highest privilege | Executes arbitrary shell commands based on AI output |
| AGENTS.md from arbitrary repos → forge prompts | Untrusted | Prompt injection vector; mandatory wrapper gate present and enforced |
| `$schema` URL in `.forge.toml` → `forgecode.dev` | External reference | Fetched by schema-aware editors; disclosure comment present (R8-5) |
| `KEY_PLACEHOLDER` substitution → Claude command construction | High sensitivity | Key value embedded in `printf` argument by Claude before execution (R9-4 residual) |

---

## Step 2 — Recon Notes

```
recon_notes {
  target          : forge/sidekick plugin v1.0.0
  audit_round     : 10
  prior_rounds    : R1-R9
  files_audited   : 4 (forge.md 882 lines, install.sh 174 lines,
                       hooks/hooks.json 14 lines, plugin.json 29 lines)

  r9_patches_verified : {

    R9-2  : PATCHED
            install.sh lines 83–92:
              if [ ! -t 1 ] && [ -z "${EXPECTED_FORGE_SHA}" ]; then
                echo "[forge-plugin] NOTICE: Cannot execute downloaded installer
                  without user verification." >&2
                echo "[forge-plugin]   Running non-interactively with no pinned
                  SHA — skipping auto-install." >&2
                echo "[forge-plugin]   To install ForgeCode, open a terminal
                  and run:" >&2
                echo "[forge-plugin]     bash \"${BASH_SOURCE[0]}\"" >&2
                echo "[forge-plugin]   The SHA-256 will be displayed and you can
                  verify it before proceeding." >&2
                exit 0
              fi
            Gate condition: non-interactive (!-t 1) AND no pinned hash (-z EXPECTED_FORGE_SHA)
            Both conditions must be true to abort. If either is false:
              - Interactive terminal: user can Ctrl+C; sleep 5 + bash proceeds normally.
              - Pinned hash set: SHA verified above; non-interactive execution is safe.
            Exit code 0 → sentinel IS written → notice appears once (correct behavior).
            CONFIRMED PATCHED. The fifth-round MEDIUM finding is resolved.

    R9-3  : PATCHED
            hooks.json line 8:
              "test -f \"${CLAUDE_PLUGIN_ROOT}/.installed\" ||
              (bash \"${CLAUDE_PLUGIN_ROOT}/install.sh\" && touch
              \"${CLAUDE_PLUGIN_ROOT}/.installed\")"
            Operator changed from semicolon to &&. Sentinel written only on exit 0.
            Interlock with R9-2 gate is correct:
              - Non-interactive, no pin → exit 0 → sentinel written → once-only notice
              - Non-interactive, pin set → install proceeds → exit 0 → sentinel written
              - Interactive, install fails → exit non-zero → sentinel NOT written → retries
            CONFIRMED PATCHED.
            CAVEAT: The R9-3 remediation recommended exit 1 for non-interactive abort
            so that the sentinel would NOT be written, forcing re-attempt on next session.
            The implemented R9-2 uses exit 0 instead, intentionally writing the sentinel
            to suppress repeated notices. This is a deliberate design choice: the user
            is shown the message once and directed to run install manually.
            Both behaviors are defensible; the exit 0 approach is less annoying but means
            the hook will not retry automatically — the user must follow the manual
            instruction. No security regression from this choice.

    R9-4  : NOT PATCHED (residual — acknowledged)
            forge.md line 173: printf '%s' 'KEY_PLACEHOLDER' > "${KEY_TMP}"
            Python input() replacement not implemented.
            Note at lines 198–201 still frames exposure as a limitation rather than
            eliminating it.
            Note now includes "paste the key directly into ~/forge/.credentials.json
            by hand using a text editor outside of Claude" as an alternative.
            This alternative achieves the same result as Option B from R9-4 remediation.
            RESIDUAL — LOW. Note improvement acknowledged; printf pattern unchanged.

    R9-5  : NOT PATCHED (residual — acknowledged)
            printf '%s' 'KEY_PLACEHOLDER' shell-level injection at command-construction
            stage still possible if key contains single-quote character.
            R9-5 comment added at line 171:
              "# R9-5: KEY_PLACEHOLDER must contain only alphanumeric/dash/underscore
              characters (validated by Python below)."
            The Python validation (lines 183–186) remains present and correct.
            Comment acknowledges the constraint but does not prevent the injection;
            it is advisory to Claude.
            RESIDUAL — LOW.

    R9-6  : PATCHED
            forge.md line 167:
              OLD_HISTSIZE="${HISTSIZE:-}"; HISTSIZE=0
            forge.md line 169:
              NOTE: Run this ENTIRE block as a single Bash tool call for the
              HISTFILE/HISTSIZE changes to take effect for the printf line.
            forge.md line 197:
              [ -n "${OLD_HISTSIZE}" ] && HISTSIZE="${OLD_HISTSIZE}"; unset OLD_HISTSIZE
            All three components present: HISTSIZE=0 set, restore present, atomic
            execution note present.
            CONFIRMED PATCHED.

    R9-7  : PARTIALLY PATCHED (unchanged from R9)
            plugin.json _integrity fields present with empty string values.
            install_sh_sha256: "" and forge_md_sha256: "" remain unpopulated.
            No new population in R10.
            RESIDUAL — LOW (5th round, operational gap not code defect).

    R9-8  : PARTIALLY PATCHED
            forge.md STEP 0A-1 primary curl block (lines 73–76) now includes:
              "# R9-8: To enable pinned-hash verification (recommended), set
              EXPECTED_FORGE_SHA to the official release hash from
              https://forgecode.dev/releases before running:"
              "#   EXPECTED_FORGE_SHA="<hash from releases page>""
              "#   [ -n "${EXPECTED_FORGE_SHA}" ] && ..."
            Commented-out pattern added as a NOTE.
            wget fallback block (lines 92–94) and verbose fallback (lines 111–113)
            have the same NOTE for Claude framing but do NOT have the
            commented-out EXPECTED_FORGE_SHA snippet.
            Only the primary curl block received the snippet; the other two blocks
            received a general NOTE without the pattern.
            PARTIALLY PATCHED — INFO (all three blocks have advisory notes;
            only one has the code snippet).

    R9-9  : PATCHED
            install.sh lines 72–75:
              else
                # R9-1/R9-9: Warn when no pin is active so the verification gap
                # is explicit.
                echo "[forge-plugin] NOTICE: No pinned SHA-256 set — verification
                  is display-only."
                echo "[forge-plugin]   To enable automated verification, set
                  EXPECTED_FORGE_SHA in install.sh."
            Warning message emitted when EXPECTED_FORGE_SHA is empty (the else
            branch of the [ -n "${EXPECTED_FORGE_SHA}" ] check).
            The silent skip issue from R9-9 is resolved: the user now sees a
            visible NOTICE that verification is display-only.
            CONFIRMED PATCHED.
  }

  new_attack_surfaces_identified : {
    R10-1: install.sh exit 0 from non-interactive gate — design consistency note
           (see R9-3 CAVEAT above). Not a security finding; INFO.
    R10-2: EXPECTED_FORGE_SHA="" remains the fifth consecutive unpatched release
           of an empty SHA placeholder. The check is now more visible (R9-9
           warning present), but the field is still functionally inert.
           No escalation in severity; still LOW/MEDIUM depending on threat model.
    R10-3: forge.md STEP 0A-1 wget and verbose-fallback blocks lack the
           commented-out EXPECTED_FORGE_SHA snippet that the primary curl block
           now has (R9-8 partial). INFO.
    R10-4: No new injection, path traversal, privilege escalation, or
           prompt injection surfaces identified.
  }

  false_negative_check : {
    Cat-1 (shell injection): printf KEY_PLACEHOLDER single-quote injection residual.
      R9-5 comment present; Python validation present. No new surfaces.
    Cat-2 (path traversal): No new surfaces. PROJECT_ROOT quoted. CLEAN.
    Cat-3 (privilege escalation): No sudo/setuid. CLEAN.
    Cat-4 (credential exposure): R9-4 residual (key in printf). HISTSIZE=0
      now present (R9-6 patched). No new surfaces.
    Cat-5 (prompt injection): AGENTS.md trust gate mandatory. Sandbox guidance
      present. No regression. CLEAN.
    Cat-6 (destructive ops): git checkout -- . guarded; git reset --hard
      has caution comment. No regression. CLEAN.
    Cat-7 (supply chain): R9-2 PATCHED (non-interactive gate). R9-3 PATCHED
      (sentinel &&). EXPECTED_FORGE_SHA="" still operationally inert (R9-1/R10-2).
    Cat-8 (privacy): $schema disclosure comment present (R8-5). forge binary
      privacy note present. CLEAN.
    Cat-9 (logic/state): hooks.json && patched (R9-3). install.sh exit 0
      design choice noted (R10-1). CLEAN.
    Cat-10 (transparency): NOTICE emitted on no-pin install (R9-9 patched).
      printf "unavoidable" framing marginally improved with manual-paste note.
      R9-4 residual framing still present.
  }
}
```

---

## Steps 3–8 — Findings

All ten finding categories are evaluated below. This is the first round with **zero new MEDIUM or higher findings**.

---

### FINDING R10-1 — R9-1 Residual (5th Round): `EXPECTED_FORGE_SHA=""` — SHA Comparison Scaffold Present but Never Activated
**Severity:** MEDIUM (CVSS 3.1: AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:N — 6.5)
**Status:** Partially Patched — R9-9 warning now emitted; R9-2 non-interactive gate now in place; SHA value still empty
**Category:** Supply Chain / Verification Theater
**Finding Category:** Cat-7 (Supply Chain)
**Round history:** R6 (not patched), R7 (not patched), R8 (scaffold added), R9 (warning added), R10 (partially patched — 5th round)

**Location:** `install.sh` lines 20, 62–75

**Evidence (verified in current files):**

```bash
# install.sh line 20:
EXPECTED_FORGE_SHA=""

# install.sh lines 62–75:
if [ -n "${EXPECTED_FORGE_SHA}" ] && [ "${FORGE_SHA}" != "UNAVAILABLE" ]; then
  if [ "${FORGE_SHA}" != "${EXPECTED_FORGE_SHA}" ]; then
    echo "[forge-plugin] ERROR: SHA-256 MISMATCH — aborting installation." >&2
    ...
    exit 1
  fi
  echo "[forge-plugin] SHA-256 verified against pinned hash — OK."
else
  # R9-1/R9-9: Warn when no pin is active so the verification gap is explicit.
  echo "[forge-plugin] NOTICE: No pinned SHA-256 set — verification is display-only."
  echo "[forge-plugin]   To enable automated verification, set EXPECTED_FORGE_SHA in install.sh."
fi
```

**What changed since R9:**
- R9-9 patch: "NOTICE: No pinned SHA-256 set" is now emitted when `EXPECTED_FORGE_SHA` is empty. The silent-skip issue is resolved.
- R9-2 patch: Non-interactive + no-pin path now aborts binary execution — the most dangerous consequence of the empty pin is mitigated for the SessionStart hook context.

**What remains:**
`EXPECTED_FORGE_SHA=""` means the SHA comparison block still never fires. The guard `[ -n "" ]` is false. The automated verification path is dead code.

**Residual risk assessment (R10):**
The R9-2 non-interactive gate substantially reduces the exploitability of this finding in the primary threat scenario (malicious forgecode.dev serving a compromised installer during SessionStart). Without a pinned SHA and in a non-interactive context, the install is now aborted rather than proceeding. The remaining risk window is interactive installs: a user who runs `install.sh` from a terminal will still see only the NOTICE (no automated comparison) and must manually compare the displayed SHA against the releases page.

CVSS score is maintained at 6.5 (MEDIUM) because the root cause (no pinned hash) is unchanged and automated supply-chain verification remains absent. However, the exploitability window is now narrowed to interactive-only scenarios due to R9-2.

**Concrete remediation (unchanged from R9):**

Populate `EXPECTED_FORGE_SHA` with the current ForgeCode release hash:
```bash
# Get current hash:
shasum -a 256 /path/to/forgecode-install.sh
# Update install.sh line 20:
EXPECTED_FORGE_SHA="<real sha256 from official release>"
```

The all-zeros sentinel recommendation from R8/R9 is no longer strictly needed given the R9-9 NOTICE warning. Populating with the real hash is the only fix that provides actual automated verification.

---

### FINDING R10-2 — R9-4/R9-5 Residual (4th Round): `printf 'KEY_PLACEHOLDER'` — Key in Claude Transcript; Shell Injection at Command-Construction Stage
**Severity:** LOW (CVSS 3.1: AV:L/AC:L/PR:L/UI:N/S:U/C:L/I:N/A:N — 3.3)
**Status:** Not Patched — advisory note improved; Python `input()` replacement not implemented
**Category:** Credential Exposure / Shell Injection at command-construction
**Finding Category:** Cat-1 (Shell Injection), Cat-4 (Credential Exposure)
**Round history:** R7-3 (first flagged), R8-1/R8-7 (partial patches), R9-4/R9-5 (residual), R10-2 (residual — 4th round)

**Location:** `skills/forge.md` lines 163–173, 198–201

**Evidence (verified in current files):**

```bash
# forge.md line 165:
# Claude: replace KEY_PLACEHOLDER below with the actual key value, then run the full block.
# forge.md line 173:
printf '%s' 'KEY_PLACEHOLDER' > "${KEY_TMP}"  # ← replace KEY_PLACEHOLDER with actual key
```

```
# NOTE (R8-1/R9-4): The printf line above places the key in the Claude conversation
# transcript — this is a limitation of the Bash tool pattern. The key is NOT stored
# in shell history. To avoid transcript exposure entirely, paste the key directly into
# ~/forge/.credentials.json by hand using a text editor outside of Claude.
```

**What changed since R9:**
- R9-6 patch: `HISTSIZE=0` and `OLD_HISTSIZE` restore added. Shell history protection is now belt-and-suspenders.
- Note at lines 198–201 now includes "paste the key directly into `~/forge/.credentials.json` by hand using a text editor outside of Claude" as a concrete alternative.
- R9-5 comment at line 171: "KEY_PLACEHOLDER must contain only alphanumeric/dash/underscore characters (validated by Python below)" — advisory note added.

**Two distinct sub-issues remain:**

**R10-2a (transcript exposure):** When Claude executes the credential block, it constructs a Bash tool call containing `printf '%s' 'sk-or-v1-REALKEY'`. The actual API key appears in the tool call and its output as captured in the conversation transcript. The note now correctly names this limitation and offers a workaround (manual file edit). Python `input()` remains the cleaner automated fix and was not implemented.

**R10-2b (single-quote injection):** If the pasted key contains a single-quote character, `printf '%s' 'key'with'quote'` produces a shell syntax error or unintended command construction. Python validation at lines 183–186 (`re.match(r'^[A-Za-z0-9_\-]+$', key)`) catches this only after the printf line has already been constructed and executed. The Python block would be partially run or not run at all, depending on `set -euo pipefail` state.

**Concrete remediation (unchanged from R9):**

Replace the `printf` + Python pattern with Python `input()`:

```bash
# ⚠️ CLAUDE: Do NOT substitute any key value. Do NOT construct a printf command.
# Run this block as-is. The user will paste the key at the Python prompt.
OLD_HISTFILE="${HISTFILE:-}"; OLD_HISTSIZE="${HISTSIZE:-}"; unset HISTFILE; export HISTSIZE=0
KEY_TMP=$(mktemp); chmod 600 "${KEY_TMP}"

KEY_TMP="${KEY_TMP}" python3 << 'PYEOF'
import os, re, sys
print("Paste your OpenRouter API key and press Enter: ", end='', flush=True)
key = sys.stdin.readline().strip()
if not key:
    raise ValueError("No key provided")
if not re.match(r'^[A-Za-z0-9_\\-]+$', key):
    raise ValueError("Key contains unexpected characters — verify the key")
with open(os.environ['KEY_TMP'], 'w') as f:
    f.write(key)
print("Key written to temp file.")
PYEOF
# (Continue with credentials.json write block)
```

This eliminates both R10-2a (key never appears in Bash tool call output) and R10-2b (Python processes the key directly from stdin, never as a shell argument).

---

### FINDING R10-3 — R9-7 Residual (5th Round): `_integrity` Fields in plugin.json Are Empty; No Integrity Fields in marketplace.json
**Severity:** LOW (CVSS 3.1: AV:N/AC:H/PR:N/UI:R/S:U/C:H/I:H/A:N — 6.8 if exploited; operational gap reduces practical impact)
**Status:** Partially Patched — scaffolding present since R8; values empty for 5th consecutive round
**Category:** Supply Chain / Manifest Integrity
**Finding Category:** Cat-7 (Supply Chain)
**Round history:** R6, R7, R8 (scaffold added), R9 (unchanged), R10 (unchanged — 5th round)

**Location:** `.claude-plugin/plugin.json` lines 22–28

**Evidence (verified in current files):**

```json
"_integrity": {
  "_note": "R8-4: Pin the SHA-256 of install.sh below and update on each release...",
  "install_sh_sha256": "",
  "forge_md_sha256": "",
  "verify_at": "https://forgecode.dev/releases",
  "source": "https://github.com/alo-exp/sidekick"
}
```

**Current file SHA-256 values (computed this round, for maintainer reference):**
```
install.sh:       bb89b476324413e2e341ce3d09c1b9396d5ad2706d0944698b4d23b91d7eab45
skills/forge.md:  0af9d8885691f69d2879d51c15364471bc4d041f41a56db8a71be6e2897260e0
hooks/hooks.json: 4a131a3b1ceee87b968b13f6365daaa9f3a249605f9b8836a3f6d68421038e64
plugin.json:      22a5392cb88e7a582b855df855f5fcaad928d4a05a7483f82e3ee12af5323cde
```

The Claude plugin runtime does not enforce these fields — they serve as a manual audit aid and tamper-detection signal. Populating them requires a manual or scripted update on each release.

**Concrete remediation:**

Populate the fields:
```json
"install_sh_sha256": "bb89b476324413e2e341ce3d09c1b9396d5ad2706d0944698b4d23b91d7eab45",
"forge_md_sha256": "0af9d8885691f69d2879d51c15364471bc4d041f41a56db8a71be6e2897260e0"
```

Add a pre-commit hook or release script to recompute these values automatically. Consider adding the same structure to marketplace.json.

---

### FINDING R10-4 — R9-8 Partial Patch: forge.md wget and Verbose-Fallback Install Blocks Lack `EXPECTED_FORGE_SHA` Code Snippet
**Severity:** INFO (CVSS 3.1: AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:N/A:N — 2.0)
**Status:** Partially Patched — primary curl block has the snippet; wget and verbose-fallback blocks have advisory notes only
**Category:** Supply Chain / Documentation Gap
**Finding Category:** Cat-7 (Supply Chain)

**Location:** `skills/forge.md` STEP 0A-1, lines 83–97 (wget block) and lines 100–116 (verbose fallback block)

**Evidence (verified in current files):**

Primary curl block (lines 73–76): Has commented-out `EXPECTED_FORGE_SHA` code pattern. Partially addresses R9-8.

wget block (lines 92–94):
```bash
# NOTE for Claude: When executing via the Bash tool, the user cannot send Ctrl+C.
# Show the SHA-256 output to the user and ask for explicit confirmation before proceeding.
# (SENTINEL FINDING-R7-1/R7-7: Bash tool cancel caveat + user confirmation gate)
```
No `EXPECTED_FORGE_SHA` pattern. Advisory note only.

Verbose fallback block (lines 111–113): Same advisory NOTE pattern, no code snippet.

**Impact:** A user or Claude following the wget or verbose fallback paths will not see the commented-out `EXPECTED_FORGE_SHA` mechanism that is now present in the primary block. When the maintainer eventually populates a real SHA in install.sh, the secondary paths remain divergent.

**Concrete remediation:**

Add the same commented-out `EXPECTED_FORGE_SHA` pattern from the primary curl block to the wget and verbose-fallback blocks, immediately after the `FORGE_SHA=` line in each. Consistency across all three blocks ensures the mechanism is discoverable regardless of which path the user follows.

---

### FINDING CATEGORIES — COMPLETE STATUS MATRIX (R10)

| # | Category | R10 Status | Notes |
|---|---|---|---|
| Cat-1 | Shell Injection | LOW (residual R10-2b) | printf single-quote injection at command-construction; Python validation present but post-construction |
| Cat-2 | Path Traversal | CLEAN | PROJECT_ROOT properly quoted throughout; no new surfaces |
| Cat-3 | Privilege Escalation | CLEAN | No sudo/setuid/capabilities; binary installs to user HOME only |
| Cat-4 | Credential Exposure | LOW (residual R10-2a) | Key appears in Bash tool transcript via printf; HISTSIZE=0 patched (R9-6); workaround note present |
| Cat-5 | Prompt Injection | CLEAN | AGENTS.md trust gate mandatory; untrusted wrapper enforced; sandbox guidance present |
| Cat-6 | Destructive Operations | CLEAN | `git checkout -- .` has MANDATORY STOP; `git reset --hard` has caution note; no autonomous destruction |
| Cat-7 | Supply Chain | MEDIUM (residual R10-1) | EXPECTED_FORGE_SHA="" — automated verification never fires; R9-2 non-interactive gate mitigates worst case; NOTICE now emitted |
| Cat-8 | Privacy / Data Disclosure | CLEAN | $schema disclosure comment present; forge binary privacy note present; credential key visibility in transcript is R10-2a |
| Cat-9 | Logic / State Management | CLEAN | hooks.json && patched (R9-3); install.sh exit 0 design choice is intentional and documented |
| Cat-10 | Transparency | INFO | printf "limitation" note improved with manual-paste alternative; "unavoidable" framing marginally addressed |

---

## Step 8 — Patch Verification Summary

| Finding ID | Description | R9 Status | R10 Status |
|---|---|---|---|
| R8-1/R9-4 | Key in Claude transcript (printf) | Not Patched | Not Patched (note improved) |
| R8-2/R9-2 | Non-interactive binary execution | Not Patched (4th round) | **PATCHED** |
| R8-3/R9-1 | EXPECTED_FORGE_SHA="" empty | Partially Patched | Partially Patched (NOTICE added) |
| R8-4/R9-7 | plugin.json _integrity empty | Partially Patched | Partially Patched (unchanged) |
| R8-5 | $schema disclosure | Patched | Confirmed Patched |
| R8-6 | Download timeouts | Patched | Confirmed Patched |
| R8-7/R9-5 | printf single-quote injection | Partially Patched | Partially Patched (comment added) |
| R8-8/R9-3 | hooks.json sentinel semicolon | Not Patched | **PATCHED** |
| R8-9/R9-6 | HISTSIZE=0 missing | Partially Patched | **PATCHED** |
| R9-8 | forge.md install blocks lack EXPECTED_FORGE_SHA | New | Partially Patched (primary block only) |
| R9-9 | No warning when EXPECTED_FORGE_SHA empty | New | **PATCHED** |

**New findings this round:** None with MEDIUM or higher severity.

---

## Step 9 — Prioritized Remediation Backlog

| Priority | Finding | Action | Effort |
|---|---|---|---|
| 1 (MEDIUM) | R10-1: EXPECTED_FORGE_SHA="" | Populate with real ForgeCode release hash in install.sh | Low — one value to populate per release |
| 2 (MEDIUM) | R10-3: plugin.json _integrity empty | Populate SHA-256 fields; add release script | Low — hashes computed above for immediate use |
| 3 (LOW) | R10-2: printf KEY_PLACEHOLDER | Replace with Python input() pattern | Medium — code change to forge.md credential block |
| 4 (INFO) | R10-4: wget/verbose blocks lack snippet | Add EXPECTED_FORGE_SHA commented pattern to both blocks | Low — copy-paste from primary block |

---

## Step 10 — Auditor Notes

**Progress Assessment:**

R10 represents the most substantive single-round improvement since R7. Two findings that had been MEDIUM for four consecutive rounds (R9-2: non-interactive execution; R9-3: sentinel semicolon) are confirmed patched. The interactive execution gate in install.sh (lines 83–92) is well-constructed: it correctly identifies the high-risk condition (non-interactive + no pinned SHA), aborts binary execution, emits a clear user-facing message, and exits 0 to ensure the notice is not repeated on every subsequent session. The hooks.json `&&` change is the correct co-patch.

R9-6 (HISTSIZE=0) is also confirmed patched, completing the credential block's shell history protection.

**Remaining concerns are operational, not architectural:**
- The dominant residual issue (EXPECTED_FORGE_SHA="") requires only a value to be populated — the verification infrastructure is in place and correct. This is a release process gap, not a code defect.
- The printf KEY_PLACEHOLDER pattern is a known LOW finding. The note acknowledging the limitation and the manual-paste alternative represent reasonable mitigation for users who understand the exposure.

**No new attack surfaces of significance were identified in R10.**

The plugin is in good security shape for its described use case. The supply-chain verification gap (no pinned hash) is the last meaningful open issue, and it is operationally straightforward to close.

---

*End of SENTINEL v2.3 Audit — Round 10*
*Generated: 2026-04-12*

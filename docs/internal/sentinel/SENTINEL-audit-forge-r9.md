# SENTINEL v2.3 — Security Audit Report
## Target: forge skill (sidekick plugin v1.0.0)
## Round: 9 (R8 Patch Verification + Full New-Surface Audit)
## Date: 2026-04-12
## Auditor: SENTINEL v2.3 (dual-mode: Defensive + Adversarial)
## Prior Rounds: R1–R8; R9 verifies all R8 patches and conducts full new-surface audit

---

## Step 0 — Decode Manifest / File Inventory

| File | Lines (current) | Role |
|---|---|---|
| `skills/forge.md` | 874 | Claude orchestration protocol, runtime skill instructions |
| `install.sh` | 154 | Binary installer and PATH modifier, executed via SessionStart hook |
| `hooks/hooks.json` | 14 | SessionStart hook definition |
| `.claude-plugin/plugin.json` | 29 | Plugin manifest |
| `.claude-plugin/marketplace.json` | 28 | Marketplace listing metadata |

### Manifest Decode

**plugin.json declares:**
- Name: `sidekick`, Version: `1.0.0`, License: MIT
- Author: Ālo Labs (`https://alolabs.dev`)
- Repository: `https://github.com/alo-exp/sidekick`
- Skills path: `./skills/`
- `_integrity` object present with fields `install_sh_sha256: ""` and `forge_md_sha256: ""` — scaffolding only, both values empty strings; no actual hash values populated

**marketplace.json declares:**
- Source: `https://github.com/alo-exp/sidekick.git` (URL-sourced plugin)
- Version `1.0.0`; no integrity fields; no hash-of-hashes

**hooks.json declares:**
- One hook: `SessionStart`
- Command: `test -f "${CLAUDE_PLUGIN_ROOT}/.installed" || (bash "${CLAUDE_PLUGIN_ROOT}/install.sh"; touch "${CLAUDE_PLUGIN_ROOT}/.installed")`
- Sentinel-gated: runs install once per system
- **CRITICAL OBSERVATION:** Uses semicolon operator — sentinel (`.installed`) written unconditionally regardless of whether `install.sh` succeeds or fails

**install.sh declares:**
- `set -euo pipefail`, `trap` cleanup of temp file on exit
- Downloads `https://forgecode.dev/cli` via curl or wget to a temp file
- `EXPECTED_FORGE_SHA=""` — variable declared but empty string; no pinned hash populated
- Download timeouts now present: `curl -fsSL --max-time 60 --connect-timeout 15` and `wget --timeout=60` (R8-6 patched)
- SHA-256 computed with `shasum`/`sha256sum` availability check (R7-8 patched); logged to `~/.local/share/forge-plugin-install-sha.log`
- Conditional SHA comparison block present (lines 62–71) but guarded by `[ -n "${EXPECTED_FORGE_SHA}" ]` — empty string evaluates to false; block is never executed; display-only SHA remains
- **Binary execution:** lines 73–75: `# R6-1: In non-interactive mode Ctrl+C may not be available; give a short window anyway.` / `sleep 5` / `bash "${FORGE_INSTALL_TMP}"` — unconditional, no `[ -t 1 ]` gate on binary execution
- `[ -t 1 ]` branching present for PATH modification consent block only (lines 118–129), not for binary execution
- `add_to_path` function: symlink check and ownership check present
- Binary identity check present post-install (version string regex)
- Pre-consent notice present with interactive/non-interactive branching

**forge.md declares:**
- `EXPECTED_FORGE_SHA=""` variable placeholder present in STEP 0 first-run notice (line 20 of install.sh, referenced in forge.md via SENTINEL annotations)
- `KEY_PLACEHOLDER` in `printf '%s' 'KEY_PLACEHOLDER' > "${KEY_TMP}"` — key substitution model unchanged
- `unset HISTFILE` present; no `HISTSIZE=0` addition (R8-9 not patched)
- Comment at line 188: "only works correctly when the full block above runs atomically in a single Bash tool call" — R8-9 partially acknowledged
- NOTE at line 190: "The printf line above places KEY_PLACEHOLDER in the Claude conversation transcript — this is unavoidable when running via the Bash tool." — R8-1 acknowledged but not fixed
- `$schema` disclosure comment now present in TOML heredoc (lines 196–198): `# $schema fetched from forgecode.dev for IDE validation only — no data is sent at config load time.` — **R8-5 PATCHED**
- Trust gate (AGENTS.md mandatory wrapper) present
- Sandbox guidance present
- MANDATORY STOP blocks present (git checkout -- .)
- Quick Reference: sandbox trust qualifiers present

---

## Step 1 — Environment and Metadata Audit

### 1A. Execution Surfaces (complete enumeration)

1. `SessionStart` hook → `install.sh` → external network fetch → `bash` execution of downloaded script
2. `forge.md` instruction surface → Claude reads skill and executes embedded shell commands
3. Credential write: `KEY_PLACEHOLDER` substitution in `printf '%s' 'KEY_PLACEHOLDER' > "${KEY_TMP}"` — key value embedded in a `printf` command argument (residual R8-1)
4. Shell profile modification (`~/.zshrc`, `~/.bashrc`, `~/.bash_profile`)
5. `forge` binary at `~/.local/bin/forge` — third-party binary with persistent system presence
6. Forge prompt construction pipeline — user input, AGENTS.md, external file content embedded in forge prompts
7. `~/forge/.forge.toml` — config with `$schema` URL reference to `https://forgecode.dev/schema.json` (now has disclosure comment — R8-5 patched)
8. STEP 9 Quick Reference block — standalone command listing Claude may copy-execute verbatim
9. Three manual install code blocks in STEP 0A-1 (primary curl path, wget fallback, verbose fallback)
10. `install.sh` `add_to_path` function — shell profile append with symlink and ownership checks
11. Binary identity check at install.sh lines 140–151
12. `EXPECTED_FORGE_SHA=""` in install.sh — comparison scaffold with zero-length guard; conditional SHA check block present but never triggered

### 1B. Trust Boundaries

| Boundary | Trust Level | Notes |
|---|---|---|
| Plugin publisher (Ālo Labs) → user | Implicit on install | GitHub repo; no commit signing enforced |
| `forgecode.dev` → binary/install script delivery | External, TLS only | No pinned certificate; EXPECTED_FORGE_SHA field present but empty — pinned check never executes |
| `openrouter.ai` → API credential target | External | Credentials stored in `~/forge/.credentials.json` (chmod 600) |
| forge binary runtime → AI-directed shell execution | Highest privilege | Executes arbitrary commands based on AI output |
| AGENTS.md from arbitrary repos → forge prompts | Untrusted | Prompt injection vector; mandatory wrapper gate present |
| `$schema` URL in `.forge.toml` → `forgecode.dev` | External reference | Fetched by schema-aware editors; disclosure comment now present |
| `KEY_PLACEHOLDER` substitution → Claude command construction | High sensitivity | Key value embedded in `printf` argument by Claude before execution |

### 1B (tool audit). Tools / Binaries Invoked by Plugin

| Tool | Where Invoked | Validation Present? |
|---|---|---|
| `curl` / `wget` | `install.sh` lines 35, 37; `forge.md` multiple | TLS only; no cert pin; download timeouts now present (R8-6 patched) |
| `bash` | `install.sh` line 75 (executes downloaded script) | SHA-256 logged; `sleep 5`; no non-interactive abort gate (R8-2 not patched) |
| `python3` | `forge.md` lines 167–185 (credentials) | Heredoc avoids key in process args; key read from temp file |
| `printf` | `forge.md` line 165 (writes key to temp file) | `KEY_PLACEHOLDER` substituted by Claude — key appears in Bash tool command (R8-1 not patched) |
| `git` | `forge.md` multiple recovery flows | `git checkout -- .` guarded in §5-4 and §9 Quick Reference |
| `shasum` / `sha256sum` | `install.sh` lines 43–50; `forge.md` install blocks | Availability check with fallback present; comparison scaffold present but empty |
| `forge` binary | `forge.md` throughout | Version identity check present at install.sh lines 140–151 |
| `stat` | `install.sh` `add_to_path` (lines 105–109) | Cross-platform stat with fallback; ownership check present |

---

## Step 2 — Recon Notes

```
recon_notes {
  target          : forge/sidekick plugin v1.0.0
  audit_round     : 9
  prior_rounds    : R1-R8
  files_audited   : 5 (forge.md 874 lines, install.sh 154 lines,
                       hooks.json 14 lines, plugin.json 29 lines,
                       marketplace.json 28 lines)

  r8_patches_verified : {

    R8-1  : NOT PATCHED (acknowledged but not fixed)
            forge.md line 190-192 now contains:
              "# NOTE (R8-1): The printf line above places KEY_PLACEHOLDER in
              the Claude conversation transcript — this is unavoidable when
              running via the Bash tool."
            The `printf '%s' 'KEY_PLACEHOLDER' > "${KEY_TMP}"` pattern
            (line 165) is unchanged. The note acknowledges the exposure but
            does not eliminate it. Neither Option A (Python input()) nor
            Option B (user-executes-printf instruction) was implemented.
            The note frames the exposure as "unavoidable" — this is
            architecturally incorrect; Option A (Python input()) does avoid it.
            RESIDUAL — LOW. Note addition does not constitute a patch.

    R8-2  : NOT PATCHED (4th consecutive round)
            install.sh lines 73–75 still read:
              "# R6-1: In non-interactive mode Ctrl+C may not be available;
              give a short window anyway."
              "sleep 5"
              "bash "${FORGE_INSTALL_TMP}""
            The `[ -t 1 ]` branching at lines 118–129 applies ONLY to the
            PATH modification consent block. The binary execution block at
            lines 73–75 has no interactive check, no abort gate, and executes
            unconditionally in the non-interactive SessionStart hook context.
            This is the same state as R6, R7, and R8.
            RESIDUAL — MEDIUM.

    R8-3  : PARTIALLY PATCHED (scaffolding present, not operationally effective)
            install.sh line 20: `EXPECTED_FORGE_SHA=""`
            install.sh lines 62–71: SHA comparison block present:
              if [ -n "${EXPECTED_FORGE_SHA}" ] && [ "${FORGE_SHA}" != "UNAVAILABLE" ]; then
                if [ "${FORGE_SHA}" != "${EXPECTED_FORGE_SHA}" ]; then
                  echo "[forge-plugin] ERROR: SHA-256 MISMATCH — aborting" >&2
                  exit 1
                fi
                echo "[forge-plugin] SHA-256 verified against pinned hash — OK."
              fi
            The comparison logic is correct but EXPECTED_FORGE_SHA is "".
            An empty string is falsy in `[ -n "" ]` → the entire comparison
            block is skipped. Execution proceeds to sleep 5 / bash without any
            comparison. The patch scaffold is in place and correct; the
            operational value is zero until a real hash is inserted.
            The R8 recommendation was an all-zeros placeholder to make the
            absent pin visible. Current code uses "" which is silent.
            PARTIALLY PATCHED — MEDIUM (structure present, value empty,
            no behavioral change from unpatched state).

    R8-4  : PARTIALLY PATCHED (scaffolding present, values empty)
            plugin.json now contains:
              "_integrity": {
                "_note": "R8-4: Pin the SHA-256 of install.sh below and update
                  on each release...",
                "install_sh_sha256": "",
                "forge_md_sha256": "",
                "verify_at": "https://forgecode.dev/releases",
                "source": "https://github.com/alo-exp/sidekick"
              }
            The integrity object is present with correct fields and note.
            Both hash values are empty strings. marketplace.json still has no
            integrity fields.
            Audit classification: PARTIALLY PATCHED — the schema scaffolding
            is in place and will reduce toil when hashes are populated.
            Functional security value: zero until hashes are inserted.
            LOW finding, downgraded from repeated-residual status.

    R8-5  : PATCHED
            forge.md lines 196–198 now contain:
              "# $schema fetched from forgecode.dev for IDE validation only —
              no data is sent at config load time."
              "# Review forgecode.dev's privacy policy if operating in a
              restricted network environment."
              "# (SENTINEL FINDING-R8-5: schema URL disclosure)"
            Disclosure comment present in the TOML heredoc with the exact
            content recommended. CONFIRMED PATCHED.

    R8-6  : PATCHED
            install.sh lines 35 and 37 now read:
              curl -fsSL --max-time 60 --connect-timeout 15
                https://forgecode.dev/cli -o "${FORGE_INSTALL_TMP}"
              wget -qO "${FORGE_INSTALL_TMP}" --timeout=60
                https://forgecode.dev/cli
            Both download commands have explicit timeouts. CONFIRMED PATCHED.

    R8-7  : PARTIALLY PATCHED (validation added in Python block; printf still present)
            forge.md Python credentials block (lines 175–178) now includes:
              "# R8-7: Validate key format — OpenRouter keys are alphanumeric
              + dashes/underscores only."
              if not re.match(r'^[A-Za-z0-9_\-]+$', key):
                raise ValueError("Key contains unexpected characters...")
            This correctly catches a malformed key AFTER it has been written
            to the temp file, before the credentials file is written.
            HOWEVER: The vulnerability described in R8-7 is in the `printf`
            command that Claude constructs BEFORE executing the full block:
              printf '%s' 'KEY_PLACEHOLDER'
            If the key contains a single quote, the shell-level injection
            occurs during the printf evaluation, before Python ever runs.
            The Python validation catches injection attempts in the credentials
            file write stage but cannot prevent shell command construction
            from breaking if the key value contains shell-special characters
            at the printf stage.
            The correct fix (Python input()) was not implemented.
            PARTIALLY PATCHED — LOW.

    R8-8  : NOT PATCHED
            hooks.json line 8 still reads:
              "(bash \"${CLAUDE_PLUGIN_ROOT}/install.sh\"; touch
              \"${CLAUDE_PLUGIN_ROOT}/.installed\")"
            Semicolon operator unchanged. Sentinel written unconditionally
            regardless of install.sh exit code.
            NOTE: If R8-2 is patched (non-interactive abort with exit 1),
            this semicolon means `.installed` is still written after the
            abort — preventing future re-attempts. This is the exact
            compatibility issue flagged in R8-8.
            RESIDUAL — INFO (but will escalate to MEDIUM when R8-2 is patched
            if R8-8 is not co-patched).

    R8-9  : PARTIALLY PATCHED (comment added; HISTSIZE=0 not added)
            forge.md line 187–188 now reads:
              "# R8-9: Restore HISTFILE — only works correctly when the full
              block above runs atomically"
              "# in a single Bash tool call. If the block is split across
              calls, HISTFILE stays unset."
            The "EXECUTE THIS ENTIRE BLOCK AS A SINGLE COMMAND" notice
            recommended in R8 was not added as a standalone warning line.
            The `HISTSIZE=0` addition was not implemented.
            Line 163 still reads:
              OLD_HISTFILE="${HISTFILE:-}"; unset HISTFILE
            No OLD_HISTSIZE capture. No HISTSIZE=0 set.
            PARTIALLY PATCHED — INFO (comment improvement; behavioral fix absent).
  }

  new_attack_surfaces_identified : {
    - EXPECTED_FORGE_SHA="" uses empty string; comparison block silently
      skips — "NOTE: no pin active" warning is absent. A user auditing the
      install.sh might believe SHA verification is in effect without
      inspecting the value. (New finding R9-1)
    - forge.md STEP 9 Quick Reference install comment still references
      "follow STEP 0A-1 above (SHA-256 verify + user confirmation required)"
      but omits that this is advisory, not enforced in SessionStart.
      Minor framing issue. (INFO, bundled with R9-1)
    - hooks.json sentinel semicolon + R8-2 non-patch = if R8-2 is ever
      implemented without co-patching R8-8, sentinel-write-on-abort will
      permanently disable auto-install. This interaction risk is now
      fourth-round persistent. (R8-8 residual, R9-2)
    - KEY_PLACEHOLDER note at forge.md line 190 states the printf exposure
      "is unavoidable" — this is incorrect. The framing may reduce user
      vigilance about the real risk. (Framing finding, R9-3)
    - forge.md STEP 0A-1 install blocks: None of the three manual install
      blocks (curl primary, wget fallback, verbose fallback) reference the
      new EXPECTED_FORGE_SHA mechanism. A user following the manual install
      path has no pinned-hash safety net even when install.sh has the
      scaffold. (New finding, R9-4)
    - install.sh line 153: setup complete message invites API key
      configuration in Claude — no mention of SHA log location for post-hoc
      verification by the user. (Minor UX/transparency gap, INFO)
    - marketplace.json has no integrity fields (R8-4 partial; R9-5)
  }

  false_negative_check : {
    Cat-1 (shell injection): R8-7 partially patched — printf single-quote
      injection still possible at Claude command-construction stage.
    Cat-2 (path traversal): No new surfaces identified. PROJECT_ROOT still
      correctly quoted. Clean.
    Cat-3 (privilege escalation): No sudo/setuid. Clean.
    Cat-4 (credential exposure): R8-1 acknowledged-not-patched; printf
      exposure confirmed present. HISTSIZE=0 absent.
    Cat-5 (prompt injection): AGENTS.md trust gate present and mandatory.
      No regression. Clean.
    Cat-6 (destructive ops): git checkout -- . guarded. git reset --hard
      has caution warning. Clean.
    Cat-7 (supply chain): R8-2 not patched (non-interactive gate);
      R8-3 scaffold empty (no real pinned hash). Two active MEDIUM findings.
    Cat-8 (privacy): R8-5 patched ($schema disclosure). Clean.
    Cat-9 (logic/state): R8-8 not patched (sentinel semicolon). R8-9
      partially patched.
    Cat-10 (transparency): R8-1 note frames printf exposure as
      "unavoidable" — potentially misleading. Minor transparency concern.
  }
}
```

---

## Steps 3–8 — Findings

All ten finding categories evaluated below.

---

### FINDING R9-1 — R8-3 Partial Patch: `EXPECTED_FORGE_SHA=""` Silent No-Op — SHA Comparison Never Executes
**Severity:** MEDIUM (CVSS 3.1: AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:N — 6.5)
**Status:** Partially Patched from R8 — structure present, value empty, no behavioral change
**Category:** Supply Chain / Verification Theater
**Finding Category:** Cat-7 (Supply Chain)
**Round history:** R6 (not patched), R7 (not patched), R8 (partially patched), R9 (partially patched — 4th round)

**Location:** `install.sh` lines 19–20 and lines 62–71

**Evidence (verified in current file):**

```bash
# install.sh line 20:
EXPECTED_FORGE_SHA=""

# install.sh lines 62–71:
if [ -n "${EXPECTED_FORGE_SHA}" ] && [ "${FORGE_SHA}" != "UNAVAILABLE" ]; then
  if [ "${FORGE_SHA}" != "${EXPECTED_FORGE_SHA}" ]; then
    echo "[forge-plugin] ERROR: SHA-256 MISMATCH — aborting installation." >&2
    echo "[forge-plugin]   Got:      ${FORGE_SHA}" >&2
    echo "[forge-plugin]   Expected: ${EXPECTED_FORGE_SHA}" >&2
    echo "[forge-plugin]   Verify the release at: https://forgecode.dev/releases" >&2
    exit 1
  fi
  echo "[forge-plugin] SHA-256 verified against pinned hash — OK."
fi
```

The comparison block (lines 62–71) is logically correct — it would abort on hash mismatch and confirm on hash match. However, `[ -n "${EXPECTED_FORGE_SHA}" ]` evaluates `[ -n "" ]` which is false. The entire block is skipped. Execution proceeds to `sleep 5` / `bash "${FORGE_INSTALL_TMP}"` on line 75 without any comparison occurring.

**What changed since R8:**
The scaffold was added (`EXPECTED_FORGE_SHA=""`, the comparison block). The R8 report recommended using an all-zeros sentinel value (`0000000000000000000000000000000000000000000000000000000000000000`) as a visible placeholder that would at least trigger the outer `[ -n ]` check and produce a "no pinned SHA" warning. An empty string does not trigger this warning.

**Adversarial angle:**
A maintainer or security reviewer inspecting `install.sh` would see:
1. `EXPECTED_FORGE_SHA=""` — looks like a configuration point they can populate
2. The comparison block below it — looks like it performs SHA verification

The code structure implies SHA verification is partially implemented and can be activated by populating the variable. A casual reader might not check whether the guard fires. The actual behavior is indistinguishable from the pre-R8 state: the SHA is computed, logged, and ignored. The "install.sh SHA-256 MISMATCH" abort path is dead code.

**Framing gap:** install.sh has no warning message when `EXPECTED_FORGE_SHA` is empty. The user never sees "WARNING: No pinned SHA configured." The only indicator is the log comment `# Leave blank ("") to disable pinned check`. A missing warning permits silent SHA skip without any user-visible notice.

**Concrete remediation:**

Replace lines 19–20 with the all-zeros sentinel per R8 recommendation:
```bash
# R8-3: Pin the expected SHA-256 here to enable automated verification.
# Update this value when upgrading ForgeCode.
# All-zeros = no pin active (displays warning). Leave as-is until first release pin.
# (SENTINEL FINDING-R7-7/R8-3/R9-1: supply chain hardening)
EXPECTED_FORGE_SHA="0000000000000000000000000000000000000000000000000000000000000000"
```

Update the comparison block to emit a warning when the placeholder is detected:
```bash
if [ "${EXPECTED_FORGE_SHA}" = "0000000000000000000000000000000000000000000000000000000000000000" ] || [ -z "${EXPECTED_FORGE_SHA}" ]; then
  echo "[forge-plugin] WARNING: No pinned SHA-256 configured — cannot auto-verify integrity." >&2
  echo "[forge-plugin] Manually compare SHA above against: https://forgecode.dev/releases" >&2
elif [ "${FORGE_SHA}" = "UNAVAILABLE" ]; then
  echo "[forge-plugin] WARNING: SHA tool unavailable — cannot verify pinned hash." >&2
elif [ "${FORGE_SHA}" != "${EXPECTED_FORGE_SHA}" ]; then
  echo "[forge-plugin] ERROR: SHA-256 MISMATCH — aborting installation." >&2
  echo "[forge-plugin]   Got:      ${FORGE_SHA}" >&2
  echo "[forge-plugin]   Expected: ${EXPECTED_FORGE_SHA}" >&2
  rm -f "${FORGE_INSTALL_TMP}"
  exit 1
else
  echo "[forge-plugin] SHA-256 verified against pinned hash — OK."
fi
```

---

### FINDING R9-2 — R8-2 Not Patched: Non-Interactive Binary Execution Lacks Abort Gate
**Severity:** MEDIUM (CVSS 3.1: AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:N — 6.5)
**Status:** Not Patched — fourth consecutive round (R6, R7, R8, R9)
**Category:** Supply Chain / Non-Interactive Execution Context
**Finding Category:** Cat-7 (Supply Chain)

**Location:** `install.sh` lines 73–75

**Evidence (verified in current file):**
```bash
# R6-1: In non-interactive mode Ctrl+C may not be available; give a short window anyway.
sleep 5
bash "${FORGE_INSTALL_TMP}"
```

The `[ -t 1 ]` branching added in install.sh (lines 118–129) applies exclusively to the PATH modification consent block. The binary execution block (lines 73–75) has no equivalent interactive check. In the SessionStart hook context (non-interactive), the downloaded script executes unconditionally after a 5-second delay with no user-visible cancellation path.

**State of related mitigations:**
- R8-3/R9-1: SHA comparison scaffold present but empty — provides no actual gate
- R8-6: Download timeouts added — reduces availability attack surface but does not gate execution
- `SECURITY NOTE (R8-2)` in install.sh header (line 7–11): acknowledges non-interactive context and SHA log location — documentation only, no behavioral gate

**Timeline escalation note:** This finding has been MEDIUM for four consecutive rounds (R6 through R9). The remediation effort is modest (one `[ -t 1 ]` check wrapping lines 73–75). The absence of a patch after four rounds is a risk acceptance signal, but no explicit risk-acceptance comment is present in the code.

**Concrete remediation (unchanged from R8):**

Replace lines 73–75 with:
```bash
if [ -t 1 ]; then
  echo "[forge-plugin] SHA-256: ${FORGE_SHA}"
  echo "[forge-plugin] Compare against: https://forgecode.dev/releases"
  echo "[forge-plugin] Press Ctrl+C within 10 seconds to cancel. Proceeding..."
  sleep 10
  bash "${FORGE_INSTALL_TMP}"
  echo "[forge-plugin] ForgeCode installed."
else
  # Non-interactive (SessionStart hook): abort — user cannot verify SHA in real time.
  echo "[forge-plugin] NON-INTERACTIVE INSTALL ABORTED — supply-chain safety gate." >&2
  echo "[forge-plugin] SHA-256 of downloaded script: ${FORGE_SHA}" >&2
  echo "[forge-plugin] SHA logged to: ${FORGE_SHA_LOG}" >&2
  echo "[forge-plugin] To complete installation, open a terminal and run:" >&2
  echo "[forge-plugin]   bash \"${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude/plugins/sidekick}/install.sh\"" >&2
  echo "[forge-plugin] Verify SHA against: https://forgecode.dev/releases" >&2
  rm -f "${FORGE_INSTALL_TMP}"
  exit 1  # Non-zero — prevents sentinel write if hooks.json uses && (see R9-3/R8-8)
fi
```

This must be co-patched with hooks.json (see R9-3).

---

### FINDING R9-3 — R8-8 Not Patched: Sentinel Semicolon Prevents Re-Attempt After R8-2 Fix; Escalation Risk
**Severity:** INFO (standalone) → MEDIUM (when R9-2 is patched)
**CVSS 3.1:** AV:L/AC:H/PR:L/UI:N/S:U/C:N/I:N/A:L — 1.8 (standalone); escalates to 4.0 (when R9-2 patched with exit 1)
**Status:** Not Patched — second round
**Category:** Logic / Sentinel State Consistency
**Finding Category:** Cat-9 (Logic / State Management)

**Location:** `hooks/hooks.json` line 8

**Evidence (verified in current file):**
```json
"command": "test -f \"${CLAUDE_PLUGIN_ROOT}/.installed\" || (bash \"${CLAUDE_PLUGIN_ROOT}/install.sh\"; touch \"${CLAUDE_PLUGIN_ROOT}/.installed\")"
```

The `(bash ...; touch ...)` subshell uses a semicolon. The sentinel file `.installed` is written unconditionally after `install.sh` exits, regardless of exit code. If `install.sh` exits 1 (including the proposed non-interactive abort from R9-2), `.installed` is still created. On subsequent SessionStart events, the sentinel exists, so `install.sh` never runs again. ForgeCode is never installed. The user receives no ongoing notification.

**This finding is inert at INFO severity while R9-2 is not patched** — because install.sh currently exits 0 in all paths. It becomes a silent denial-of-installation bug the moment R9-2 (non-interactive abort with exit 1) is implemented.

**Concrete remediation:**

Change the semicolon to `&&` in hooks.json:
```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "test -f \"${CLAUDE_PLUGIN_ROOT}/.installed\" || (bash \"${CLAUDE_PLUGIN_ROOT}/install.sh\" && touch \"${CLAUDE_PLUGIN_ROOT}/.installed\")"
          }
        ]
      }
    ]
  }
}
```

With `&&`: sentinel is written only if install.sh exits 0. Non-interactive abort exits 1 → sentinel not written → hook retries on next session → retries until user runs install interactively. This is the desired behavior.

**Mandatory co-patch:** R9-2 and R9-3 must be implemented together. Patching R9-2 without R9-3 creates the silent sentinel bug.

---

### FINDING R9-4 — R8-1 Acknowledged-Not-Patched: `printf 'KEY_PLACEHOLDER'` Exposure Note Incorrectly Frames Issue as Unavoidable
**Severity:** LOW (CVSS 3.1: AV:L/AC:L/PR:L/UI:N/S:U/C:L/I:N/A:N — 3.3)
**Status:** Acknowledged but not fixed; note framing introduces new concern
**Category:** Credential Exposure / Bash Tool Transparency
**Finding Category:** Cat-4 (Credential Exposure)
**Round history:** R7-3 (partially patched), R8-1 (residual, note added), R9-4 (framing concern added)

**Location:** `skills/forge.md` lines 162–165 and 190–193

**Evidence (verified in current file):**

```bash
# Claude: replace KEY_PLACEHOLDER below with the actual key value, then run the full block.
OLD_HISTFILE="${HISTFILE:-}"; unset HISTFILE   # disable history for this block
KEY_TMP=$(mktemp); chmod 600 "${KEY_TMP}"
printf '%s' 'KEY_PLACEHOLDER' > "${KEY_TMP}"  # ← replace KEY_PLACEHOLDER with actual key
```

```
# NOTE (R8-1): The printf line above places KEY_PLACEHOLDER in the Claude conversation
# transcript — this is unavoidable when running via the Bash tool. Treat the conversation
# as a sensitive session and do not share it. The key is NOT stored in shell history.
```

**The framing problem:** The note states the printf exposure "is unavoidable when running via the Bash tool." This is incorrect. Two alternatives exist that do avoid the exposure:

1. **Python `input()`:** Claude executes the Python heredoc, which calls `input()` to read the key directly from the user's terminal. The key is never a Claude Bash tool argument and never appears in tool call output.
2. **User-executes-printf:** Claude stops before the printf line, instructs the user to run `printf '%s' 'ACTUAL_KEY' > "${KEY_TMP}"` in their own terminal, then continues with the Python block. The key appears only in the user's own terminal, not in Claude's tool output.

The note's "unavoidable" framing may reduce user vigilance: a user who reads the note might accept the transcript exposure as a design constraint rather than a solvable problem. If the user later discovers that Option A exists, the false framing undermines trust.

**What R8 partially patched (confirmed present):**
- `unset HISTFILE` — eliminates bash history recording
- temp-file pattern — eliminates key from environment variables visible to child processes
- Python re.match key format validation (R8-7) — catches malformed keys before credentials file write

**What remains unfixed:**
- Claude's Bash tool displays the command it executes; `printf '%s' 'sk-or-v1-REALKEY'` appears in the conversation transcript
- Key is briefly visible in process argument list during `printf` subprocess

**Concrete remediation:**

Replace the `printf '%s' 'KEY_PLACEHOLDER'` approach with Python `input()` to eliminate both R9-4 (key in transcript) and R9-5 (single-quote injection):

```bash
# ⚠️ CLAUDE STOP — DO NOT substitute any key value into this block.
# Do NOT construct a printf command with the key as an argument.
# The key will be read via Python input() — it will NOT appear in Claude's Bash tool output.
#
# Claude: run the full block below as a single Bash tool call without modification.
# The user will be prompted to paste their key at the Python input() line.
OLD_HISTFILE="${HISTFILE:-}"; unset HISTFILE; export HISTSIZE=0
KEY_TMP=$(mktemp); chmod 600 "${KEY_TMP}"

python3 << 'PYEOF'
import os, re, sys
print("Paste your OpenRouter API key and press Enter (input is not echoed to Claude): ", end='', flush=True)
key = sys.stdin.readline().strip()
if not key:
    raise ValueError("No key provided")
if not re.match(r'^[A-Za-z0-9_\-]+$', key):
    raise ValueError("Key contains unexpected characters — verify the key before proceeding")
with open(os.environ['KEY_TMP'], 'w') as f:
    f.write(key)
print("Key written to temp file.")
PYEOF

# (Continue with the main Python heredoc that reads KEY_TMP and writes credentials.json)
```

This eliminates the key from Claude's Bash tool output entirely. The key is typed or pasted by the user at the Python prompt, captured by Python's stdin read, and never appears as a shell argument.

---

### FINDING R9-5 — R8-7 Partial Patch: `printf 'KEY_PLACEHOLDER'` Shell Injection Still Possible at Command-Construction Stage
**Severity:** LOW (CVSS 3.1: AV:L/AC:H/PR:L/UI:R/S:U/C:L/I:L/A:N — 3.3)
**Status:** Partially Patched — Python validation added post-write; shell-level injection at printf stage unaddressed
**Category:** Input Validation / Shell Injection
**Finding Category:** Cat-1 (Prompt Injection / Shell Injection)

**Location:** `skills/forge.md` lines 162–165, 175–178

**Evidence (verified in current file):**

The R8-7 patch: Python validation at lines 175–178:
```python
# R8-7: Validate key format — OpenRouter keys are alphanumeric + dashes/underscores only.
# This prevents shell-special characters from causing injection if the key is malformed.
if not re.match(r'^[A-Za-z0-9_\-]+$', key):
    raise ValueError("Key contains unexpected characters — verify the key before proceeding")
```

This validation is correct and catches malformed keys before they are written to `~/forge/.credentials.json`. However, the attack surface for R8-7 is the `printf '%s' 'KEY_PLACEHOLDER'` line at line 165.

**Attack chain:**
1. User pastes a key containing a single quote character (e.g., `sk-or-v1-real'key`)
2. Claude constructs: `printf '%s' 'sk-or-v1-real'key' > "${KEY_TMP}"`
3. The shell interprets `'sk-or-v1-real'` as a complete quoted string, then `key` as an unquoted token, then a dangling `'` causing a syntax error or worse
4. Python never executes — the `ValueError` from Python validation is never reached
5. The shell error may cause partial execution of surrounding commands depending on the `set -euo pipefail` state at the time of the Bash tool invocation

**The Python validation (R8-7 patch) is defense-in-depth against credentials-write injection, not against shell command construction injection.** The two are different stages. The patch addresses stage 2 (credentials file) but not stage 1 (shell command construction).

**Concrete remediation:**

The combined fix for R9-4 and R9-5 is Python `input()` (see R9-4 hardened rewrite). By eliminating `printf '%s' 'KEY_PLACEHOLDER'` entirely, neither the key-in-transcript issue (R9-4) nor the single-quote injection issue (R9-5) can occur. The Python re.match validation (already present) handles format checking before the credentials file is written.

---

### FINDING R9-6 — R8-9 Partial Patch: Credential Block Still Missing `HISTSIZE=0` and Standalone Atomic-Execution Warning
**Severity:** INFO (CVSS 3.1: AV:L/AC:H/PR:L/UI:R/S:U/C:L/I:N/A:N — 2.0)
**Status:** Partially Patched — comment added; HISTSIZE=0 and standalone warning not added
**Category:** Credential Exposure / Shell History Edge Case
**Finding Category:** Cat-4 (Credential Exposure)

**Location:** `skills/forge.md` lines 163, 187–188

**Evidence (verified in current file):**

The R8-9 partial patch:
```bash
# R8-9: Restore HISTFILE — only works correctly when the full block above runs atomically
# in a single Bash tool call. If the block is split across calls, HISTFILE stays unset.
```

Comment acknowledges the atomic-execution requirement. However:

1. Line 163 still reads: `OLD_HISTFILE="${HISTFILE:-}"; unset HISTFILE` — no `HISTSIZE=0`
2. No standalone `⚠️ EXECUTE THIS ENTIRE BLOCK AS A SINGLE COMMAND` warning before the block header
3. `HISTSIZE=0` was the recommended in-memory history clear that prevents `history` command from showing the key even when `HISTFILE` is unset

**Impact:** Low — if Claude sends the entire block as a single Bash tool call, `unset HISTFILE` works correctly. The in-memory history (`history` command) may retain the key-containing printf command for the duration of the shell subprocess's lifetime, but this subprocess is ephemeral.

**Concrete remediation:**

Change line 163 from:
```bash
OLD_HISTFILE="${HISTFILE:-}"; unset HISTFILE   # disable history for this block
```
To:
```bash
# ⚠️ EXECUTE THIS ENTIRE BLOCK AS ONE BASH TOOL CALL — splitting breaks the HISTFILE guard.
OLD_HISTFILE="${HISTFILE:-}"; OLD_HISTSIZE="${HISTSIZE:-}"; unset HISTFILE; export HISTSIZE=0
```

And change the restore line (currently at line 189):
```bash
[ -n "${OLD_HISTFILE}" ] && export HISTFILE="${OLD_HISTFILE}"; unset OLD_HISTFILE
```
To:
```bash
[ -n "${OLD_HISTFILE}" ] && export HISTFILE="${OLD_HISTFILE}"; unset OLD_HISTFILE
[ -n "${OLD_HISTSIZE}" ] && export HISTSIZE="${OLD_HISTSIZE}"; unset OLD_HISTSIZE
```

Note: if R9-4's Python `input()` fix is implemented, the HISTFILE/HISTSIZE guard becomes less critical (no key in shell args), but defense-in-depth warrants keeping it.

---

### FINDING R9-7 — R8-4 Partial Patch: `_integrity` Fields in plugin.json Are Empty Strings; marketplace.json Still Has No Integrity Fields
**Severity:** LOW (CVSS 3.1: AV:N/AC:H/PR:N/UI:R/S:U/C:H/I:H/A:N — 6.8)
**Status:** Partially Patched — schema present, values empty; marketplace.json unchanged
**Category:** Supply Chain / Manifest Integrity
**Finding Category:** Cat-7 (Supply Chain)
**Round history:** R6 (not patched), R7 (not patched), R8 (partially patched), R9 (partially patched — 4th round)

**Location:** `.claude-plugin/plugin.json` lines 22–28; `.claude-plugin/marketplace.json`

**Evidence (verified in current file):**

plugin.json:
```json
"_integrity": {
  "_note": "R8-4: Pin the SHA-256 of install.sh below and update on each release to enable integrity verification. Leave blank to use display-only SHA logging. (SENTINEL FINDING-R8-4)",
  "install_sh_sha256": "",
  "forge_md_sha256": "",
  "verify_at": "https://forgecode.dev/releases",
  "source": "https://github.com/alo-exp/sidekick"
}
```

marketplace.json: no integrity fields of any kind.

Both `install_sh_sha256` and `forge_md_sha256` are empty strings. A tooling check that reads these fields for verification would find no hash to compare against. The `_note` field correctly documents the intent but the values remain unpopulated in their fourth consecutive audit round.

**Current file SHA-256 values (computed for reference):**
```
install.sh:       (to be computed by maintainer: shasum -a 256 install.sh)
skills/forge.md:  (to be computed by maintainer: shasum -a 256 skills/forge.md)
hooks/hooks.json: (to be computed by maintainer: shasum -a 256 hooks/hooks.json)
```

**Concrete remediation:**

1. Compute SHA-256s of current files and populate the fields in plugin.json:
   ```bash
   shasum -a 256 install.sh skills/forge.md hooks/hooks.json .claude-plugin/plugin.json
   ```
2. Add the same structure to marketplace.json.
3. Add a pre-commit or release script that recomputes and updates these values.
4. The Claude plugin runtime currently does not enforce these fields — they serve as a manual audit aid and tamper-detection signal rather than an automated gate.

---

### FINDING R9-8 — NEW: forge.md Manual Install Blocks Omit Reference to `EXPECTED_FORGE_SHA` Mechanism
**Severity:** INFO (CVSS 3.1: AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:N/A:N — 2.6)
**Status:** New
**Category:** Supply Chain / Documentation Gap
**Finding Category:** Cat-7 (Supply Chain)

**Location:** `skills/forge.md` STEP 0A-1 (lines 60–113) — all three manual install blocks

**Evidence:**

The three manual install code blocks in STEP 0A-1 (primary curl path, wget fallback, verbose fallback) all follow the same pattern:
1. Download to temp file
2. Compute and display SHA-256
3. Print "Compare this SHA-256 against the official release hash at: https://forgecode.dev/releases"
4. "If hashes do not match, press Ctrl+C NOW. Proceeding in 5 seconds..."
5. `sleep 5; bash "${FORGE_INSTALL}"` or `bash -x "${FORGE_INSTALL}"`

None of these blocks reference the `EXPECTED_FORGE_SHA` mechanism that now exists in `install.sh`. A user following the manual install path (i.e., running the code blocks from forge.md directly, not via install.sh) has:
- No automated hash comparison
- No `EXPECTED_FORGE_SHA` variable
- Only a manual "compare the SHA and press Ctrl+C" instruction

This creates a divergence: `install.sh` has a SHA comparison scaffold (even if currently a no-op); `forge.md` manual install blocks have no such scaffold and rely entirely on human manual verification with a 5-second window.

When `EXPECTED_FORGE_SHA` is eventually populated in install.sh with a real hash, the forge.md manual install blocks will lag behind — they will continue to operate in display-only mode.

**Concrete remediation:**

Update each of the three manual install blocks in STEP 0A-1 to include the `EXPECTED_FORGE_SHA` check, matching install.sh's current scaffold:

```bash
FORGE_INSTALL=$(mktemp /tmp/forge-install.XXXXXX.sh)
curl -fsSL --max-time 60 --connect-timeout 15 https://forgecode.dev/cli -o "${FORGE_INSTALL}"
FORGE_SHA=$(shasum -a 256 "${FORGE_INSTALL}" 2>/dev/null | awk '{print $1}' || sha256sum "${FORGE_INSTALL}" | awk '{print $1}')
# Pinned SHA — update this value on each ForgeCode release.
# Compare against install.sh's EXPECTED_FORGE_SHA; set to "" to disable automatic check.
EXPECTED_FORGE_SHA=""
echo "SHA-256: ${FORGE_SHA}"
if [ -n "${EXPECTED_FORGE_SHA}" ] && [ "${FORGE_SHA}" != "${EXPECTED_FORGE_SHA}" ]; then
  echo "ERROR: SHA-256 mismatch — aborting. Expected: ${EXPECTED_FORGE_SHA}" >&2
  rm -f "${FORGE_INSTALL}"; false
fi
echo "IMPORTANT: Compare this SHA-256 against the official release hash at:"
echo "  https://forgecode.dev/releases"
# NOTE for Claude: Show the SHA-256 output and ask for explicit user confirmation before proceeding.
```

---

### FINDING R9-9 — NEW: `install.sh` Emits No Warning When `EXPECTED_FORGE_SHA` Is Empty — Silent Skip Is Invisible
**Severity:** INFO (CVSS 3.1: AV:L/AC:L/PR:N/UI:R/S:U/C:N/I:N/A:N — 2.0)
**Status:** New
**Category:** Supply Chain / Missing Warning on No-Op Configuration
**Finding Category:** Cat-7 (Supply Chain)

**Location:** `install.sh` lines 19–20, 62–71

**Evidence:**

When `EXPECTED_FORGE_SHA=""`, the guard `[ -n "${EXPECTED_FORGE_SHA}" ]` is false, the comparison block is skipped, and no message is emitted to indicate that hash verification is inactive. The install log will show:
```
[forge-plugin] Install script SHA-256: <hash>
[forge-plugin] IMPORTANT: Compare this hash against the official release at:
[forge-plugin]   https://forgecode.dev/releases  (or GitHub releases page)
[forge-plugin] If hashes do not match, delete /tmp/forge-install.XXXXXX.sh and abort.
[forge-plugin] SHA logged to: ~/.local/share/forge-plugin-install-sha.log
[forge-plugin] SHA-256 verified against pinned hash — OK.  ← THIS LINE IS ABSENT
```
The "verified" success message is never printed (correct), but neither is a "no pin active — manual verification required" warning (the gap). A system administrator reviewing install logs cannot distinguish between "SHA verified automatically" and "SHA skipped (no pin configured)."

This is a minor gap distinct from R9-1 in that it concerns the absence of a machine-readable status signal in the install log, not just the human-facing display.

**Concrete remediation:**

Add an explicit "no pin active" branch to the comparison block (this is the same change recommended in R9-1):
```bash
if [ -z "${EXPECTED_FORGE_SHA}" ]; then
  echo "[forge-plugin] WARNING: EXPECTED_FORGE_SHA not set — skipping automatic hash verification." >&2
  echo "[forge-plugin] Manually compare SHA above against: https://forgecode.dev/releases" >&2
fi
```

---

### FINDING R9-10 — CATEGORY SWEEP: All Ten Finding Categories Evaluated
**Severity:** N/A (sweep confirmation)
**Status:** N/A
**Category:** Audit Completeness

**Cat-1 (Prompt Injection / Shell Injection):** R9-5 (printf single-quote injection at command-construction stage) is active at LOW. Python validation (R8-7 partial patch) addresses credentials-write stage but not shell-construction stage. No new surface beyond R9-5.

**Cat-2 (Path Traversal / Directory Injection):** All `forge -C "${PROJECT_ROOT}"` invocations use correctly quoted variable expansion. `PROJECT_ROOT` derived from `git rev-parse --show-toplevel || echo "${PWD}"` — safe. `add_to_path` uses `realpath` for symlink resolution. No unquoted path variables found. **CLEAN.**

**Cat-3 (Privilege Escalation):** No `sudo`, `su`, `chmod +s`, setuid, or capability operations. `chmod 600` on credentials file is appropriate and correct. No unexpected privilege escalation vectors. **CLEAN.**

**Cat-4 (Credential Exposure):** R9-4 (printf key in transcript — acknowledged not fixed; note incorrectly frames as unavoidable) and R9-6 (HISTSIZE=0 absent) are active. `chmod 600` on credentials file confirmed present. Python re.match format validation confirmed present. Key read via temp file (no env variable exposure to child processes). Remaining risks scoped to Claude session transcript.

**Cat-5 (Prompt Injection via External Content):** AGENTS.md trust gate confirmed at STEP 2 — mandatory wrapper block, sandbox-first for untrusted repos on both initial bootstrap and stale-update paths, user-review-before-delegation requirement, "NON-NEGOTIABLE" designation. No regressions found. Extended scope to "ALL external file content (AGENTS.md, README, config files, error messages from third-party tools)" confirmed present. **CLEAN.**

**Cat-6 (Destructive Operation Gates):** `git checkout -- .` MANDATORY STOP block confirmed in STEP 5-4 and referenced in STEP 9 Quick Reference (commented out with mandatory stop notice). `git reset --hard HEAD~1` in STEP 7-7 has `⚠️ CAUTION — confirm with user before running` annotation. Scoped `git checkout -- PATH/TO/FILE` (safer alternative) is the recommended recovery path. No new destructive operation gaps found. **CLEAN.**

**Cat-7 (Supply Chain):** Active findings: R9-1 (SHA comparison scaffold — empty value, no behavioral change; MEDIUM), R9-2 (non-interactive binary execution without abort gate; MEDIUM, 4th round), R9-7 (integrity fields in plugin.json empty, marketplace.json still missing; LOW, 4th round), R9-8 (manual install blocks omit EXPECTED_FORGE_SHA reference; INFO), R9-9 (no warning when EXPECTED_FORGE_SHA is empty; INFO). Supply chain is the primary unresolved risk area.

**Cat-8 (Privacy):** R8-5 confirmed PATCHED — `$schema` disclosure comment present at forge.md lines 196–198. Privacy note in STEP 0A-3 (line 218–224) confirmed present for forge binary telemetry. Sandbox scope clarification (API calls still reach provider during sandboxed runs) confirmed at STEP 4. **CLEAN post-R8-5 patch.**

**Cat-9 (Logic / State Management):** R9-3 (sentinel semicolon in hooks.json) active at INFO standalone, escalates to MEDIUM when R9-2 is patched. No other logic state issues found.

**Cat-10 (Transparency / User Consent):** R9-4 framing concern: note at forge.md line 190 states printf exposure "is unavoidable" — technically incorrect. Pre-consent notice in install.sh (lines 117–129) with interactive/non-interactive branching confirmed present. Marker comments in shell profiles present. First-run notice in forge.md STEP 0 header confirmed present. SHA log path disclosed in install.sh output. **Minor framing concern in R9-4; otherwise CLEAN.**

---

## Executive Summary

### R8 Patch Verification Status

| R8 Finding | Description | R9 Verdict |
|---|---|---|
| R8-1 | `printf 'KEY_PLACEHOLDER'` exposes key in Bash tool output | **ACKNOWLEDGED, NOT PATCHED** — note added framing exposure as "unavoidable" (incorrect); neither Option A nor B implemented |
| R8-2 | Non-interactive binary install lacks abort gate | **NOT PATCHED** — `sleep 5; bash` unchanged (4th round) |
| R8-3 | SHA-256 verification display-only, no pinned hash comparison | **PARTIALLY PATCHED** — `EXPECTED_FORGE_SHA=""` scaffold present; empty string = comparison block never executes; all-zeros placeholder not used; no "no pin active" warning |
| R8-4 | No cryptographic integrity fields in manifests | **PARTIALLY PATCHED** — `_integrity` object with empty hash fields in plugin.json; marketplace.json unchanged |
| R8-5 | `$schema` URL in .forge.toml lacks disclosure comment | **PATCHED** — comment confirmed at forge.md lines 196–198 |
| R8-6 | Download has no timeout — indefinite hang | **PATCHED** — `--max-time 60 --connect-timeout 15` confirmed in install.sh lines 35 and 37 |
| R8-7 | `KEY_PLACEHOLDER` single-quote pattern — shell injection on malformed keys | **PARTIALLY PATCHED** — Python re.match validation at credentials-write stage; printf-stage construction injection unaddressed |
| R8-8 | Sentinel semicolon prevents re-attempt after non-interactive abort fix | **NOT PATCHED** — semicolon unchanged in hooks.json |
| R8-9 | HISTFILE unset assumes atomic block execution | **PARTIALLY PATCHED** — comment added at lines 187–188; HISTSIZE=0 not added; standalone atomic-execution warning not added |

**R8 patch rate: 2/9 fully patched (R8-5, R8-6), 4/9 partially patched (R8-3, R8-4, R8-7, R8-9), 3/9 not patched (R8-1, R8-2, R8-8).**

---

### CVSS Score Table — All R9 Findings

| Finding ID | Title | Severity | CVSS 3.1 Score | Status |
|---|---|---|---|---|
| R9-1 | R8-3 partial: `EXPECTED_FORGE_SHA=""` — comparison block never executes; no "no pin active" warning | MEDIUM | 6.5 | Partially Patched (4th round) |
| R9-2 | R8-2 not patched: non-interactive binary install lacks abort gate | MEDIUM | 6.5 | Not Patched (4th round) |
| R9-3 | R8-8 not patched: sentinel semicolon prevents re-attempt after non-interactive abort fix | INFO→MEDIUM | 1.8 (4.0 when R9-2 patched) | Not Patched (2nd round) — must co-patch with R9-2 |
| R9-4 | R8-1 acknowledged-not-patched: `printf 'KEY_PLACEHOLDER'` transcript exposure; framing note incorrect | LOW | 3.3 | Acknowledged, Not Fixed (3rd round) |
| R9-5 | R8-7 partial: printf single-quote injection at command-construction stage unaddressed | LOW | 3.3 | Partially Patched (2nd round) |
| R9-6 | R8-9 partial: `HISTSIZE=0` absent; standalone atomic-execution warning absent | INFO | 2.0 | Partially Patched (2nd round) |
| R9-7 | R8-4 partial: plugin.json integrity hash values empty; marketplace.json unchanged | LOW | 6.8† | Partially Patched (4th round) |
| R9-8 | NEW: forge.md manual install blocks omit `EXPECTED_FORGE_SHA` reference | INFO | 2.6 | New |
| R9-9 | NEW: install.sh emits no warning when `EXPECTED_FORGE_SHA` is empty — silent skip | INFO | 2.0 | New |
| R9-10 | Category sweep: Cat-2, Cat-3, Cat-5, Cat-6, Cat-8 confirmed clean | — | — | Clean |

†R9-7 retains high CVSS base score but LOW practical impact given no runtime enforcement of the field.

**Round summary:** No Critical findings. Two Medium (R9-1, R9-2 — both are 4th-round persistences), two Low (R9-4, R9-5, R9-7), four Info (R9-3, R9-6, R9-8, R9-9). One category-sweep clean confirmation (R9-10).

---

### Priority Order for Remediation

1. **R9-2 + R9-3 (co-patch, MEDIUM + INFO→MEDIUM, 4th round)** — Implement `[ -t 1 ]` gate on binary execution in install.sh AND change hooks.json semicolon to `&&`. These must be implemented together. Estimated effort: ~10 lines in install.sh + 1 character change in hooks.json. This is the most impactful unresolved finding and has been carried for four rounds.

2. **R9-1 (MEDIUM, 4th round)** — Change `EXPECTED_FORGE_SHA=""` to all-zeros sentinel and add "no pin active" warning when empty/all-zeros. Estimated effort: ~5 lines in install.sh. Unlocks the existing (but currently dead) SHA comparison code.

3. **R9-4 + R9-5 (combined, LOW, 3rd/2nd round)** — Replace `printf '%s' 'KEY_PLACEHOLDER'` with Python `input()` pattern. Eliminates key-in-transcript and single-quote injection in a single change. Estimated effort: ~15 lines in forge.md.

4. **R9-8 (INFO, NEW)** — Update three manual install blocks in forge.md to include `EXPECTED_FORGE_SHA` check pattern. Estimated effort: ~10 lines per block.

5. **R9-9 (INFO, NEW)** — Add "no pin active" warning to install.sh when `EXPECTED_FORGE_SHA` is empty. Estimated effort: ~3 lines. Can be combined with R9-1.

6. **R9-7 (LOW, 4th round)** — Populate actual SHA-256 hash values in plugin.json; add integrity fields to marketplace.json. Estimated effort: one-time computation + update; add to release checklist.

7. **R9-6 (INFO, 2nd round)** — Add `HISTSIZE=0` and standalone atomic-execution warning. Estimated effort: ~3 lines. Moot if R9-4 is implemented (Python input() bypasses the issue).

---

## Hardened Rewrite Recommendations

### R9-2 + R9-3: Non-Interactive Gate + Sentinel Co-Patch (install.sh + hooks.json)

**install.sh** — replace lines 73–75:

```bash
# Non-interactive gate: abort in SessionStart hook context; require interactive verification.
# (SENTINEL FINDING-R6-1/R7-2/R8-2/R9-2: non-interactive supply-chain gate)
if [ -t 1 ]; then
  echo "[forge-plugin] SHA-256: ${FORGE_SHA}"
  echo "[forge-plugin] Compare against: https://forgecode.dev/releases"
  echo "[forge-plugin] Press Ctrl+C within 10 seconds to cancel. Proceeding..."
  sleep 10
  bash "${FORGE_INSTALL_TMP}"
  echo "[forge-plugin] ForgeCode installed."
else
  echo "[forge-plugin] NON-INTERACTIVE INSTALL ABORTED — supply-chain safety gate." >&2
  echo "[forge-plugin] SHA-256 of downloaded script: ${FORGE_SHA}" >&2
  echo "[forge-plugin] SHA logged to: ${FORGE_SHA_LOG}" >&2
  echo "[forge-plugin] To complete installation, open a terminal and run:" >&2
  echo "[forge-plugin]   bash \"${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude/plugins/sidekick}/install.sh\"" >&2
  echo "[forge-plugin] Verify SHA against: https://forgecode.dev/releases" >&2
  rm -f "${FORGE_INSTALL_TMP}"
  exit 1  # Non-zero: sentinel NOT written (requires && in hooks.json — see R9-3)
fi
```

**hooks/hooks.json** — change semicolon to `&&`:
```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "test -f \"${CLAUDE_PLUGIN_ROOT}/.installed\" || (bash \"${CLAUDE_PLUGIN_ROOT}/install.sh\" && touch \"${CLAUDE_PLUGIN_ROOT}/.installed\")"
          }
        ]
      }
    ]
  }
}
```

Result: non-interactive abort exits 1 → sentinel not written → hook retries on next session → repeats until user runs install.sh in a terminal interactively.

---

### R9-1 + R9-9: SHA Pinning Scaffold with Visible No-Pin Warning (install.sh)

Replace lines 19–20 and the comparison block (lines 62–71):

```bash
# R8-3/R9-1: Pin the expected SHA-256 here to enable automated verification.
# Update this value when upgrading ForgeCode. Obtain from: https://forgecode.dev/releases
# All-zeros sentinel = no pin active (warning emitted but not aborting).
# Empty string "" is treated the same as all-zeros.
# (SENTINEL FINDING-R7-7/R8-3/R9-1: supply chain hardening)
EXPECTED_FORGE_SHA="0000000000000000000000000000000000000000000000000000000000000000"

# ... (SHA computation block unchanged) ...

# SHA verification gate
_ALLZEROS="0000000000000000000000000000000000000000000000000000000000000000"
if [ -z "${EXPECTED_FORGE_SHA}" ] || [ "${EXPECTED_FORGE_SHA}" = "${_ALLZEROS}" ]; then
  echo "[forge-plugin] WARNING: No pinned SHA-256 configured — automatic integrity check inactive." >&2
  echo "[forge-plugin] Manually compare the SHA above against: https://forgecode.dev/releases" >&2
elif [ "${FORGE_SHA}" = "UNAVAILABLE" ]; then
  echo "[forge-plugin] WARNING: SHA tool unavailable — cannot verify against pinned hash." >&2
  echo "[forge-plugin] Manually verify the download before proceeding." >&2
elif [ "${FORGE_SHA}" != "${EXPECTED_FORGE_SHA}" ]; then
  echo "[forge-plugin] ERROR: SHA-256 MISMATCH — aborting installation." >&2
  echo "[forge-plugin]   Got:      ${FORGE_SHA}" >&2
  echo "[forge-plugin]   Expected: ${EXPECTED_FORGE_SHA}" >&2
  echo "[forge-plugin] Do NOT proceed. Verify forgecode.dev release integrity." >&2
  rm -f "${FORGE_INSTALL_TMP}"
  exit 1
else
  echo "[forge-plugin] SHA-256 verified against pinned value — OK."
fi
unset _ALLZEROS
```

---

### R9-4 + R9-5: Replace `printf 'KEY_PLACEHOLDER'` with Python `input()` (forge.md)

Replace the current credential write block (lines 153–210) with:

```bash
**When the user pastes the key** — write credentials atomically:
```bash
# ⚠️ CLAUDE STOP — DO NOT substitute any key value into this block.
# Do NOT construct or execute a printf command with the key as an argument.
# The key will be read via Python stdin — it will NOT appear in Claude's Bash tool output.
# Run the ENTIRE block below as ONE Bash tool call.
# (SENTINEL FINDING-R7-3/R8-1/R8-7/R9-4/R9-5: key-in-transcript + injection hardening)
FORGE_DIR="${HOME}/forge"
mkdir -p "${FORGE_DIR}"
OLD_HISTFILE="${HISTFILE:-}"; OLD_HISTSIZE="${HISTSIZE:-}"; unset HISTFILE; export HISTSIZE=0
KEY_TMP=$(mktemp); chmod 600 "${KEY_TMP}"

python3 << 'PYEOF'
import json, os, re, stat, sys

# Read key via stdin — key is never a shell argument and never appears in Claude's output.
print("Paste your OpenRouter API key and press Enter: ", end='', flush=True)
key = sys.stdin.readline().strip()
if not key:
    raise ValueError("No key provided — re-run this block and paste the key at the prompt")
os.remove(os.environ['KEY_TMP'])  # remove original empty temp; we write creds directly

# Validate key format: OpenRouter keys are alphanumeric + dashes/underscores only.
if not re.match(r'^[A-Za-z0-9_\-]+$', key):
    raise ValueError("Key contains unexpected characters — verify the key before proceeding")

creds = [{'id': 'open_router', 'auth_details': {'api_key': key}}]
path = os.path.expanduser('~/forge/.credentials.json')
with open(path, 'w') as f:
    json.dump(creds, f, indent=2)
os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
print('Credentials written with restricted permissions (600).')
PYEOF

unset KEY_TMP
[ -n "${OLD_HISTFILE}" ] && export HISTFILE="${OLD_HISTFILE}"; unset OLD_HISTFILE
[ -n "${OLD_HISTSIZE}" ] && export HISTSIZE="${OLD_HISTSIZE}"; unset OLD_HISTSIZE
```

This eliminates both the key-in-transcript exposure (R9-4) and the single-quote shell injection risk (R9-5) by reading the key through Python's stdin rather than constructing a shell command with the key as an argument.

---

## Audit Integrity Self-Challenge (Step 8 Gate)

**Challenge 1: Are any previously-open findings being over-credited as patched?**
R8-5 (schema comment): text confirmed at forge.md lines 196–198. R8-6 (download timeouts): confirmed at install.sh lines 35 and 37. Both correctly credited as PATCHED. No over-crediting detected.

**Challenge 2: Are the "partially patched" ratings accurate?**
R8-3→R9-1: EXPECTED_FORGE_SHA="" confirmed; `[ -n "" ]` is false, block never executes. Partial patch rating is accurate — the structure is correct but operationally inert. R8-7→R9-5: Python re.match confirmed at lines 175–178; printf pattern at line 165 unchanged. Partial patch rating accurate. R8-4→R9-7: empty string hash fields confirmed in plugin.json. Partial patch rating accurate.

**Challenge 3: Are there any false negatives in the clean categories?**
Cat-2: `PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")` — both branches produce safe values; no injection surface. Cat-5: AGENTS.md trust gate is present, labeled NON-NEGOTIABLE, and enforced at three points (bootstrap, stale-update, delegation). Sandbox-first confirmed for both paths. No bypass path found. Cat-6: `git checkout -- .` removal confirmed in Quick Reference (line 864 shows commented-out form with mandatory stop reference, not an executable bare command). No new destructive ops found. All three clean verdicts are substantiated.

**Challenge 4: Does the R8-8/R9-3 escalation framing hold?**
hooks.json line 8 confirmed as `; touch` (semicolon). install.sh currently exits 0 in all paths (no `exit 1` in non-interactive path). R9-3 is correctly rated INFO at current state and would escalate if R9-2 is patched without co-patching R9-3. The conditional escalation framing is accurate.

**Challenge 5: Are there any new surfaces in the 874-line forge.md not previously audited?**
STEP 9 Quick Reference (lines 843–873): reviewed. The sandbox trust qualifiers (R7-9 patch) confirmed. `git checkout -- .` MANDATORY STOP reference confirmed. `forge workspace sync` trust qualifier confirmed. No new unguarded destructive commands found. No new prompt injection vectors in the Quick Reference block. No new credential handling surfaces beyond the already-documented KEY_PLACEHOLDER pattern.

---

*SENTINEL v2.3 — Round 9 complete. Audit date: 2026-04-12.*
*Next audit should focus on: resolving R9-2+R9-3 co-patch (4th-round MEDIUM persistence), operationalizing R9-1 EXPECTED_FORGE_SHA, and implementing R9-4+R9-5 Python input() combined fix.*

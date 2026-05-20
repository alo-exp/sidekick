# SENTINEL v2.3 — Security Audit Report
## Target: forge skill (sidekick plugin v1.0.0)
## Round: 8 (R7 Patch Verification + Full New-Surface Audit)
## Date: 2026-04-12
## Auditor: SENTINEL v2.3 (dual-mode: Defensive + Adversarial)
## Prior Rounds: R1–R7; R8 verifies all R7 patches and conducts full new-surface audit

---

## Step 0 — Decode Manifest / File Inventory

| File | Lines (current) | Role |
|---|---|---|
| `skills/forge.md` | 862 | Claude orchestration protocol, runtime skill instructions |
| `install.sh` | 129 | Binary installer and PATH modifier, executed via SessionStart hook |
| `hooks/hooks.json` | 14 | SessionStart hook definition |
| `.claude-plugin/plugin.json` | 23 | Plugin manifest |
| `.claude-plugin/marketplace.json` | 28 | Marketplace listing metadata |

### Manifest Decode

**plugin.json declares:**
- Name: `sidekick`, Version: `1.0.0`, License: MIT
- Author: Ālo Labs (`https://alolabs.dev`)
- Repository: `https://github.com/alo-exp/sidekick`
- Skills path: `./skills/`
- `_integrity_note`: informational only — references SHA-256 verification against `https://forgecode.dev/releases`; no cryptographic hash field present

**marketplace.json declares:**
- Source: `https://github.com/alo-exp/sidekick.git` (URL-sourced plugin)
- Version `1.0.0`; no integrity fields; no hash-of-hashes

**hooks.json declares:**
- One hook: `SessionStart`
- Command: `test -f "${CLAUDE_PLUGIN_ROOT}/.installed" || (bash "${CLAUDE_PLUGIN_ROOT}/install.sh"; touch "${CLAUDE_PLUGIN_ROOT}/.installed")`
- Sentinel-gated: runs install once per system, not on every session start
- Semicolon operator (not `&&`): sentinel written unconditionally even if install fails

**install.sh declares:**
- `set -euo pipefail`, `trap` cleanup of temp file on exit
- Downloads `https://forgecode.dev/cli` via curl or wget to a temp file
- SHA-256 computed and logged to `~/.local/share/forge-plugin-install-sha.log`
- No comparison against pinned/embedded expected hash
- `sleep 5` + `bash "${FORGE_INSTALL_TMP}"` — executes without interactive gate in non-interactive path
- Binary placed at `~/.local/bin/forge`
- `add_to_path` function appends PATH modification with marker comment
- Symlink check and ownership check present in `add_to_path`
- Binary identity check present post-install (version string regex)
- Pre-consent notice present with `[ -t 1 ]` branching (interactive vs. non-interactive)

**forge.md declares:**
- Credential write pattern: `KEY_PLACEHOLDER` in `printf '%s' 'KEY_PLACEHOLDER' > "${KEY_TMP}"` — Claude is instructed to substitute the actual key here before executing
- `unset HISTFILE` block present before credential write
- Trust gate (AGENTS.md), sandbox guidance, MANDATORY STOP blocks, SHA-256 display-only checks
- Quick Reference (STEP 9): `git checkout -- .` commented out with MANDATORY STOP reference (patched); `forge workspace sync` has trust qualifier comment (patched)

---

## Step 1 — Environment and Metadata Audit

### 1A. Execution Surfaces (complete enumeration)

1. `SessionStart` hook → `install.sh` → external network fetch → `bash` execution of downloaded script
2. `forge.md` instruction surface → Claude reads skill and executes embedded shell commands
3. Credential write: `KEY_PLACEHOLDER` substitution in `printf '%s' 'KEY_PLACEHOLDER' > "${KEY_TMP}"` — key value embedded in a `printf` command argument
4. Shell profile modification (`~/.zshrc`, `~/.bashrc`, `~/.bash_profile`)
5. `forge` binary at `~/.local/bin/forge` — third-party binary with persistent system presence
6. Forge prompt construction pipeline — user input, AGENTS.md, external file content embedded in forge prompts
7. `~/forge/.forge.toml` — config with `$schema` URL reference to `https://forgecode.dev/schema.json`
8. STEP 9 Quick Reference block — standalone command listing Claude may copy-execute verbatim
9. Three manual install code blocks in STEP 0A-1 (primary curl path, wget fallback, verbose fallback)
10. `install.sh` `add_to_path` function — shell profile append with symlink and ownership checks
11. Binary identity check at install.sh lines 115–126

### 1B. Trust Boundaries

| Boundary | Trust Level | Notes |
|---|---|---|
| Plugin publisher (Ālo Labs) → user | Implicit on install | GitHub repo; no commit signing enforced |
| `forgecode.dev` → binary/install script delivery | External, TLS only | No pinned certificate, no published signature, no embedded expected hash |
| `openrouter.ai` → API credential target | External | Credentials stored in `~/forge/.credentials.json` (chmod 600) |
| forge binary runtime → AI-directed shell execution | Highest privilege | Executes arbitrary commands based on AI output |
| AGENTS.md from arbitrary repos → forge prompts | Untrusted | Prompt injection vector; mandatory wrapper gate present |
| `$schema` URL in `.forge.toml` → `forgecode.dev` | External reference | Fetched by schema-aware editors at config-open time |
| `KEY_PLACEHOLDER` substitution → Claude command construction | High sensitivity | Key value embedded in `printf` argument by Claude before execution |

### 1B (tool audit). Tools / Binaries Invoked by Plugin

| Tool | Where Invoked | Validation Present? |
|---|---|---|
| `curl` / `wget` | `install.sh` lines 22–25; `forge.md` multiple | TLS only — no cert pin, no pinned hash |
| `bash` | `install.sh` line 50 (executes downloaded script) | SHA-256 displayed and logged; `sleep 5`; no abort in non-interactive path |
| `python3` | `forge.md` lines 167–181 (credentials), lines 689–693 (key read) | Heredoc avoids key in process args; key read from temp file |
| `printf` | `forge.md` line 165 (writes key to temp file) | `KEY_PLACEHOLDER` substituted by Claude — key appears in Bash tool command construction |
| `git` | `forge.md` multiple recovery flows | `git checkout -- .` guarded in §5-4 and §9 Quick Reference |
| `shasum` / `sha256sum` | `install.sh` lines 31–38; `forge.md` install blocks | Availability check with fallback present in install.sh; no comparison against pinned hash |
| `forge` binary | `forge.md` throughout | Version identity check present at install.sh lines 115–126 |
| `stat` | `install.sh` `add_to_path` (lines 80–84) | Cross-platform stat with fallback; ownership check present |

---

## Step 2 — Recon Notes

```
recon_notes {
  target          : forge/sidekick plugin v1.0.0
  audit_round     : 8
  prior_rounds    : R1-R7
  files_audited   : 5 (forge.md 862 lines, install.sh 129 lines,
                       hooks.json 14 lines, plugin.json 23 lines,
                       marketplace.json 28 lines)

  r7_patches_verified : {
    R7-1  : PATCHED — NOTE comment added to wget fallback block (lines 89-91)
            AND verbose fallback block (lines 108-110). Both blocks now carry:
            "NOTE for Claude: When executing via the Bash tool, the user cannot
            send Ctrl+C. Show the SHA-256 output to the user and ask for explicit
            confirmation before proceeding. (SENTINEL FINDING-R7-1/R7-7)"
            All three install paths now have the Bash tool cancel caveat. CONFIRMED.

    R7-2  : NOT PATCHED — install.sh lines 48-50 still read:
            "# R6-1: In non-interactive mode Ctrl+C may not be available; give a
            short window anyway."
            "sleep 5"
            "bash "${FORGE_INSTALL_TMP}""
            The recommended Option A (abort in non-interactive path, require
            interactive re-run) was not implemented. The `[ -t 1 ]` branching
            added is for the PATH-modification consent block (lines 93-104), NOT
            for the binary execution block. In the SessionStart hook context, the
            binary is still downloaded and executed without any interactive gate.
            RESIDUAL — MEDIUM.

    R7-3  : PARTIALLY PATCHED — significant improvement but new residual introduced.
            The `export OPENROUTER_KEY="KEY"` pattern is GONE. The new pattern is:
              KEY_TMP=$(mktemp); chmod 600 "${KEY_TMP}"
              printf '%s' 'KEY_PLACEHOLDER' > "${KEY_TMP}"  # ← replace KEY_PLACEHOLDER
            This replaces the direct env-variable-with-literal-key pattern with a
            temp-file write. The `unset HISTFILE` block is present and correct.
            HOWEVER: Claude is instructed (line 162) to "replace KEY_PLACEHOLDER
            below with the actual key value, then run the full block." When Claude
            does this, it constructs and executes:
              printf '%s' 'sk-or-v1-ACTUALKEY' > "${KEY_TMP}"
            The actual key value appears in the Bash tool command argument, which:
              (a) is visible in the Claude session transcript
              (b) may appear in Claude API request/response logs
              (c) appears in the argument list of the printf process (briefly)
            The shell history exposure is mitigated by `unset HISTFILE`. The
            process-list and Claude-transcript exposures remain. This is a
            meaningful improvement over R7 but not a full fix. New finding R8-1
            documents the residual. PARTIALLY PATCHED — LOW (downgraded from
            MEDIUM due to HISTFILE mitigation and temp-file pattern).

    R7-4  : PATCHED — STEP 9 Quick Reference lines 850-852 now read:
            "# 🛑 MANDATORY STOP: git checkout -- . discards ALL uncommitted
            changes permanently. Show user the file list (git status) and get
            explicit confirmation before running. See STEP 5-4 for the full
            mandatory-stop protocol. (SENTINEL FINDING-R7-4)"
            The bare `git checkout -- .` command is no longer present in Quick
            Reference. Only `git checkout -- PATH/TO/FILE` (scoped, safer)
            remains as an executable line. CONFIRMED PATCHED.

    R7-5  : PATCHED — install.sh lines 79-84 now include:
            local file_owner
            file_owner=$(stat -c '%U' "${profile}" 2>/dev/null || stat -f '%Su'
              "${profile}" 2>/dev/null || echo "")
            local current_user="${USER:-$(id -un)}"
            if [ -n "${file_owner}" ] && [ "${file_owner}" != "${current_user}" ]; then
              WARNING and return 0
            fi
            File ownership check implemented. Note: stat order differs from R7
            recommendation (macOS stat -f '%Su' first was recommended; current
            code uses Linux stat -c '%U' first then macOS fallback) — functionally
            correct on both platforms. CONFIRMED PATCHED.

    R7-6  : NOT PATCHED — plugin.json still contains only:
            "_integrity_note": "R6-8: ..."  (informational text)
            No `integrity` object with SHA-256 hashes of plugin files has been
            added. marketplace.json still has no integrity fields. RESIDUAL.

    R7-7  : NOT PATCHED — install.sh still has no EXPECTED_FORGE_SHA comparison.
            The SHA is computed and logged (lines 31-47) but never compared against
            an embedded expected value. Execution at line 50 proceeds without any
            hash comparison. forge.md install blocks continue the same display-only
            pattern. RESIDUAL — MEDIUM.

    R7-8  : PATCHED — install.sh lines 31-38 now use:
            if command -v shasum &>/dev/null; then
              FORGE_SHA=$(shasum -a 256 ...)
            elif command -v sha256sum &>/dev/null; then
              FORGE_SHA=$(sha256sum ...)
            else
              WARNING: "Neither shasum nor sha256sum found"
              FORGE_SHA="UNAVAILABLE"
            fi
            Availability check with fallback and explicit warning implemented.
            CONFIRMED PATCHED.

    R7-9  : PATCHED — STEP 9 Quick Reference lines 858-860 now read:
            "# Trusted repos: forge workspace sync -C "${PROJECT_ROOT}""
            "# Untrusted repos: forge --sandbox index-only -C "${PROJECT_ROOT}"
              workspace sync"
            "(SENTINEL FINDING-R7-9: trust qualifier — see STEP 2 for full guidance)"
            Trust qualifier present in Quick Reference. CONFIRMED PATCHED.

    R7-10 : STATUS UNKNOWN — `$schema` disclosure note not verified as added to
            STEP 0A-3 privacy note. The `$schema` field is still present in the
            TOML heredoc (forge.md line 187). No new comment was found in the
            heredoc or the privacy note. Checking below.
  }

  r7_10_detailed_check : {
    forge.md lines 186-193 (TOML heredoc):
      "cat > "${FORGE_DIR}/.forge.toml" << 'TOML'"
      '"$schema" = "https://forgecode.dev/schema.json"'
      No inline comment about schema fetch. NOT PATCHED (INFO level — residual).
  }

  new_attack_surfaces_identified : {
    - KEY_PLACEHOLDER substitution in printf argument — key in Claude Bash
      tool output and process args (R7-3 residual, now R8-1)
    - printf '%s' 'KEY_PLACEHOLDER' is executed atomically by the shell — the
      key value is a shell token, visible in shell's own debug trace if set -x
      is active (new surface not previously noted)
    - install.sh binary execution still unconditional in non-interactive path
      (R7-2 residual, now R8-2)
    - No pinned hash for forgecode.dev/cli download (R7-7 residual, now R8-3)
    - No cryptographic integrity in manifests (R7-6 residual, now R8-4)
    - $schema URL in .forge.toml — no disclosure comment (R7-10 residual, R8-5)
    - forge.md line 184: `[ -n "${OLD_HISTFILE}" ] && export HISTFILE=...`
      restores HISTFILE — correct but depends on OLD_HISTFILE capture being
      trustworthy. If HISTFILE was unset before entry, OLD_HISTFILE="" and the
      conditional prevents re-export. Correct behavior verified.
    - install.sh: no timeout on curl/wget download — indefinite hang possible
      in adversarial network environments (new finding R8-6)
    - forge.md STEP 0A-3: `forge info` called after credential write — this
      passes credentials to the forge binary, which may log API responses
      containing error details to stdout. Not a new finding; noted as clean.
  }

  false_negative_check : applied (see Step 8 Self-Challenge Gate)
}
```

---

## Steps 3–8 — Findings

All ten finding categories evaluated below.

---

### FINDING R8-1 — R7-3 Partial Patch: `printf '%s' 'KEY_PLACEHOLDER'` Still Exposes Key in Claude Bash Tool Output
**Severity:** LOW (CVSS 3.1: AV:L/AC:L/PR:L/UI:N/S:U/C:L/I:N/A:N — 3.3)
**Status:** Residual — partially patched from R7 (downgraded from MEDIUM to LOW due to significant improvement)
**Category:** Credential Exposure / Bash Tool Transparency
**Finding Category:** Cat-4 (Credential Exposure)

**Location:** `skills/forge.md` lines 162–165

**Evidence:**

The current credential write block reads:
```bash
# Claude: replace KEY_PLACEHOLDER below with the actual key value, then run the full block.
OLD_HISTFILE="${HISTFILE:-}"; unset HISTFILE   # disable history for this block
KEY_TMP=$(mktemp); chmod 600 "${KEY_TMP}"
printf '%s' 'KEY_PLACEHOLDER' > "${KEY_TMP}"  # ← replace KEY_PLACEHOLDER with actual key
```

**What R7 fixed (confirmed present):**
- `export OPENROUTER_KEY="KEY"` is gone — eliminates the environment variable pattern that was visible in `ps aux` for the python3 subprocess
- `unset HISTFILE` block is present — eliminates bash shell history recording of the credential write block
- The actual key never enters a python3 process argument

**What remains unfixed:**
When Claude follows the instruction at line 162 and substitutes the actual key for `KEY_PLACEHOLDER`, it constructs and executes the bash command:
```bash
printf '%s' 'sk-or-v1-<ACTUAL-KEY>' > "${KEY_TMP}"
```

This command:
1. **Is visible in the Claude session transcript** — Claude's Bash tool displays the command it is executing, so the literal key appears in the conversation
2. **May be logged in Claude API request/response data** — if the user has session logging, the key appears in tool call arguments
3. **Is visible in the process argument list** during the brief window when bash forks the `printf` subprocess — `ps aux | grep printf` or `/proc/<pid>/cmdline` could expose it on Linux
4. **Appears in any shell trace** (`set -x` debug output) that may be active

The R7 patch plan's recommended solution — `read -rs OPENROUTER_KEY < /dev/tty` — was not implemented. The temp-file pattern is a meaningful improvement (key not in env variable exposed to child processes, not in bash history) but does not address the Claude-tool-call transparency issue.

**Adversarial angle:** A user who pastes their OpenRouter key to Claude Code will have Claude emit the `printf '%s' 'sk-or-v1-REALKEY'` command visibly in the session. If session transcripts are stored (e.g., Claude Code session logging, third-party logging proxies, screen recording), the key is permanently captured.

**Concrete remediation:**

The most robust fix is to instruct Claude to NOT embed the key in any command at all, but instead write the key to a file in a way that the key value is never a shell argument. Two options:

**Option A — Python heredoc only (preferred):** Instruct Claude to write only to the Python heredoc's stdin:
```bash
# Claude: Do NOT substitute the key into any shell command line or printf argument.
# Instead, prompt the user to type or paste their key at the Python input() prompt below.
# The key will be captured by Python directly and never appear in any shell command.
KEY_TMP=$(mktemp); chmod 600 "${KEY_TMP}"
python3 << 'PYEOF'
import os, sys
key = input("Paste your OpenRouter API key (input is NOT echoed to shell): ").strip()
with open(os.environ['KEY_TMP'], 'w') as f:
    f.write(key)
print("Key written to temp file.")
PYEOF
```
This requires the user to interact with the Python prompt directly, but the key never appears in Claude's Bash tool output.

**Option B — Explicit user action gate:** Add a comment instructing Claude to pause execution and ask the user to run the `printf` line themselves in their terminal:
```bash
# ⚠️ CLAUDE STOP: Do NOT run the next line via the Bash tool.
# Ask the user to run this line themselves in their own terminal.
# This prevents the key from appearing in Claude session output.
# User command (replace KEY_VALUE with the actual key):
#   printf '%s' 'KEY_VALUE' > "${KEY_TMP}" && echo "Key written."
```

**Severity downgrade rationale:** Downgraded from MEDIUM (R7-3 was 5.5) to LOW (3.3) because the HISTFILE mitigation eliminates the most persistent exposure vector (bash history), and the temp-file pattern is correct for child processes. The remaining exposure is to Claude session transcript, which is scoped to the current session and controlled by the user.

---

### FINDING R8-2 — R7-2 Not Patched: install.sh Non-Interactive Binary Execution Still Lacks Abort Gate
**Severity:** MEDIUM (CVSS 3.1: AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:N — 6.5)
**Status:** Not Patched — R6-1 Option B (sleep 5) remains; Option A (non-interactive abort) not implemented
**Category:** Supply Chain / Non-Interactive Execution Context
**Finding Category:** Cat-7 (Supply Chain)

**Location:** `install.sh` lines 48–51

**Evidence:**
```bash
# R6-1: In non-interactive mode Ctrl+C may not be available; give a short window anyway.
sleep 5
bash "${FORGE_INSTALL_TMP}"
echo "[forge-plugin] ForgeCode installed."
```

The `[ -t 1 ]` branching added in R7 (lines 93–104) applies ONLY to the PATH modification consent block, not to the binary download-and-execute block. The binary execution block (lines 48–51) remains unconditional regardless of whether the session is interactive.

Verification: lines 93–104 contain the `[ -t 1 ]` check with the interactive/non-interactive notice for PATH modification. Lines 48–51 have no equivalent branching. The `sleep 5` is the only delay, and no `[ -t 1 ]` check gates binary execution.

**Timeline of this finding across rounds:**
- R6: Originally identified. Two options offered (Option A = abort non-interactive; Option B = sleep 5). Option B implemented.
- R7: Re-identified as R7-2 (residual). Option A again recommended. Not implemented.
- R8: Third consecutive round with this finding at MEDIUM severity.

**Adversarial angle:** When the SessionStart hook fires, the Claude session is not interactive. The user is not watching a terminal. A compromised `https://forgecode.dev/cli` endpoint serves a malicious script. The script is downloaded, its SHA-256 is displayed in Claude's session output (not on a terminal the user watches), and `bash "${FORGE_INSTALL_TMP}"` executes 5 seconds later. The net result is arbitrary code execution without any user-verifiable gate.

**Concrete remediation (unchanged from R7, Option A):**

Replace the binary execution block (lines 48–51) with:
```bash
printf '%s  %s  (downloaded %s)\n' "${FORGE_SHA}" "forgecode-install.sh" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${FORGE_SHA_LOG}"
echo "[forge-plugin] SHA logged to: ${FORGE_SHA_LOG}"
if [ -t 1 ]; then
  # Interactive terminal: give user a cancellation window
  echo "[forge-plugin] SHA-256: ${FORGE_SHA}"
  echo "[forge-plugin] Compare against: https://forgecode.dev/releases"
  echo "[forge-plugin] Press Ctrl+C within 10 seconds to cancel. Proceeding..."
  sleep 10
  bash "${FORGE_INSTALL_TMP}"
  echo "[forge-plugin] ForgeCode installed."
else
  # Non-interactive (SessionStart hook): log SHA and abort.
  # Require the user to verify the hash and run install interactively.
  echo "[forge-plugin] NON-INTERACTIVE INSTALL ABORTED — supply-chain safety gate." >&2
  echo "[forge-plugin] SHA-256 of downloaded script: ${FORGE_SHA}" >&2
  echo "[forge-plugin] To complete installation, open a terminal and run:" >&2
  echo "[forge-plugin]   bash '${CLAUDE_PLUGIN_ROOT:-~/.claude/plugins/sidekick}/install.sh'" >&2
  echo "[forge-plugin] Verify SHA against: https://forgecode.dev/releases" >&2
  rm -f "${FORGE_INSTALL_TMP}"
  exit 0
fi
```

Note: `exit 0` (not `exit 1`) so the hook's sentinel file logic is not disrupted — the hook will attempt re-install on the next SessionStart, which is the correct behavior.

---

### FINDING R8-3 — R7-7 Not Patched: SHA-256 Verification Remains Display-Only, No Pinned Hash Comparison
**Severity:** MEDIUM (CVSS 3.1: AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:N — 6.5)
**Status:** Not Patched — third consecutive round with this finding
**Category:** Supply Chain / Verification Theater
**Finding Category:** Cat-7 (Supply Chain)

**Location:** `install.sh` lines 31–50; `skills/forge.md` STEP 0A-1 (all three install blocks)

**Evidence:**

`install.sh` lines 31–50:
```bash
if command -v shasum &>/dev/null; then
  FORGE_SHA=$(shasum -a 256 "${FORGE_INSTALL_TMP}" | awk '{print $1}')
elif command -v sha256sum &>/dev/null; then
  FORGE_SHA=$(sha256sum "${FORGE_INSTALL_TMP}" | awk '{print $1}')
else
  echo "[forge-plugin] WARNING: Neither shasum nor sha256sum found ..."
  FORGE_SHA="UNAVAILABLE"
fi
...
echo "[forge-plugin] Install script SHA-256: ${FORGE_SHA}"
echo "[forge-plugin] IMPORTANT: Compare this hash against the official release at:"
echo "[forge-plugin]   https://forgecode.dev/releases"
...
sleep 5
bash "${FORGE_INSTALL_TMP}"
```

R7-8's `shasum`/`sha256sum` availability check was correctly implemented — that finding is patched. However, R7-7's core issue remains: the SHA is computed and displayed but never compared against any embedded expected value. Execution proceeds unconditionally after `sleep 5`.

**The same-domain compromise scenario remains fully applicable:** `forgecode.dev` controls both `/cli` and `/releases`. A CDN-level attacker serving a malicious script can update `/releases` to show the matching hash. The `_integrity_note` in plugin.json explicitly directs users to `https://forgecode.dev/releases` as the comparison source — pointing to attacker-controlled infrastructure.

**Note:** `FORGE_SHA="UNAVAILABLE"` (when neither shasum nor sha256sum is present) does not abort execution. The script still proceeds to `bash "${FORGE_INSTALL_TMP}"`. This means the UNAVAILABLE path also executes the script without any verification.

**Concrete remediation (same as R7-7):**

Add to `install.sh` after `FORGE_SHA` is computed:
```bash
# Pinned SHA-256 — update this value on each ForgeCode release.
# Obtain from: https://forgecode.dev/releases or the GitHub release artifacts.
# Leave as all-zeros to disable pinning (displays warning but does not abort).
EXPECTED_FORGE_SHA="0000000000000000000000000000000000000000000000000000000000000000"

if [ "${EXPECTED_FORGE_SHA}" = "0000000000000000000000000000000000000000000000000000000000000000" ]; then
  echo "[forge-plugin] WARNING: No pinned SHA-256 set. Cannot automatically verify integrity." >&2
  echo "[forge-plugin] Compare the SHA above against: https://forgecode.dev/releases" >&2
elif [ "${FORGE_SHA}" = "UNAVAILABLE" ]; then
  echo "[forge-plugin] WARNING: Cannot verify SHA — no hash tool available. Proceeding at risk." >&2
elif [ "${FORGE_SHA}" != "${EXPECTED_FORGE_SHA}" ]; then
  echo "[forge-plugin] FATAL: SHA-256 mismatch — aborting installation." >&2
  echo "[forge-plugin]   Expected: ${EXPECTED_FORGE_SHA}" >&2
  echo "[forge-plugin]   Got:      ${FORGE_SHA}" >&2
  echo "[forge-plugin] Do NOT proceed. Verify forgecode.dev release integrity." >&2
  rm -f "${FORGE_INSTALL_TMP}"
  exit 1
else
  echo "[forge-plugin] SHA-256 verified against pinned value. Proceeding."
fi
```

The `EXPECTED_FORGE_SHA` placeholder (all-zeros) allows the plugin to ship before pinning is operational while making the missing pin explicitly visible. When ForgeCode publishes a release, the plugin maintainer updates the value.

---

### FINDING R8-4 — R7-6 Not Patched: No Cryptographic Integrity Fields in Plugin Manifests
**Severity:** LOW (CVSS 3.1: AV:N/AC:H/PR:N/UI:R/S:U/C:H/I:H/A:N — 6.8)
**Status:** Not Patched — fourth consecutive round with this finding
**Category:** Supply Chain / Manifest Integrity
**Finding Category:** Cat-7 (Supply Chain)

**Location:** `.claude-plugin/plugin.json` line 22; `.claude-plugin/marketplace.json`

**Evidence:**

`plugin.json` current state:
```json
"_integrity_note": "R6-8: install.sh downloads ForgeCode from https://forgecode.dev/cli — verify SHA-256 against https://forgecode.dev/releases before trusting. Plugin source: https://github.com/alo-exp/sidekick"
```

No `integrity` object with SHA-256 hashes of `install.sh`, `skills/forge.md`, or `hooks/hooks.json` is present. `marketplace.json` has no integrity fields of any kind.

This finding has been raised in R6, R7, and now R8. The informational `_integrity_note` was added in R6 and has not been extended with cryptographic fields in two subsequent rounds.

**Assessment of feasibility:** The absence may reflect a platform constraint — if the Claude plugin runtime does not consume or validate integrity fields, maintaining them manually creates toil without enforcement. However, even without runtime enforcement, integrity fields create a detectable inconsistency if an attacker modifies plugin files without updating the manifest — a meaningful detection signal for manual audits.

**Concrete remediation (unchanged from R7-6):**

Add `integrity` object to `plugin.json`:
```json
"integrity": {
  "algorithm": "sha256",
  "files": {
    "install.sh": "<sha256-of-install.sh>",
    "skills/forge.md": "<sha256-of-forge.md>",
    "hooks/hooks.json": "<sha256-of-hooks.json>"
  },
  "generated": "2026-04-12",
  "note": "Recompute: shasum -a 256 install.sh skills/forge.md hooks/hooks.json"
}
```

Add the same structure to `marketplace.json`. Update as part of any release process.

---

### FINDING R8-5 — R7-10 Not Patched: `$schema` URL in .forge.toml References External Domain Without Disclosure Comment
**Severity:** INFO (CVSS 3.1: AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:N/A:N — 2.6)
**Status:** Not Patched — second round
**Category:** Privacy / External Reference Disclosure
**Finding Category:** Cat-8 (Privacy)

**Location:** `skills/forge.md` line 187

**Evidence:**

```toml
"$schema" = "https://forgecode.dev/schema.json"
```

No inline comment has been added to the TOML heredoc, and the STEP 0A-3 privacy note has not been extended to mention the `$schema` reference. The finding from R7 remains exactly as described.

**Concrete remediation (same as R7-10):**

Add inline comment in the TOML heredoc:
```toml
# $schema is fetched by schema-aware editors (VS Code, JetBrains) — remove if network
# privacy is required or in air-gapped environments.
"$schema" = "https://forgecode.dev/schema.json"
```

This is a one-line comment addition.

---

### FINDING R8-6 — NEW: install.sh Download Has No Timeout — Indefinite Hang Possible
**Severity:** LOW (CVSS 3.1: AV:N/AC:H/PR:N/UI:N/S:U/C:N/I:N/A:L — 3.7)
**Status:** New
**Category:** Reliability / Denial of Service (Session Hang)
**Finding Category:** Cat-6 (Denial of Service / Reliability)

**Location:** `install.sh` lines 22–25

**Evidence:**
```bash
if command -v curl &>/dev/null; then
  curl -fsSL https://forgecode.dev/cli -o "${FORGE_INSTALL_TMP}"
elif command -v wget &>/dev/null; then
  wget -qO "${FORGE_INSTALL_TMP}" https://forgecode.dev/cli
```

Neither the `curl` nor the `wget` invocation specifies a timeout. Default timeouts for both tools are either very long or infinite depending on configuration. In the SessionStart hook context:

1. If `forgecode.dev` is slow (high latency CDN, geographic routing issue) or returns a partial response, the download can hang indefinitely.
2. If the user is behind a captive portal (hotel WiFi, corporate network requiring authentication), the request will silently hang.
3. A network-level attacker performing a TCP slowloris or similar connection stall can keep the download open indefinitely, blocking the entire Claude SessionStart hook.
4. There is no maximum file size limit — a stall-and-drip attack serves bytes slowly enough to prevent timeout detection.

**Impact:** A hung SessionStart hook blocks or delays the Claude session startup, degrading usability. In the worst case (infinite hang), the session never becomes usable without manually killing the hook process.

**Adversarial angle:** A network adversary (MITM on public WiFi, BGP hijack, DNS poisoning) who intercepts the `forgecode.dev/cli` request can stall the connection indefinitely, denying the user access to Claude sessions that trigger the hook. Combined with R8-2 (non-interactive execution), a slow-drip attack delays the `sleep 5` window while serving a malicious payload byte by byte.

**Concrete remediation:**

Add explicit timeouts to both download commands:
```bash
if command -v curl &>/dev/null; then
  curl -fsSL --max-time 60 --connect-timeout 15 \
    https://forgecode.dev/cli -o "${FORGE_INSTALL_TMP}"
elif command -v wget &>/dev/null; then
  wget -qO "${FORGE_INSTALL_TMP}" --timeout=60 https://forgecode.dev/cli
```

`--max-time 60` (curl) / `--timeout=60` (wget): total operation timeout of 60 seconds.
`--connect-timeout 15` (curl): fail fast if the server is unreachable.

If the download times out:
```bash
if ! curl -fsSL --max-time 60 --connect-timeout 15 \
    https://forgecode.dev/cli -o "${FORGE_INSTALL_TMP}"; then
  echo "[forge-plugin] ERROR: Download timed out or failed." >&2
  echo "[forge-plugin] Check network connectivity and retry: bash '${CLAUDE_PLUGIN_ROOT}/install.sh'" >&2
  exit 1
fi
```

Apply the same pattern to the `forge.md` install blocks.

---

### FINDING R8-7 — NEW: `KEY_PLACEHOLDER` Substitution Could Produce Syntactically Broken Command on Keys Containing Single Quotes
**Severity:** LOW (CVSS 3.1: AV:L/AC:H/PR:L/UI:R/S:U/C:L/I:L/A:N — 3.3)
**Status:** New
**Category:** Input Validation / Shell Injection
**Finding Category:** Cat-1 (Prompt Injection / Shell Injection)

**Location:** `skills/forge.md` lines 162–165

**Evidence:**
```bash
printf '%s' 'KEY_PLACEHOLDER' > "${KEY_TMP}"  # ← replace KEY_PLACEHOLDER with actual key
```

The shell command uses single-quoted argument: `'KEY_PLACEHOLDER'`. When Claude substitutes the actual OpenRouter API key for `KEY_PLACEHOLDER`, the resulting command is:
```bash
printf '%s' 'sk-or-v1-<ACTUALKEY>' > "${KEY_TMP}"
```

OpenRouter API keys currently follow a format that does not contain single-quote characters. However:

1. **Future key formats** may include characters that break single-quote shell quoting (a single quote `'` in the key would terminate the quoted argument and inject arbitrary shell syntax)
2. **User transcription errors** — a user who pastes a key that contains a stray `'` character (from copy-paste artifacts, clipboard formatting) could cause Claude to construct a shell-injection payload
3. **Other providers** — the same pattern is used for any key Claude is asked to configure; other providers may use keys with characters that require escaping

If the key contains `'`, the constructed command becomes:
```bash
printf '%s' 'part1'INJECTED_SHELL_CODE'part2' > "${KEY_TMP}"
```

This could result in command injection if INJECTED_SHELL_CODE is shell-interpretable.

**Concrete remediation:**

Use double-quote escaping instead of single-quote, and add a key format validation step:
```bash
# Validate key format before writing (basic sanity check)
if ! echo "${KEY_TMP_VALUE}" | grep -qE '^[A-Za-z0-9_\-]+$'; then
  echo "WARNING: Key contains unexpected characters. Verify the key is correct." >&2
fi
```

Alternatively, instruct Claude to always write the key using the Python heredoc's `input()` method (R8-1 Option A), which bypasses shell quoting entirely.

The most robust fix is to use Python's `input()` to capture the key, avoiding any shell quoting of the key value.

---

### FINDING R8-8 — NEW: hooks.json Command Uses OR-Short-Circuit Preventing Sentinel Write on Partial Install Success
**Severity:** INFO (CVSS 3.1: AV:L/AC:H/PR:L/UI:N/S:U/C:N/I:N/A:L — 1.8)
**Status:** New
**Category:** Logic / Sentinel State Consistency
**Finding Category:** Cat-9 (Logic / State Management)

**Location:** `hooks/hooks.json` lines 6–9

**Evidence:**
```json
"command": "test -f \"${CLAUDE_PLUGIN_ROOT}/.installed\" || (bash \"${CLAUDE_PLUGIN_ROOT}/install.sh\"; touch \"${CLAUDE_PLUGIN_ROOT}/.installed\")"
```

The `(bash ...; touch ...)` subshell uses a semicolon, meaning the sentinel file (`.installed`) is written unconditionally after `install.sh` exits, regardless of its exit code. R6-3 noted this as intentional — the sentinel prevents re-running even if the install failed, avoiding repeated failed attempts.

However, with R8-2's recommendation (Option A: `exit 0` in non-interactive path), the install script will exit 0 with the message "NON-INTERACTIVE INSTALL ABORTED." The sentinel file will be written. ForgeCode will NOT be installed. On subsequent SessionStart events, the sentinel file exists, so `install.sh` will never run again — the user will receive no notification that installation was not completed, and `forge` will not be available.

**This is not a new flaw in the current code** — it is a compatibility issue that will arise if R8-2's remediation (non-interactive abort) is implemented without updating the hooks.json or install.sh sentinel logic.

**Concrete remediation:**

If R8-2 is implemented, the sentinel-write logic must distinguish between "successfully installed" and "deferred for user interaction." Two options:

**Option A:** Use a different sentinel for "deferred":
```json
"command": "test -f \"${CLAUDE_PLUGIN_ROOT}/.installed\" || bash \"${CLAUDE_PLUGIN_ROOT}/install.sh\" && touch \"${CLAUDE_PLUGIN_ROOT}/.installed\""
```
Here `&&` only writes `.installed` if `install.sh` exits 0 and `install.sh` exits 0 only when installation actually completes. For the non-interactive abort path, `install.sh` exits 0 without installing, so `.installed` is NOT written — hook re-runs next session.

But this causes the hook to re-attempt on every session until interactive install completes — which is actually the desired behavior.

**Option B:** Keep the current `(bash ...; touch ...)` for non-interactive abort but change the abort exit code to non-zero and use `&&` for the sentinel write. This requires install.sh to exit 0 ONLY on full success.

Recommended combined fix: change hooks.json to use `&&` for the sentinel touch, and ensure install.sh exits 0 only when the binary is successfully installed. Non-interactive abort exits 0 without installing — hook retries on next session. This is the cleanest behavior.

---

### FINDING R8-9 — NEW: forge.md Credential Write Block: `OLD_HISTFILE` Restoration Assumes Single-Command Block Execution
**Severity:** INFO (CVSS 3.1: AV:L/AC:H/PR:L/UI:R/S:U/C:L/I:N/A:N — 2.0)
**Status:** New
**Category:** Credential Exposure / Shell History Edge Case
**Finding Category:** Cat-4 (Credential Exposure)

**Location:** `skills/forge.md` lines 163 and 183

**Evidence:**
```bash
OLD_HISTFILE="${HISTFILE:-}"; unset HISTFILE   # disable history for this block
...
[ -n "${OLD_HISTFILE}" ] && export HISTFILE="${OLD_HISTFILE}"; unset OLD_HISTFILE
```

The `unset HISTFILE` pattern correctly disables shell history for the current shell session when the entire block is executed as one unit. However:

1. **Partial execution:** If Claude executes the block in multiple Bash tool calls (e.g., the `mktemp` line first, then the `printf` line, then the Python heredoc as separate calls), each Bash tool invocation launches a new subshell. `unset HISTFILE` in one subshell has no effect on the parent shell or other subshell invocations. The key substitution in `printf` could occur in a subshell that never executed `unset HISTFILE`.

2. **Claude Bash tool shell model:** Claude's Bash tool typically executes each command block in a fresh bash subprocess. If the entire credential block is not sent as a single atomic tool call, the HISTFILE guard is ineffective.

3. **`HISTFILE` vs. `HISTSIZE`:** `unset HISTFILE` prevents history from being written to the file. However, if bash is running with `set -o history`, commands are still stored in the in-memory history (`history` command shows them). Setting `HISTSIZE=0` as well would clear the in-memory history: `OLD_HISTFILE="${HISTFILE:-}"; unset HISTFILE; export HISTSIZE=0`.

**Impact:** Low — if the entire block is sent as a single Bash tool call (the intended usage), the HISTFILE guard works correctly. The risk is implementation-dependent on how Claude uses the Bash tool.

**Concrete remediation:**

Add `HISTSIZE=0` to the history-disable line for defense in depth, and add a comment clarifying that the entire block must be executed atomically:
```bash
# ⚠️ EXECUTE THIS ENTIRE BLOCK AS A SINGLE COMMAND — do not split across multiple
# Bash tool calls or the HISTFILE guard will be ineffective.
OLD_HISTFILE="${HISTFILE:-}"; OLD_HISTSIZE="${HISTSIZE:-}"; unset HISTFILE; export HISTSIZE=0
```

And restore:
```bash
[ -n "${OLD_HISTFILE}" ] && export HISTFILE="${OLD_HISTFILE}"; unset OLD_HISTFILE
[ -n "${OLD_HISTSIZE}" ] && export HISTSIZE="${OLD_HISTSIZE}"; unset OLD_HISTSIZE
```

---

### FINDING R8-10 — CATEGORY SWEEP: All Ten Finding Categories Evaluated
**Severity:** N/A (clean sweep confirmation)
**Status:** N/A
**Category:** Audit Completeness

The following categories were evaluated and found clean (no new findings beyond those already documented):

**Cat-2 (Path Traversal / Directory Injection):** All `forge -C "${PROJECT_ROOT}"` invocations use quoted variable expansion. `PROJECT_ROOT` is derived from `git rev-parse --show-toplevel` with a safe `|| echo "${PWD}"` fallback. No unquoted variable expansion in path contexts found.

**Cat-3 (Privilege Escalation):** No `sudo`, `su`, `chmod +s`, or setuid operations. `chmod 600` on credentials file is appropriate. No unexpected privilege escalation vectors identified.

**Cat-5 (Prompt Injection via External Content):** AGENTS.md trust gate (mandatory wrapper, user review requirement, sandbox-first for untrusted repos) is present and marked NON-NEGOTIABLE. `forge.md` STEP 2 correctly scopes all external content (AGENTS.md, README, config files, error messages). No regression found.

**Cat-6 (Destructive Operation Gates):** `git checkout -- .` guard confirmed present in both STEP 5-4 (full MANDATORY STOP block) and STEP 9 Quick Reference (commented out, mandatory stop reference). `git reset --hard` in STEP 7-7 has a `⚠️ CAUTION` warning. `git checkout -- path/to/wrong/file` (scoped) is the recommended safe alternative. No new destructive operation gaps found beyond R8-6 (timeout/hang, documented above).

**Cat-10 (Transparency / User Consent):** Pre-consent notice present in `install.sh` (lines 92–104) with `[ -t 1 ]` branching for interactive vs. non-interactive contexts. Marker comments in shell profiles present. First-run notice in `forge.md` STEP 0 header present. Privacy note in STEP 0A-3 present (though `$schema` not mentioned — R8-5). No transparency regressions found.

**Summary:** Categories 2, 3, 5, 6 (partial — see R8-6), and 10 are clean. Categories 1, 4, 7, 8, 9 have active findings documented above.

---

## Executive Summary

### R7 Patch Verification Status

| R7 Finding | Description | R8 Verdict |
|---|---|---|
| R7-1 | Bash tool note missing from wget/verbose install blocks | **PATCHED** — notes confirmed at lines 89–91 and 108–110 |
| R7-2 | Non-interactive binary install executes without gate | **NOT PATCHED** — sleep 5 only; no interactive abort |
| R7-3 | Credential export pattern exposes key | **PARTIALLY PATCHED** — KEY_PLACEHOLDER tempfile pattern; HISTFILE unset; printf arg still exposes key in Bash tool output |
| R7-4 | Quick Reference `git checkout -- .` unguarded | **PATCHED** — commented out with MANDATORY STOP reference at line 850 |
| R7-5 | `add_to_path` missing ownership check | **PATCHED** — file_owner check confirmed at lines 79–84 |
| R7-6 | No cryptographic integrity fields in manifests | **NOT PATCHED** — `_integrity_note` only |
| R7-7 | SHA-256 display-only, no pinned hash comparison | **NOT PATCHED** — same pattern; no embedded expected hash |
| R7-8 | `shasum` availability not checked | **PATCHED** — availability check with sha256sum fallback confirmed at lines 31–38 |
| R7-9 | `forge workspace sync` in Quick Reference lacks trust qualifier | **PATCHED** — trust qualifier comment confirmed at lines 858–860 |
| R7-10 | `$schema` URL in .forge.toml lacks disclosure comment | **NOT PATCHED** — no comment added |

**R7 patch rate: 5/10 fully patched, 1/10 partially patched, 4/10 not patched.**

---

### CVSS Score Table — All R8 Findings

| Finding ID | Title | Severity | CVSS 3.1 Score | Status |
|---|---|---|---|---|
| R8-1 | R7-3 partial: `printf 'KEY_PLACEHOLDER'` exposes key in Bash tool output | LOW | 3.3 | Residual (downgraded from MEDIUM) |
| R8-2 | R7-2 not patched: non-interactive binary install still lacks abort gate | MEDIUM | 6.5 | Not Patched (3rd round) |
| R8-3 | R7-7 not patched: SHA-256 verification display-only, no pinned hash | MEDIUM | 6.5 | Not Patched (3rd round) |
| R8-4 | R7-6 not patched: no cryptographic integrity fields in manifests | LOW | 6.8 | Not Patched (4th round) |
| R8-5 | R7-10 not patched: `$schema` URL lacks disclosure comment | INFO | 2.6 | Not Patched (2nd round) |
| R8-6 | NEW: download has no timeout — indefinite hang on stalled network | LOW | 3.7 | New |
| R8-7 | NEW: `KEY_PLACEHOLDER` single-quote pattern — shell injection on malformed keys | LOW | 3.3 | New |
| R8-8 | NEW: sentinel write on non-interactive abort will prevent future re-attempts | INFO | 1.8 | New (compatibility issue with R8-2 fix) |
| R8-9 | NEW: HISTFILE unset assumes atomic block execution — partial exec bypasses guard | INFO | 2.0 | New |
| R8-10 | Category sweep: Cat-2, Cat-3, Cat-5, Cat-6, Cat-10 confirmed clean | — | — | Clean |

**Round summary:** No Critical findings. Two Medium (R8-2, R8-3), three Low (R8-1, R8-4 reclassified†, R8-6, R8-7), three Info (R8-5, R8-8, R8-9).

†R8-4 (manifest integrity) retains its R7 CVSS score of 6.8 (which scores as Low per base score bands) but is functionally a Low-impact finding given that no runtime enforces the field.

---

### Priority Order for Remediation

1. **R8-2** (non-interactive binary install, MEDIUM, 3rd round) — Implement Option A: `[ -t 1 ]` gate on binary execution. One-time implementation, eliminates a genuine supply-chain gap.
2. **R8-3** (SHA display-only, MEDIUM, 3rd round) — Add `EXPECTED_FORGE_SHA` with all-zeros placeholder. Even a placeholder makes the missing pin visible and provides the scaffolding for real pinning.
3. **R8-1** (printf KEY_PLACEHOLDER, LOW) — Instruct Claude to stop before executing the printf line and ask the user to run it in their own terminal, or implement Option A (Python input()).
4. **R8-6** (download timeout, LOW, new) — Add `--max-time 60 --connect-timeout 15` to curl/wget. Two-minute change.
5. **R8-7** (single-quote shell injection on malformed keys, LOW, new) — Add key format validation or switch to Python input() pattern (combined fix with R8-1).
6. **R8-4** (manifest integrity, LOW, 4th round) — Add SHA-256 hash-of-hashes to plugin.json and marketplace.json.
7. **R8-8** (sentinel write compatibility with R8-2, INFO) — Address concurrently with R8-2 by changing hooks.json to use `&&` for sentinel touch.
8. **R8-9** (HISTFILE unset assumes atomic execution, INFO) — Add `HISTSIZE=0` and atomic-execution comment.
9. **R8-5** (`$schema` URL disclosure, INFO, 2nd round) — One-line comment addition.

---

## Hardened Rewrite Recommendations for New Findings

### R8-2 + R8-8: install.sh Non-Interactive Gate with Correct Sentinel Handling

**install.sh** — replace lines 48–51:
```bash
if [ -t 1 ]; then
  # Interactive terminal: user can verify and cancel
  echo "[forge-plugin] Press Ctrl+C within 10 seconds to cancel. Proceeding..."
  sleep 10
  bash "${FORGE_INSTALL_TMP}"
  echo "[forge-plugin] ForgeCode installed."
else
  # Non-interactive (SessionStart hook): abort. Require interactive completion.
  echo "[forge-plugin] NON-INTERACTIVE INSTALL ABORTED — supply-chain safety gate." >&2
  echo "[forge-plugin] SHA-256 of downloaded script: ${FORGE_SHA}" >&2
  echo "[forge-plugin] To install ForgeCode, open a terminal and run:" >&2
  echo "[forge-plugin]   bash \"${CLAUDE_PLUGIN_ROOT:-${HOME}/.claude/plugins/sidekick}/install.sh\"" >&2
  echo "[forge-plugin] Verify the SHA-256 against: https://forgecode.dev/releases" >&2
  rm -f "${FORGE_INSTALL_TMP}"
  exit 1   # Non-zero exit: prevents sentinel write if hooks.json uses &&
fi
```

**hooks/hooks.json** — change semicolon to `&&` for sentinel write:
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

With this change: non-interactive abort exits non-zero → sentinel not written → hook retries on next session → retries until user opens a terminal and runs install.sh interactively.

### R8-3: install.sh SHA Pinning Scaffold

Add after the `FORGE_SHA` computation block (after line 47):
```bash
# Pinned SHA-256 of known-good ForgeCode install script.
# Update this value on each ForgeCode release.
# Set to all-zeros to disable automatic abort (warning only).
EXPECTED_FORGE_SHA="0000000000000000000000000000000000000000000000000000000000000000"

if [ "${EXPECTED_FORGE_SHA}" != "0000000000000000000000000000000000000000000000000000000000000000" ]; then
  if [ "${FORGE_SHA}" = "UNAVAILABLE" ]; then
    echo "[forge-plugin] WARNING: SHA tool unavailable — cannot verify against pinned hash." >&2
  elif [ "${FORGE_SHA}" != "${EXPECTED_FORGE_SHA}" ]; then
    echo "[forge-plugin] FATAL: SHA-256 mismatch. Aborting." >&2
    echo "[forge-plugin]   Expected: ${EXPECTED_FORGE_SHA}" >&2
    echo "[forge-plugin]   Got:      ${FORGE_SHA}" >&2
    rm -f "${FORGE_INSTALL_TMP}"
    exit 1
  else
    echo "[forge-plugin] SHA-256 verified against pinned value."
  fi
else
  echo "[forge-plugin] WARNING: No pinned SHA configured. Manual verification recommended." >&2
fi
```

### R8-6: Download Timeout

Replace `install.sh` lines 22–25:
```bash
if command -v curl &>/dev/null; then
  if ! curl -fsSL --max-time 60 --connect-timeout 15 \
      https://forgecode.dev/cli -o "${FORGE_INSTALL_TMP}"; then
    echo "[forge-plugin] ERROR: Download failed or timed out after 60s." >&2
    echo "[forge-plugin] Check connectivity and retry: bash '${CLAUDE_PLUGIN_ROOT}/install.sh'" >&2
    exit 1
  fi
elif command -v wget &>/dev/null; then
  if ! wget -qO "${FORGE_INSTALL_TMP}" --timeout=60 https://forgecode.dev/cli; then
    echo "[forge-plugin] ERROR: Download failed or timed out after 60s." >&2
    exit 1
  fi
```

### R8-1 + R8-7: forge.md Credential Write — Hardened Pattern

Replace `skills/forge.md` lines 160–165 with:
```bash
# ⚠️ CLAUDE STOP — DO NOT run the key-write line via the Bash tool.
# Running 'printf' with the actual key as an argument exposes the key in
# Claude session output and the process argument list.
#
# INSTEAD, use one of these approaches:
#
# Option A (preferred — key never appears in Claude output):
#   1. Tell the user: "Please run this command yourself in your terminal,
#      replacing KEY_VALUE with your actual OpenRouter key:"
#         printf '%s' 'KEY_VALUE' > "${KEY_TMP}" && echo "Key written."
#   2. After the user confirms, proceed with the Python heredoc below.
#
# Option B (acceptable — key captured by Python, not shell):
#   Ask the user to type/paste the key at the Python input() prompt:
KEY_TMP=$(mktemp); chmod 600 "${KEY_TMP}"
python3 -c "
import os, sys
key = input('Paste your OpenRouter API key and press Enter: ').strip()
with open(os.environ['KEY_TMP'], 'w') as f:
    f.write(key)
print('Key written.')
" KEY_TMP="${KEY_TMP}"
```

This eliminates both the `KEY_PLACEHOLDER` substitution pattern (R8-1) and the single-quote injection risk (R8-7) by routing the key through Python's `input()` function where it is never a shell token.

---

## Step 8 — Self-Challenge Gate (Zero False Negative Confirmation)

### Challenge 1: Are all R7 findings verified against current file content?
Confirmed. Each R7 finding was evaluated against specific line ranges of the current files. Evidence cited with line numbers. Five R7 findings confirmed fully patched (R7-1, R7-4, R7-5, R7-8, R7-9). One partially patched (R7-3 → R8-1). Four not patched (R7-2, R7-6, R7-7, R7-10).

### Challenge 2: Is the downgrade of R8-1 (from MEDIUM to LOW) justified?
Justified. R7-3 was MEDIUM (5.5) because the `export OPENROUTER_KEY="KEY"` pattern stored the key persistently in bash shell history. The R7 patch introduced `unset HISTFILE` (history persistence eliminated) and the temp-file pattern (child process exposure eliminated). The remaining exposure — Bash tool output visibility — is scoped to the current Claude session and is not persistently stored to disk by default. CVSS AV:L/PR:L/C:L scores as 3.3, which is Low. The downgrade is appropriate.

### Challenge 3: Are there any code execution paths not examined?
All `bash`, `curl`, `wget`, `python3`, `printf`, `forge`, `git`, `shasum`, `sha256sum`, `stat`, and `realpath` invocations have been examined in both `install.sh` and `forge.md`. The `hooks.json` command string was evaluated for semicolon vs. `&&` logic in the context of R8-2/R8-8. The `marketplace.json` was read and confirmed to have no integrity fields. No new execution surfaces were identified beyond those documented.

### Challenge 4: Are any new findings false positives?
- **R8-6 (download timeout):** Could be argued as "standard practice to not specify timeouts and rely on defaults." Retained because in the SessionStart hook context, indefinite hangs cause user-facing failures, and the adversarial slow-drip scenario is realistic on public networks.
- **R8-7 (single-quote injection):** Could be argued as "OpenRouter keys don't contain single quotes." Retained because the pattern will be reused for other providers, and defensive input validation is appropriate when writing to security-sensitive files. LOW severity reflects the low likelihood.
- **R8-8 (sentinel compatibility):** Retained as INFO because it is a genuine forward-compatibility issue that must be addressed concurrently with R8-2. Not a standalone security finding but a correctness issue.
- **R8-9 (HISTFILE assumes atomic execution):** Retained as INFO. If Claude does split the block across tool calls, the guard fails silently. The comment-and-HISTSIZE fix costs nothing.

### Challenge 5: Does any unfixed finding warrant escalation to Critical?
No. R8-2 and R8-3 are both MEDIUM. R8-2 requires a compromised `forgecode.dev` CDN (AC:H). R8-3 requires the same compromised CDN plus the same-domain releases page. Neither is Critical because exploitation requires network-level compromise of a third-party service, not a vulnerability in the plugin itself. The combination of R8-2 + R8-3 (unverified script executed without user gate) is concerning and warrants HIGH urgency remediation, but does not meet Critical thresholds under CVSS 3.1 base scoring.

### Challenge 6: Are there any findings from R1–R6 that were marked patched but are now regressed?
Reviewed:
- **R2 (chmod 600 on credentials):** CONFIRMED present at forge.md line 179.
- **R2 (prompt injection AGENTS.md trust gate):** CONFIRMED present at forge.md lines 337–365 (mandatory, non-negotiable).
- **R3 (path injection hardening — forge config write):** CONFIRMED present at forge.md lines 660–668 (hardcoded path, no command substitution).
- **R4 (sandbox-first for AGENTS.md bootstrap on untrusted repos):** CONFIRMED present at forge.md lines 329–332.
- **R5 (sandbox-first for stale AGENTS.md update on untrusted repos):** CONFIRMED present at forge.md lines 377–381.
- **R6-3 (hooks.json semicolon for unconditional sentinel write):** Partially relevant — see R8-8 note about changing to `&&` if R8-2 is implemented. Current code is correct for current behavior.
- **R6-4 (sandbox note includes API transmission scope):** CONFIRMED at forge.md lines 503–505.
- **R6-9 (MANDATORY STOP in §5-4):** CONFIRMED at forge.md lines 575–580.
- **R6-10 (binary identity check):** CONFIRMED at install.sh lines 115–126.

No regressions from R1–R6 confirmed-patched findings.

**Conclusion: No false negatives identified. All R7 findings independently verified from current file content. All new findings adversarially challenged. Zero findings suppressed.**

---

## Round 8 Verdict

> **ROUND 8 STATUS: FINDINGS PRESENT — NOT CLEAN**
>
> 9 active findings (0 Critical, 2 Medium, 4 Low, 3 Info).
> 5 of 10 R7 findings fully patched. 1 partially patched. 4 not patched.
> 4 new findings (R8-6, R8-7, R8-8, R8-9).
>
> The two unfixed Medium findings (R8-2, R8-3) are supply-chain issues now entering their
> third consecutive audit round. Both require modest implementation effort (10–20 lines of
> `install.sh` changes) and represent genuine supply-chain execution gaps.
>
> The credential write pattern (R8-1) is meaningfully improved from R7 but still exposes
> the key in Claude Bash tool output. The Python input() solution (R8-1 hardened rewrite)
> would fully close this category.
>
> Two new low-severity findings (R8-6 download timeout, R8-7 single-quote injection) are
> straightforward to fix. Two new info-level findings (R8-8 sentinel compatibility, R8-9
> HISTFILE atomicity) require minor additions.
>
> Priority remediation: R8-2, R8-3, R8-1, R8-6 (in that order).
> A Round 9 audit should be brief if R8-2 and R8-3 are addressed.

---

*SENTINEL v2.3 — Report generated 2026-04-12*
*All findings independently verified against current file content. Prior-round findings are not credited as fixed unless confirmed by line-number evidence in current files.*

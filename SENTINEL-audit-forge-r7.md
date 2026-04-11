# SENTINEL v2.3 — Security Audit Report
## Target: forge skill (sidekick plugin v1.0.0)
## Round: 7 (R6 Patch Verification + New Surface Audit)
## Date: 2026-04-12
## Auditor: SENTINEL v2.3 (dual-mode: Defensive + Adversarial)
## Prior Rounds: R1–R6; R7 verifies all R6 patches and conducts full new-surface audit

---

## Step 0 — Decode Manifest / File Inventory

| File | SHA-256 Fingerprint (content-based, for reference) | Role |
|---|---|---|
| `skills/forge.md` | (audited in full, 845 lines) | Claude orchestration protocol, runtime skill instructions |
| `install.sh` | (audited in full, 113 lines) | Binary installer and PATH modifier, executed via SessionStart hook |
| `hooks/hooks.json` | (audited in full, 14 lines) | SessionStart hook definition |
| `.claude-plugin/plugin.json` | (audited in full, 23 lines) | Plugin manifest |
| `.claude-plugin/marketplace.json` | (audited in full, 29 lines) | Marketplace listing metadata |

### Manifest Decode

**plugin.json declares:**
- Name: `sidekick`, Version: `1.0.0`, License: MIT
- Author: Ālo Labs (`https://alolabs.dev`)
- Repository: `https://github.com/alo-exp/sidekick`
- Skills path: `./skills/`
- `_integrity_note`: references SHA-256 verification against `https://forgecode.dev/releases` — informational only, no cryptographic field

**hooks.json declares:**
- One hook: `SessionStart`
- Command: `test -f "${CLAUDE_PLUGIN_ROOT}/.installed" || (bash "${CLAUDE_PLUGIN_ROOT}/install.sh"; touch "${CLAUDE_PLUGIN_ROOT}/.installed")`
- Scope: runs once per install (sentinel-gated), not on every session

**install.sh declares:**
- `set -euo pipefail`, `trap` cleanup of temp file
- Downloads `https://forgecode.dev/cli` via curl or wget to a temp file
- SHA-256 logged to `~/.local/share/forge-plugin-install-sha.log`
- Binary placed at `~/.local/bin/forge`
- Appends PATH modification to `~/.zshrc`, `~/.bashrc`, `~/.bash_profile`

---

## Step 1 — Environment and Metadata Audit

### 1A. Execution Surfaces (complete enumeration)

1. `SessionStart` hook → `install.sh` → external network fetch → `bash` execution of downloaded script
2. `forge.md` instruction surface → Claude reads skill and executes embedded shell commands
3. Credentials file written to `~/forge/.credentials.json` (chmod 600)
4. Shell profile modification (`~/.zshrc`, `~/.bashrc`, `~/.bash_profile`)
5. `forge` binary at `~/.local/bin/forge` — third-party binary with persistent system presence
6. Forge prompt construction pipeline — user input, AGENTS.md, external file content embedded in forge prompts
7. `~/forge/.forge.toml` — config with `$schema` URL reference to `https://forgecode.dev/schema.json`
8. STEP 9 Quick Reference block — standalone command listing that Claude may copy-execute verbatim
9. Multiple manual install code blocks in STEP 0A-1 (primary curl path, wget fallback, verbose fallback)

### 1B. Trust Boundaries

| Boundary | Trust Level | Notes |
|---|---|---|
| Plugin publisher (Ālo Labs) → user | Implicit on install | GitHub repo, no commit signing enforced |
| `forgecode.dev` → binary/install script delivery | External, TLS only | No pinned certificate, no published hash |
| `openrouter.ai` → API credential target | External | |
| forge binary runtime → AI-directed shell execution | Highest privilege | Executes arbitrary commands based on AI output |
| AGENTS.md from arbitrary repos → forge prompts | Untrusted | Prompt injection vector |
| `$schema` URL in `.forge.toml` → `forgecode.dev` | External reference | Loaded by tooling at config parse time |

### 1B (tool audit). Tools / Binaries Invoked by Plugin

| Tool | Where Invoked | Validation Present? |
|---|---|---|
| `curl` / `wget` | `install.sh` lines 22–25; `forge.md` multiple | TLS only — no cert pin |
| `bash` | `install.sh` line 42 (executes downloaded script) | SHA-256 displayed, `sleep 5`, no interactive abort in non-interactive path |
| `python3` | `forge.md` lines 159–170 (credentials), lines 677–681 (key read) | Correct: heredoc avoids CLI arg exposure (see R6-7 verification) |
| `git` | `forge.md` multiple recovery flows | `git checkout -- .` guard present in §5-4 only |
| `shasum` | `install.sh` line 30; `forge.md` install blocks | Display only — no automated comparison against known-good value |
| `forge` binary | `forge.md` throughout | Version identity check present at install.sh lines 99–107 |

---

## Step 2 — Recon Notes

```
recon_notes {
  target          : forge/sidekick plugin v1.0.0
  audit_round     : 7
  prior_rounds    : R1-R6
  files_audited   : 5 (forge.md 845 lines, install.sh 113 lines,
                       hooks.json 14 lines, plugin.json 23 lines,
                       marketplace.json 29 lines)

  r6_patches_verified : {
    R6-1  : PARTIALLY_PATCHED — sleep 5 added (Option B). Option A (abort
            in non-interactive) not implemented. Residual: SHA window
            still non-functional in SessionStart context.
    R6-2  : PATCHED — NOTE comment added to forge.md STEP 0A-1 primary
            curl block. GAP: wget fallback and verbose fallback blocks
            (lines 80-92, 94-107) do NOT have this note. Two of three
            code paths are unprotected.
    R6-3  : PATCHED — hooks.json uses semicolon (not &&). Sentinel
            written unconditionally.
    R6-4  : PATCHED — sandbox note expanded to include code transmission.
    R6-5  : PARTIALLY_PATCHED — symlink target outside HOME is checked.
            File ownership check (stat owner != id -un) recommended in
            R6 patch plan NOT implemented.
    R6-6  : PATCHED — workspace sync trust qualifier added with sandbox
            mode recommendation for untrusted repos.
    R6-7  : PARTIALLY_PATCHED — python3 heredoc avoids key in python3
            process args. HOWEVER: 'export OPENROUTER_KEY="KEY"' line
            (forge.md line 157) still requires Claude to substitute the
            actual key into a bash command line, which appears in shell
            history (~/.bash_history), Claude Bash tool output, and
            potentially process list during bash execution. New finding
            R7-3 documents this residual.
    R6-8  : NOT_PATCHED — plugin.json has _integrity_note (informational
            text) but no cryptographic hash or signature field. Residual.
    R6-9  : PATCHED — MANDATORY STOP block present in §5-4.
            GAP: §9 Quick Reference (line 838) contains bare
            'git checkout -- .' without any guard. New finding R7-4.
    R6-10 : PATCHED — binary identity check (forge/forgecode version
            string regex) added to install.sh lines 99-107.
  }

  new_attack_surfaces_identified : {
    - STEP 0A-1 wget fallback (lines 80-92): missing R6-2 Bash tool note
    - STEP 0A-1 verbose fallback (lines 94-107): missing R6-2 Bash tool note
    - STEP 9 Quick Reference (line 838): bare git checkout -- . without guard
    - export OPENROUTER_KEY=KEY pattern: bash history / tool output exposure
    - forge.md §5-12 PATH export: no concern identified
    - marketplace.json: no integrity fields (same as plugin.json)
    - install.sh add_to_path: missing ownership check (R6-5 partial)
    - shasum comparison: no automated verification against known hash
  }

  false_negative_check : applied (see Step 8b)
}
```

---

## Steps 3–8 — Findings

---

### FINDING R7-1 — R6-2 Partial Patch: Bash Tool Warning Absent from wget and Verbose Install Fallback Blocks
**Severity:** LOW (CVSS 3.1: AV:L/AC:H/PR:N/UI:R/S:U/C:L/I:L/A:N — 3.6)
**Status:** Residual (R6-2 partially patched; two of three code paths remain unguarded)
**Category:** UX Deception / Automated Context

**Location:** `skills/forge.md` lines 80–92 (wget fallback), lines 94–107 (verbose fallback)

**Evidence:**

The primary curl install block (lines 64–78) was correctly patched with:
```
# NOTE for Claude: When executing this via the Bash tool, the user cannot send Ctrl+C
# to cancel the subprocess. Show the SHA-256 output to the user BEFORE executing the
# bash step and ask for explicit confirmation to proceed. (SENTINEL FINDING-R6-2)
```

However the wget fallback block (lines 80–92) and the verbose/debug fallback block (lines 94–107) contain identical `sleep 5` + "press Ctrl+C NOW" patterns but no equivalent NOTE. Both blocks end with `bash "${FORGE_INSTALL}"; rm -f "${FORGE_INSTALL}"` and will be executed by Claude's Bash tool in contexts where Ctrl+C is non-functional.

**Adversarial angle:** A user whose system lacks `curl` (common on minimal Linux environments) or who encounters the "install fails silently" scenario is directed to the unguarded code paths. Claude will execute `bash "${FORGE_INSTALL}"` without asking for explicit confirmation, while presenting a misleading "press Ctrl+C NOW" message.

**Concrete remediation:**

Add the identical NOTE comment to the wget block and verbose block, immediately before each `sleep 5` line:
```bash
# NOTE for Claude: When executing this via the Bash tool, the user cannot send Ctrl+C
# to cancel the subprocess. Show the SHA-256 output to the user BEFORE executing the
# bash step and ask for explicit confirmation to proceed. (SENTINEL FINDING-R6-2)
sleep 5
bash "${FORGE_INSTALL}"; rm -f "${FORGE_INSTALL}"
```

This is a copy-paste addition to two locations.

---

### FINDING R7-2 — R6-1 Partial Patch: install.sh Non-Interactive Binary Install Still Executes Without User-Verifiable Gate
**Severity:** MEDIUM (CVSS 3.1: AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:N — 6.5)
**Status:** Residual (R6-1 minimum viable option implemented; recommended option not implemented)
**Category:** Supply Chain / Non-Interactive Execution Context

**Location:** `install.sh` lines 30–42

**Evidence:**
```bash
FORGE_SHA=$(shasum -a 256 "${FORGE_INSTALL_TMP}" | awk '{print $1}')
...
echo "[forge-plugin] Install script SHA-256: ${FORGE_SHA}"
echo "[forge-plugin] IMPORTANT: Compare this hash against the official release at:"
echo "[forge-plugin]   https://forgecode.dev/releases  (or GitHub releases page)"
echo "[forge-plugin] If hashes do not match, delete ${FORGE_INSTALL_TMP} and abort."
# R6-1: In non-interactive mode Ctrl+C may not be available; give a short window anyway.
sleep 5
bash "${FORGE_INSTALL_TMP}"
```

The R6 report offered two remediation options. Option A (recommended): log the SHA and abort in non-interactive mode — require the user to re-run interactively to complete installation. Option B (minimum viable): add `sleep 5` with Ctrl+C messaging. The implementer chose Option B.

The R6 report explicitly warned: "Option B is weaker than Option A since the user likely cannot respond to a backgrounded hook, but it at least introduces a delay." In the actual SessionStart hook execution context, the user is not watching a terminal in real time. The `sleep 5` delay does not allow the user to inspect the SHA against the official release or abort — they would need to interrupt the entire Claude session within 5 seconds of a background hook firing.

The net result: the SHA is logged to `~/.local/share/forge-plugin-install-sha.log` (a meaningful improvement) but the binary is still downloaded and executed without any opportunity for the user to verify or cancel in the primary deployment scenario (SessionStart hook).

**Adversarial angle:** A compromised `https://forgecode.dev/cli` endpoint returns a malicious script. The script is downloaded, its SHA-256 is printed and logged, and it is executed 5 seconds later — all without any human in the loop during the SessionStart hook path. The SHA log entry becomes evidence of the attack, not a prevention mechanism.

**Concrete remediation (Option A, as originally recommended in R6):**

In `install.sh`, branch on `[ -t 1 ]`:
```bash
if [ -t 1 ]; then
  # Interactive: give user a cancellation window
  echo "[forge-plugin] SHA-256: ${FORGE_SHA}"
  echo "[forge-plugin] Compare against: https://forgecode.dev/releases"
  echo "[forge-plugin] Press Ctrl+C within 10 seconds to cancel. Proceeding..."
  sleep 10
  bash "${FORGE_INSTALL_TMP}"
else
  # Non-interactive (SessionStart hook): log SHA and abort.
  # The user must verify the hash and re-run interactively to complete installation.
  echo "[forge-plugin] NON-INTERACTIVE INSTALL ABORTED for safety."
  echo "[forge-plugin] SHA-256 of downloaded script: ${FORGE_SHA}"
  echo "[forge-plugin] SHA logged to: ${FORGE_SHA_LOG}"
  echo "[forge-plugin] To complete installation, open a new terminal and run:"
  echo "[forge-plugin]   bash '${CLAUDE_PLUGIN_ROOT}/install.sh'"
  echo "[forge-plugin] Verify the SHA-256 against: https://forgecode.dev/releases"
  rm -f "${FORGE_INSTALL_TMP}"
  exit 0
fi
```

This converts the SessionStart hook path from silent execution to an opt-in interactive install, eliminating the supply-chain execution gap.

---

### FINDING R7-3 — R6-7 Residual: `export OPENROUTER_KEY="KEY"` Pattern Exposes API Key in Shell History and Claude Bash Tool Output
**Severity:** MEDIUM (CVSS 3.1: AV:L/AC:L/PR:L/UI:N/S:U/C:H/I:N/A:N — 5.5)
**Status:** Residual (R6-7 partially patched; python3 process-list exposure fixed, but shell history exposure introduced)
**Category:** Credential Exposure

**Location:** `skills/forge.md` line 157

**Evidence:**
```bash
export OPENROUTER_KEY="KEY"   # ← replace KEY with the actual key value
```

R6-7's patch correctly replaced `python3 -c 'import json; ...; api_key="THEKEY"...'` (key in python3 process args) with a heredoc pattern that reads the key from the environment variable. This eliminates the `ps aux` process-list exposure for the python3 subprocess.

However, the instruction to Claude is: `# Claude: assign the user's key to OPENROUTER_KEY, then execute the heredoc below.` When Claude follows this instruction, it constructs and executes a bash command that includes `export OPENROUTER_KEY="<actual-api-key>"`. This command:

1. **Appears in Claude's Bash tool output** — visible in the Claude session transcript and any logs Claude Code generates.
2. **Is recorded in bash shell history** (`~/.bash_history`) if Claude's Bash tool inherits a history-enabled shell session, or if the user re-runs the command manually.
3. **May appear in process list** during the brief window when bash is parsing the `export` statement, depending on how the OS exposes command arguments.
4. **Is included in Claude API request/response logs** if the user has logging enabled.

The R6 patch plan actually recommended `read -rs OPENROUTER_KEY && export OPENROUTER_KEY` as the correct pattern — reading the key interactively from stdin so it never appears in any command line. This was not implemented.

**Adversarial angle:** A user who pastes their OpenRouter key to Claude and says "configure forge" will have Claude emit a bash command containing their literal API key in plaintext. Anyone with access to Claude session history, bash history, or any log file capturing Claude's tool calls can extract the API key.

**Concrete remediation:**

Replace line 157 with a comment-only instruction to Claude plus a `read -rs` pattern:
```bash
# Claude: Do NOT embed the API key in this command line. Instead:
# 1. Tell the user: "Please type or paste your OpenRouter API key at the prompt below (it will be hidden):"
# 2. Use the read command below to capture it without exposing it in command output or history.
read -rs OPENROUTER_KEY < /dev/tty
export OPENROUTER_KEY
```

If `read -rs` is not suitable in Claude's Bash tool context (no TTY), an alternative is to write the key to a temporary file with restricted permissions and read from that file — but the `read -rs` pattern is preferable as it never touches disk.

As a fallback for non-interactive Claude tool execution, add a comment instructing Claude to write the key to a temp file (`chmod 600`, read with `cat`, `unset`) rather than embedding it in the `export` line.

---

### FINDING R7-4 — R6-9 Residual: `git checkout -- .` in STEP 9 Quick Reference Lacks MANDATORY STOP Guard
**Severity:** LOW (CVSS 3.1: AV:L/AC:L/PR:L/UI:N/S:U/C:N/I:H/A:H — 7.1 — note: no external network; impact is local data loss)
**Status:** Residual (R6-9 patched §5-4 only; §9 Quick Reference unguarded)
**Category:** Destructive Operation Gate

**Location:** `skills/forge.md` lines 836–839

**Evidence:**
```bash
# ── Recovery ─────────────────────────────────────────────────────
git diff --stat                              # see what changed
git checkout -- .                            # discard all changes
forge config set model open_router google/gemma-4-31b-it  # if 429
```

The STEP 5-4 section correctly includes the MANDATORY STOP block (lines 563–569) that prevents Claude from executing `git checkout -- .` autonomously. However, STEP 9 Quick Reference presents an identical command as a bare one-liner without any guard or warning.

STEP 9 is titled "Quick Reference" and is explicitly designed to be a fast lookup section. It is more likely to be copy-executed verbatim than the detailed prose of STEP 5-4. Claude reading from the Quick Reference does not receive the MANDATORY STOP instruction.

**Adversarial angle:** A Claude instance that loads forge.md and consults only the Quick Reference section for a recovery command will encounter `git checkout -- .` without any behavioral stop instruction. Under STEP 1's "bias heavily toward delegation" directive, Claude may execute the command without surfacing it to the user — permanently discarding uncommitted changes.

**Concrete remediation:**

Replace the bare Quick Reference line with a reference to the safe procedure:
```bash
# ── Recovery ─────────────────────────────────────────────────────
git diff --stat                              # see what changed
# MANDATORY STOP: Before running 'git checkout -- .', see STEP 5-4 for
# required user-confirmation procedure. Do NOT execute autonomously.
# git checkout -- .                         # discard all — CONFIRM FIRST
forge config set model open_router google/gemma-4-31b-it  # if 429
```

Commenting out the command and adding the mandatory stop reference preserves usability while preventing autonomous execution.

---

### FINDING R7-5 — R6-5 Partial Patch: `add_to_path` Missing File Ownership Verification
**Severity:** LOW (CVSS 3.1: AV:L/AC:H/PR:L/UI:N/S:U/C:N/I:L/A:N — 2.5)
**Status:** Residual (R6-5 symlink check patched; ownership check not implemented)
**Category:** Filesystem Hardening

**Location:** `install.sh` lines 58–72 (`add_to_path` function)

**Evidence:**

The current `add_to_path` function checks whether a symlink points outside `$HOME`:
```bash
if [[ "${real_target}" != "${home_prefix}/"* ]]; then
  echo "[forge-plugin] WARNING: ${profile} is a symlink pointing outside HOME..."
  return 0
fi
```

The R6 patch plan explicitly recommended an additional ownership check:
```bash
profile_owner=$(stat -f '%Su' "${real_profile}" 2>/dev/null || stat -c '%U' "${real_profile}" 2>/dev/null)
if [ "${profile_owner}" != "$(id -un)" ]; then
  echo "[forge-plugin] WARNING: ${profile} is owned by ${profile_owner} — skipping"
  return
fi
```

This ownership check was not implemented. A shell profile file within `$HOME` but owned by a different user (e.g., root-owned `~/.zshrc` in a poorly administered environment, or a shared home directory scenario) could receive a PATH modification it did not consent to.

**Concrete remediation:**

Add ownership check after the symlink check, before the `printf` append:
```bash
# Verify file ownership — only append to files owned by the current user
local real_target_to_check="${profile}"
if [ -L "${profile}" ]; then
  real_target_to_check=$(realpath "${profile}" 2>/dev/null || echo "${profile}")
fi
local profile_owner
profile_owner=$(stat -f '%Su' "${real_target_to_check}" 2>/dev/null \
             || stat -c '%U' "${real_target_to_check}" 2>/dev/null \
             || echo "unknown")
if [ "${profile_owner}" != "$(id -un)" ]; then
  echo "[forge-plugin] WARNING: ${profile} is owned by '${profile_owner}', not current user. Skipping PATH addition." >&2
  return 0
fi
```

---

### FINDING R7-6 — R6-8 Not Patched: No Cryptographic Integrity Field in plugin.json or marketplace.json
**Severity:** LOW (CVSS 3.1: AV:N/AC:H/PR:N/UI:R/S:U/C:H/I:H/A:N — 6.8)
**Status:** Not Patched (informational `_integrity_note` field added; no cryptographic hash)
**Category:** Supply Chain / Manifest Integrity

**Location:** `.claude-plugin/plugin.json` line 22; `.claude-plugin/marketplace.json`

**Evidence:**

`plugin.json` now contains:
```json
"_integrity_note": "R6-8: install.sh downloads ForgeCode from https://forgecode.dev/cli — verify SHA-256 against https://forgecode.dev/releases before trusting. Plugin source: https://github.com/alo-exp/sidekick"
```

This is an informational text field. It documents the supply chain but provides no cryptographic guarantee. A compromised GitHub repository could update `install.sh` and `_integrity_note` simultaneously, negating any protective value.

`marketplace.json` has no integrity field at all.

The R6 recommendation to add a `SHA-256` or `SHA-512` hash-of-hashes covering the canonical plugin files (`install.sh`, `forge.md`, `hooks.json`) was not implemented. This would allow a sufficiently motivated user (or a future plugin runtime with integrity checking) to detect tampering.

**Concrete remediation:**

Add a `integrity` object to `plugin.json` with SHA-256 hashes of each auditable file:
```json
"integrity": {
  "algorithm": "sha256",
  "files": {
    "install.sh": "<sha256-of-install.sh>",
    "skills/forge.md": "<sha256-of-forge.md>",
    "hooks/hooks.json": "<sha256-of-hooks.json>"
  },
  "generated": "2026-04-12",
  "note": "Recompute with: shasum -a 256 install.sh skills/forge.md hooks/hooks.json"
}
```

Update this field as part of any release process. Add the same structure to `marketplace.json`. This is not a strong guarantee (the hashes live in the same repository as the files) but it creates a detectable inconsistency if an attacker modifies files without updating the manifest.

---

### FINDING R7-7 — forge.md: SHA-256 Comparison Has No Automated Verification — Display-Only Across All Code Paths
**Severity:** MEDIUM (CVSS 3.1: AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:N — 6.5)
**Status:** New
**Category:** Supply Chain / Verification Theater

**Location:** `install.sh` lines 30–38; `skills/forge.md` STEP 0A-1 (all three install blocks)

**Evidence:**

Every install path in both `install.sh` and `forge.md` follows this pattern:
```bash
FORGE_SHA=$(shasum -a 256 "${FORGE_INSTALL_TMP}" | awk '{print $1}')
echo "SHA-256: ${FORGE_SHA}"
echo "IMPORTANT: Compare this SHA-256 against the official release at: https://forgecode.dev/releases"
```

The SHA is computed and displayed, but never compared against a known-good value embedded in the plugin. The user is told to compare manually against a URL (`https://forgecode.dev/releases`). However:

1. The plugin contains no embedded reference hash to compare against.
2. The `forgecode.dev/releases` page is served by the same infrastructure as `forgecode.dev/cli`. A compromised CDN could serve a malicious script and a matching fake releases page with the malicious hash.
3. When Claude executes the install blocks via its Bash tool, the SHA appears in output — but Claude's current behavior does not include fetching the releases page and comparing hashes autonomously (nor should it, since that page is also on the same domain).
4. The `install.sh` SHA log (`~/.local/share/forge-plugin-install-sha.log`) is a forensic tool, not a prevention mechanism.

The net result: the SHA-256 display creates user-visible evidence of security consciousness but does not prevent execution of a malicious script in any automated or semi-automated scenario.

**Adversarial angle:** The attack model here is a CDN-level compromise of `forgecode.dev`. The attacker controls both `/cli` and `/releases`. They serve a malicious script with a computed SHA and update `/releases` to match. All verification steps pass. The `_integrity_note` in `plugin.json` instructs users to check `/releases` — pointing directly at the attacker-controlled page.

**Concrete remediation:**

Two complementary approaches:

**A (short-term):** Embed a known-good hash in `plugin.json` (or a separate `FORGE_RELEASE_SHA256` variable in `install.sh`) pinned to the current ForgeCode release version. Compare the downloaded script's SHA against this embedded value before executing:

```bash
EXPECTED_SHA="<pinned-sha256-of-known-good-forgecode-install.sh>"
if [ "${FORGE_SHA}" != "${EXPECTED_SHA}" ]; then
  echo "[forge-plugin] ERROR: SHA-256 mismatch. Expected: ${EXPECTED_SHA}" >&2
  echo "[forge-plugin] ERROR: Got: ${FORGE_SHA}" >&2
  echo "[forge-plugin] ERROR: Aborting — do NOT proceed. Verify forgecode.dev integrity." >&2
  rm -f "${FORGE_INSTALL_TMP}"
  exit 1
fi
```

This requires updating `EXPECTED_SHA` on each ForgeCode release but provides genuine protection against CDN compromise within a release window.

**B (long-term):** Adopt a release signing model — ForgeCode publishes a GPG/minisign signature alongside each installer. `install.sh` fetches and verifies the signature before executing. This is the standard for package managers and removes the same-domain trust issue entirely.

Note: Approach A requires coordinating the `plugin.json`/`install.sh` update with each ForgeCode release. If `alo-exp/sidekick` and `forgecode.dev` are maintained by the same team, this is feasible.

---

### FINDING R7-8 — install.sh: `shasum` Availability Not Verified Before Use
**Severity:** LOW (CVSS 3.1: AV:L/AC:H/PR:N/UI:N/S:U/C:N/I:L/A:L — 3.6)
**Status:** New
**Category:** Reliability / Silent Failure

**Location:** `install.sh` line 30; `skills/forge.md` all three install blocks

**Evidence:**
```bash
FORGE_SHA=$(shasum -a 256 "${FORGE_INSTALL_TMP}" | awk '{print $1}')
```

`shasum` is a standard macOS tool and is available on most Linux distributions via `perl` or `coreutils`. However, on minimal Alpine Linux containers, Debian slim images, or certain CI environments, `shasum` may not be installed. If `shasum` is absent:

- `FORGE_SHA` will be an empty string
- The SHA log entry (`~/.local/share/forge-plugin-install-sha.log`) will record an empty hash
- The security messages `"Install script SHA-256: "` will display a blank value
- The user and any automated monitoring will see no hash, potentially not noticing
- `bash "${FORGE_INSTALL_TMP}"` still executes — the failure is silent

**Adversarial angle:** In minimal environments (Docker containers, CI pipelines), `shasum` is absent. The plugin silently installs without any hash verification. A user in such an environment receives false assurance from the security messaging, which implies verification occurred.

**Concrete remediation:**

Add a `shasum` availability check before the download:
```bash
if ! command -v shasum &>/dev/null && ! command -v sha256sum &>/dev/null; then
  echo "[forge-plugin] WARNING: Neither 'shasum' nor 'sha256sum' found." >&2
  echo "[forge-plugin] SHA-256 verification will be skipped." >&2
  echo "[forge-plugin] Install 'perl' (for shasum) or 'coreutils' (for sha256sum) to enable verification." >&2
  FORGE_SHA="UNVERIFIED"
else
  FORGE_SHA=$(shasum -a 256 "${FORGE_INSTALL_TMP}" 2>/dev/null \
           || sha256sum "${FORGE_INSTALL_TMP}" 2>/dev/null \
           | awk '{print $1}')
fi
```

Also update the `forge.md` install blocks to try `sha256sum` as a fallback (already common on Linux systems where `shasum` may be absent).

---

### FINDING R7-9 — forge.md STEP 9 Quick Reference: `forge workspace sync` Listed Without Trust Qualifier
**Severity:** LOW (CVSS 3.1: AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:L/A:N — 3.7)
**Status:** New
**Category:** Prompt Injection / Trust Boundary

**Location:** `skills/forge.md` line 843

**Evidence:**
```bash
forge workspace sync -C "${PROJECT_ROOT}"    # semantic index for large codebases
```

STEP 2 (lines 374–385) was correctly patched (R6-6) to include a trust qualifier and sandbox recommendation for `forge workspace sync` on untrusted repositories. However, STEP 9 Quick Reference again presents the bare `forge workspace sync` command without any trust qualifier or note.

This mirrors the same pattern identified in FINDING R7-4 (`git checkout -- .`): behavioral guards added to the detailed protocol sections are not reflected in the Quick Reference, which is a high-likelihood execution path.

**Concrete remediation:**

Add an inline comment to the Quick Reference entry:
```bash
# For trusted repos only — use --sandbox flag for untrusted/external repos (see STEP 2)
forge workspace sync -C "${PROJECT_ROOT}"    # semantic index for large codebases
```

---

### FINDING R7-10 — forge.md: `$schema` URL in .forge.toml Config References External Domain Without Disclosure
**Severity:** INFO (CVSS 3.1: AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:N/A:N — 2.6)
**Status:** New
**Category:** Privacy / External Reference

**Location:** `skills/forge.md` lines 174–181

**Evidence:**
```toml
cat > "${FORGE_DIR}/.forge.toml" << 'TOML'
"$schema" = "https://forgecode.dev/schema.json"
max_tokens = 16384

[session]
provider_id = "open_router"
model_id = "qwen/qwen3.6-plus"
TOML
```

The `.forge.toml` config file includes a `$schema` reference to `https://forgecode.dev/schema.json`. This URL is fetched by JSON/TOML-aware editors (VS Code, JetBrains IDEs, etc.) that support schema-based validation. When a user opens `.forge.toml` in such an editor:

1. The editor contacts `forgecode.dev/schema.json`
2. This reveals the user's IP address and the fact that they are using ForgeCode to the `forgecode.dev` infrastructure
3. For sensitive environments (air-gapped networks, regulated industries), this outbound reference may violate network policies

The STEP 0A-3 privacy note (lines 195–199) covers forge binary telemetry but does not mention the `$schema` URL in the config file.

**Concrete remediation:**

Two options:
- Add a comment to the TOML heredoc: `# $schema: fetched by schema-aware editors — remove if network privacy is required`
- Expand the STEP 0A-3 privacy note to mention the schema URL: "Additionally, the `$schema` field in `.forge.toml` will be fetched by schema-aware editors (VS Code, etc.) when opening the config file. Remove this field in air-gapped or network-restricted environments."

This is informational only and does not require changing the schema URL itself.

---

## Executive Summary

### CVSS Score Table

| Finding ID | Title | Severity | CVSS 3.1 Score | Status |
|---|---|---|---|---|
| R7-1 | R6-2 partial: missing Bash tool note in wget/verbose install paths | LOW | 3.6 | Residual |
| R7-2 | R6-1 partial: non-interactive install still executes without user gate | MEDIUM | 6.5 | Residual |
| R7-3 | R6-7 partial: `export OPENROUTER_KEY` exposes key in shell history/Bash tool output | MEDIUM | 5.5 | Residual |
| R7-4 | R6-9 partial: `git checkout -- .` in Quick Reference lacks MANDATORY STOP | LOW | 7.1* | Residual |
| R7-5 | R6-5 partial: `add_to_path` missing file ownership check | LOW | 2.5 | Residual |
| R7-6 | R6-8 not patched: no cryptographic integrity field in manifests | LOW | 6.8 | Not Patched |
| R7-7 | SHA-256 verification display-only: no automated comparison against embedded hash | MEDIUM | 6.5 | New |
| R7-8 | `shasum` availability not verified — silent failure on minimal systems | LOW | 3.6 | New |
| R7-9 | `forge workspace sync` in Quick Reference lacks trust qualifier | LOW | 3.7 | New |
| R7-10 | `$schema` URL in .forge.toml references external domain without disclosure | INFO | 2.6 | New |

*R7-4 CVSS score reflects local data-loss impact (I:H/A:H) rather than network exploitability.

**Round summary:** No Critical findings. Three Medium (R7-2, R7-3, R7-7), four Low, one Info. The three Mediums are all supply-chain or credential-handling issues that are partially addressed but not fully closed from R6.

**Priority order for remediation:**
1. **R7-3** (shell history credential exposure) — 1-line change to forge.md, high impact. Use `read -rs` or write-to-tempfile pattern.
2. **R7-2** (non-interactive install executes without gate) — Implement Option A from R6: abort in non-interactive path, require interactive re-run.
3. **R7-7** (SHA verification display-only) — Embed a pinned expected hash and compare before executing.
4. **R7-4** (Quick Reference `git checkout -- .` unguarded) — Comment out with mandatory stop note.
5. **R7-1** (Bash tool note missing from wget/verbose install blocks) — Copy-paste addition.
6. **R7-6** (no cryptographic integrity fields in manifests) — Add hash-of-hashes to plugin.json.
7. **R7-9** (workspace sync in Quick Reference lacks trust qualifier) — Inline comment addition.
8. **R7-8** (`shasum` availability check) — Add command -v check with sha256sum fallback.
9. **R7-5** (ownership check in add_to_path) — Add stat owner check.
10. **R7-10** (`$schema` URL disclosure) — Add informational comment.

---

## Hardened Rewrite Recommendations for New Findings

### R7-3: Credential Write — Hardened Pattern

Replace `skills/forge.md` lines 156–157:
```bash
# Claude: Do NOT embed the API key in any command line, shell variable assignment, or
# Bash tool invocation. Doing so exposes the key in shell history and Claude session logs.
# Instead, prompt the user to provide the key interactively using the pattern below.
# If the Bash tool cannot use /dev/tty, instruct the user to set OPENROUTER_KEY in their
# terminal first, then tell Claude to run only the python3 heredoc block.
read -rs OPENROUTER_KEY < /dev/tty
export OPENROUTER_KEY
```

### R7-2: install.sh Non-Interactive Path — Hardened Pattern

In `install.sh`, within the binary install block, after computing `FORGE_SHA`:
```bash
printf '%s  %s  (downloaded %s)\n' "${FORGE_SHA}" "forgecode-install.sh" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${FORGE_SHA_LOG}"
echo "[forge-plugin] SHA logged to: ${FORGE_SHA_LOG}"
if [ -t 1 ]; then
  # Interactive terminal: give user a cancellation window
  echo "[forge-plugin] Press Ctrl+C within 10 seconds to cancel. Proceeding..."
  sleep 10
  bash "${FORGE_INSTALL_TMP}"
else
  # Non-interactive (SessionStart): abort and require interactive re-run for safety.
  echo "[forge-plugin] NON-INTERACTIVE INSTALL ABORTED — supply-chain safety gate." >&2
  echo "[forge-plugin] To install ForgeCode, open a terminal and run:" >&2
  echo "[forge-plugin]   bash '${CLAUDE_PLUGIN_ROOT}/install.sh'" >&2
  echo "[forge-plugin] Compare the printed SHA against: https://forgecode.dev/releases" >&2
  rm -f "${FORGE_INSTALL_TMP}"
  exit 0
fi
```

### R7-7: SHA Pinning Pattern

Add to `install.sh` (update `EXPECTED_FORGE_SHA` on each ForgeCode release):
```bash
# Pinned SHA-256 of forgecode install script — update on each ForgeCode release.
# Obtain from: https://forgecode.dev/releases (or GitHub release artifacts)
EXPECTED_FORGE_SHA="0000000000000000000000000000000000000000000000000000000000000000"
if [ "${FORGE_SHA}" != "${EXPECTED_FORGE_SHA}" ]; then
  echo "[forge-plugin] FATAL: SHA-256 mismatch — aborting installation." >&2
  echo "[forge-plugin]   Expected: ${EXPECTED_FORGE_SHA}" >&2
  echo "[forge-plugin]   Got:      ${FORGE_SHA}" >&2
  echo "[forge-plugin] Do NOT proceed. Verify the forgecode.dev release integrity." >&2
  rm -f "${FORGE_INSTALL_TMP}"
  exit 1
fi
```

---

## Step 8 — Self-Challenge Gate (Zero False Negative Confirmation)

### Challenge 1: Are all R6 findings verified against current file content?
Confirmed. Each R6 finding was evaluated against the specific line ranges of the current files, not assumed to be patched. Five findings confirmed fully patched (R6-3, R6-4, R6-6, R6-9, R6-10). Four confirmed partially patched (R6-1, R6-2, R6-5, R6-7). One confirmed not patched (R6-8). Evidence cited with line numbers for each.

### Challenge 2: Are there any code execution paths not examined?
All `bash`, `curl`, `wget`, `python3`, `forge`, `git`, and `shasum` invocations have been examined in both `install.sh` and `forge.md`. The STEP 9 Quick Reference was specifically audited as a separate execution surface from the detailed protocol sections — yielding R7-4 and R7-9.

### Challenge 3: Are any new findings false positives?
- R7-7 (SHA display-only): Could be argued as "working as intended given the documentation says to compare manually." Retained because the security messaging ("IMPORTANT: Compare this SHA-256") implies automated protection that does not exist, and the same-domain compromise scenario makes manual comparison ineffective.
- R7-10 (`$schema` URL): Retained as INFO only. Not a security flaw but a disclosure gap for privacy-sensitive environments.
- R7-8 (`shasum` availability): Retained as Low. Silent verification failure is a meaningful gap even if uncommon.

### Challenge 4: Did any R6 fix introduce new issues?
R6-7's partial fix (python3 heredoc) required adding `export OPENROUTER_KEY="KEY"` to the bash command — which shifts exposure from python3 process args to bash shell history and Claude tool output. This is R7-3. The R6 patch plan's recommended `read -rs` approach would have avoided this regression. Confirmed as a patch-introduced regression.

### Challenge 5: Is the severity rating for R7-4 inflated?
R7-4 receives CVSS I:H/A:H because `git checkout -- .` on a project with significant uncommitted changes permanently destroys that work (Integrity: High impact — authoritative data destroyed; Availability: High — work product permanently unavailable). The network vector is Local (AV:L) and no external exploitation is required. The score reflects local impact severity, not network exploitability.

**Conclusion: No false negatives identified. All R6 findings independently verified from file content. All new findings adversarially challenged. Zero findings suppressed.**

---

## Round 7 Verdict

> **ROUND 7 STATUS: FINDINGS PRESENT — NOT CLEAN**
> 10 findings (0 Critical, 3 Medium, 5 Low, 1 Info, 1 Info-residual).
> Five R6 findings fully confirmed patched. Five R6 findings confirmed partially patched or not patched.
> Three new findings discovered (R7-7, R7-8, R7-9) plus one patch-introduced regression (R7-3, R7-10 informational).
> Plugin is functional and has improved meaningfully from R1 baseline.
> The three Medium findings (R7-2, R7-3, R7-7) represent genuine unfixed or regression issues from R6.
> Proceed with remediation in priority order above before declaring audit-clean.
> A Round 8 patch-verification pass should be brief if R7-2, R7-3, and R7-7 are addressed.

---

*SENTINEL v2.3 — Report generated 2026-04-12*
*All findings are independently verified against current file content. Prior-round findings are not credited as fixed unless confirmed by line-number evidence in the current files.*

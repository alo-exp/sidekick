---
phase: v1.2.1-pre-release
reviewed: 2026-04-18T00:00:00Z
depth: standard
files_reviewed: 8
files_reviewed_list:
  - docs/pre-release-quality-gate.md
  - hooks/validate-release-gate.sh
  - CHANGELOG.md
  - .claude-plugin/plugin.json
  - skills/forge/SKILL.md
  - hooks/forge-delegation-enforcer.sh
  - hooks/forge-progress-surface.sh
  - commands/forge-replay.md
  - commands/forge-history.md
findings:
  critical: 2
  warning: 3
  info: 2
  total: 7
status: issues_found
---

# v1.2.1 Pre-Release Code Review — Reviewer B

**Reviewed:** 2026-04-18
**Depth:** standard
**Files Reviewed:** 9 (4 new/changed + 5 in-scope unchanged)
**Status:** issues_found

## Summary

The new `validate-release-gate.sh` hook has two critical correctness defects that make it non-functional as deployed: it reads from the wrong JSON field (the real Claude Code PreToolUse payload wraps the command under `tool_input.command`, not at the top level), and when it does block, it exits 1 (bare non-zero) rather than emitting the `permissionDecision: deny` JSON envelope that Claude Code requires. The result is that the hook will silently pass every real `gh release create` call from Claude Code — the gate is a no-op at runtime despite appearing correct in isolation.

The unchanged in-scope files (`forge-delegation-enforcer.sh`, `forge-progress-surface.sh`, `commands/`, `skills/forge/SKILL.md`) are well-structured and the contract-compliance work from v1.2.0 is solid. One pre-existing path inconsistency in `SKILL.md` (wrong credentials path) is flagged as it surfaced during the review.

---

## Critical Issues

### CR-01: Wrong JSON field path — gate never fires on real Claude Code input

**File:** `hooks/validate-release-gate.sh:13`

**Issue:** The hook extracts the Bash command from the top-level `.command` field of the JSON payload:

```python
json.load(sys.stdin).get('command', '')
```

Claude Code's PreToolUse hook payload nests the command under `tool_input.command`, not at the top level. The actual JSON shape is:

```json
{ "tool_name": "Bash", "tool_input": { "command": "gh release create ..." } }
```

`json.load(sys.stdin).get('command', '')` returns an empty string for every real invocation. The `if [[ "$COMMAND" != *"gh release create"* ]]` guard is then always true, and the hook exits 0 unconditionally — the quality gate never blocks anything.

**Verified:** running `printf '{"tool_name":"Bash","tool_input":{"command":"gh release create v1.2.1"}}' | bash hooks/validate-release-gate.sh` exits 0 with no output and no block.

**Fix:**
```python
# Replace line 13:
COMMAND=$(printf '%s' "$INPUT" | python3 -c \
  "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null)
```

---

### CR-02: Non-zero exit used for denial — violates Claude Code PreToolUse hook contract

**File:** `hooks/validate-release-gate.sh:46`

**Issue:** When the gate is incomplete, the hook exits 1:

```bash
exit 1
```

The Claude Code PreToolUse hook contract is:
- Exit 0 + empty stdout → pass-through (no decision)
- Exit 0 + JSON stdout → decision applied (`hookSpecificOutput` envelope)
- Non-zero exit → **hard precondition failure** — Claude Code treats this as a hook error, not a permission denial. Depending on the Claude Code version and configuration, this either crashes the hook silently or surfaces an error that confuses the user.

The correct pattern (as implemented correctly in `hooks/forge-delegation-enforcer.sh`) is to emit a `permissionDecision: deny` JSON envelope on stdout and exit 0.

**Fix:**
```bash
# Replace the final `exit 1` at line 46 with:
jq -cn \
  --arg reason "Pre-release quality gate incomplete. Missing: $(IFS=', '; echo "${missing[*]}")" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
exit 0
```

---

## Warnings

### WR-01: python3 absence silently disables the gate

**File:** `hooks/validate-release-gate.sh:13`

**Issue:** The `python3 -c ...` call is wrapped in `2>/dev/null` with no fallback. If `python3` is not on `PATH`, `COMMAND` is the empty string and the hook exits 0 unconditionally — the gate is completely bypassed. This is a silent failure mode with no warning to the operator.

**Fix:** Add a guard before the command extraction:

```bash
if ! command -v python3 >/dev/null 2>&1; then
  echo "validate-release-gate: python3 not found — gate cannot run" >&2
  exit 2
fi
```

Or alternatively, use `jq` (already required by the enforcer hook) for the extraction:

```bash
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
```

---

### WR-02: Wrong credentials path in `SKILL.md` health check

**File:** `skills/forge/SKILL.md:25`

**Issue:** The health check command references `~/forge/.credentials.json`:

```
jq -e '...' ~/forge/.credentials.json
```

The correct Forge credentials path is `~/.forge/.credentials.json` (dotfile directory). The docs/pre-release-quality-gate.md explicitly calls this out in two places (lines 132 and 191) as a known correctness requirement. A missing dot in the path causes health check #3 to fail on every valid install, preventing `/forge` activation.

**Fix:** Change line 25 of `SKILL.md`:
```
# Wrong:
~/forge/.credentials.json

# Correct:
~/.forge/.credentials.json
```

---

### WR-03: `rewrite_forge_p()` is dead code — inline duplicate in `decide_bash`

**File:** `hooks/forge-delegation-enforcer.sh:316-326`

**Issue:** `rewrite_forge_p()` is defined at line 316 but never called. `decide_bash()` duplicates its logic inline at lines 354-356. The two copies are structurally identical today, but divergence is a latent bug risk — a future patch to one copy will silently leave the other stale. Maintenance burden, not correctness today.

**Fix:** Either remove `rewrite_forge_p()` entirely, or refactor `decide_bash` to call it:

```bash
# Option A: remove the dead function and add a comment why it was inlined.

# Option B: call it:
rewritten="$(rewrite_forge_p "$cmd")"
emit_decision "allow" "Sidekick: injected --conversation-id + --verbose + output prefixing." "$rewritten"
```

Note: If option B is chosen, `rewrite_forge_p` must be updated to also return the UUID so `append_idx_row` receives the same UUID that was injected into the command.

---

## Info

### IN-01: Box-drawing alignment off by one column

**File:** `hooks/validate-release-gate.sh:38`

**Issue:** The `printf` format string `"║  ✗ %-59s║\n"` produces rows that are 65 display columns wide, while the header/footer lines are 64 display columns wide. This results in misaligned box borders in terminal output (the right-side `║` hangs one column past the corner characters).

```
╔══════════════════════════════════════════════════════════════╗   ← 64 cols
║  ✗ Stage 1 missing                                            ║   ← 65 cols
```

**Fix:** Change `%-59s` to `%-58s` on line 38.

---

### IN-02: `validate-release-gate.sh` missing from `_integrity` in `plugin.json`

**File:** `.claude-plugin/plugin.json:48-62`

**Issue:** `hooks/validate-release-gate.sh` is a new v1.2.1 file but has no SHA-256 entry in the `_integrity` block. The CHANGELOG correctly notes it is "wired into the user's `~/.claude/settings.json`" (not the plugin manifest), so omitting it from `plugin.json`'s `PreToolUse` hooks list is intentional. However, because the file is part of the plugin bundle and audited as a security surface, the absence of an integrity hash means `tests/test_plugin_integrity.bash` provides no tamper-detection for it.

**Fix:** Add an entry to `_integrity`:
```json
"validate_release_gate_sha256": "<sha256 of hooks/validate-release-gate.sh>"
```
And add a corresponding assertion to `tests/test_plugin_integrity.bash`.

---

_Reviewed: 2026-04-18_
_Reviewer: Claude (gsd-code-reviewer / Reviewer B)_
_Depth: standard_

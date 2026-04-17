# Phase 6 Research — Delegation Enforcement Hook + Audit Index

**Researched:** 2026-04-18
**Scope:** What does the planner need to know to plan Phase 6 well?
**Phase goal (from ROADMAP.md):** When `/forge` mode is active, direct `Write`/`Edit`/`NotebookEdit` calls are deterministically blocked at the harness level, `Bash forge -p` commands are rewritten to inject a valid UUID `--conversation-id` and `--verbose`, read-only Brain-role Bash commands pass through unmodified, and every rewritten Forge invocation is appended to `.forge/conversations.idx`.

---

## 1. Claude Code PreToolUse Hook Contract (CANONICAL)

Source: https://code.claude.com/docs/en/hooks.md and https://code.claude.com/docs/en/hooks-guide.md (verified 2026-04-18).

### Hook invocation

- Claude Code spawns the hook as a subprocess.
- Hook receives **tool call context via stdin as JSON**, including `tool_name` and `tool_input` fields.
- Hook communicates its decision via **stdout as JSON** (recommended) OR **exit code + stderr**.

### Canonical JSON output shape

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow" | "deny" | "ask" | "defer",
    "permissionDecisionReason": "<user-visible reason, shown in transcript>",
    "updatedInput": {
      "command": "<rewritten Bash command>"
    }
  }
}
```

- **`permissionDecision`** values:
  - `"allow"` → tool call proceeds. If `updatedInput` is present, the tool runs with the modified input.
  - `"deny"` → tool call is blocked. `permissionDecisionReason` is surfaced to Claude (and the user) as an error.
  - `"ask"` → prompts the user interactively (not useful for us; not a Bash rewrite use case).
  - `"defer"` → pass through to the next hook in the chain.
- **`updatedInput.command`** is the exact string that will replace the original Bash command. **NOT** `modifiedCommand` (the v1.2 spec's guess was wrong).
- Hook MUST **exit 0** to have its JSON read. Non-zero exit codes are treated as errors; **exit 2** specifically blocks the tool call with stderr surfaced as the reason (legacy path — prefer the JSON path for structured output).

### Implications for `forge-delegation-enforcer.sh`

1. The hook reads stdin JSON, parses `tool_name` and `tool_input`, and decides one of:
   - Emit `permissionDecision: "deny"` with a user-visible reason (for blocked `Write`/`Edit`/`NotebookEdit`).
   - Emit `permissionDecision: "allow"` with `updatedInput.command` rewritten (for `Bash forge -p …`).
   - Emit **no output** and exit 0 (pass-through for read-only Bash and when `/forge` mode is inactive).
2. Stdin JSON parsing in pure bash is ugly — use `jq` for both input parse and output emit. `jq` is required.
3. The shebang should be `#!/usr/bin/env bash` and the hook must be `chmod +x`.
4. The hook runs once **per tool call**, so performance matters (keep it cheap — no network I/O, no Forge subprocess).

---

## 2. Forge CLI Conversation ID Constraints (VERIFIED)

Source: direct testing against Forge 2.11.3, captured in [v12_claude_code_api_corrections memory](../memory) and [forge_conversation_id_format memory](../memory).

### Hard constraints

- `forge --conversation-id <id> --verbose -p "<prompt>"` is the **only working flag order**. `forge -p --conversation-id …` causes Forge to treat `--conversation-id` as the `-p` prompt value (silent misuse).
- `--conversation-id` **must be a valid RFC 4122 UUID, lowercase**. Forge rejects custom formats with: `invalid conversation id: invalid character: found 's' at 1`.
- Generate the UUID with: `uuidgen | tr 'A-Z' 'a-z'`. Verified on macOS (`uuidgen` ships with base OS) and Linux (`util-linux` provides `uuidgen`).

### Implications for the hook

1. Inject `--conversation-id <uuid> --verbose` **immediately after** `forge` and **before** the `-p` flag. Regex:
   - Match `\bforge\b(.*?) -p ` and rewrite to `\bforge\b --conversation-id <uuid> --verbose\1 -p ` — but keep it simple; the spec's intent is that most callers say literally `forge -p …`.
   - A string-substitution approach that inserts `--conversation-id <uuid> --verbose ` right after the `forge ` token works for 95% of cases. Document the assumption.
2. Idempotency: if the input command already contains `--conversation-id`, skip rewrite and pass through with `permissionDecision: "allow"` (no `updatedInput`).
3. The human-readable `sidekick-<unix>-<rand8>` tag lives ONLY in `.forge/conversations.idx` row 3 (label column). It is never passed to Forge.

---

## 3. Output Pipe Wrapping for `[FORGE]`/`[FORGE-LOG]` Prefixing

### Approach

Wrap the rewritten command so stdout is prefixed with `[FORGE] ` and stderr with `[FORGE-LOG] `:

```bash
forge --conversation-id <uuid> --verbose -p "<prompt>" 2> >(sed 's/^/[FORGE-LOG] /' >&2) | sed 's/^/[FORGE] /'
```

### Known issues

- **ANSI escape codes:** Forge emits color codes by default. Strip via an extra `sed 's/\x1b\[[0-9;]*m//g'` between `forge` and the prefix-sed. This belongs in Phase 7 (progress surface), not Phase 6 — but the Phase 6 rewrite should leave space for it (e.g., the pipe chain is easy to extend).
- **Subshell semantics:** `2> >(…)` is a process substitution, bash-only (not POSIX sh). The hook MUST use `#!/usr/bin/env bash`, not `/bin/sh`.
- **Exit code preservation:** Piping through `sed` loses the original exit code. If exit codes matter downstream (e.g., Claude uses them to detect Forge failure), use `set -o pipefail` or redirect via `wait`/`PIPESTATUS[0]`.

---

## 4. `.forge/conversations.idx` Format

### Proposed format (append-only, newline-delimited)

Each row is a tab-separated tuple (or space-separated if values are constrained):

```
<ISO8601-UTC>\t<UUID>\t<sidekick-tag>\t<task-hint>
```

Example:

```
2026-04-18T03:42:17Z	4c2a8f1e-9b3d-4a5e-8c6f-1e2d3f4a5b6c	sidekick-1776438137-4c2a8f1e	Refactor utils.py to use early returns
```

Notes:

- `task-hint`: first 80 chars of the `-p` prompt, stripped of newlines and tabs. Purely for human display in `/forge:history` — never parsed by anything critical.
- ISO8601 UTC with `Z` suffix, via `date -u +%FT%TZ`.
- Tab separator keeps parsing trivial for `/forge:history` (Phase 8): `cut -f1,2,3,4`.
- File is project-scoped: `$CLAUDE_PROJECT_DIR/.forge/conversations.idx`.

### Growth control

- Defer pruning to `/forge:history` in Phase 8 (spec: prune >30 days on each invocation).
- Phase 6 writes unbounded; in practice one row per Forge invocation, so growth is bounded by usage.

---

## 5. Activation / Deactivation Lifecycle

### Marker file

`~/.claude/.forge-delegation-active` (zero-byte) is the canonical "mode on" signal. Created by `/forge` activation (Phase 1, already shipped), deleted by `/forge:deactivate`.

### Phase 6 adds to activation (ACT-01, ACT-02, ACT-03)

1. **ACT-01:** Before activating, run `forge conversation list >/dev/null 2>&1`. If exit code != 0, the DB is locked or Forge is not healthy — print a clear error and abort activation. This is a one-line check in `commands/forge.md`.
2. **ACT-02:** On successful activation, `mkdir -p "$CLAUDE_PROJECT_DIR/.forge"` and `touch "$CLAUDE_PROJECT_DIR/.forge/conversations.idx"` if missing. Do NOT overwrite an existing idx.
3. **ACT-03:** Deactivation (existing `/forge:deactivate` command) deletes the marker file. Leave `.forge/conversations.idx` in place — it's history, not state.

ACT-04 (output-style switch) lives in Phase 7, not here.

---

## 6. Existing Project Artifacts to Preserve

Phase 6 must NOT modify:

- `install.sh` (binary installer — already shipped)
- `hooks/hooks.json` (existing SessionStart hooks — unrelated)
- `skills/forge.md` (862-line existing skill — unchanged; only `skills/forge/SKILL.md` is touched in Phase 7)
- Any `.planning/` artifacts for shipped Phases 1-5

Phase 6 creates:

- `hooks/forge-delegation-enforcer.sh` — new PreToolUse hook
- `hooks/README.md` — if not already present, document the hook contract (optional but recommended for v1.2 contributors)
- `commands/forge.md` — UPDATE existing file to add the `forge conversation list` health check + `.forge/conversations.idx` init (additive only; do not remove existing activation logic)
- `.claude-plugin/plugin.json` — ADD the PreToolUse hook registration (version bump to 1.2.0 is deferred to Phase 8, but the hook registration can land here to make the Phase 6 artifact testable; or Phase 8 absorbs all plugin.json churn — planner decides)

---

## 7. Testing Strategy (Phase 6 scope)

Phase 6 tests are WRITTEN but executed as part of Phase 9's broader test suite. Phase 6 ships the tests **so they exist and are runnable**, but the Phase 9 verifier asserts the full suite passes.

### Minimum test matrix for Phase 6

1. **Hook no-op when `/forge` mode is inactive** — unit test: run the hook with `~/.claude/.forge-delegation-active` absent; assert empty stdout, exit 0.
2. **Hook deny on `Write` when active** — stdin contains `{"tool_name":"Write",…}` with marker present; assert JSON output with `permissionDecision: "deny"` and a reason mentioning `forge -p`.
3. **Hook rewrite on `Bash forge -p`** — stdin: `{"tool_name":"Bash","tool_input":{"command":"forge -p 'Refactor utils.py'"}}`; assert `permissionDecision: "allow"`, `updatedInput.command` matches regex `forge --conversation-id [0-9a-f-]{36} --verbose -p '…'` and ends with the output-prefix pipe chain.
4. **UUID validity** — generated IDs match RFC 4122 lowercase regex `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`.
5. **Idempotent rewrite** — command already containing `--conversation-id` passes through unchanged (no second injection).
6. **Read-only Bash passthrough** — `git status`, `ls`, `grep`, `cat`, `find` produce no hook output (passthrough).
7. **Mutating Bash block** — `rm foo`, `git commit -m "x"`, etc. produce `permissionDecision: "deny"` unless `FORGE_LEVEL_3=1` is set.
8. **`.forge/conversations.idx` append** — after a rewrite, the idx file gains exactly one new line in the documented format.

`bats` or pure-bash test harness — the existing test suite format should drive this (see `tests/` directory when planning).

---

## 8. Execution Order & Dependencies

The 16 requirements decompose naturally into three bands:

- **Band A (foundation):** HOOK-01 (register in plugin.json), HOOK-02 (no-op when inactive), HOOK-08 (UUID generation), HOOK-09 (exit codes), ACT-02 (idx init on activation), AUDIT-03 (idx creation on activation).
- **Band B (decision logic):** HOOK-03 (deny Write/Edit/NotebookEdit), HOOK-04 (allow + rewrite forge -p), HOOK-05 (deny mutating Bash), HOOK-06 (passthrough read-only Bash), HOOK-07 (idempotent rewrite), ACT-01 (DB-writable check), ACT-03 (deactivation preserves idx).
- **Band C (audit)::** AUDIT-01 (idx append on rewrite), AUDIT-02 (sidekick-tag alongside UUID), AUDIT-04 (no duplication of Forge native storage — this is a negative requirement, a design constraint more than a task).

**Recommended plan decomposition:**

- Plan 06-01: Foundation — hook skeleton, UUID helper, no-op path, plugin.json registration (Band A; requirements HOOK-01, HOOK-02, HOOK-08, HOOK-09, MAN-adjacent plumbing if Phase 6 owns it).
- Plan 06-02: Decision logic — deny Write/Edit/NotebookEdit, rewrite forge -p with UUID injection and output-pipe wrapping, mutating-Bash block with Level-3 bypass, read-only passthrough, idempotency (Band B; requirements HOOK-03..07).
- Plan 06-03: Audit index + activation lifecycle — idx init on activation, DB-writable pre-check, append-on-rewrite, deactivation preservation, and the Phase 6 test suite (Band C + ACT-01..03 + AUDIT-01..04 + Phase 6 test files).

This keeps each plan under ~4 concrete tasks and parallelizable-within-wave where practical.

---

## 9. Open Risks / Unknowns

- **Claude Code PreToolUse hook behavior on `updatedInput` for Bash** — verified via docs; untested in this repo yet. First integration run may reveal edge cases (e.g., does `Monitor` work on an `updatedInput`-rewritten Bash? Likely yes, but Phase 7's integration test confirms.)
- **Process substitution + `jq` portability** — works on macOS bash 3.2, Linux bash 4+. Windows WSL is supported by Sidekick's installer path; native Windows PowerShell is not. Confirm the plugin's supported platforms in plugin.json / README.
- **`forge conversation list` performance** — used as a DB-writable check during `/forge` activation. If this is slow (>1s), activation UX degrades. Mitigation: defer the check to first actual delegation; or accept 1-2s activation latency as acceptable.
- **Token budget for the hook itself** — the hook runs per tool call. If it emits >500 bytes of JSON per call, and Claude reads that back, long sessions accumulate overhead. Keep hook output tight.

---

## RESEARCH COMPLETE

---
name: kay-delegate
description: Canonical Kay delegation workflow for the Kay sidekick. Use when activating Kay mode before delegated implementation work.
---

# Kay Delegate Workflow

Kay is the implementation sidekick. The host AI plans, explains, and verifies.
Kay writes files, runs tests, and executes implementation work.

```
Host AI = Brain
Kay     = Hands
```

## Host Routing

- Claude Code and Codex hosts both follow STEP 0 through STEP 3.
- When the active host is Codex, treat Kay as a child execution process launched through `kay exec`; do not confuse host Codex planning work with delegated Kay implementation work.

The stop workflow lives canonically in `kay-stop/SKILL.md` in this generated codex skill root (`agents/codex/kay-stop/SKILL.md` in the repository).

## Runtime Readiness

Kay readiness is checked when delegation starts for the current session. SessionStart does not update or repair the Kay runtime; if the health check fails, guide the user through the Kay setup or login path below.

## STEP 0 -- Health Check

Before delegating, verify the runtime is available:

```bash
for candidate in kay code coder; do
  if command -v "$candidate" >/dev/null 2>&1 \
    && "$candidate" --version 2>/dev/null | grep -qiE '^kay([[:space:]]|$)' \
    && "$candidate" exec --help >/dev/null 2>&1; then
    KAY_RUNTIME="$candidate"
    break
  fi
done
test -n "${KAY_RUNTIME:-}" || { echo "No Kay-compatible runtime found"; exit 1; }
```

Then verify Kay config:

- `$CODE_HOME/config.toml` defaults to `~/.kay/config.toml`
- legacy `~/.code/config.toml` and `~/.codex/config.toml` are compatibility-only
- provider should be `opencode-go` for Sidekick's Kay delegation path
- Sidekick routes Kay models automatically by task type:
  - planning, main workhorse, and reviewing tasks -> `mimo-v2.5-pro`
  - vision and visual reasoning tasks -> `mimo-v2.5`
  - trivial technical work -> `minimax-m2.7`
  - work completion verification, not review -> `deepseek-v4-flash`

If login is missing, guide the user to:

```bash
kay login --provider opencode-go --with-api-key
```

If `kay` is unavailable, install or repair Kay. The `code` and `coder` names are compatibility aliases only. The `codex` binary name is reserved for the real OpenAI Codex CLI.

## STEP 1 -- Activate Kay Mode

Create the current-session Kay marker before delegating so Sidekick hooks can enforce direct-edit denial, inject `--full-auto`, surface bounded redacted Kay output with `[KAY]` and `[KAY-SUMMARY]` markers, and maintain `.kay/conversations.idx`:

```bash
SIDEKICK_SESSION="${SIDEKICK_SESSION_ID:-${CODEX_THREAD_ID:-${SESSION_ID:-}}}"
test -n "${SIDEKICK_SESSION}" || { echo "No host session id found for Kay mode"; exit 1; }
KAY_STATE_ROOT="${HOME}/.kay"
CODEX_STATE_ROOT="${HOME}/.codex"
mkdir -p "${KAY_STATE_ROOT}/sessions/${SIDEKICK_SESSION}" \
  "${HOME}/.codex/sessions/${SIDEKICK_SESSION}" \
  "${HOME}/.sidekick/sessions/${SIDEKICK_SESSION}"
rm -f "${CODEX_STATE_ROOT}/sessions/${SIDEKICK_SESSION}/.codex-delegation-active"
printf '%s\n' "kay" > "${HOME}/.sidekick/sessions/${SIDEKICK_SESSION}/active-sidekick"
: > "${KAY_STATE_ROOT}/sessions/${SIDEKICK_SESSION}/.kay-delegation-active"
```

Kay and Codex are mutually exclusive per host session. Kay activation clears any current-session Codex marker and writes `active-sidekick=kay`, so the Codex hook becomes a no-op before Kay commands start.

Confirm: **"Kay sidekick mode activated for this session. Delegating implementation work to Kay."**

To stop: `/sidekick:kay-stop`

## STEP 2 -- Delegation Protocol

Child runtime command used after Kay mode is active:

```bash
kay exec --full-auto "<task description>"
```

Compatibility aliases (`code`, `codex`, `coder`) accept the same arguments when an older environment only exposes them.

Sidekick injects the OpenCode Go provider and task-specific model automatically when Kay mode is active. Do not hand-add `-c model_provider=...` or `-c model=...` unless you are debugging the routing layer.

Useful options:

- `--json` for machine-readable progress
- `--output-last-message` for final-response-only output
- `resume --last` to continue prior non-interactive sessions

## STEP 3 -- Native Workflow

- Use Kay's native `kay exec` automation for file changes, tests, and commits.
- Use repository `AGENTS.md` instructions.
- Use native Kay agents/subagents when tasks benefit from parallel work.

## STEP 4 -- Host Verification and Recovery

Use this loop after every sidekick task or subtask before reporting completion, starting dependent work, or accepting a sidekick `STATUS: SUCCESS`. Treat `STATUS: SUCCESS` as a claim to audit, not proof.

Verification checklist:

- Compare the final repo state and diff against the original task prompt and success criteria.
- Run the smallest meaningful verification commands: tests, type checks, linters, builds, or targeted runtime checks.
- Inspect integration points: filenames, signatures, types, imports, configuration, and existing behavior touched by the change.
- Classify any failure with one or more taxonomy codes: `MISSED_REQUIREMENT`, `INTEGRATION_ERROR`, `REGRESSION`, `WRONG_LOGIC`, `SYNTAX_ERROR`, `WRONG_FILE`, `UNVERIFIED_ASSUMPTION`, `KNOWLEDGE_GAP`, `MISUNDERSTOOD_TASK`, `TRIAL_INCOMPLETE`, `API_FAILURE`, `EXECUTION_ERROR_EXTERNAL`.

Recovery protocol:

1. If a failure is detected, relaunch the active Kay sidekick for the missed task, missed subtask, or correction.
2. Give Kay a focused correction prompt with the original task prompt, failure code(s), observed evidence, relevant files/tests, constraints, and exact success criteria.
3. Actively handhold when needed: split the work into smaller subtasks, point to repo examples, specify the expected API/signature, or forbid the wrong location or approach.
4. Repeat verify -> relaunch until the success criteria pass and no taxonomy failure remains.
5. For `TRIAL_INCOMPLETE`, `API_FAILURE`, or `EXECUTION_ERROR_EXTERNAL`, do not treat partial output as complete; retry after the model provider or environment is usable, or report the external blocker with evidence.

The host AI only reports completion after its own verification evidence supports the result.

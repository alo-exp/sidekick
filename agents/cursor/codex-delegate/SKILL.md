---
name: codex
description: Canonical Codex delegation workflow for the OpenAI Codex CLI sidekick. Use when activating Codex mode before delegated implementation work.
argument-hint: "<task to delegate to Codex>"
---

# Codex Delegate Workflow

Codex is the OpenAI execution sidekick. The host AI plans, explains, and verifies.
Codex writes files, runs tests, and executes implementation work through the local OpenAI Codex CLI.

```
Host AI = Brain
Codex   = Hands
```

## Host Routing

- Claude Code, Codex, and Cursor hosts all follow STEP 0 through STEP 3.
- When the active host is Codex, treat the delegated Codex CLI session as a child execution process, not as a replacement for the host's own planning and communication role.
- When the active host is Cursor, treat the delegated Codex CLI session as a child execution process; Cursor's sessionStart hook binds `SIDEKICK_SESSION_ID` before activation, and sessionEnd clears session-scoped delegation markers.

## Division of Labor (active delegation)

While Codex mode is active, the host AI remains the user-interactor, orchestrator, verifier, advisor, and mentor. Codex is the primary implementation executor.

The host keeps freedom to:

- Read, search, and inspect the codebase for verification and diagnosis
- Run read-only or verification shell commands (`git status`, `git diff`, `bash tests/*.bash`, and similar)
- Launch Task subagents for non-implementation orchestration when appropriate
- Edit planning docs under `.planning/` and `site/`
- Communicate with the user

Sidekick hooks narrow enforcement to implementation ownership: direct Write/Edit/Delete on implementation files is denied on Claude/Codex hosts and surfaced as an advisory on Cursor via postToolUse. Delegate implementation through `codex exec`.

## Runtime Readiness

Codex readiness is checked when delegation starts for the current session. SessionStart does not install or repair the runtime. If the health check fails, guide the user through the local OpenAI Codex CLI setup path first.

## STEP 0 -- Health Check

Before delegating, verify the local OpenAI Codex CLI is available:

```bash
if command -v codex >/dev/null 2>&1 \
  && ! codex --version 2>/dev/null | grep -qiE '^kay([[:space:]]|$)' \
  && codex exec --help 2>/dev/null | grep -q -- '--ask-for-approval'; then
  CODEX_RUNTIME="codex"
fi
test -n "${CODEX_RUNTIME:-}" || { echo "No OpenAI Codex CLI runtime found"; exit 1; }
```

This check intentionally rejects the legacy Kay compatibility alias exposed as `codex`. Sidekick's Codex mode requires the real OpenAI Codex CLI.

Delegation defaults:

- model -> `gpt-5.4-mini`
- reasoning effort -> `xhigh`
- sandbox -> `workspace-write`
- approval policy -> `never`

If the CLI is installed but not authenticated, guide the user through the local OpenAI Codex CLI login flow before continuing.

## STEP 1 -- Activate Codex Mode

Create the current-session Codex marker before delegating so Sidekick hooks can enforce direct-edit denial, inject the Codex runtime flags above, surface bounded redacted Codex output with `[CODEX]` and `[CODEX-SUMMARY]` markers, and maintain `.codex/conversations.idx`:

```bash
SIDEKICK_SESSION="${SIDEKICK_SESSION_ID:-${SESSION_ID:-}}"
test -n "${SIDEKICK_SESSION}" || { echo "No host session id found for Codex mode"; exit 1; }
CODEX_STATE_ROOT="${HOME}/.codex"
mkdir -p "${CODEX_STATE_ROOT}/sessions/${SIDEKICK_SESSION}" \
  "${HOME}/.sidekick/sessions/${SIDEKICK_SESSION}"
rm -f "${HOME}/.kay/sessions/${SIDEKICK_SESSION}/.kay-delegation-active"
printf '%s\n' "codex" > "${HOME}/.sidekick/sessions/${SIDEKICK_SESSION}/active-sidekick"
: > "${CODEX_STATE_ROOT}/sessions/${SIDEKICK_SESSION}/.codex-delegation-active"
```

Session-scoped markers only:

- `~/.sidekick/sessions/<session>/active-sidekick` — shared selector (`kay` or `codex`)
- `~/.codex/sessions/<session>/.codex-delegation-active` — Codex enforcement marker

Delegation ends when the host session ends (Cursor sessionEnd hook clears markers) or when `/sidekick:codex-stop` runs. Do not use project-level or repo-root activation markers.

Codex and Kay are mutually exclusive per host session. Codex activation clears any current-session Kay marker and writes `active-sidekick=codex`, so the Kay hook becomes a no-op before Codex commands start.

Confirm: **"Codex sidekick mode activated for this session. Delegating implementation work to Codex."**

To stop: `/sidekick:codex-stop`

## STEP 2 -- Delegation Protocol

Child runtime command used after Codex mode is active:

```bash
codex exec -m gpt-5.4-mini -c model_reasoning_effort=xhigh --sandbox workspace-write --ask-for-approval never "<task description>"
```

Sidekick injects the model, reasoning, sandbox, and approval flags automatically while Codex mode is active. Do not hand-add them unless you are debugging the routing layer.

Useful options:

- `--json` for machine-readable progress
- `--output-last-message` for final-response-only output
- `resume --last` to continue prior non-interactive sessions

## STEP 3 -- Native Workflow

- Use the OpenAI Codex CLI's native `codex exec` automation for file changes, tests, and commits.
- Use repository `AGENTS.md` instructions.
- Keep the host AI responsible for architecture, explanations, review, and user communication.

## STEP 4 -- Host Verification and Recovery

Use this loop after every sidekick task or subtask before reporting completion, starting dependent work, or accepting a sidekick `STATUS: SUCCESS`. Treat `STATUS: SUCCESS` as a claim to audit, not proof.

Verification checklist:

- Compare the final repo state and diff against the original task prompt and success criteria.
- Run the smallest meaningful verification commands: tests, type checks, linters, builds, or targeted runtime checks.
- Inspect integration points: filenames, signatures, types, imports, configuration, and existing behavior touched by the change.
- Classify any failure with one or more taxonomy codes: `MISSED_REQUIREMENT`, `INTEGRATION_ERROR`, `REGRESSION`, `WRONG_LOGIC`, `SYNTAX_ERROR`, `WRONG_FILE`, `UNVERIFIED_ASSUMPTION`, `KNOWLEDGE_GAP`, `MISUNDERSTOOD_TASK`, `TRIAL_INCOMPLETE`, `API_FAILURE`, `EXECUTION_ERROR_EXTERNAL`.

Recovery protocol:

1. If a failure is detected, relaunch the active Codex sidekick for the missed task, missed subtask, or correction.
2. Give Codex a focused correction prompt with the original task prompt, failure code(s), observed evidence, relevant files/tests, constraints, and exact success criteria.
3. Actively handhold when needed: split the work into smaller subtasks, point to repo examples, specify the expected API/signature, or forbid the wrong location or approach.
4. Repeat verify -> relaunch until the success criteria pass and no taxonomy failure remains.
5. For `TRIAL_INCOMPLETE`, `API_FAILURE`, or `EXECUTION_ERROR_EXTERNAL`, do not treat partial output as complete; retry after the model provider or environment is usable, or report the external blocker with evidence.

The host AI only reports completion after its own verification evidence supports the result.

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

The stop workflow lives canonically in `skills/kay-stop/SKILL.md`.

## Runtime Readiness

Kay readiness is checked when delegation starts for the current session. SessionStart does not update or repair the Kay runtime; if the health check fails, guide the user through the Kay setup or login path below.

## STEP 0 -- Health Check

Before delegating, verify the runtime is available:

```bash
for candidate in kay code codex coder; do
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

If `kay` is unavailable, install or repair Kay. The `code`, `codex`, and `coder` names are compatibility aliases only.

## STEP 1 -- Activate Kay Mode

Create the current-session Kay marker before delegating so Sidekick hooks can enforce direct-edit denial, inject `--full-auto`, surface bounded redacted Kay output with `[KAY]` and `[KAY-SUMMARY]` markers, and maintain `.kay/conversations.idx`:

```bash
if [[ -z "${SIDEKICK_HOST_HOME:-}" ]]; then
  if [[ -n "${CODEX_HOME:-${CODEX_THREAD_ID:-${CODEX_PROJECT_DIR:-${CODEX_PLUGIN_ROOT:-}}}}" ]]; then
    SIDEKICK_HOST_HOME="${CODEX_HOME:-${HOME}/.codex}"
  elif [[ -n "${CLAUDE_SESSION_ID:-${CLAUDE_PROJECT_DIR:-${CLAUDE_PLUGIN_ROOT:-}}}" ]]; then
    SIDEKICK_HOST_HOME="${HOME}/.claude"
  else
    echo "No host home found for Kay mode"; exit 1
  fi
fi
SIDEKICK_SESSION="${SIDEKICK_SESSION_ID:-${SIDEKICK_HOST_SESSION_ID:-${CODEX_THREAD_ID:-${CLAUDE_SESSION_ID:-${SESSION_ID:-}}}}}"
test -n "${SIDEKICK_SESSION}" || { echo "No host session id found for Kay mode"; exit 1; }
KAY_STATE_ROOT="${HOME}/.kay"
CODEX_STATE_ROOT="${HOME}/.codex"
mkdir -p "${KAY_STATE_ROOT}/sessions/${SIDEKICK_SESSION}" \
  "${SIDEKICK_HOST_HOME}/sessions/${SIDEKICK_SESSION}" \
  "${HOME}/.sidekick/sessions/${SIDEKICK_SESSION}"
rm -f "${SIDEKICK_HOST_HOME}/sessions/${SIDEKICK_SESSION}/.forge-delegation-active" \
  "${SIDEKICK_HOST_HOME}/sessions/${SIDEKICK_SESSION}/.forge-level3-active" \
  "${CODEX_STATE_ROOT}/sessions/${SIDEKICK_SESSION}/.codex-delegation-active"
printf '%s\n' "kay" > "${HOME}/.sidekick/sessions/${SIDEKICK_SESSION}/active-sidekick"
: > "${KAY_STATE_ROOT}/sessions/${SIDEKICK_SESSION}/.kay-delegation-active"
```

Kay, Codex, and Forge are mutually exclusive per host session. Kay activation clears any current-session Forge and Codex markers and writes `active-sidekick=kay`, so the other hooks become no-ops before Kay commands start.

Confirm: **"Kay sidekick mode activated for this session. Delegating implementation work to Kay."**

To stop: `/kay-stop`

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

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
- provider should match the chosen backend path, usually `minimax` or `opencode-go`
- MiniMax path should use `MiniMax-M2.7`

If login is missing, guide the user to:

```bash
kay login --provider minimax --with-api-key
```

If `kay` is unavailable, install or repair Kay. The `code`, `codex`, and `coder` names are compatibility aliases only.

## STEP 1 -- Activate Kay Mode

Create the current-session Kay marker before delegating so Sidekick hooks can enforce direct-edit denial, inject `--full-auto`, surface bounded redacted Kay output with `[KAY]` and `[KAY-SUMMARY]` markers, and maintain `.kay/conversations.idx`:

```bash
SIDEKICK_SESSION="${SIDEKICK_SESSION_ID:-${CODEX_THREAD_ID:-${CLAUDE_SESSION_ID:-${SESSION_ID:-}}}}"
test -n "${SIDEKICK_SESSION}" || { echo "No host session id found for Kay mode"; exit 1; }
mkdir -p "${HOME}/.kay/sessions/${SIDEKICK_SESSION}" \
  "${HOME}/.claude/sessions/${SIDEKICK_SESSION}" \
  "${HOME}/.codex/sessions/${SIDEKICK_SESSION}" \
  "${HOME}/.sidekick/sessions/${SIDEKICK_SESSION}"
rm -f "${HOME}/.claude/sessions/${SIDEKICK_SESSION}/.forge-delegation-active" \
  "${HOME}/.claude/sessions/${SIDEKICK_SESSION}/.forge-level3-active" \
  "${HOME}/.codex/sessions/${SIDEKICK_SESSION}/.forge-delegation-active" \
  "${HOME}/.codex/sessions/${SIDEKICK_SESSION}/.forge-level3-active"
printf '%s\n' "kay" > "${HOME}/.sidekick/sessions/${SIDEKICK_SESSION}/active-sidekick"
: > "${HOME}/.kay/sessions/${SIDEKICK_SESSION}/.kay-delegation-active"
```

Kay and Forge are mutually exclusive per host session. Kay activation clears any current-session Forge marker and writes `active-sidekick=kay`, so the Forge hook becomes a no-op before Kay commands start.

Confirm: **"Kay sidekick mode activated for this session. Delegating implementation work to Kay."**

To stop: `/kay-stop`

## STEP 2 -- Delegation Protocol

Child runtime command used after Kay mode is active:

```bash
kay exec --full-auto "<task description>"
```

Compatibility aliases (`code`, `codex`, `coder`) accept the same arguments when an older environment only exposes them.

Useful options:

- `--json` for machine-readable progress
- `--output-last-message` for final-response-only output
- `resume --last` to continue prior non-interactive sessions

## STEP 3 -- Native Workflow

- Use Kay's native `kay exec` automation for file changes, tests, and commits.
- Use repository `AGENTS.md` instructions.
- Use native Kay agents/subagents when tasks benefit from parallel work.

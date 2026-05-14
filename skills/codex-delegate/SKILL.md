---
name: kay-delegate
description: Canonical Kay delegation workflow for the Kay sidekick. Use when delegating implementation work to kay exec.
---

# Kay Delegate Workflow

Every Kay is the implementation sidekick. Claude plans, explains, and verifies.
Kay writes files, runs tests, and executes implementation work.

```
Claude = Brain
Kay    = Hands
```

## Host Routing

- When the active host is Claude Code, follow STEP 0 through STEP 2 as written.
- When the active host is Codex, keep this skill to packaging/runtime configuration guidance only. Do not attempt to delegate work to the same runtime.

## Runtime Readiness

Kay readiness is checked when delegation starts for the current session. SessionStart does not update or repair the Kay runtime; if the health check fails, guide the user through the Kay setup or login path below.

## STEP 0 -- Health Check

Before delegating, verify the runtime is available:

```bash
kay --version 2>/dev/null || code --version 2>/dev/null || codex --version 2>/dev/null || coder --version 2>/dev/null
kay exec --help 2>/dev/null || for alias in code codex coder; do "$alias" exec --help 2>/dev/null && break; done
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

## STEP 1 -- Delegation Protocol

Preferred delegation command:

```bash
kay exec --full-auto "<task description>"
```

Compatibility aliases (`code`, `codex`, `coder`) accept the same arguments when an older environment only exposes them.

Useful options:

- `--json` for machine-readable progress
- `--output-last-message` for final-response-only output
- `resume --last` to continue prior non-interactive sessions

## STEP 2 -- Native Workflow

- Use Kay's native `kay exec` automation for file changes, tests, and commits.
- Use repository `AGENTS.md` instructions.
- Use native Kay agents/subagents when tasks benefit from parallel work.

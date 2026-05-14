---
name: kay-delegate
description: Canonical Kay delegation workflow for the Kay sidekick. Use when delegating implementation work to code/codex/coder exec.
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
- When the active host is Code, keep this skill to packaging/runtime configuration guidance only. Do not attempt to delegate work to the same runtime.

## Runtime Readiness

Kay readiness is checked when delegation starts for the current session. SessionStart does not update or repair the Code/Kay runtime; if the health check fails, guide the user through the Code/Kay setup or login path below.

## STEP 0 -- Health Check

Before delegating, verify the runtime is available:

```bash
code --version 2>/dev/null || codex --version 2>/dev/null || coder --version 2>/dev/null
code exec --help 2>/dev/null || codex exec --help 2>/dev/null || coder exec --help 2>/dev/null
```

Then verify MiniMax-backed config:

- `$CODE_HOME/config.toml` defaults to `~/.code/config.toml`
- legacy `~/.codex/config.toml` is still read for compatibility
- provider should be `minimax`
- model should be `MiniMax-M2.7`

If login is missing, guide the user to:

```bash
code login --provider minimax --with-api-key
```

If `code` is unavailable, use `codex`; if `code` conflicts with another app, use `coder`.

## STEP 1 -- Delegation Protocol

Preferred delegation command:

```bash
code exec --full-auto "<task description>"
```

Fallbacks:

```bash
codex exec --full-auto "<task description>"
coder exec --full-auto "<task description>"
```

Useful options:

- `--json` for machine-readable progress
- `--output-last-message` for final-response-only output
- `resume --last` to continue prior non-interactive sessions

## STEP 2 -- Native Workflow

- Use Code's native `code exec` automation for file changes, tests, and commits.
- Use repository `AGENTS.md` instructions.
- Use native Code agents/subagents when tasks benefit from parallel work.

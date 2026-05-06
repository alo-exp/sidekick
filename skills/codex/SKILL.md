---
name: codex
description: Core orchestration skill for the Codex sidekick. Use when delegating implementation work, installing Codex, or configuring MiniMax-backed code exec sessions.
---

# Codex — Claude Orchestration Protocol

Codex CLI is the implementation sidekick. Claude plans, explains, and verifies. Codex writes files, runs tests, and does the work.

```
Claude = Brain
Codex  = Hands
```

## STEP 0 — Health Check

Before activating `/codex`, verify the runtime is available:

```bash
codex --version 2>/dev/null || code --version 2>/dev/null || coder --version 2>/dev/null
codex exec --help 2>/dev/null || code exec --help 2>/dev/null || coder exec --help 2>/dev/null
```

Then check that Codex can use the MiniMax-backed configuration the Sidekick package expects:

- `$CODE_HOME/config.toml` defaults to `~/.code/config.toml`
- legacy `~/.codex/config.toml` is still read for compatibility
- the active provider should be `minimax`
- the active model should be `MiniMax-M2.7`

If login is missing, guide the user to:

```bash
codex login --provider minimax --with-api-key
```

If `codex` is unavailable, use `code`; if `code` is already claimed by another app, use `coder` instead of `code`.

## STEP 1 — Delegation Protocol

Use Codex for actual implementation work.

Preferred delegation command:

```bash
codex exec --full-auto "<task description>"
```

If `codex` is unavailable, use:

```bash
code exec --full-auto "<task description>"
```

If `code` is also unavailable or conflicts with another tool, use:

```bash
coder exec --full-auto "<task description>"
```

Useful options:

- `--json` for machine-readable progress
- `--output-last-message` for only the final response
- `resume --last` to continue a previous non-interactive session

Codex already supports native `AGENTS.md`, `SKILL.md`, agents, and subagent commands. Do not recreate Forge-style skill injection or conversation indexing here.

## STEP 2 — Native Workflow

- Use Codex’s own `codex exec` automation for file changes, tests, and commits.
- Use the repository’s `AGENTS.md` files for project instructions.
- Use native Codex agents and subagents when a task benefits from parallel reasoning.
- Keep the host and the sidekick separate: Claude sets intent and checks results; Codex executes.

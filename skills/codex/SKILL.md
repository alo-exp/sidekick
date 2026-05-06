---
name: codex
description: Core orchestration skill for the Code sidekick (Every Code extension). Use when delegating implementation work, packaging Sidekick for Code, installing Every Code, or configuring MiniMax-backed code exec sessions.
---

# Code — Claude Orchestration Protocol

Every Code is the implementation sidekick. Claude plans, explains, and verifies. Code writes files, runs tests, and does the work.

```
Claude = Brain
Code   = Hands
```

## Host Routing

- When the active host is Claude Code, follow STEP 0 through STEP 2 as written.
- When the active host is Code, keep this skill to packaging and runtime configuration guidance only. Do not attempt to delegate work to the same runtime or treat the Claude = Brain framing as a self-reference.
- Codex compatibility stays available through the `codex` and `codex-delegate` aliases plus the legacy config path; Code remains the canonical runtime.

## STEP 0 — Health Check

Before activating `/codex`, verify the runtime is available:

```bash
code --version 2>/dev/null || codex --version 2>/dev/null || coder --version 2>/dev/null
code exec --help 2>/dev/null || codex exec --help 2>/dev/null || coder exec --help 2>/dev/null
```

Then check that Code can use the MiniMax-backed configuration the Sidekick package expects:

- `$CODE_HOME/config.toml` defaults to `~/.code/config.toml`
- legacy `~/.codex/config.toml` is still read for compatibility
- the active provider should be `minimax`
- the active model should be `MiniMax-M2.7`

If login is missing, guide the user to:

```bash
code login --provider minimax --with-api-key
```

If `code` is unavailable, use `codex`; if `code` is claimed by another app, use `coder` instead of `code`.

## STEP 1 — Delegation Protocol

Use Code for actual implementation work.

Preferred delegation command:

```bash
code exec --full-auto "<task description>"
```

If `code` is unavailable, use:

```bash
codex exec --full-auto "<task description>"
```

If `code` is already unavailable or conflicts with another tool, use:

```bash
coder exec --full-auto "<task description>"
```

Useful options:

- `--json` for machine-readable progress
- `--output-last-message` for only the final response
- `resume --last` to continue a previous non-interactive session

Code already supports native `AGENTS.md`, `SKILL.md`, agents, and subagent commands. Do not recreate Forge-style skill injection or conversation indexing here. Sidekick's `codex-stop` and `codex-history` workflows are bundled in `commands/` so they appear in Codex's picker, and the skill bridges remain for compatibility with the shared docs.

This packaging follows the official Codex developer-doc pattern: keep repeatable workflows as skills, and present Codex with a composable CLI surface it can use for actual implementation work. See the developer-mode, Docs MCP, and Codex CLI docs for the source pattern.

## STEP 2 — Native Workflow

- Use Code’s own `code exec` automation for file changes, tests, and commits.
- Use the repository’s `AGENTS.md` files for project instructions.
- Use native Code agents and subagents when a task benefits from parallel reasoning.
- Keep the host and the sidekick separate: Claude sets intent and checks results; Code executes.

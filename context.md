# Sidekick Plugin — Current Context

**Date:** 2026-05-23
**Repo:** https://github.com/alo-exp/sidekick
**Local path:** `/Users/shafqat/projects/sidekick/repo`
**Plugin version:** v0.6.2

---

## What Sidekick Does

Sidekick is a Claude Code and Codex plugin that gives the host AI three execution agents:

| Sidekick | Runtime | Role |
|---|---|---|
| Forge | `forge` | ForgeCode execution agent with fallback ladder, progress surface, and mentoring loop |
| Kay | `kay` | OSS Codex-lineage execution agent with OpenCode Go default-provider routing and task-based model selection for MiMo-V2.5-Pro non-trivial work, MiMo-V2.5 for vision / visual reasoning, MiniMax M2.7 trivial work, and DeepSeek V4 Flash test running / issue reporting / completion verification |
| Codex | `codex` | Local OpenAI Codex CLI sidekick with GPT-5.4 Mini, `xhigh` reasoning, workspace-write sandboxing, and never-ask approval injected at delegation time |

The host AI stays in the planning, review, communication, and mentoring role. Forge, Kay, or Codex performs implementation work.

```
Host AI = Brain and mentor
Forge/Kay = Hands
```

---

## Current Runtime Contracts

- Forge delegates through `forge -p`.
- Kay activates through `kay-delegate` / `sidekick:kay-delegate`; active Kay mode routes child execution through `kay exec --full-auto` and Sidekick injects `model_provider=opencode-go` plus the routed model automatically.
- Codex activates through `codex-delegate` / `sidekick:codex-delegate`; active Codex mode routes child execution through `codex exec` and Sidekick injects `gpt-5.4-mini`, `model_reasoning_effort=xhigh`, `workspace-write`, and `ask-for-approval=never` automatically.
- Kay keeps `code`, `codex`, and `coder` as compatibility aliases only.
- Sidekick does not install SessionStart hooks; runtime readiness checks happen when a delegation workflow starts.
- Active Forge delegation markers live under the active host session root (`.claude/sessions/...` for Claude Code, `.codex/sessions/...` for Codex). Kay markers live under `.kay/sessions/...`. Codex sidekick markers live under `.codex/sessions/...`. The shared `~/.sidekick/sessions/<session>/active-sidekick` selector makes Forge, Kay, and Codex mutually exclusive in the same host session.
- Trace indexes live in `.forge/conversations.idx`, `.kay/conversations.idx`, and `.codex/conversations.idx`.

---

## Repository Structure

```
sidekick/
├── .claude-plugin/          # Claude plugin manifest and integrity hash block
├── .codex-plugin/           # Codex plugin manifest
├── site/                    # Website, Help Center, architecture, testing, ADRs
├── hooks/                   # PreToolUse and PostToolUse hook scripts plus helpers
├── output-styles/           # Forge/Kay/Codex narration contracts
├── sidekicks/registry.json  # Runtime metadata and pinned installer hashes
├── skills/                  # Canonical host-agnostic Forge, Kay, and Codex workflow skills
├── agents/                  # Generated Claude/Codex host skill bundles
├── scripts/                 # Host surface renderer and maintenance helpers
├── tests/                   # Bash test suite
├── install.sh               # Explicit bootstrap and clean reinstall support
└── README.md
```

---

## Installation Mechanics

`hooks/hooks.json` registers no SessionStart hooks. Explicit delegation starts the current-session hook behavior.

`install.sh`:

- Installs ForgeCode from the pinned `https://forgecode.dev/cli` installer.
- Installs Kay from a pinned `alo-labs/kay` installer commit that creates the `kay` binary.
- Creates Kay compatibility aliases for older environments.
- Rewrites installed hook surfaces for Claude or Codex host paths.
- Seeds hook trust state after the final hook surface is in place.
- Does not update or repair runtimes on every session start.

---

## Verification

Strict non-live verification:

```bash
bash tests/run_unit.bash
```

Skip-safe local sweep:

```bash
bash tests/run_all.bash
```

Release verification:

```bash
SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
```

To include optional Forge live stages when Forge provider testing is available, add `SIDEKICK_LIVE_FORGE=1` to either run.

The live stages make real model/runtime calls and are intentionally skipped unless the env vars are set.

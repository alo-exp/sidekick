# Sidekick Plugin — Current Context

**Date:** 2026-05-14
**Repo:** https://github.com/alo-exp/sidekick
**Local path:** `/Users/shafqat/projects/sidekick/repo`
**Plugin version:** v0.5.5

---

## What Sidekick Does

Sidekick is a Claude Code and Codex plugin that gives the host AI two execution agents:

| Sidekick | Runtime | Role |
|---|---|---|
| Forge | `forge` | ForgeCode execution agent with fallback ladder, progress surface, and mentoring loop |
| Kay | `kay` | OSS Codex-lineage execution agent with MiniMax.io defaults and OpenCode Go compatibility |

The host AI stays in the planning, review, communication, and mentoring role. Forge or Kay performs implementation work.

```
Host AI = Brain and mentor
Forge/Kay = Hands
```

---

## Current Runtime Contracts

- Forge delegates through `forge -p`.
- Kay delegates through `kay exec --full-auto`.
- Kay keeps `code`, `codex`, and `coder` as compatibility aliases only.
- SessionStart only runs first-run bootstrap and legacy hook cleanup; runtime readiness checks happen when a delegation workflow starts.
- Active delegation markers live under `.claude/sessions/...` for Forge and `.kay/sessions/...` for Kay.
- Trace indexes live in `.forge/conversations.idx` and `.kay/conversations.idx`.

---

## Repository Structure

```
sidekick/
├── .claude-plugin/          # Claude plugin manifest and integrity hash block
├── .codex-plugin/           # Codex plugin manifest
├── docs/                    # Website, Help Center, architecture, testing, ADRs
├── hooks/                   # SessionStart, PreToolUse, and PostToolUse hook scripts
├── output-styles/           # Forge/Kay narration contracts
├── sidekicks/registry.json  # Runtime metadata and pinned installer hashes
├── skills/                  # Canonical Forge and Kay workflow skills
├── tests/                   # Bash test suite
├── install.sh               # First-run bootstrap and clean reinstall support
└── README.md
```

---

## Installation Mechanics

`hooks/hooks.json` runs two SessionStart entries:

1. `hooks/scrub-legacy-user-hooks.py` removes stale user-hook blocks from legacy Codex hook files.
2. `install.sh` runs only when the package-local `.installed` sentinel is absent.

`install.sh`:

- Installs ForgeCode from the pinned `https://forgecode.dev/cli` installer.
- Installs Kay from a pinned `alo-labs/kay` installer commit that creates the `kay` binary.
- Creates Kay compatibility aliases for older environments.
- Rewrites installed hook surfaces for Claude or Codex host paths.
- Seeds hook trust state after the final hook surface is in place.
- Does not update or repair runtimes on every session start.

---

## Verification

Primary local verification:

```bash
bash tests/run_all.bash
```

Release verification:

```bash
SIDEKICK_LIVE_FORGE=1 SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
```

The live stages make real model/runtime calls and are intentionally skipped unless the env vars are set.

# Sidekick — AI Coding Agents for Claude Code

**Coding agents as Claude sidekicks** — each agent auto-installs, configures itself, and lets Claude delegate implementation work while focusing on planning and communication.

## Sidekicks

| Sidekick | Skill | Agent | Status |
|----------|-------|-------|--------|
| **Forge** | `forge` | [ForgeCode](https://forgecode.dev) — #2 Terminal-Bench 2.0 (81.8%) | ✅ v1.5.3 |
| **Code** | `code` | Every Code extension — `code exec` / `codex exec` / `coder exec`, MiniMax M2.7 | ✅ v1.5.3 |

More sidekicks planned.

---

## Installation

Add to `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "alo-labs": {
      "source": {
        "source": "github",
        "repo": "alo-exp/sidekick"
      },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "sidekick@alo-labs": true
  }
}
```

On the next Claude session, all sidekicks install automatically.

---

## Forge — ForgeCode Sidekick

### What it does
- **Auto-installs** ForgeCode on first session start
- **Guides** OpenRouter API key setup (Qwen3 Coder Plus — best coding model, $0.33/$1.95/MTok)
- **Turns Claude into an orchestrator**: Claude plans and communicates, Forge executes all file changes, tests, and commits
- **Fallback ladder**: automatic 3-level recovery on failure — L1 Guide (reframe), L2 Handhold (decompose), L3 Take over (Claude acts directly + DEBRIEF)
- **AGENTS.md mentoring**: after every task, Claude extracts learnings and writes them to a 3-tier instruction store (`~/forge/AGENTS.md`, `./AGENTS.md`, session logs) — delegation gets smarter over time
- **Skill injection**: 4 bootstrap skills (testing-strategy, code-review, security, quality-gates) auto-injected into task prompts based on task type
- **Token optimization**: task prompts capped at 2,000 tokens with validated `.forge.toml` compaction defaults

## Code — Every Code Sidekick

### What it does
- **Auto-installs** the Code runtime into `~/.local/bin/code` on first session start
- **Provides** `codex` and `coder` aliases for compatibility so Sidekick can route tasks to `code exec --full-auto`, then `codex exec --full-auto`, or fall back to `coder exec --full-auto`
- **Uses** Every Code's native agents, skills, subagents, and `AGENTS.md` support instead of recreating Forge-style prompt injection
- **Follows** the Codex developer-doc pattern (developer mode, Docs MCP, Codex CLI) of packaging repeatable work as skills and driving implementation through a composable CLI Codex can use
- **Defaults** to MiniMax `MiniMax-M2.7` through the packaged `~/.code/config.toml` / legacy `~/.codex/config.toml` compatibility path
- **Keeps** a project-local audit index at `.codex/conversations.idx` plus the shared `codex-history` and `codex-stop` command wrappers; the canonical workflows live in `skills/codex-history/SKILL.md` and `skills/codex-stop/SKILL.md`, and the Code sidekick also exposes a discoverable `codex-delegate` bridge skill, with compatibility wrappers kept in `skills/codex.md` and `skills/codex-delegate.md`

### How it works

```
You → Claude (plan + communicate) → Code (implement + commit) → Claude (review + report)
```

Claude handles: architecture, explanations, research, code review
Code handles: writing files, features, tests, git commits

### How it works

```
You → Claude (plan + communicate) → Forge (implement + commit) → Claude (review + report)
```

Claude handles: architecture, explanations, research, code review
Forge handles: writing files, features, tests, git commits

### Forge installation

Claude will guide you to:
1. Sign up at **openrouter.ai** (Google/GitHub OAuth, ~30 seconds)
2. Add $5 credits at **openrouter.ai/settings/credits**
3. Create an API key and paste it into Claude

Claude configures Forge automatically and delegates all coding work from that point.

### Providers & Models
| Provider | Model | Notes |
|----------|-------|-------|
| **OpenRouter** (recommended) | **Qwen3 Coder Plus** `qwen/qwen3-coder-plus` | Default. 1M context, tool-use, $0.33/$1.95/MTok |
| OpenRouter | **Gemma 4** `google/gemma-4-31b-it` | Alternative. Dense, fast, separate rate limit |
| **MiniMax Coding** | **MiniMax M2.7** `MiniMax-M2.7` | Direct API — get key at platform.minimaxi.com |

---

## Testing

`tests/run_release.bash` chains the unit suites plus the live Forge/Codex install, smoke, and E2E gates.

| Tier | Script | Runs without Forge/Code | Purpose |
|------|--------|:---:|---------|
| **Unit + integration** | `tests/run_all.bash` | ✅ | 22 suites — hook classifiers, idx audit, plugin integrity, slash commands, post-release cleanup, and Forge/Code coverage gaps. |
| **Forge smoke** | `tests/smoke/run_smoke.bash` | skip | `forge --version` + trivial `forge -p` round-trip against the real binary. |
| **Forge live E2E** | `tests/run_live_e2e.bash` | skip | Full Claude→Forge delegation on a seeded-buggy testapp (`tests/testapp/`) — proves the 5-field prompt shape, tool-use, and verification loop work end-to-end. |
| **Code smoke** | `tests/smoke/run_codex_smoke.bash` | skip | `code --version` + trivial `code exec` round-trip against the real binary, with `codex` kept as the compatibility alias. |
| **Code live E2E** | `tests/run_live_codex_e2e.bash` | skip | Full Claude→Code delegation on the same seeded-buggy testapp — proves the 5-field prompt shape, edit, and verification loop work end-to-end. |

The live stages are gated behind `SIDEKICK_LIVE_FORGE=1` and `SIDEKICK_LIVE_CODEX=1` so they never run in CI. Before tagging a new version:

```bash
SIDEKICK_LIVE_FORGE=1 SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
```

Before any release, complete the 4-stage pre-release quality gate until it passes twice in a row, then run the full live Forge/Codex pyramid twice with both live env vars, then publish through the release flow.

After the release is published, run `bash tests/post_release_cleanup.bash` so the local repo returns to a clean post-release state.

Without those env vars the gate still runs stage 1 and cleanly skips the live stages (exit 0), so it's safe to wire into CI.

---

## License

MIT — Ālo Labs

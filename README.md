# Sidekick — AI Coding Agents for Claude Code

**Coding agents as Claude sidekicks** — each agent auto-installs, configures itself, and lets Claude delegate implementation work while focusing on planning and communication.

## Sidekicks

| Sidekick | Skill | Agent | Status |
|----------|-------|-------|--------|
| **Forge** | `forge` | [ForgeCode](https://forgecode.dev) — #2 Terminal-Bench 2.0 (81.8%) | ✅ v1.2.0 |

More sidekicks planned.

---

## Installation

Add to `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "alo-exp": {
      "source": {
        "source": "github",
        "repo": "alo-exp/sidekick"
      },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "sidekick@alo-exp": true
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

### How it works

```
You → Claude (plan + communicate) → Forge (implement + commit) → Claude (review + report)
```

Claude handles: architecture, explanations, research, code review
Forge handles: writing files, features, tests, git commits

### After installation

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

Three-tier pyramid. All three stages are chained by `tests/run_release.bash`, which is the gate every release must pass.

| Tier | Script | Runs without Forge | Purpose |
|------|--------|:---:|---------|
| **Unit + integration** | `tests/run_all.bash` | ✅ | 13 suites, ~80+ assertions — hook classifiers, idx audit, plugin integrity, slash commands, v1.2 coverage gaps. |
| **Smoke** | `tests/smoke/run_smoke.bash` | skip | `forge --version` + trivial `forge -p` round-trip against the real binary. |
| **Live E2E** | `tests/run_live_e2e.bash` | skip | Full Claude→Forge delegation on a seeded-buggy testapp (`tests/testapp/`) — proves the 5-field prompt shape, tool-use, and verification loop work end-to-end. |

Stages 2 and 3 are gated behind `SIDEKICK_LIVE_FORGE=1` so they never run in CI. Before tagging a new version:

```bash
SIDEKICK_LIVE_FORGE=1 bash tests/run_release.bash
```

Without the env var the gate still runs stage 1 and cleanly skips 2+3 (exit 0), so it's safe to wire into CI.

---

## License

MIT — Ālo Labs

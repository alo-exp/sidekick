# Sidekick — AI Coding Agents for Claude Code

**Coding agents as Claude sidekicks** — each agent auto-installs, configures itself, and lets Claude delegate implementation work while focusing on planning and communication.

## Sidekicks

| Sidekick | Skill | Agent | Status |
|----------|-------|-------|--------|
| **Forge** | `forge` | [ForgeCode](https://forgecode.dev) — #2 Terminal-Bench 2.0 (81.8%) | ✅ v1.0.0 |

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
- **Guides** OpenRouter API key setup (Qwen 3.6 Plus — best coding model, $0.33/$1.95/MTok)
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

### Models
### Providers & Models
| Provider | Model | Notes |
|----------|-------|-------|
| **OpenRouter** (recommended) | **Qwen 3.6 Plus** `qwen/qwen3.6-plus` | Default. 1M context, vision, $0.33/$1.95/MTok |
| OpenRouter | **Gemma 4** `google/gemma-4-31b-it` | Alternative. Dense, fast, separate rate limit |
| **MiniMax Coding** | **MiniMax M2.7** `MiniMax-M2.7` | Direct API — get key at platform.minimaxi.com |

---

## License

MIT — Ālo Labs

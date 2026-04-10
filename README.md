# Forge Plugin for Claude Code

**ForgeCode as a Claude sidekick** — auto-installs ForgeCode, configures it via OpenRouter, and turns Claude into an orchestrator that delegates all coding work to Forge.

## What it does

- **Auto-installs** ForgeCode on first session start (no manual setup)
- **Guides** you through OpenRouter API key setup (Qwen 3.6 Plus — best cost/performance for coding)
- **Transforms Claude** into an orchestrator: Claude plans and communicates, Forge executes all file changes, tests, and commits
- **Context-aware**: Forge always runs in the right project directory with full codebase context

## Installation

### Option 1: Add to your Claude Code settings

Add to `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "alo-exp": {
      "source": {
        "source": "github",
        "repo": "alo-exp/forge"
      },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "forge@alo-exp": true
  }
}
```

### Option 2: Manual install

```bash
git clone https://github.com/alo-exp/forge.git ~/.claude/plugins/forge
bash ~/.claude/plugins/forge/install.sh
```

## After installation

On the next Claude session, Forge will be installed automatically. Claude will then guide you to:

1. Create a free account at **openrouter.ai**
2. Add $5 credits (lasts weeks of daily use)
3. Create an API key and paste it into Claude

That's it — Claude will configure Forge and from that point, delegate all coding tasks automatically.

## How it works

```
You → Claude (plan + communicate) → Forge (implement + commit) → Claude (review + report)
```

Claude handles: architecture decisions, explaining code, research, reviewing output
Forge handles: writing files, implementing features, running tests, git commits

## Models

Default: **Qwen 3.6 Plus** via OpenRouter — #1 open model on Terminal-Bench 2.0, $0.33/$1.95 per MTok, 1M context

Switch to Gemma 4 31B: `forge config set model open_router google/gemma-4-31b-it`

## Benchmarks

ForgeCode with Qwen 3.6 Plus: **#2 on Terminal-Bench 2.0** (81.8%, behind only Pilot at 82.9%)

## License

MIT — Ālo Labs

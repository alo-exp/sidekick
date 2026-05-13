# Sidekick — AI Coding Agents for Claude Code

**Coding agents as Claude sidekicks** — each agent auto-installs, configures itself, and lets Claude delegate implementation work while focusing on planning and communication.

## Sidekicks

| Sidekick | Skill | Agent | Status |
|----------|-------|-------|--------|
| **Forge** | `forge` | [ForgeCode](https://forgecode.dev) — #2 Terminal-Bench 2.0 (81.8%) | ✅ v0.5.5 |
| **Kay** | `code` | Every Kay extension — `code exec` / `codex exec` / `coder exec`, MiniMax M2.7 | ✅ v0.5.5 |

More sidekicks planned.

---

## Docs

If you want the docs in the right order, start here:

- [Start Here](docs/START-HERE.md) — task-first navigation
- [Audience](docs/AUDIENCE.md) — who each doc is for
- [Glossary](docs/GLOSSARY.md) — canonical terminology
- [Compatibility](docs/COMPATIBILITY.md) — Claude, Codex, and Kay runtime differences
- [ADR index](docs/ADR/README.md) — durable docs-system decisions

For help-site workflows, use the [Help Center](docs/help/).

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

On the next Claude session, all sidekicks install automatically and keep themselves current on later session starts.

---

## Forge — ForgeCode Sidekick

### What it does
- **Auto-installs** ForgeCode on first session start and self-updates it on later session starts using Forge's native `forge update`
- **Guides** OpenRouter API key setup (Qwen3 Coder Plus — best coding model, $0.33/$1.95/MTok)
- **Turns Claude into an orchestrator**: Claude plans and communicates, Forge executes all file changes, tests, and commits
- **Fallback ladder**: automatic 3-level recovery on failure — L1 Guide (reframe), L2 Handhold (decompose), L3 Take over (Claude acts directly + DEBRIEF)
- **AGENTS.md mentoring**: after every task, Claude extracts learnings and writes them to a 3-tier instruction store (`~/forge/AGENTS.md`, `./AGENTS.md`, session logs) — delegation gets smarter over time
- **Skill injection**: 4 bootstrap skills (testing-strategy, code-review, security, quality-gates) auto-injected into task prompts based on task type
- **Token optimization**: task prompts capped at 2,000 tokens with validated `.forge.toml` compaction defaults

## Kay — Every Kay Sidekick

### What it does
- **Auto-installs** the Code runtime from the latest `alo-labs/kay` installer on first session start and self-updates it on later session starts using the native `codex update` command
- **Provides** `codex` and `coder` aliases for compatibility so Sidekick can route tasks to `code exec --full-auto`, then `codex exec --full-auto`, or fall back to `coder exec --full-auto`
- **Uses** Every Code's native agents, skills, subagents, and `AGENTS.md` support instead of recreating Forge-style prompt injection
- **Follows** the Codex developer-doc pattern (developer mode, Docs MCP, Codex CLI) of packaging repeatable work as skills and driving implementation through a composable CLI Codex can use
- **Defaults** to MiniMax `MiniMax-M2.7` through the packaged `~/.code/config.toml` / legacy `~/.codex/config.toml` compatibility path
- **Keeps** a project-local audit index at `.kay/conversations.idx`; the canonical Kay workflows live in the delegate and stop skills, with the legacy flat alias preserved only as a hidden compatibility entry at `skills/codex-delegate.md`.

### How it works

```
You → Claude (plan + communicate) → Code (implement + commit) → Claude (review + report)
```

Claude handles: architecture, explanations, research, code review
Kay handles: writing files, features, tests, git commits

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

`tests/run_release.bash` chains the unit suites plus the live Forge/Kay install, smoke, E2E, and Code marketplace-install gates.

| Tier | Script | Runs without Forge/Kay | Purpose |
|------|--------|:---:|---------|
| **Unit + integration** | `tests/run_all.bash` | ✅ | 27 suites — hook classifiers, idx audit, plugin integrity, docs contract, help-site navigation, slash commands, post-release cleanup, clean reinstall bootstrap, and Forge/Kay coverage gaps. |
| **Forge smoke** | `tests/smoke/run_smoke.bash` | skip | `forge --version` + trivial `forge -p` round-trip against the real binary. |
| **Forge live E2E** | `tests/run_live_e2e.bash` | skip | Full Claude→Forge delegation on a seeded-buggy testapp (`tests/testapp/`) — proves the 5-field prompt shape, tool-use, and verification loop work end-to-end. |
| **Code smoke** | `tests/smoke/run_codex_smoke.bash` | skip | `code --version` + trivial `code exec` round-trip against the real binary, with `codex` kept as the compatibility alias. |
| **Code live E2E** | `tests/run_live_codex_e2e.bash` | skip | Full Claude→Code delegation on the same seeded-buggy testapp — proves the 5-field prompt shape, edit, and verification loop work end-to-end. |

The live stages are gated behind `SIDEKICK_LIVE_FORGE=1` and `SIDEKICK_LIVE_CODEX=1` so they never run in CI. Before tagging a new version:

```bash
SIDEKICK_LIVE_FORGE=1 SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
```

Before any release, complete the 4-stage pre-release quality gate until it passes twice in a row, then run the full live Forge/Kay pyramid twice with both live env vars, then publish through the release flow.

After the release is published, run `bash tests/post_release_cleanup.bash` so the local repo returns to a clean post-release state.
This cleanup only removes transient build/cache artifacts; `.planning/`, docs/specs, and docs/design content stay in place.

Without those env vars the gate still runs stage 1 and cleanly skips the live stages (exit 0), so it's safe to wire into CI.

---

## License

MIT — Ālo Labs

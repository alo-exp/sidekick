# Changelog

## 1.1.0 — 2026-04-13

- **Forge delegation mode** (`/forge` skill): explicit activation/deactivation with health check and session state
- **Fallback ladder**: 3-level automatic recovery — L1 Guide (reframe + retry), L2 Handhold (atomic subtask decomposition, max 3 attempts), L3 Take over (Claude acts directly + structured DEBRIEF)
- **Skill injection**: 4 bootstrap skills (testing-strategy, code-review, security, quality-gates) auto-injected based on task type; injection budget enforced (≤2 skills)
- **AGENTS.md mentoring loop**: post-task extraction of corrections, preferences, patterns; 3-tier write (global/project/session log); 2-phase deduplication (exact + semantic)
- **Token optimization**: task prompts capped at 2,000 tokens; validated `.forge.toml` compaction defaults (token_threshold=80000, eviction_window=0.20, retention_window=6, max_tokens=16384)
- **Help Center** (`docs/help/`): 5-page static documentation site with search, dark/light theme, covering Getting Started, Core Concepts, Delegation Workflow, Command Reference, and Troubleshooting
- **Test suite**: 8 automated test suites, 70 assertions covering all Phase 1-4 additions

## 1.0.0 — 2026-04-10

- Initial release as **Sidekick** plugin (renamed from Forge plugin)
- First sidekick: **Forge** (ForgeCode) — skill name `forge`
- Auto-install ForgeCode on SessionStart (one-time, .installed sentinel)
- OpenRouter setup guidance (Qwen 3.6 Plus default)
- Full Claude orchestration skill: delegates coding/file/git tasks to Forge
- AGENTS.md context continuity pattern
- Model switching (Qwen 3.6 Plus ↔ Gemma 4 31B)
- Troubleshooting guide for common errors (402, 429, PATH)

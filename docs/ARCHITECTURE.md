# Architecture

> High-level architecture of the Sidekick plugin. Detailed phase-level designs live in `.planning/phases/*/` (active milestone) or `docs/specs/` (archived).

**Plugin version:** v1.2.0 • **Target:** Claude Code harness + Forge CLI (`~/.local/bin/forge` ≥ 2.11.3)

---

## System Overview

Sidekick is a Claude Code plugin that installs and orchestrates the ForgeCode (`forge`) coding agent. It turns Claude into a planner/communicator and delegates all implementation work to Forge through a **harness-enforced** delegation protocol.

Two roles are preserved at every layer:

- **Brain (Claude)** — plans, composes task prompts, inspects results, narrates to the user, verifies success criteria, writes structured learnings.
- **Hands (Forge)** — writes files, edits code, runs shell commands, makes commits. Never speaks directly to the user.

Enforcement is three-layered so that neither the LLM nor an untrusted prompt can bypass delegation:

1. **Skill prompting** (`skills/forge/SKILL.md`) — tells Claude *what* to delegate and *how* to compose the 5-field task prompt.
2. **Harness enforcement** (`hooks/forge-delegation-enforcer.sh`, PreToolUse) — while the marker file exists, `Write`/`Edit`/`NotebookEdit` are denied by the harness and `Bash forge -p …` is rewritten to inject a valid UUID `--conversation-id`, `--verbose`, and `[FORGE]`/`[FORGE-LOG]` line-prefix pipes.
3. **Progress surface** (`hooks/forge-progress-surface.sh`, PostToolUse) — parses Forge's `STATUS:` block, strips ANSI, emits a bounded `[FORGE-SUMMARY]` additionalContext, and surfaces the `/forge:replay <uuid>` hint.

Result: when `/forge` is active, every mutating operation is either a Forge subprocess call (rewritten + indexed + surfaced) or a hard-deny from the harness.

---

## Core Components

| Component | Path | Purpose |
|---|---|---|
| Install hook | `install.sh`, `hooks/hooks.json` (SessionStart) | One-shot Forge binary install guarded by `.installed` sentinel. |
| Skill — `/forge` | `skills/forge/SKILL.md` | Activation / deactivation, health check, delegation protocol, 5-field prompt, fallback ladder (L1 Guide / L2 Handhold / L3 Take over), skill injection, AGENTS.md mentoring loop. |
| Skill — legacy orchestration | `skills/forge.md` | Orchestration reference retained for behavior that `/forge` extends. |
| Enforcer hook | `hooks/forge-delegation-enforcer.sh` (~426 lines) | PreToolUse on `Write\|Edit\|NotebookEdit\|Bash`. Read-only bash allowlist, mutating-flag rejector (`sed -i`, `awk -i inplace`), idempotent `forge -p` rewriter, UUID injector, audit-index appender. |
| Progress hook | `hooks/forge-progress-surface.sh` (~118 lines) | PostToolUse on `Bash`. No-op unless active + `forge -p` ran. Extracts first 20 lines of `STATUS:` block, emits styled summary + replay hint. |
| Audit index | `.forge/conversations.idx` (project-local, created on activation) | Append-only ISO 8601 UTC rows: `<timestamp> <UUID> <sidekick-tag> <task-hint>`. Lookup only — content lives in Forge's native `~/forge/.forge.db`. |
| Commands | `commands/forge-replay.md`, `commands/forge-history.md` | `/forge:replay <uuid>` wraps `forge conversation dump --html` + `stats --porcelain`. `/forge:history` renders last 20 idx rows joined with `forge conversation info`, prunes >30-day entries. |
| Output style | `output-styles/forge.md` | Narration contract while `/forge` is active. Documents `[FORGE]` / `[FORGE-LOG]` / `[FORGE-SUMMARY]` markers — *not* a tool-output colorizer (Claude Code output styles shape assistant prose, not raw tool output). |
| Plugin manifest | `.claude-plugin/plugin.json` | v1.2.0. Registers hooks, directory-style `commands/`, `outputStyles/`, `skills/`. `_integrity` field carries SHA-256 of all executable artifacts. |
| Marketplace manifest | `.claude-plugin/marketplace.json` | Advertises the plugin to the `alo-exp/sidekick` marketplace. |
| Forge project config | `.forge/agents/forge.md`, `.forge.toml` | Bootstrapped on first activation (non-destructive). Agent frontmatter carries `tools: ["*"]` (critical — missing this silently provisions zero tools). `.forge.toml` caps `max_tokens = 16384`, compaction at 80k tokens, 20% eviction, 6-message retention. |

---

## Layered View

```
User
  │
  ▼
Claude Code (Brain)                         harness boundary
  │                                             │
  │  composes 5-field task prompt               │
  ├──► Bash("forge -p '…'", run_in_background)  │
  │          │                                  │
  │          │ ┌─ PreToolUse enforcer hook ─────┤
  │          │ │  if active:                    │
  │          │ │    · deny Write/Edit/NotebookEdit
  │          │ │    · allow forge -p, rewrite:  │
  │          │ │        + --conversation-id <UUID>
  │          │ │        + --verbose             │
  │          │ │        + stdout → [FORGE]      │
  │          │ │        + stderr → [FORGE-LOG]  │
  │          │ │    · append .forge/conversations.idx
  │          │ └────────────────────────────────┤
  │          ▼                                  │
  │     Forge subprocess (Hands)                │
  │          │  reads/writes files,             │
  │          │  runs commands, commits          │
  │          │  emits STATUS block              │
  │          ▼                                  │
  │  ┌─ PostToolUse progress hook ──────────────┤
  │  │  strip ANSI, parse STATUS (20-line cap)  │
  │  │  emit additionalContext:                 │
  │  │   [FORGE-SUMMARY] STATUS / FILES / …     │
  │  │   Replay: /forge:replay <uuid>           │
  │  └──────────────────────────────────────────┤
  │                                             │
  ▼                                             │
User receives styled narration           ◄──────┘
  │
  │  (later) /forge:history  → table from .forge/conversations.idx
  │          /forge:replay   → HTML dump + token/cost stats
```

---

## Design Principles

1. **Delegate at the harness layer, not the prompt layer.** Prompt-only rules can be rationalized around. A PreToolUse hook returning `permissionDecision: "deny"` cannot.
2. **Leverage Forge's native storage — don't reinvent.** Sidekick indexes (UUID + tag + hint), Forge stores (content, snapshots, stats). `.forge/conversations.idx` is lookup-only; `forge conversation dump/stats/info` answers all content queries.
3. **Zero Claude-to-Forge roundtrip per rewrite.** The enforcer is shell, not an LLM wrapper — deterministic, millisecond latency, no token cost.
4. **Non-destructive on install.** Plugin config files (`.forge/agents/forge.md`, `.forge.toml`) are written only when absent. Re-activation re-runs the health check but never overwrites user edits.
5. **Graceful degradation off the happy path.** No marker file → both hooks are no-ops. Output style missing → line prefixes degrade to plain text, no break. Monitor unavailable (Bedrock/Vertex/Foundry) → skill documents foreground-Bash fallback.
6. **Every Forge task is replayable.** Stable UUID from the hook + durable `~/forge/.forge.db` + `/forge:replay` = any task can be reopened as an HTML transcript with token/cost stats, weeks later.

---

## Technology Choices

| Choice | Rationale |
|---|---|
| Bash + Markdown only (no compiled code) | Matches Claude Code plugin contract. Zero install dependencies. Readable, diff-friendly audit trail. |
| PreToolUse + PostToolUse hooks | The only Claude Code mechanism that runs *before* a tool call with veto power (`permissionDecision`) and *after* it with `additionalContext` injection. |
| Valid RFC 4122 UUID for `--conversation-id` | Forge 2.11.3 rejects the earlier `sidekick-<ts>-<hash>` format. The human-readable tag is preserved as a separate column in the idx for display only. |
| `set -euo pipefail` in hooks | Fails loud on classifier bugs during development. Every classifier branch returns explicit `{ "continue": true }` JSON to avoid accidental deny from an empty exit. |
| ISO 8601 UTC lexical date pruning in `/forge:history` | Portable across BSD `date -v` and GNU `date -d` without parsing. |
| Seeded-buggy Python testapp for live E2E | A baseline-must-fail assertion proves the E2E actually exercises the fix path, not happy-case parsing. |

---

## Extension Points

- **New sidekick** (additional coding agent): add `skills/<name>/SKILL.md`, optional `commands/<name>-*.md`, register in `plugin.json`. Does not require changes to the Forge enforcement layer.
- **Additional bootstrap skills**: extend the injection mapping in `skills/forge/SKILL.md` §Skill Injection. Ship as `.forge/skills/<name>/SKILL.md` with Forge-compatible frontmatter (`id`, `title`, `description`, `trigger`).
- **Custom progress parsing**: `forge-progress-surface.sh` currently caps at 20 lines of the STATUS block. Extending to other Forge output shapes is a single `awk` stanza.

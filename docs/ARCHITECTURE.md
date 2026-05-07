# Architecture

> High-level architecture of the Sidekick plugin. Detailed phase-level designs live in `.planning/phases/*/` (active milestone) or `docs/specs/` (archived).

**Plugin version:** v1.5.2 • **Target:** Claude Code harness + Forge/Code sidekicks (`~/.local/bin/forge` ≥ 2.11.3, `~/.local/bin/code` ≥ 0.6.99)

---

## System Overview

Sidekick is a Claude Code plugin that installs and orchestrates multiple coding agents. ForgeCode (`forge`) and Code (`code` / `codex` / `coder`) are the first supported sidekicks. Code is built through the Every Code extension line, not as a direct Codex fork. Sidekick turns Claude into a planner/communicator and delegates all implementation work to the active sidekick through a **harness-enforced** delegation protocol.

Two roles are preserved at every layer:

- **Brain (Claude)** — plans, composes task prompts, inspects results, narrates to the user, verifies success criteria, writes structured learnings.
- **Hands (active sidekick)** — writes files, edits code, runs shell commands, makes commits. Never speaks directly to the user.

Enforcement is three-layered so that neither the LLM nor an untrusted prompt can bypass delegation:

1. **Skill prompting** (`skills/forge/SKILL.md`, `skills/codex/SKILL.md`) — tells Claude *what* to delegate and *how* to compose the task prompt for the active sidekick.
2. **Harness enforcement** (`hooks/forge-delegation-enforcer.sh`, `hooks/codex-delegation-enforcer.sh`, PreToolUse) — while a marker file exists, mutating `Write`/`Edit`/`NotebookEdit` tools are denied and the matching sidekick shell commands are rewritten or refused according to the active registry entry.
3. **Progress surface** (`hooks/forge-progress-surface.sh`, `hooks/codex-progress-surface.sh`, PostToolUse) — parses each sidekick's terminal output, strips ANSI, emits bounded `[FORGE-SUMMARY]` or `[CODEX-SUMMARY]` additionalContext, and surfaces the matching history hint.

Result: when `/forge` or `/codex` is active, every mutating operation is either a sidekick subprocess call (rewritten + indexed + surfaced) or a hard-deny from the harness.

---

## Core Components

| Component | Path | Purpose |
|---|---|---|
| Install hook | `install.sh`, `hooks/hooks.json` (SessionStart) | One-shot bootstrap that installs Forge and Code runtimes and guards the session with `.installed`. |
| Registry | `sidekicks/registry.json`, `hooks/lib/sidekick-registry.sh` | Shared metadata for sidekick names, marker files, delegate/history commands, and installer digests. |
| Skill — `/forge` | `skills/forge/SKILL.md` | Activation / deactivation, health check, delegation protocol, 5-field prompt, fallback ladder (L1 Guide / L2 Handhold / L3 Take over), skill injection, AGENTS.md mentoring loop. |
| Skill — `/codex` | `skills/codex/SKILL.md` | Health check, MiniMax-backed `code exec` delegation, native agents/subagents, `AGENTS.md` workflow, and `codex`/`coder` fallback guidance for the Every Code extension line. The packaging follows the Codex developer-doc pattern for "Create a CLI Codex can use" plus "Save workflows as skills" in the official developer-mode / Docs MCP / Codex CLI docs. |
| Skill — legacy orchestration | `skills/forge.md`, `skills/codex.md` | Orchestration references retained for behavior that `/forge` and `/codex` extend. |
| Enforcer hooks | `hooks/forge-delegation-enforcer.sh`, `hooks/codex-delegation-enforcer.sh` | PreToolUse on `Write\|Edit\|NotebookEdit\|Bash`. Per-sidekick read-only allowlists, mutating-flag rejectors, command rewriters, UUID/audit injectors, and deny paths. |
| Progress hooks | `hooks/forge-progress-surface.sh`, `hooks/codex-progress-surface.sh` | PostToolUse on `Bash`. No-op unless the matching marker is active. Extracts terminal summary blocks, emits styled sidekick summaries, and links the matching history command. |
| Audit indexes | `.forge/conversations.idx`, `.codex/conversations.idx` | Append-only ISO 8601 UTC rows: `<timestamp> <UUID> <sidekick-tag> <task-hint>`. Lookup only — content lives in each runtime's native history store. |
| Commands | `commands/forge-stop.md`, `commands/forge-history.md`, `commands/codex-stop.md`, `commands/codex-history.md` | Canonical activation/deactivation and history workflow docs. Claude and Codex both expose them as commands; Codex materializes them as skills through the importer path, and the `skills/<name>/SKILL.md` bridges keep the source tree and picker surface aligned. The `codex-delegate` alias now has a first-class bridge skill so the picker sees it directly. |
| Output styles | `output-styles/forge.md`, `output-styles/codex.md` | Narration contracts for active sidekick sessions. Documents `[FORGE]` / `[CODEX]` prefixes and `[...-SUMMARY]` blocks. |
| Codex plugin manifest | `.codex-plugin/plugin.json` | v1.5.2. Registers hooks, skills, and the shared source `commands/` surface for Codex's importer path. |
| Plugin manifest | `.claude-plugin/plugin.json` | v1.5.2. Registers hooks, directory-style `commands/`, `outputStyles/`, `skills/`. `_integrity` field carries SHA-256 of all executable artifacts. |
| Marketplace manifest | `.claude-plugin/marketplace.json` | Advertises the plugin to the `alo-exp/sidekick` marketplace. |
| Forge project config | `.forge/agents/forge.md`, `.forge.toml` | Bootstrapped on first activation (non-destructive). Agent frontmatter carries `tools: ["*"]` (critical — missing this silently provisions zero tools). `.forge.toml` caps `max_tokens = 16384`, compaction at 80k tokens, 20% eviction, 6-message retention. |
| Code project config | `~/.code/config.toml`, `~/.codex/config.toml` | Runtime configuration for Code. The Sidekick installer keeps the modern and legacy config paths aligned with MiniMax defaults. |

---

## Layered View

```
User
  │
  ▼
Claude Code (Brain)                         harness boundary
  │                                             │
  │  composes task prompt                        │
  ├──► Bash("forge -p '…'") or Bash("code exec --full-auto '…'") │
  │          │                                  │
  │          │ ┌─ PreToolUse sidekick hooks ─────┤
  │          │ │  if matching marker active:     │
  │          │ │    · deny Write/Edit/NotebookEdit
  │          │ │    · rewrite Forge or Code exec
  │          │ │    · append .forge/.codex idx   │
  │          │ └────────────────────────────────┤
  │          ▼                                  │
  │     Forge or Code subprocess (Hands)      │
  │          │  reads/writes files,             │
  │          │  runs commands, commits          │
  │          │  emits STATUS / task summary     │
  │          ▼                                  │
  │  ┌─ PostToolUse progress hook ──────────────┤
  │  │  strip ANSI, parse sidekick summary      │
  │  │  emit additionalContext:                 │
  │  │   [FORGE-SUMMARY] ... or [CODEX-SUMMARY] │
  │  │   History: /forge-history or /codex-history
  │  └──────────────────────────────────────────┤
  │                                             │
  ▼                                             │
User receives styled narration           ◄──────┘
  │
  │  (later) /forge-history or /codex-history → table from the matching idx
```

---

## Design Principles

1. **Delegate at the harness layer, not the prompt layer.** Prompt-only rules can be rationalized around. A PreToolUse hook returning `permissionDecision: "deny"` cannot.
2. **Keep sidekick state isolated.** Sidekick indexes, markers, and history commands stay per-sidekick so Forge and Code never collide in the same project directory.
3. **Leverage each runtime's native storage.** Sidekick indexes only carry lookup metadata; Forge and Code keep their own conversation/history stores.
4. **Zero Claude-to-sidekick roundtrip per rewrite.** The enforcer is shell, not an LLM wrapper — deterministic, millisecond latency, no token cost.
5. **Non-destructive on install.** Plugin config files (`.forge/agents/forge.md`, `.forge.toml`) are written only when absent. Re-activation re-runs the health check but never overwrites user edits.
6. **Graceful degradation off the happy path.** No marker file → both hooks are no-ops. Output style missing → line prefixes degrade to plain text, no break. Monitor unavailable (Bedrock/Vertex/Foundry) → skill documents foreground-Bash fallback.
7. **Every sidekick task is traceable.** Stable UUID from the hook + durable project-local idx + `/forge-history` or `/codex-history` = any past task can be found and reviewed by tag, timestamp, and status.

---

## Technology Choices

| Choice | Rationale |
|---|---|
| Bash + Markdown only (no compiled code) | Matches Claude Code plugin contract. Zero install dependencies. Readable, diff-friendly audit trail. |
| Registry-driven sidekick selection | Lets the plugin add more sidekicks without hard-coding them into every hook and command. |
| PreToolUse + PostToolUse hooks | The only Claude Code mechanism that runs *before* a tool call with veto power (`permissionDecision`) and *after* it with `additionalContext` injection. |
| Valid RFC 4122 UUID for `--conversation-id` | Forge 2.11.3 rejects the earlier `sidekick-<ts>-<hash>` format. The human-readable tag is preserved as a separate column in the idx for display only. |
| `set -euo pipefail` in hooks | Fails loud on classifier bugs during development. Every classifier branch returns explicit `{ "continue": true }` JSON to avoid accidental deny from an empty exit. |
| ISO 8601 UTC lexical date pruning in `/forge-history` | Portable across BSD `date -v` and GNU `date -d` without parsing. |
| Seeded-buggy Python testapp for live E2E | A baseline-must-fail assertion proves the E2E actually exercises the fix path, not happy-case parsing. |

---

## Extension Points

- **New sidekick** (additional coding agent): add `skills/<name>/SKILL.md`, `commands/<name>-*.md`, `output-styles/<name>.md`, and a row in `sidekicks/registry.json`. Keep bridge skills only when a runtime needs a compatibility alias; the canonical command docs remain the source of truth. The shared hook library and manifest wiring should not need to change.
- **Additional bootstrap skills**: extend the injection mapping in `skills/forge/SKILL.md` §Skill Injection. Ship as `.forge/skills/<name>/SKILL.md` with Forge-compatible frontmatter (`id`, `title`, `description`, `trigger`).
- **Custom progress parsing**: `forge-progress-surface.sh` currently caps at 20 lines of the STATUS block. Extending to other Forge output shapes is a single `awk` stanza.

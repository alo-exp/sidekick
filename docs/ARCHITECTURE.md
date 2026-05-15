# Architecture

> High-level architecture of the Sidekick plugin. Detailed phase-level designs live in `.planning/phases/*/` (active milestone) or `docs/specs/` (archived). Preserved design notes live in `docs/design/`.

**Plugin version:** v0.5.6 • **Target:** Claude Code and Codex hosts + Forge/Kay sidekicks (`~/.local/bin/forge` ≥ 2.11.3, `~/.local/bin/kay` ≥ 0.9.4)

---

## System Overview

Sidekick is a Claude Code and Codex plugin that installs and orchestrates multiple coding agents. ForgeCode (`forge`) and Kay (`kay`) are the first supported sidekicks. Kay keeps `code`, `codex`, and `coder` as compatibility aliases, but `kay` is the primary runtime identity. Sidekick turns the host AI into a planner, reviewer, and mentor while delegated agents perform implementation work through a **harness-enforced** delegation protocol.

Two roles are preserved at every layer:

- **Brain (host AI)** — plans, composes task prompts, inspects results, narrates to the user, verifies success criteria, writes structured learnings.
- **Hands (active sidekick)** — writes files, edits code, runs shell commands, makes commits. Never speaks directly to the user.

Enforcement is three-layered so that neither the LLM nor an untrusted prompt can bypass delegation:

1. **Skill prompting** (`skills/forge/SKILL.md`, `skills/codex-delegate/SKILL.md`) — tells the host AI *what* to delegate and *how* to compose the task prompt for the active sidekick.
2. **Harness enforcement** (`hooks/forge-delegation-enforcer.sh`, `hooks/codex-delegation-enforcer.sh`, PreToolUse) — while a marker file exists, mutating `Write`/`Edit`/`NotebookEdit` tools are denied and the matching sidekick shell commands are rewritten or refused according to the active registry entry. The shared `active-sidekick` selector is an override that suppresses the opposite sidekick when it is present.
3. **Progress surface** (`hooks/forge-progress-surface.sh`, `hooks/codex-progress-surface.sh`, PostToolUse) — parses each sidekick's terminal output, strips ANSI, emits bounded `[FORGE-SUMMARY]` or `[KAY-SUMMARY]` additionalContext, and surfaces the matching stop hint.

Result: when Forge or Kay delegation mode is active, every mutating operation is either a sidekick subprocess call (rewritten + indexed + surfaced) or a hard-deny from the harness.

---

## Core Components

| Component | Path | Purpose |
|---|---|---|
| Install hook | `install.sh`, `hooks/hooks.json` (SessionStart) | Guarded first-run bootstrap when the package-local `.installed` sentinel is absent: install missing Forge/Kay runtimes, fetch the pinned Kay installer that creates `kay` plus compatibility aliases, bootstrap a missing versioned cache tree from the local snapshot on clean reinstall, rewrite host-specific paths, archive and retire any legacy uppercase `~/.Codex` tree after the lowercase install is valid, then seed trust/state after the final merged hook surface using the exact source each trust prefix names. It does not update or repair runtimes on later session starts. |
| Legacy hook scrub | `hooks/scrub-legacy-user-hooks.py`, `hooks/hooks.json` (SessionStart) | One-time scrub of stale Sidekick hook blocks from `~/.codex/hooks.json`; legacy `~/.Codex/hooks.json` mirrors are migration-only and get backed up under `~/.sidekick/legacy-hooks-scrub-backups/` before rollback/removal. Touches only matching Sidekick entries and can restore them with `--rollback`. |
| Registry | `sidekicks/registry.json`, `hooks/lib/sidekick-registry.sh` | Shared metadata for sidekick names, marker files, delegate/stop commands, and installer digests. |
| Skill — `/forge` | `skills/forge/SKILL.md` | Activation / deactivation, health check, delegation protocol, 5-field prompt, fallback ladder (L1 Guide / L2 Handhold / L3 Take over with `sidekick forge-level3 start|stop`), skill injection, AGENTS.md mentoring loop. |
| Skill — `kay-delegate` | `skills/codex-delegate/SKILL.md` | Canonical Kay delegation workflow: runtime health checks, Kay-mode activation, `kay exec --full-auto` child execution, and compatibility aliases for older environments. |
| Alias activation skills | `skills/forge:delegate/SKILL.md`, `skills/kay:delegate/SKILL.md` | User-facing shortcuts used by the website setup flow. They dispatch to the canonical `/forge` and `kay-delegate` workflows. |
| Skill — legacy orchestration | `skills/forge.md`, `skills/codex-delegate.md` | Compatibility aliases retained for legacy entry points; canonical long-form bodies live in `skills/*/SKILL.md`. |
| Enforcer hooks | `hooks/forge-delegation-enforcer.sh`, `hooks/codex-delegation-enforcer.sh` | PreToolUse on `Write\|Edit\|NotebookEdit\|Bash`. Per-sidekick read-only allowlists, mutating-flag rejectors, command rewriters, UUID/audit injectors, and deny paths. |
| Progress hooks | `hooks/forge-progress-surface.sh`, `hooks/codex-progress-surface.sh` | PostToolUse on `Bash`. No-op unless the matching marker is active. Extracts terminal summary blocks, emits styled sidekick summaries, and links the matching stop command. |
| Audit indexes | `.forge/conversations.idx`, `.kay/conversations.idx` | Append-only ISO 8601 UTC rows: `<timestamp> <UUID> <sidekick-tag> <task-hint>`. Lookup only — content lives in each runtime's native history store. |
| Delegation lifecycle skills | `skills/codex-delegate/SKILL.md`, `skills/codex-stop/SKILL.md`, `skills/forge/SKILL.md`, `skills/forge-stop/SKILL.md` | The canonical four-skill Sidekick surface for Forge/Kay sidekick pickers, with `/forge:delegate` and `/kay:delegate` aliases kept as thin dispatchers. |
| Output styles | `output-styles/forge.md`, `output-styles/codex.md` | Narration contracts for active sidekick sessions. Documents `[FORGE]` / `[KAY]` prefixes and `[...-SUMMARY]` blocks. |
| Codex plugin manifest | `.codex-plugin/plugin.json` | v0.5.6. Skills-only packaging for Codex with shared hook wiring. |
| Plugin manifest | `.claude-plugin/plugin.json` | v0.5.6. Points at `hooks/hooks.json`, `outputStyles/`, and `skills/`. `_integrity` carries SHA-256 for the canonical skill bodies plus runtime assets. |
| Marketplace manifest | `.claude-plugin/marketplace.json` | Advertises the plugin to the `alo-exp/sidekick` marketplace. |
| Forge project config | `.forge/agents/forge.md`, `.forge.toml` | Bootstrapped on first activation (non-destructive). Agent frontmatter carries `tools: ["*"]` (critical — missing this silently provisions zero tools). `.forge.toml` caps `max_tokens = 16384`, compaction at 80k tokens, 20% eviction, 6-message retention. |
| Kay project config | `~/.kay/config.toml` | Runtime configuration for Kay. Legacy `~/.code` / `~/.codex` paths are compatibility-only; any uppercase `~/.Codex` tree is treated as backup-only migration material and is retired after a successful reinstall. |

---

## Layered View

```
User
  │
  ▼
Host AI (Brain: Claude Code or Codex)        harness boundary
  │                                             │
  │  composes task prompt                        │
  ├──► /forge or kay-delegate; child Bash runs forge/kay exec │
  │          │                                  │
  │          │ ┌─ PreToolUse sidekick hooks ─────┤
  │          │ │  if matching marker active:     │
  │          │ │    · deny Write/Edit/NotebookEdit
  │          │ │    · rewrite Forge or Kay exec
  │          │ │    · append .forge/.kay idx   │
  │          │ └────────────────────────────────┤
  │          ▼                                  │
  │     Forge or Kay subprocess (Hands)       │
  │          │  reads/writes files,             │
  │          │  runs commands, commits          │
  │          │  emits STATUS / task summary     │
  │          ▼                                  │
  │  ┌─ PostToolUse progress hook ──────────────┤
  │  │  strip ANSI, parse sidekick summary      │
  │  │  emit additionalContext:                 │
  │  │   [FORGE-SUMMARY] ... or [KAY-SUMMARY] │
  │  │   Stop: /forge-stop or /kay-stop
  │  └──────────────────────────────────────────┤
  │                                             │
  ▼                                             │
User receives styled narration           ◄──────┘
  │
  │  (later) inspect `.forge/conversations.idx` or `.kay/conversations.idx` for task traceability
```

---

## Design Principles

1. **Delegate at the harness layer, not the prompt layer.** Prompt-only rules can be rationalized around. A PreToolUse hook returning `permissionDecision: "deny"` cannot.
2. **Keep sidekick state isolated.** Sidekick indexes, markers, and history commands stay per-sidekick, while a shared current-session `active-sidekick` selector makes Forge and Kay mutually exclusive before hooks enforce either mode.
3. **Leverage each runtime's native storage.** Sidekick indexes only carry lookup metadata; Forge and Kay keep their own conversation/history stores.
4. **Zero host-to-sidekick roundtrip per rewrite.** The enforcer is shell, not an LLM wrapper — deterministic, millisecond latency, no token cost.
5. **Non-destructive on install/update.** Plugin config files (`.forge/agents/forge.md`, `.forge.toml`) are written only when absent. Re-activation re-runs the current-session health check but never overwrites user edits.
6. **Graceful degradation off the happy path.** No marker file → both hooks are no-ops. Output style missing → line prefixes degrade to plain text, no break. Monitor unavailable (Bedrock/Vertex/Foundry) → skill documents foreground-Bash fallback.
7. **Every sidekick task is traceable.** Stable UUID from the hook + durable project-local idx = any past task can be found and reviewed by tag, timestamp, and status.

---

## Technology Choices

| Choice | Rationale |
|---|---|
| Bash + Markdown only (no compiled code) | Matches host plugin contracts. Zero install dependencies. Readable, diff-friendly audit trail. |
| Registry-driven sidekick selection | Lets the plugin add more sidekicks without hard-coding them into every hook and command. |
| PreToolUse + PostToolUse hooks | The host hook mechanism that runs *before* a tool call with veto power (`permissionDecision`) and *after* it with `additionalContext` injection. |
| Valid RFC 4122 UUID for `--conversation-id` | Forge 2.11.3 rejects the earlier `sidekick-<ts>-<hash>` format. The human-readable tag is preserved as a separate column in the idx for display only. |
| `set -euo pipefail` in hooks | Fails loud on classifier bugs during development. Every classifier branch returns explicit `{ "continue": true }` JSON to avoid accidental deny from an empty exit. |
| ISO 8601 UTC timestamps in sidekick idx rows | Portable, sortable, and safe for shell-based parsing without locale ambiguity. |
| Seeded-buggy Python testapp for live E2E | A baseline-must-fail assertion proves the E2E actually exercises the fix path, not happy-case parsing. |

---

## Extension Points

- **New sidekick** (additional coding agent): add `skills/<name>/SKILL.md`, `output-styles/<name>.md`, and a row in `sidekicks/registry.json`. Keep bridge skills only when a runtime needs a compatibility alias; the canonical instruction body lives in the skill file. The shared hook library and manifest wiring should not need to change.
- **Additional bootstrap skills**: extend the injection mapping in `skills/forge/SKILL.md` §Skill Injection. Ship as `.forge/skills/<name>/SKILL.md` with Forge-compatible frontmatter (`id`, `title`, `description`, `trigger`).

## Documentation Surfaces

The docs layer around this architecture uses a reader-first system:

- `docs/START-HERE.md` routes people to the right task path
- `docs/AUDIENCE.md` maps docs to readers
- `docs/GLOSSARY.md` defines canonical terms
- `docs/COMPATIBILITY.md` captures runtime differences across Claude, Codex, and Kay
- `docs/ADR/` stores durable docs and architecture decisions

The architecture doc should point readers at those files instead of repeating the same definitions in several places.
- **Custom progress parsing**: `forge-progress-surface.sh` currently caps at 20 lines of the STATUS block. Extending to other Forge output shapes is a single `awk` stanza.

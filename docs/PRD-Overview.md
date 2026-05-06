# Product Requirements Overview

> High-level product vision and requirement areas. Synced with `.planning/REQUIREMENTS.md` — the authoritative source managed by GSD. Updated at the finalization step of each phase and at milestone completion.

**Current milestone:** v1.4.0 (shipped 2026-04-25). All 77 requirements across v1 + v1.2 remain validated.

---

## Product Vision

Sidekick is a Claude Code plugin that turns Claude into a **planner and communicator** and delegates all implementation work — file writes, edits, shell mutations, git operations — to an embedded coding agent. The first shipped sidekick is **Forge** (ForgeCode). Target user: a developer using Claude Code who wants a capable, low-cost coding agent handling the execution while Claude handles the thinking and the conversation.

---

## Core Value

**When `/forge` is active, Claude does not write code.** Delegation is harness-enforced (PreToolUse hook returns `permissionDecision: "deny"` on direct `Write`/`Edit`/`NotebookEdit`), Forge subprocess output is live-visible in the transcript with stable `[FORGE]` markers, and every task is durably indexed by UUID, browsable via `/forge-history`. The ONE thing that must work above all else: **delegation cannot be bypassed, and every task is traceable.**

---

## Requirement Areas

Mapped to phases in `.planning/REQUIREMENTS.md`. All validated as of 2026-04-18.

### v1 — Forge Delegation Mode (v1.1.0 + v1.1.2)

| Area | Req IDs | What it guarantees |
|---|---|---|
| Core `/forge` skill | `SKIL-01..04` | Skill file exists, activation creates marker, health check covers 4 preconditions, deactivation cleans up |
| Delegation protocol | `DLGT-01..05` | 5-field task prompt composition, submission, monitoring; Claude never writes code while active (except L3 fallback) |
| Fallback ladder | `FALL-01..05` | L1 Guide (reframe + retry), L2 Handhold (atomic decomposition, max 3), L3 Take over (direct tool use + DEBRIEF) |
| Skill injection | `SINJ-01..05` | 4 bootstrap skills (testing-strategy, code-review, security, quality-gates), task-type mapping, ≤2 skills per task |
| AGENTS.md mentoring | `AGNT-01..08` | 3-tier write (global / project / session), 2-phase dedup (exact + semantic) |
| Forge config | `FCFG-01..04` | `.forge/agents/forge.md` carries `tools: ["*"]`, `.forge.toml` compaction defaults, non-destructive creation |
| Token optimization | `TOKN-01..04` | 2,000-token cap on task prompts, validated `.forge.toml` compaction |
| Test coverage | `TEST-01..05` | 70 assertions across 8 v1 suites |

### v1.2 — Forge Delegation + Live Visibility (v1.2.0)

| Area | Req IDs | What it guarantees |
|---|---|---|
| Delegation enforcement | `HOOK-01..09` | PreToolUse hook denies direct mutations, allows + rewrites `forge -p`, idempotent, generates valid UUIDs |
| Audit trail | `AUDIT-01..04` | `.forge/conversations.idx` append-only rows, Sidekick never duplicates Forge's native storage |
| Live visibility | `VIS-01..04` | `run_in_background: true` + Monitor for >10s tasks, foreground fallback for Bedrock/Vertex/Foundry |
| Progress surface | `SURF-01..05` | PostToolUse STATUS-block parsing, ANSI strip, replay hint emission, 20-line cap |
| Visual distinction | `STYLE-01..04` | Output-style narration contract — `[FORGE]` / `[FORGE-LOG]` / `[FORGE-SUMMARY]` markers |
| Slash commands | `REPLAY-01..04` | `/forge-history` → joined table + 30-day prune (v1.4.0: `/forge-replay` removed; `forge conversation dump --html` no longer available) |
| Activation lifecycle | `ACT-01..04` | DB-writability check, idx init, output style switch/revert, SKILL.md STEP 4/5/6 documentation |
| Plugin manifest | `MAN-01..04` | Version bumped to 1.2.0, hooks registered, commands + output styles registered, `_integrity` refreshed |
| v1.2 test coverage | `TEST-V12-01..05` | 47 new assertions across enforcer hook, progress surface, UUID format, history pruning, full v1.2 flow |

---

## Out of Scope

Explicit non-goals. See `.planning/REQUIREMENTS.md` §Out of Scope for the authoritative list.

| Item | Reason |
|---|---|
| Headless / non-interactive Forge invocation | Forge has no documented headless CLI mode beyond `-p`; interaction is otherwise ZSH-interactive. |
| Backward compatibility with Forge < 2.11.3 | Targeting latest only. `--conversation-id` UUID validation is a 2.11.3 behavior the plugin depends on. |
| Replacing `skills/forge.md` | The new `/forge` skill extends the legacy orchestration skill; it does not supersede it. |
| Forge MCP server management | User manages MCP separately; plugin does not touch MCP config. |
| Multi-Forge parallelism | Single conversation per task assumption. Candidate for v1.3. |
| Cross-machine conversation sync | Conversations live in `~/forge/.forge.db` on the local machine only. Candidate for v1.3. |
| Custom output style outside `/forge` mode | Output style is activated only when the marker file exists; default style is preserved otherwise. |
| Web UI replay viewer | HTML dump opens in the OS default browser; no bundled viewer. |
| Automatic session-end AGENTS.md extraction | No Forge built-in for this; Claude drives extraction explicitly at task completion. |

---

## Evolution

This doc is a high-level summary — not the source of truth.

- **Source of truth for requirements:** `.planning/REQUIREMENTS.md` (77 requirements, all validated as of v1.4.0).
- **Source of truth for phase structure:** `.planning/ROADMAP.md` (9 phases, all shipped).
- **Source of truth for project state:** `.planning/STATE.md` (`status: complete`, last_updated 2026-04-25).

Update this overview when:
- A new milestone opens (add a section for the new requirement area)
- A requirement moves into / out of Out of Scope
- The Core Value changes (extremely rare — would mean a product-level pivot)

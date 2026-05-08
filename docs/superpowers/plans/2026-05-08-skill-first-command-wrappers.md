# Skill-First Command Wrappers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Sidekick's skills the canonical instruction source and turn `commands/` into thin slash-command wrappers that point at those skills.

**Architecture:** Keep the substantive workflows in `skills/<name>/SKILL.md`, especially for stop/history commands. Leave `commands/<name>.md` as short wrapper docs for discoverability and slash-command UX. Update the skill/orchestration docs, packaging guide, and tests so the repository consistently treats skills as the source of truth.

**Tech Stack:** Markdown docs, Bash test scripts, plugin manifests, Codex/Claude plugin packaging.

---

### Task 1: Invert the packaging guide

**Files:**
- Modify: `docs/internal/codex-command-packaging-guide.md`
- Modify: `docs/knowledge/INDEX.md`
- Modify: `docs/knowledge/2026-05.md`
- Modify: `docs/lessons/2026-05.md`

- [ ] **Step 1: Rewrite the guide**

Explain that `skills/<name>/SKILL.md` is canonical, `commands/<name>.md` is a wrapper/pointer, and Codex still discovers the wrapper path through the plugin manifest.

- [ ] **Step 2: Update the docs index and monthly notes**

Add the new guide to the index and append notes that the project now uses skill-first command packaging.

### Task 2: Move canonical content into skills and turn commands into wrappers

**Files:**
- Modify: `commands/codex-stop.md`
- Modify: `commands/codex-history.md`
- Modify: `commands/forge-stop.md`
- Modify: `commands/forge-history.md`
- Modify: `skills/codex-stop/SKILL.md`
- Modify: `skills/codex-history/SKILL.md`
- Modify: `skills/forge-stop/SKILL.md`
- Modify: `skills/forge-history/SKILL.md`
- Modify: `skills/codex/SKILL.md`
- Modify: `skills/forge/SKILL.md`

- [ ] **Step 1: Replace command bodies with wrappers**

Each `commands/*.md` file should link to the corresponding skill and describe itself as a thin slash-command wrapper.

- [ ] **Step 2: Restore the full workflows in the skill files**

Move the stop/history procedures, pruning logic, and notes into the `skills/*/SKILL.md` files so they are the canonical instruction bodies.

- [ ] **Step 3: Update the orchestration skills**

Refresh `skills/codex/SKILL.md` and `skills/forge/SKILL.md` so they describe commands as wrappers and skills as the source of truth.

### Task 3: Align tests and docs with the new source-of-truth model

**Files:**
- Modify: `tests/test_codex_commands.bash`
- Modify: `tests/test_forge_commands.bash`
- Modify: `tests/run_live_codex_marketplace_install.bash`
- Modify: `docs/ARCHITECTURE.md`
- Modify: `docs/TESTING.md`
- Modify: `README.md`
- Modify: `.claude-plugin/plugin.json`
- Modify: `.codex-plugin/plugin.json`

- [ ] **Step 1: Invert the structural assertions**

Tests should verify that commands are wrappers and skills contain the substantive workflows.

- [ ] **Step 2: Update the docs and manifest copy**

Refresh the architecture, testing, README, and manifest descriptions so they match the skill-first packaging model.

# Codex Skill-First Packaging Guide

> Reusable pattern for making Sidekick workflows canonical in skills and exposing thin command wrappers for slash-command discoverability.

## Goal

Put the full instruction body in `skills/<name>/SKILL.md` and keep `commands/<name>.md` as a thin wrapper or pointer for slash-command UX. That keeps one source of truth while still letting Codex and Claude surface the action in the picker/import path.

This is the pattern Sidekick uses now, and it is the one other Ālo Labs plugins should copy.

## The pattern

Use three layers:

1. **Canonical skill** in `skills/<name>/SKILL.md`
2. **Thin command wrapper** in `commands/<name>.md`
3. **Codex plugin manifest** in `.codex-plugin/plugin.json`

The skill holds the actual workflow. The command is only a wrapper so the command name is visible in slash-command UX. The manifest ties the bundle together.

### Recommended layout

```text
plugin-root/
├── .codex-plugin/
│   └── plugin.json
├── commands/
│   ├── codex-stop.md
│   └── codex-history.md
└── skills/
    ├── codex-stop/
    │   └── SKILL.md
    └── codex-history/
        └── SKILL.md
```

If you need aliases, add a second skill bridge for the alias name, but keep it pointed at the same canonical skill.

## What goes where

### `skills/<name>/SKILL.md`

Write the full workflow here. This is the source of truth.

Keep these files focused on the actual action the plugin should perform:

- what the command does
- what context it needs
- what output it should produce
- what files or state it must preserve

Do not split the real instructions across multiple files. The skill should be the only place that contains the substantive workflow.

### `commands/<name>.md`

Write a thin wrapper here. It should:

- point to the canonical skill
- explain that the skill is the source of truth
- avoid duplicating the full workflow text

Example wrapper:

```markdown
---
name: codex-stop
description: Thin slash-command wrapper for the canonical skills/codex-stop/SKILL.md workflow.
---

# /codex-stop

Use the canonical [`skills/codex-stop/SKILL.md`](../skills/codex-stop/SKILL.md) workflow.
That skill is the source of truth; this command exists so Codex and Claude can surface the action in slash-command UX.
```

That wrapper shape makes the command visible without copying the implementation text.

### `.codex-plugin/plugin.json`

Register the shared command surface, shared skills, hooks, and interface metadata in the Codex plugin manifest.

Keep the Codex manifest and the Claude manifest on the same version, and make sure the Codex manifest points at the shared command directory:

```json
{
  "name": "sidekick",
  "version": "1.5.3",
  "skills": "./skills/",
  "commands": "./commands/",
  "hooks": "./hooks/hooks.json"
}
```

## How Codex discovers the workflows

The important behavior is not just "the files exist." The important behavior is that Codex can read the plugin, see the thin command wrappers, and surface the underlying skill names in `plugin/read` so the picker/import path can show them.

For Sidekick, the live check verifies the skill names appear as:

- `sidekick:codex-delegate`
- `sidekick:codex-history`
- `sidekick:codex-stop`
- `sidekick:forge-delegate`
- `sidekick:forge-history`
- `sidekick:forge-stop`

That is the outcome other plugins should aim for:

- canonical skill exists
- thin command wrapper exists
- Codex can see the skill in the live plugin reader

## When to add an alias bridge

Add an alias bridge when you want one of these:

- a compatibility name for older users
- a more discoverable picker name
- a short alias that mirrors a different runtime's command naming

Keep the alias bridge thin. Do not create a second copy of the workflow. Point it back to the canonical skill.

## Verification checklist

When another Ālo Labs plugin copies this pattern, run the same checks:

1. **Skill check** - the canonical workflow lives in `skills/<name>/SKILL.md`.
2. **Wrapper check** - the command doc points to that skill and does not duplicate the workflow body.
3. **Live discovery check** - Codex `plugin/read` surfaces the expected skill names.
4. **Live install check** - the plugin installs cleanly from the Codex marketplace.
5. **Behavior check** - the workflow actually runs the right action when invoked.

For Sidekick, the current test set is:

- `tests/test_codex_commands.bash`
- `tests/test_codex_plugin_manifest.bash`
- `tests/run_live_codex_plugin_read.bash`
- `tests/run_live_codex_marketplace_install.bash`
- `tests/run_live_codex_e2e.bash`

## Rules of thumb

- Keep one canonical body for each workflow in a skill.
- Keep command wrappers short and explicit.
- Keep command names, skill names, and tests in sync.
- Prefer relative links from the wrapper back to the skill.
- Update both the Claude and Codex manifests when the packaging shape changes.
- If Codex starts loading the skill docs directly in a future runtime, keep the wrappers anyway for compatibility and slash-command discoverability.

## Copy this for another plugin

If another Ālo Labs plugin wants the same behavior, copy the pattern, not the Sidekick text:

1. Put the real workflow in `skills/<name>/SKILL.md`.
2. Add a thin wrapper at `commands/<name>.md`.
3. Register the shared command and skill roots in `.codex-plugin/plugin.json`.
4. Add a live `plugin/read` test that proves the skill names appear.
5. Keep the wrapper thin and keep the skill canonical.

That gives you the same discoverability result without duplicating the instructions in two places.

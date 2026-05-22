# Codex Skill Packaging Guide (Current, Correct Method)

This replaces the older command-centric guidance.

## What Codex supports today

For third-party plugins in Codex, **skills are the runtime contract**.

- Codex discovers plugin skills from the directory named by `.codex-plugin/plugin.json`'s `skills` field.
- There is no separate third-party command runtime to maintain.
- `commands/` wrappers are not required for Codex picker visibility.

For Sidekick, treat `skills/**/SKILL.md` as the host-agnostic canonical authoring source and `agents/codex/**/SKILL.md` as the generated Codex-facing package surface.

## Required plugin shape

```text
plugin-root/
├── .codex-plugin/
│   └── plugin.json
├── skills/
│   ├── <skill-a>/
│   │   └── SKILL.md
│   ├── <skill-b>/
│   │   └── SKILL.md
│   └── ...
└── agents/
    └── codex/
        ├── <skill-a>/
        │   └── SKILL.md
        ├── <skill-b>/
        │   └── SKILL.md
        └── ...
```

`.codex-plugin/plugin.json` must point at the generated Codex surface:

```json
{
  "name": "<plugin-name>",
  "version": "<x.y.z>",
  "skills": "./agents/codex/",
  "hooks": "./hooks/hooks.json"
}
```

Do not add a `commands` contract for Codex packaging.

## Picker behavior mapping

Use this to reason about why a skill does or does not appear:

1. `/` picker and `$` skills picker: driven by `skills/list` (enabled skills).
2. `@` plugin/skills surfaces: driven by plugin skill metadata (`plugin/read`) for installed plugin skills.
3. If `SKILL.md` exists but the skill is missing, first verify `skills/list` and `plugin/read` outputs.

## Naming and ordering rules

Codex skill names are namespaced as `<plugin>:<name>` from SKILL frontmatter `name`.

To keep deterministic order across picker surfaces:

1. Keep only one canonical skill per workflow.
2. Use stable, lexicographically ordered names for intended display order.
3. Avoid duplicate/near-duplicate canonical+bridge skills unless compatibility truly requires it.
4. Remove obsolete skills instead of leaving stale entries in `skills/`.

For Sidekick, the canonical 4-skill delegation surface is:

1. `sidekick:forge-delegate`
2. `sidekick:forge-stop`
3. `sidekick:kay-delegate`
4. `sidekick:kay-stop`

Sidekick also ships thin setup aliases for website copy and slash-style activation:

1. `sidekick:forge:delegate`
2. `sidekick:kay:delegate`

Codex currently reports plugin skills in lexicographic order, so `plugin/read` surfaces the Forge entries before the Kay entries even though both agent families are canonical.

## Cross-plugin rollout checklist

Apply this sequence for any plugin that should appear correctly in Codex pickers:

1. Move full workflow bodies into `skills/<name>/SKILL.md`.
2. Remove stale command wrappers/obsolete SKILL entries.
3. Regenerate host surfaces with `bash scripts/sync-host-surfaces.sh`.
4. Ensure `.codex-plugin/plugin.json` uses `"skills": "./agents/codex/"`.
5. Verify local integrity/tests.
6. Verify Codex runtime surfaces:
   - `skills/list` includes expected names.
   - `plugin/read` includes expected names and order.
7. Bump patch version and release.
8. Reinstall plugin cleanly in local Codex env and re-verify picker surfaces.

## Troubleshooting

If skills appear in `/` or `$` but not as expected in `@`:

1. Check installed plugin version/cache actually matches the released tree.
2. Confirm removed skills are truly deleted from `skills/**/SKILL.md` and regenerated out of `agents/codex/**/SKILL.md` (not just deprecated in prose).
3. Confirm `plugin/read` returns exactly the expected skill names.
4. Reinstall plugin cleanly to flush stale cache entries.

This process is now the source of truth for Sidekick and should be reused for other plugins.

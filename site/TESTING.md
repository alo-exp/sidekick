# Testing Strategy

> Current Sidekick test strategy for Kay and Codex delegation.

Sidekick is a Shell/Bash and Markdown project. Tests are Bash scripts under `tests/`, and the public site has dedicated contract checks so the docs stay aligned with supported sidekicks.

## Main Commands

```bash
# Strict non-live unit and integration suites
bash tests/run_unit.bash

# Skip-safe local sweep
bash tests/run_all.bash

# Live release gate for the local Codex sidekick path
bash tests/run_in_kay.bash SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
```

## Test Pyramid

| Tier | Script | Purpose |
| --- | --- | --- |
| Strict unit and integration | `tests/run_unit.bash` | Runs static, hook, installer, manifest, generated-surface, docs, and runner-contract checks. |
| Skip-safe local sweep | `tests/run_all.bash` | Runs unit checks plus live wrappers in skip-safe mode when live env vars are absent. |
| Live Codex release gate | `tests/run_in_kay.bash SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash` | Exercises the release-authorizing live path for delegated Codex work. |

## Public Site Contract Tests

| Suite | Coverage |
| --- | --- |
| `tests/test_homepage_sidekicks.bash` | Homepage names Sidekick 0.7.1, Kay, Codex, activation commands, stop commands, host verification, and release evidence. |
| `tests/test_help_site_navigation.bash` | Help pages exist, share navigation, document Kay/Codex workflows, and include recovery content. |
| `tests/test_docs_contract.bash` | Public Markdown docs align with the current Sidekick contract. |
| `tests/test_og_image.bash` | Social preview source names Kay and Codex delegation and the host verification promise. |

## Generated Surface Checks

Generated host bundles are not hand-maintained. When a canonical skill changes, run:

```bash
bash scripts/sync-host-surfaces.sh
bash tests/test_agent_surface_render.bash
```

If install, hook, skill, generated surface, output-style, or registry files change, refresh manifest integrity values and run:

```bash
bash tests/test_plugin_integrity.bash
```

## Runtime-Specific Checks

Kay runtime checks cover:

- Kay activation and stop marker behavior.
- `kay exec` command routing.
- Provider selectors for OpenCode Go and Xiaomi routing.
- Project-local Kay lookup state.

Codex sidekick checks cover:

- Local OpenAI Codex CLI readiness.
- `codex exec` command routing.
- `gpt-5.4-mini` and extra-high reasoning configuration.
- Project-local Codex lookup state.

## Host Verification Coverage

Verification should catch at least:

- Missed requirements.
- Integration errors.
- Regressions.
- Wrong logic.
- Syntax errors.
- Wrong files.
- Unverified assumptions.
- Knowledge gaps.
- Misunderstood task scope.
- Incomplete trials.
- Provider API failures.
- External execution failures.

When a verification check fails, the host relaunches the active sidekick with focused guidance and reruns the relevant checks.

# Project: Sidekick

## Project Conventions

- Shell/Bash + Markdown stack -- no compiled languages.
- Supported sidekicks are Kay and Codex.
- Canonical workflows live under `skills/`: `kay-delegate`, `kay-stop`, `codex-delegate`, and `codex-stop`.
- Generated host bundles under `agents/claude/` and `agents/codex/` are rendered by `bash scripts/sync-host-surfaces.sh`; do not hand-edit generated copies unless you also update the canonical source and renderer contract.
- Tests live in `tests/` and run via `bash tests/run_all.bash`.
- Plugin manifests live in `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`; refresh `_integrity` SHA-256 values when install, hook, skill, generated surface, output-style, or registry files change.

## Delegation Contract

- The host AI plans, communicates, delegates, verifies, and owns final correctness.
- Kay delegates to the Kay/OpenCode Go runtime.
- Codex delegates to the local Codex CLI using `gpt-5.4-mini` with Extra High reasoning.
- Activation is selected by the shared `active-sidekick` marker. Only one sidekick may be active in a host session.
- After every sidekick task, the host must verify the result against the original prompt and surrounding repository behavior before reporting completion.

## Host Verification

The host verification pass must check for at least these failure classes:

- `MISSED_REQUIREMENT`
- `INTEGRATION_ERROR`
- `REGRESSION`
- `WRONG_LOGIC`
- `SYNTAX_ERROR`
- `WRONG_FILE`
- `UNVERIFIED_ASSUMPTION`
- `KNOWLEDGE_GAP`
- `MISUNDERSTOOD_TASK`
- `TRIAL_INCOMPLETE`
- `API_FAILURE`
- `EXECUTION_ERROR_EXTERNAL`

If verification finds a failure, relaunch or guide the active sidekick for the missed subtask, then verify again. Completion is only valid after the host confirms the delegated result is correct.

## Integrity Workflow

When modifying files covered by manifest integrity, recompute the matching SHA-256 in `.claude-plugin/plugin.json` in the same change set.

Useful checks:

```bash
bash scripts/sync-host-surfaces.sh
bash tests/test_plugin_integrity.bash
bash tests/run_unit.bash
```

Recompute a hash with:

```bash
shasum -a 256 <file> | awk '{print $1}'
```

## Release Discipline

- Keep release docs and manifests aligned with the currently supported sidekicks.
- Run `bash tests/run_all.bash` before a release candidate.
- Run the Kay-hosted live release gate described in `site/pre-release-quality-gate.md` before publishing.
- Planning artifacts under `.planning/` should land separately from product/release changes when possible, so release diffs stay reviewable.

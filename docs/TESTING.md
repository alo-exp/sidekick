# Testing Strategy

> How the Sidekick plugin is tested. All six tiers are chained by `tests/run_release.bash`, which is the gate every release must pass. After publishing, `tests/post_release_cleanup.bash` returns the local repo to a clean state.

---

## Test pyramid

Six tiers, fail-fast, each with a distinct purpose. The lower a failure appears in the pyramid, the cheaper it is to find.

| Tier | Script | Runs in CI | Exercises real agent | Purpose |
|------|--------|:---:|:---:|---|
| **1. Unit + integration** | `tests/run_all.bash` | ✅ | ✗ (mocked / static inspection) | Classifier correctness, idx audit-row shape, plugin manifest integrity, skills-only packaging, Forge/Code coverage gaps, post-release cleanup, repository layout. |
| **2. Forge smoke** | `tests/smoke/run_smoke.bash` | skip | ✓ Forge | `forge --version` succeeds; trivial `forge -p` round-trip emits a `STATUS:` block; auto-injected `--conversation-id` is a valid UUID. |
| **3. Forge live E2E** | `tests/run_live_e2e.bash` | skip | ✓ Forge | Full Claude→Forge delegation on a seeded-buggy Python testapp. Baseline-must-fail + `add()` patched + `sub()` preserved + all 3 tests pass after fix. |
| **4. Code marketplace install** | `tests/run_live_codex_marketplace_install.bash` | skip | ✓ Code | Installs Sidekick from the Codex marketplace, resolves the packaged runtime, and proves the marketplace packaging path is live. |
| **5. Code smoke** | `tests/smoke/run_codex_smoke.bash` | skip | ✓ Code | `code --version` succeeds; trivial `code exec` round-trip completes against the real binary. |
| **6. Code live E2E** | `tests/run_live_codex_e2e.bash` | skip | ✓ Code | Full Claude→Code delegation on the same seeded-buggy Python testapp. Baseline-must-fail + `add()` patched + `sub()` preserved + all 3 tests pass after fix. |

Stages 2 through 6 are gated behind `SIDEKICK_LIVE_FORGE=1` and `SIDEKICK_LIVE_CODEX=1` so they never run in CI. Without the env vars, those stages exit 0 cleanly and the release gate still runs stage 1.

---

## Unit + integration suites (tier 1)

Core suites in `tests/`. Each suite is an independent Bash script with a pass/fail counter.

| Suite | Coverage |
|---|---|
| `test_forge_skill.bash` | `/forge` activation / deactivation, marker lifecycle, health check |
| `test_fallback_ladder.bash` | L1 Guide reframe, L2 Handhold atomic decomposition, L3 Take-over + DEBRIEF |
| `test_skill_injection.bash` | Task-type → skill mapping, injection budget cap, skill-file existence |
| `test_agents_md_dedup.bash` | 3-tier AGENTS.md write, exact-match + semantic dedup |
| `test_forge_enforcer_hook.bash` | PreToolUse behavior: deny Write/Edit/NotebookEdit, rewrite `forge -p`, read-only allowlist passthrough, idempotent rewrites, UUID format |
| `test_forge_progress_surface.bash` | PostToolUse behavior: no-op inactive, STATUS parsing, ANSI strip, 20-line cap, stop-hint emission |
| `test_forge_v12_integration.bash` | End-to-end Pre → Post hook flow: marker on → Bash → rewrite → STATUS → summary → idx row |
| `test_forge_e2e.bash` | Static E2E of prompt composition + skill injection without live Forge |
| `test_v12_coverage.bash` | Coverage-gap suite: `sed -i` / `awk -i inplace` denial, `>>` append, `> /dev/null` passthroughs, env-var prefix, 80-char task-hint truncation, unknown tool_name passthrough, stdout-only summary fallback |
| `test_v13_coverage.bash` | Forge v1.3 coverage gaps: helper extraction, path allowlist, SRI, and sentinel-related regressions |
| `test_validate_release_gate_hook.bash` | Release-gate hook: blocks `gh release create` until all four quality-gate markers are present |
| `test_post_release_cleanup.bash` | Post-release cleanup script: removes transient repo-local artifacts and is idempotent |
| `test_repo_layout.bash` | Repository layout guard: expected top-level files/directories and docs structure stay organized |
| `test_codex_skill.bash` | Code skill structure, activation/deactivation markers, and packaging expectations |
| `test_codex_enforcer_hook.bash` | Code PreToolUse behavior: deny direct mutation, rewrite `code exec` (with compatibility aliases), allow read-only passthrough |
| `test_codex_progress_surface.bash` | Code PostToolUse behavior: STATUS parsing, ANSI strip, summary emission, stop hint |
| `test_codex_plugin_manifest.bash` | Code plugin manifest structure, interface metadata, and path wiring |
| `test_codex_marketplace_manifest.bash` | Sidekick marketplace entry, source pinning, and install-packaging expectations |
| `test_plugin_integrity.bash` | Every `_integrity` SHA-256 in `plugin.json` matches the on-disk artifact |
| `test_install_sh.bash` | Installer idempotency, sentinel behavior, credentials schema validation |
| `test_fresh_install_sim.bash` | Simulates fresh-install path: no `.forge/`, no `.installed` sentinel |

All listed suites are invoked by `tests/run_all.bash` with fail-fast reporting.

---

## Smoke harness (tier 2)

`tests/smoke/run_smoke.bash` — 3 assertions gated on `SIDEKICK_LIVE_FORGE=1`:

1. `forge --version` exits 0 and prints a semver.
2. Minimal `forge -p '…'` round-trip emits a `STATUS:` block within 30s.
3. The hook-injected `--conversation-id` matches `^[0-9a-f]{8}-…` (valid lowercase RFC 4122 UUID).

When the env var is absent, the script prints a yellow skip notice and exits 0.

---

## Live E2E driver (tier 3)

`tests/run_live_e2e.bash` + `tests/testapp/`:

**Fixture.** `tests/testapp/calc.py` defines two functions: `add(a, b)` (seeded bug — returns `a - b`) and `sub(a, b)` (correct). `tests/testapp/test_calc.py` is pure-stdlib `unittest` — `test_add_positive`, `test_add_negative_and_positive`, `test_sub`.

**Flow.**
1. Copy testapp to `$TMPDIR` sandbox.
2. Run the tests — baseline **must fail** (bug is real).
3. Send Forge a 5-field task prompt through `forge -C <sandbox> -p '…'` (180s timeout).
4. Assert `calc.py`'s `add` now returns `a + b` (regex-verified).
5. Assert `sub` is untouched — no over-fix.
6. Re-run tests — all 3 must now pass.
7. Sandbox is preserved on disk for maintainer inspection.

Gated on `SIDEKICK_LIVE_FORGE=1`. Never runs in CI — it makes a real model call and takes ~30–120 seconds.

---

## Release gate

`tests/run_release.bash` chains all six tiers with fail-fast stage aborts:

```bash
SIDEKICK_LIVE_FORGE=1 SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash   # full pyramid — maintainer pre-tag
bash tests/run_release.bash                                               # stage 1 only, stages 2-6 skip cleanly — safe for CI
```

Every release must first pass the 4-stage pre-release quality gate twice in a row, then pass the full live Forge/Codex pyramid twice locally before the version tag is pushed.

After the GitHub release is published, run `bash tests/post_release_cleanup.bash` to remove any transient repo-local artifacts left behind by the release process.

---

## Coverage goals

- **Classifier branches** (enforcer hook `is_read_only`, `decide_bash`): every branch covered by `test_forge_enforcer_hook.bash` + `test_v12_coverage.bash`. Target: 100% branch coverage; current: 100%.
- **Hook JSON contract**: every `permissionDecision` shape (`allow` / `deny` / passthrough) and `updatedInput.command` rewrite is asserted against the exact Claude Code PreToolUse schema.
- **Idempotence**: rewriting an already-rewritten `forge -p` command is asserted to be a no-op.
- **Happy-path E2E**: tier-3 live run confirms the full flow works end-to-end on every release.

Not covered today (accepted gaps, documented in `.planning/`):

- Multi-Forge parallelism (single conversation per task assumption).
- Cross-machine conversation sync.
- Bedrock/Vertex/Microsoft Foundry hosts (Monitor unavailable — skill documents the foreground-Bash fallback path; not exercised by an automated test).

---

## Running tests locally

```bash
# Tier 1 only (fast, ~5s):
bash tests/run_all.bash

# Pre-release gate (~2 min when both live env vars are set):
SIDEKICK_LIVE_FORGE=1 SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash

# Single suite:
bash tests/test_forge_enforcer_hook.bash
```

Each suite prints `PASS` / `FAIL` per assertion with colored output and a count summary at the end. A failing tier aborts the release gate before the next tier runs.

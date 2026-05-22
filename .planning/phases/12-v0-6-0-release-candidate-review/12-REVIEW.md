---
phase: 12-v0-6-0-release-candidate-review
reviewed: 2026-05-22T19:19:41Z
depth: deep
files_reviewed: 76
files_reviewed_list:
  - .claude-plugin/marketplace.json
  - .claude-plugin/plugin.json
  - .codex-plugin/plugin.json
  - .github/workflows/ci.yml
  - CHANGELOG.md
  - README.md
  - agents/claude/codex-delegate.md
  - agents/claude/codex-delegate/SKILL.md
  - agents/claude/codex-stop/SKILL.md
  - agents/claude/forge-stop/SKILL.md
  - agents/claude/forge.md
  - agents/claude/forge/SKILL.md
  - agents/claude/forge:delegate/SKILL.md
  - agents/claude/kay:delegate/SKILL.md
  - agents/codex/codex-delegate.md
  - agents/codex/codex-delegate/SKILL.md
  - agents/codex/codex-stop/SKILL.md
  - agents/codex/forge-stop/SKILL.md
  - agents/codex/forge.md
  - agents/codex/forge/SKILL.md
  - agents/codex/forge:delegate/SKILL.md
  - agents/codex/kay:delegate/SKILL.md
  - context.md
  - hooks/lib/sidekick-registry.sh
  - hooks/scrub-legacy-user-hooks.py
  - hooks/validate-release-gate.sh
  - install.sh
  - scripts/render-agent-bundle.py
  - scripts/sync-host-surfaces.sh
  - silver-bullet.md
  - site/ARCHITECTURE.md
  - site/CICD.md
  - site/COMPATIBILITY.md
  - site/PRD-Overview.md
  - site/TESTING.md
  - site/help/concepts/index.html
  - site/help/getting-started/index.html
  - site/help/index.html
  - site/help/reference/index.html
  - site/help/search.js
  - site/help/troubleshooting/index.html
  - site/help/workflows/index.html
  - site/index.html
  - site/internal/codex-command-packaging-guide.md
  - site/internal/pre-release-quality-gate.md
  - site/knowledge/2026-04.md
  - site/pre-release-quality-gate.md
  - skills/codex-delegate/SKILL.md
  - skills/codex-stop/SKILL.md
  - skills/forge-stop/SKILL.md
  - skills/forge/SKILL.md
  - tests/post_release_cleanup.bash
  - tests/run_all.bash
  - tests/run_live_codex_marketplace_install.bash
  - tests/run_live_codex_plugin_read.bash
  - tests/run_release.bash
  - tests/run_unit.bash
  - tests/test_agent_surface_render.bash
  - tests/test_clean_reinstall.bash
  - tests/test_codex_enforcer_hook.bash
  - tests/test_codex_marketplace_manifest.bash
  - tests/test_codex_marketplace_release_gate.bash
  - tests/test_codex_plugin_manifest.bash
  - tests/test_codex_skill.bash
  - tests/test_docs_contract.bash
  - tests/test_forge_skill.bash
  - tests/test_help_site_navigation.bash
  - tests/test_homepage_sidekicks.bash
  - tests/test_host_surface_rewrite.bash
  - tests/test_install_sh.bash
  - tests/test_legacy_hook_scrub.bash
  - tests/test_plugin_integrity.bash
  - tests/test_post_release_cleanup.bash
  - tests/test_repo_layout.bash
  - tests/test_runner_contract.bash
  - tests/test_validate_release_gate_hook.bash
findings:
  critical: 1
  warning: 2
  info: 0
  total: 3
status: issues_found
---

# Phase 12: Code Review Report

**Reviewed:** 2026-05-22T19:19:41Z
**Depth:** deep
**Files Reviewed:** 76
**Status:** issues_found

## Summary

Reviewed the full release diff `v0.5.8..4cc412e81c826552f7299e638f8822756610a367` for Sidekick Stage 1 pre-release blockers. The strict non-live suite passed in an isolated temp checkout, but the release is still blocked by a clean-reinstall deletion risk and two release-process contract defects.

Verification performed:
- `git diff --stat v0.5.8..4cc412e81c826552f7299e638f8822756610a367`
- `git diff v0.5.8..4cc412e81c826552f7299e638f8822756610a367`
- `git diff --check v0.5.8..4cc412e81c826552f7299e638f8822756610a367` passed.
- In a temp checkout of `4cc412e81c826552f7299e638f8822756610a367`, `HOME=<temp> bash tests/run_unit.bash` passed all strict non-live suites.
- An isolated clean-reinstall probe showed an out-of-home Sidekick-shaped cache directory was deleted and the installer exited 0.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01 [CRITICAL]: Clean reinstall can delete Sidekick-shaped cache roots outside the active host home

**File:** `install.sh:684`

**Issue:** `validate_clean_reinstall_cache_target` only checks that `plugin_root_dir` contains `/.codex/plugins/cache/` or `/.claude/plugins/cache/`, ends in `/sidekick`, and that the target leaf is version-like. It does not resolve the path or require it to live under the current host home. The destructive call at `install.sh:728` then runs `rm -rf "${plugin_root_dir}"`.

I verified this with an isolated temp run: `HOME` pointed at one temp directory, `CODEX_PLUGIN_ROOT` pointed at a different temp tree shaped like `.../.codex/plugins/cache/market/sidekick/v0.6.0`, and `SIDEKICK_CLEAN_REINSTALL=1` deleted the existing `sidekick` cache directory while exiting 0. In real use, a stale or malformed host root can therefore remove another cache tree that merely matches the path pattern.

**Impact:** Release safety regression. Clean reinstall is explicitly supposed to avoid arbitrary host/user-root deletion; this implementation can delete outside the active host home if the host root env is stale, symlinked through another tree, or otherwise malformed.

**Fix:** Resolve and constrain the deletion target before `rm -rf`. Require the resolved `plugin_root_dir` to be inside the active host's cache root under `$HOME`, reject symlinked/intermediate paths resolving outside that root, and add a regression that seeds a keep file outside `$HOME` and proves clean reinstall refuses before deletion.

```bash
host_cache_root_for_clean_reinstall() {
  case "$1" in
    codex) printf '%s/.codex/plugins/cache\n' "$HOME" ;;
    claude) printf '%s/.claude/plugins/cache\n' "$HOME" ;;
    *) return 1 ;;
  esac
}

cache_root="$(host_cache_root_for_clean_reinstall "$host")"
real_cache_root="$(realpath "$cache_root" 2>/dev/null || python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve(strict=False))' "$cache_root")"
real_plugin_root="$(realpath "$plugin_root_dir" 2>/dev/null || python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve(strict=False))' "$plugin_root_dir")"

case "${real_plugin_root}/" in
  "${real_cache_root}/"*/sidekick/) ;;
  *) echo "[forge-plugin] ERROR: Refusing clean reinstall outside active ${host} cache: ${plugin_root_dir}" >&2; return 1 ;;
esac
```

## Important Issues

### IM-01 [IMPORTANT]: Release docs invalidate commit-scoped markers by ordering artifact commits after the live gate

**File:** `site/CICD.md:35`

**Issue:** The release flow tells maintainers to complete the 4-stage quality gate, then run the live gate twice, then update release artifacts and commit them at `site/CICD.md:43-50`. The hook now requires both stage and live-pyramid markers to match the current `HEAD` SHA. If a maintainer follows this order, the release artifact commit changes `HEAD` after the markers are written, so the release hook correctly denies tag publication and `gh release create`.

**Impact:** Public release instructions are internally inconsistent with the current-commit enforcement. This will either block maintainers during publication or train them to bypass the hook.

**Fix:** Reorder the CI/CD release flow so release metadata and integrity hashes are updated and committed before the four-stage gate and the two live-pyramid runs. Alternatively, state explicitly that all four stage markers and both live-pyramid runs must be repeated after the final release commit.

```markdown
1. Update release artifacts and commit the final release candidate.
2. Complete the 4-stage pre-release quality gate against that exact commit.
3. Run `SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash` twice against that same commit.
4. Tag, push, and create the GitHub release.
```

### IM-02 [IMPORTANT]: `run_all.bash` is not the advertised skip-safe everything runner

**File:** `tests/run_all.bash:23`

**Issue:** `run_all.bash` delegates to `run_unit.bash`, then runs only `test_forge_e2e.bash` and `run_live_codex_plugin_read.bash`. It omits other skip-safe live-gated scripts that are part of the release pyramid: `smoke/run_smoke.bash`, `run_live_e2e.bash`, `run_live_codex_marketplace_install.bash`, `smoke/run_codex_smoke.bash`, and `run_live_codex_e2e.bash`.

**Impact:** The runner contract requested for this release says `run_all.bash` is skip-safe everything. Users running the public aggregate do not exercise most skip-safe live wrappers, even when the corresponding live env vars are set, so regressions in those wrappers only surface in `run_release.bash`.

**Fix:** Either add the omitted skip-safe scripts to `run_all.bash` without recording release markers, or rename/document `run_all.bash` as a partial local sweep. To satisfy the requested contract, include the missing scripts.

```bash
run_suite "Skip-safe Forge smoke" "${SCRIPT_DIR}/smoke/run_smoke.bash"
run_suite "Skip-safe Forge live E2E" "run_live_e2e.bash"
run_suite "Skip-safe Kay marketplace install" "run_live_codex_marketplace_install.bash"
run_suite "Skip-safe Kay smoke" "${SCRIPT_DIR}/smoke/run_codex_smoke.bash"
run_suite "Skip-safe Kay live E2E" "run_live_codex_e2e.bash"
```

## Positive Observations

- Host-facing manifests now point to generated `agents/claude/` and `agents/codex/` skill roots, while canonical sources remain under `skills/`.
- The release hook now enforces current-session and current-commit stage/live markers, and the release hook suite covers many direct, wrapped, API, GraphQL, and tag-push publication paths.
- Kay installer metadata is read from `SOURCE_PLUGIN_ROOT`, and the unit suite includes a stale `SIDEKICK_PLUGIN_ROOT` regression.
- Public homepage, README, manifests, and PRD overview now surface `v0.6.0`; stale `v0.5.6` state is not advertised on the main public surfaces reviewed.

## Verdict

Ready to release? No.

Release should wait for the clean-reinstall deletion guard and the release-process contract fixes above.

---

_Reviewed: 2026-05-22T19:19:41Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: deep_

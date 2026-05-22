---
phase: release-candidate-v0.6.0-stage1-gsd-clean-pass-a
reviewed: 2026-05-22T17:09:57Z
depth: deep
files_reviewed: 66
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
  - install.sh
  - scripts/render-agent-bundle.py
  - scripts/sync-host-surfaces.sh
  - silver-bullet.md
  - site/CICD.md
  - site/COMPATIBILITY.md
  - site/TESTING.md
  - site/help/concepts/index.html
  - site/help/getting-started/index.html
  - site/help/index.html
  - site/help/reference/index.html
  - site/help/search.js
  - site/help/troubleshooting/index.html
  - site/help/workflows/index.html
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
  - tests/test_forge_skill.bash
  - tests/test_help_site_navigation.bash
  - tests/test_host_surface_rewrite.bash
  - tests/test_plugin_integrity.bash
  - tests/test_post_release_cleanup.bash
  - tests/test_repo_layout.bash
  - tests/test_runner_contract.bash
findings:
  critical: 2
  warning: 2
  info: 0
  total: 4
status: issues_found
---

# Phase release-candidate-v0.6.0-stage1-gsd-clean-pass-a: Code Review Report

**Reviewed:** 2026-05-22T17:09:57Z
**Depth:** deep
**Files Reviewed:** 66
**Status:** issues_found

## Summary

Reviewed Sidekick release candidate range `v0.5.8..40d0e31d32c533b932f9f28e6789e7c8d6c73d36`, focusing on host-specific skill reorg, runner split, release-gate hardening, generated host surfaces, plugin manifests, hooks, cleanup, and docs. The external Codex marketplace pin was treated as provisional per review instructions and is not flagged here.

Release verdict: BLOCKED. Two BLOCKER findings affect release readiness: the strict non-live suite fails in an isolated checkout, and release-gate stage markers are not bound to the commit under release. I also found two WARNING items that should be fixed before final polish but are secondary to the blockers.

Verification performed:
- `git diff --check v0.5.8..40d0e31d32c533b932f9f28e6789e7c8d6c73d36` passed.
- A temp clone of `40d0e31d32c533b932f9f28e6789e7c8d6c73d36` with isolated `HOME` ran `tests/run_unit.bash`; result was `1 SUITE(S) FAILED`, in `tests/test_legacy_hook_scrub.bash`.

Review note: the working tree had uncommitted edits after this review started. Findings below are anchored to the requested commit SHA, not later local edits.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01 [BLOCKER]: Legacy hook scrubber misses Sidekick-owned hooks under path aliases

**File:** `hooks/scrub-legacy-user-hooks.py:30`

**Issue:** The scrubber resolves its own plugin root with `Path(__file__).resolve()` and then checks hook command ownership with a raw substring test against that resolved path at `hooks/scrub-legacy-user-hooks.py:137-149`. In an isolated checkout under macOS temp paths, hook fixture commands used `/var/folders/.../repo`, while `Path.resolve()` canonicalized the script path to `/private/var/folders/.../repo`. The raw string check failed, so `runtime-sync`, `delegation-enforcers`, `validate-release-gate`, and progress-surface blocks were left in `hooks.json`.

This is both a test failure and a functional cleanup bug: legacy hooks installed through symlinked or alias paths can survive the migration. The release's strict non-live test runner fails because `tests/test_legacy_hook_scrub.bash:167-173` expects the scrubber to remove all Sidekick-owned blocks and the assertion at `tests/test_legacy_hook_scrub.bash:135-140` is not satisfied.

**Fix:**

Canonicalize both sides of path ownership checks, or track both lexical and resolved plugin-root spellings. Add a regression that runs the scrubber from a symlinked or `/var` versus `/private/var` checkout.

```python
SCRIPT_PATH = Path(__file__)
PLUGIN_ROOTS = {
    SCRIPT_PATH.parent.parent,
    SCRIPT_PATH.resolve().parent.parent,
}

def command_has_sidekick_owner(command: str) -> bool:
    normalized = command.replace("\\", "/")
    if any(str(root).replace("\\", "/") in normalized for root in PLUGIN_ROOTS):
        return True
    # Keep existing host-marker and cache-path checks here.
```

Also normalize path-like command fragments before matching, so `/var/...` and `/private/var/...` aliases compare as the same checkout.

### CR-02 [BLOCKER]: Release-gate stage markers are not bound to the commit being released

**File:** `hooks/validate-release-gate.sh:2876`

**Issue:** Stage markers are accepted when a line exactly matches `quality-gate-stage-N session=<session>`, but there is no current `HEAD` component. The docs also instruct maintainers to write only session-scoped stage markers at `site/pre-release-quality-gate.md:14` and `site/pre-release-quality-gate.md:153-156`, with the same pattern in `site/internal/pre-release-quality-gate.md:14` and `site/internal/pre-release-quality-gate.md:145-148`.

The hook already binds live-pyramid markers to the current Git SHA at `hooks/validate-release-gate.sh:2882-2900`, which highlights the gap: a maintainer can complete Stages 1-4, change code or manifests in the same host session, run two current live-pyramid passes, and the release hook will still accept stale Stage 1-4 review and verification evidence. That directly undercuts the release-gate hardening this candidate is adding.

The release docs' final verification snippets compound the risk by counting live markers by session only at `site/pre-release-quality-gate.md:386-389` and `site/internal/pre-release-quality-gate.md:364-367`, even though the hook requires current-SHA live markers.

**Fix:**

Require the current short SHA on every stage marker and update all marker-write snippets and tests accordingly.

```bash
current_head_sha="$(git -C "${REPO_ROOT}" rev-parse --short=12 HEAD)"
if ! grep -qxF "quality-gate-stage-${stage} session=${QUALITY_GATE_SESSION_ID} sha=${current_head_sha}" "$STATE_FILE" 2>/dev/null; then
  missing+=("${stage}")
fi
```

```bash
SIDEKICK_QG_SHA="$(git rev-parse --short=12 HEAD)"
printf 'quality-gate-stage-1 session=%s sha=%s\n' "$SIDEKICK_QG_SESSION" "$SIDEKICK_QG_SHA" >> "$SIDEKICK_QG_STATE"
```

Add release-gate tests that prove stale same-session stage markers from a previous SHA are denied.

## Warnings

### WR-01 [WARNING]: Strict unit runner deletes checkout-local artifacts before layout tests

**File:** `tests/run_unit.bash:52`

**Issue:** `tests/run_unit.bash` runs `tests/post_release_cleanup.bash` directly against the real checkout before repository layout tests. That cleanup script deletes paths under `SIDEKICK_REPO_ROOT`, including `.tmp`, `.cache`, `target`, `build`, `dist`, `coverage`, `.pytest_cache`, `node_modules`, and a literal `~` directory at `tests/post_release_cleanup.bash:18-34`.

The strict non-live runner should be a verification surface, not a mutating cleanup operation. This can delete untracked local artifacts when a maintainer runs the documented tier-1 suite, and it can mask `tests/test_repo_layout.bash` by deleting offending root artifacts immediately before the layout check runs.

**Fix:**

Keep the sandboxed cleanup test, but remove the direct cleanup call from `run_unit.bash`, or require an explicit opt-in environment flag.

```bash
run_suite "Post-release cleanup script tests" "test_post_release_cleanup.bash"
if [ "${SIDEKICK_RUN_REPO_CLEANUP:-0}" = "1" ]; then
  SIDEKICK_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)" bash "${SCRIPT_DIR}/post_release_cleanup.bash"
fi
run_suite "Repository layout tests" "test_repo_layout.bash"
```

### WR-02 [WARNING]: Generated flat host wrappers still point readers at canonical `skills/` paths

**File:** `scripts/render-agent-bundle.py:53`

**Issue:** The renderer rewrites host-specific alias paths only for `SKILL.md` files under `forge:delegate` and `kay:delegate`. It does not rewrite flat compatibility wrappers, so the generated host bundles still tell readers to use canonical source-tree paths instead of generated host-root paths. Examples in the requested release commit:

- `agents/claude/forge.md:6` says `/forge` comes from `skills/forge/SKILL.md`, and `agents/claude/forge.md:10` labels the local generated link as `skills/forge/SKILL.md`.
- `agents/codex/forge.md:6` and `agents/codex/forge.md:10` have the same mismatch.
- `agents/claude/codex-delegate.md:3` and `agents/codex/codex-delegate.md:3` tell host-package readers to prefer `skills/codex-delegate/SKILL.md`.

The existing generated-surface test covers only directory-style alias skills at `tests/test_agent_surface_render.bash:109-115`, so this stale flat-wrapper text can regress without detection.

**Fix:**

Apply the same alias replacements to `forge.md` and `codex-delegate.md`, then extend `tests/test_agent_surface_render.bash` to assert flat wrappers do not contain canonical `skills/...` paths in generated host bundles.

```python
if (
    path.name == "SKILL.md"
    and path.parent.name in {"forge:delegate", "kay:delegate"}
) or path.name in {"forge.md", "codex-delegate.md"}:
    for old, new in host_alias_replacements(agent):
        updated = updated.replace(old, new)
```

---

_Reviewed: 2026-05-22T17:09:57Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: deep_

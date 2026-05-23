---
phase: 12-v0-6-0-release-candidate-review
reviewed: 2026-05-23T08:20:20Z
depth: deep
files_reviewed: 77
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
  - hooks/hooks.json
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

**Reviewed:** 2026-05-23T08:20:20Z
**Depth:** deep
**Files Reviewed:** 77
**Status:** issues_found

## Summary

Reviewed the v0.6.0 release-candidate diff `v0.5.8..aff4fc05fa39ec0e34888ceae726fbbf3a21a0ca`, with emphasis on generated host skill surfaces, strict and release runners, release-gate fail-closed behavior, plugin integrity, marketplace pinning, and release documentation consistency.

The generated Claude/Codex host bundles and integrity checks look internally consistent under the strict non-live suite. The release candidate is not shippable because the release hook still lets a bare non-semver tag push pass through without any pre-release or live-pyramid evidence.

Verification performed:
- `git diff --check v0.5.8..aff4fc05fa39ec0e34888ceae726fbbf3a21a0ca -- . ':!.planning/'` passed.
- `bash -n` over changed shell scripts passed.
- `python3 -m py_compile scripts/render-agent-bundle.py hooks/scrub-legacy-user-hooks.py` passed.
- `bash tests/run_unit.bash` passed all strict non-live suites, including 439 release-gate hook scenarios.
- Targeted hook probe for `git tag release-candidate HEAD && git push origin release-candidate` returned `rc=0` with no deny JSON.
- Control probe for `git tag release-candidate HEAD && git push origin refs/tags/release-candidate` returned a `permissionDecision=deny` JSON.
- `SIDEKICK_RELEASE_GATE=1 bash tests/test_codex_marketplace_manifest.bash` failed because `git status --porcelain` reports `?? ~/`.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Bare non-semver tag pushes bypass the release gate

**File:** `hooks/validate-release-gate.sh:1221`

**Issue:** `token_is_release_tag_ref` only treats `refs/tags/*` and semver-shaped tokens as release tag refs. `refspec_targets_release_tag` then returns false for any static unqualified non-semver refspec, and `git_push_release_tag_command` allows the command to pass. The mirrored metadata parser has the same semver-only assumption at `hooks/validate-release-gate.sh:4756`, `hooks/validate-release-gate.sh:4776`, and `hooks/validate-release-gate.sh:5684`.

This lets a real tag publication shape pass with no markers:

```bash
git tag release-candidate HEAD && git push origin release-candidate
```

The hook emitted no deny JSON for that command. Git accepts `git push origin <tagname>` for an existing unqualified tag when the name is not ambiguous, so this bypasses the release hook's requirement that release publication only proceed against explicit current trusted Sidekick targets after the four pre-release markers and two live-pyramid markers.

**Fix:** In both the classifier and metadata pass, resolve unqualified `git push` refspecs against the target checkout before deciding they are branch-safe. Treat the refspec as release-sensitive when the source or destination is `refs/tags/*`, when it resolves to `refs/tags/<name>`, or when an earlier segment in the same shell command created or updated that tag. If resolution is impossible or ambiguous, fail closed unless the refspec is explicitly `refs/heads/*` or otherwise proven branch-only. Also update `git_tag_mutates_release_ref` so mutating `git tag <name>` tracks any tag name, not only semver names.

Concrete regression examples to add:

```bash
assert_denied_command "git push bare non-semver tag is denied" \
  "git tag release-candidate HEAD && git push origin release-candidate"

assert_denied_command "git push bare non-semver local tag is denied" \
  "git push origin release-candidate"
```

For the second case, seed a temp checkout with `refs/tags/release-candidate` and run the hook from that cwd. Add parallel passing coverage for an explicit branch-only push such as `git push origin refs/heads/release-candidate`.

## Warnings

### WR-01: The hook suite misses the bare non-semver tag form

**File:** `tests/test_validate_release_gate_hook.bash:2190`

**Issue:** The release-gate suite covers `refs/tags/release-candidate`, numeric tag refs, bare semver tags, and dynamic refspecs, but it does not cover a bare non-semver tag such as `release-candidate`. That is the exact form Git users commonly type and the exact form the hook currently lets through.

**Fix:** Add no-marker denial tests for bare non-semver local tags, same-command tag creation followed by a bare push, and env-expanded bare tag names that resolve to local tags. Keep the existing dynamic branch passthrough test, but require explicit branch evidence for non-semver unqualified names.

### WR-02: Current release-gate marketplace validation fails on a dirty checkout

**File:** `tests/test_codex_marketplace_manifest.bash:44`

**Issue:** Release-gate mode requires a clean Sidekick checkout before validating marketplace metadata. The current repo fails that check with:

```text
?? ~/
```

The untracked directory contains `./~/.codex/.silver-bullet/config-cache-6f1547fa77b087ac266955164f3c1379`.

**Fix:** Remove the accidental untracked `~/` tree, or commit/ignore it if it is intentional. Then rerun:

```bash
SIDEKICK_RELEASE_GATE=1 bash tests/test_codex_marketplace_manifest.bash
```

---

STATUS: failed
ACCEPTED_FINDINGS: 3
ASSESSMENT: blocked

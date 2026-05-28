# Pre-Release Quality Gate -- Sidekick

Before any release, complete this gate after the final release-candidate commit exists and before publishing a tag or GitHub release.

Sidekick currently supports Kay and Codex only. Release checks must not rely on removed sidekick runtime, skill, hook, or runner surfaces.

---

## Enforcement

**State file**: host-specific Sidekick state.

- Claude/source installs: `~/.claude/.sidekick/quality-gate-state`
- Codex installs: `~/.codex/.sidekick/quality-gate-state`

**Marker format**: `quality-gate-stage-N session=<current-host-session-id> sha=<git-sha>`

**Live-pyramid marker format**: `quality-gate-live-pyramid session=<current-host-session-id> sha=<git-sha> at=<utc-timestamp> run_id=<wrapper-run-id> source=kay-wrapper proof_sha256=<wrapper-proof-sha256> candidate_sha256=<candidate-sha256> command_sha256=<command-sha256>`

Required evidence before release:

- Current-session, current-commit `quality-gate-stage-1`
- Current-session, current-commit `quality-gate-stage-2`
- Current-session, current-commit `quality-gate-stage-3`
- Current-session, current-commit `quality-gate-stage-4`
- Two distinct current-session, current-commit `quality-gate-live-pyramid` markers written by successful Kay-hosted live runs of `tests/run_release.bash`

Markers are scoped to the current host session and commit SHA. A previous session or previous commit does not satisfy the gate.

Resolve the state file once in the release shell:

```bash
SIDEKICK_QG_DIR="${HOME}/.claude/.sidekick"
if [ -n "${CODEX_PLUGIN_ROOT:-}" ] || [ -n "${CODEX_HOME:-}" ] || [ -n "${CODEX_THREAD_ID:-}" ]; then
  SIDEKICK_QG_DIR="${HOME}/.codex/.sidekick"
fi
SIDEKICK_QG_STATE="${SIDEKICK_QG_DIR}/quality-gate-state"
SIDEKICK_QG_SHA="$(git rev-parse --short=12 HEAD 2>/dev/null || true)"
test -n "$SIDEKICK_QG_SHA" || { echo "No git SHA found"; exit 1; }
mkdir -p "${SIDEKICK_QG_DIR}"
```

After each stage passes and `/superpowers:verification-before-completion` has been invoked, record:

```bash
printf 'quality-gate-stage-N session=%s sha=%s\n' "$SIDEKICK_QG_SESSION" "$SIDEKICK_QG_SHA" >> "$SIDEKICK_QG_STATE"
```

---

## Stage 1 -- Code Review

Goal: zero accepted issues across all source files changed in this release.

1. Run the reviewer workflow from `/superpowers:requesting-code-review`.
2. Review changed source, scripts, manifests, generated host bundles, and release docs.
3. Triage findings with `/superpowers:receiving-code-review`.
4. Fix every accepted issue.
5. Repeat until the reviewer pass has no accepted issues.

Review focus:

- Supported sidekicks remain Kay and Codex only.
- `skills/kay-delegate/SKILL.md` and `skills/codex-delegate/SKILL.md` contain the host verification and relaunch taxonomy.
- Generated host bundles match canonical skills after `bash scripts/sync-host-surfaces.sh`.
- Removed sidekick files, hooks, output styles, tests, registry entries, manifest metadata, and docs do not reappear.
- Release notes and manifests state the correct version and supported sidekick set.

---

## Stage 2 -- Structure And Integrity

Goal: packaging metadata, generated surfaces, and repo layout are internally consistent.

Run:

```bash
bash scripts/sync-host-surfaces.sh
bash tests/test_agent_surface_render.bash
bash tests/test_plugin_integrity.bash
bash tests/test_repo_layout.bash
bash tests/test_removed_sidekick_absent.bash
git diff --check
```

Required outcomes:

- Manifest `_integrity` hashes match live files.
- Kay and Codex generated bundles match canonical `skills/` sources.
- Removed sidekick files and runtime directories are absent.
- No whitespace or patch-format issues are present.

---

## Stage 3 -- Local Test Pyramid

Goal: all non-live and skip-safe checks pass locally.

Run:

```bash
bash tests/run_unit.bash
bash tests/run_all.bash
```

Expected behavior:

- `run_unit.bash` is strict and non-live.
- `run_all.bash` includes skip-safe live wrappers.
- Live wrappers skip cleanly unless `SIDEKICK_LIVE_CODEX=1` is set.
- Docs and help pages describe Kay and Codex only.

---

## Stage 4 -- Release Candidate Audit

Goal: the exact release candidate is coherent before live authorization.

Run:

```bash
git status --short
git diff --stat
git diff -- .claude-plugin/plugin.json .codex-plugin/plugin.json .claude-plugin/marketplace.json
git diff -- README.md context.md site/ tests/ hooks/ skills/ agents/ sidekicks/ install.sh scripts/
```

Confirm:

- Version values are consistent across plugin manifests and public docs.
- Current docs do not advertise removed sidekick support.
- `CHANGELOG.md` contains the release entry and no placeholder text.
- No temporary scripts, debug output, or local-only artifacts are staged.
- Any remaining removed-sidekick references are historical changelog/planning records or explicit legacy cleanup tests, not active product support.

---

## Live Release Pyramid

After the four local stages are complete, run the live release gate twice through Kay:

```bash
bash tests/run_in_kay.bash SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
bash tests/run_in_kay.bash SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
```

`tests/run_release.bash` runs strict unit checks, live Codex marketplace install verification, Kay smoke, and Kay live E2E. It writes candidate evidence only. `tests/run_in_kay.bash` validates wrapper proof and promotes successful canonical runs to final `quality-gate-live-pyramid` markers.

Before publishing, verify two final live markers exist for the current session and current commit:

```bash
grep "quality-gate-live-pyramid " "$SIDEKICK_QG_STATE" | grep "sha=${SIDEKICK_QG_SHA}"
```

---

## Publishing

Publish only after all local stages and both live runs pass.

1. Resolve the target SHA:

   ```bash
   git rev-parse HEAD
   ```

2. Create and push the tag:

   ```bash
   git tag vX.Y.Z
   git push origin main
   git push origin vX.Y.Z
   ```

3. Create the GitHub release with an explicit repo and literal target SHA:

   ```bash
   gh release create vX.Y.Z --repo alo-exp/sidekick --target <current-sha> --notes-file <notes.md>
   ```

4. Run cleanup:

   ```bash
   bash tests/post_release_cleanup.bash
   ```

The release command must target `alo-exp/sidekick` on GitHub.com and the literal current `HEAD` SHA. Ambiguous repos, alternate remotes, raw API writes, generated release scripts, shell-substituted targets, destructive tag operations, and implicit release targets are not acceptable release evidence.

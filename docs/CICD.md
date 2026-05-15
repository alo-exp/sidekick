# CI / CD

> How Sidekick validates and ships. Two GitHub Actions workflows + one local release gate.

---

## Pipelines

### 1. `ci.yml` — continuous validation

**Trigger:** every `push` and every `pull_request`.
**Runner:** `ubuntu-latest`.
**Step:** `bash tests/run_all.bash` (tier 1 of the test pyramid — see `docs/TESTING.md`).

Always-green for anything merged to `main`. Live-Forge tiers (smoke + E2E) are NOT run in CI — they're gated on `SIDEKICK_LIVE_FORGE=1` and exit 0 cleanly when unset, so the CI runner wouldn't exercise them even if called.

### 2. `pages.yml` — docs site deployment

**Trigger:** `push` to `main` touching `docs/**`; also `workflow_dispatch`.
**Runner:** `ubuntu-latest`.
**Flow:** `checkout` → `configure-pages` → `upload-pages-artifact` (path: `docs`) → `deploy-pages`.
**Concurrency:** `group: pages`, `cancel-in-progress: false` — a new deploy waits for the prior one to finish rather than cancelling it.
**Permissions:** `contents: read`, `pages: write`, `id-token: write`.

The deployed site lives at https://sidekick.alolabs.dev (CNAME set in `docs/CNAME`).

---

## Release flow (local, manual)

No automated tag-on-push. Releases are cut by the maintainer against a fully-green local gate, then pushed.

1. **Pre-release quality gate** — maintainer completes the 4-stage gate in `docs/pre-release-quality-gate.md` until it passes twice in a row.
2. **Pre-tag live gate** — maintainer runs the full pyramid with live Forge and Kay twice:
   ```bash
   SIDEKICK_LIVE_FORGE=1 SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
   ```
   This chains tier 1 (`run_all.bash`) → tier 2 (`smoke/run_smoke.bash`) → tier 3 (`run_live_e2e.bash`) → tier 4 (`run_live_codex_marketplace_install.bash`) → tier 5 (`smoke/run_codex_smoke.bash`) → tier 6 (`run_live_codex_e2e.bash`) with fail-fast aborts. Each live run records a current-session `quality-gate-live-pyramid` marker; the release hook requires two of those markers before it allows `gh release create`.

3. **Update artifacts** — `CHANGELOG.md` (root) appended with the version entry, `README.md` version badge bumped, `.planning/STATE.md` flipped to `shipped`, `_integrity` SHA-256 hashes in `plugin.json` refreshed for any changed hook / command / skill / output-style file.

4. **Commit + tag + push:**
   ```bash
   git commit -m "…"
   git tag vX.Y.Z
   git push origin main
   git push origin vX.Y.Z
   ```

5. **GitHub Release** — `gh release create vX.Y.Z --notes-file <notes.md>`.

6. **Post-release cleanup** — remove non-essential repo-local artifacts with:
   ```bash
   bash tests/post_release_cleanup.bash
   ```
   This clears transient build / cache directories from the local repo so the release session ends cleanly.

7. **Plugin cache sync** — host plugin auto-update picks up the new tag on the next session start. For an immediate local bump, refresh the Claude Code cache under `~/.claude/plugins/cache/alo-exp/sidekick/<version>/` and the Codex cache under the matching `~/.codex/plugins/cache/.../sidekick/<version>/` path.

---

## What CI intentionally does NOT do

| Missing | Reason |
|---|---|
| Live `forge` binary install in CI | Tier 2 + 3 would fail without it; gating on `SIDEKICK_LIVE_FORGE` keeps CI runtime fast and deterministic, and keeps costs at zero. |
| Automated tagging on merge | Release notes are narrative; the maintainer writes them. Auto-tagging on every merge would pollute the release page. |
| Plugin publishing step | Distribution is host marketplace pull, not a push pipeline. `marketplace.json` and the Codex plugin manifest version are the release metadata sources. |
| Linting / formatting workflow | Codebase is Bash + Markdown; `shellcheck` is run ad-hoc when the enforcer hook is modified, not as a gate. |
| Coverage reporting | Test counts are in `docs/TESTING.md`; coverage-as-a-percentage is not tracked (branch-level coverage is asserted by dedicated suites). |

---

## If CI fails

1. Read the failing assertion in the GitHub Actions log — each suite prints suite name + assertion name + expected vs actual.
2. Reproduce locally: `bash tests/<failing-suite>.bash`.
3. If it's a classifier gap (a new Bash command shape that the enforcer doesn't handle): add a case in `is_read_only()` / `decide_bash()`, add an assertion in `test_v12_coverage.bash`, re-run `run_all.bash`.
4. If it's a manifest integrity drift: run `plugin.json`'s `_integrity` update (SHA-256 of the changed file) and re-commit.

---

## If `pages.yml` fails

1. Check the `configure-pages` step — most common cause is the Pages source being set to "Branch" instead of "GitHub Actions" in the repo settings.
2. Dead links or missing nav entries don't fail the build (no link-check step) — they surface only when the site is viewed.
3. Manual redeploy: `gh workflow run pages.yml`.

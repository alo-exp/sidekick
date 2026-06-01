# CI / CD

> How Sidekick validates, deploys, and releases the current Kay/Codex site and plugin.

## Pipelines

### `ci.yml` - Continuous Validation

Trigger: every push and pull request.

Runner: `ubuntu-latest`.

Command:

```bash
bash tests/run_unit.bash
```

CI runs strict non-live checks only. Live Kay and Codex release evidence is produced locally by maintainers.

### `pages.yml` - Site Deployment

Trigger: pushes to `main` touching `site/**`, plus manual `workflow_dispatch`.

Flow:

```text
checkout -> configure-pages -> upload-pages-artifact path=site -> deploy-pages
```

The deployed site lives at:

```text
https://sidekick.alolabs.dev
```

The custom domain is set by `site/CNAME`, and the repository Pages source is GitHub Actions.

## Release Flow

1. Update release artifacts, generated host bundles, manifests, docs, and changelog.
2. Commit the exact release candidate that will be tagged.
3. Complete the four-stage [pre-release quality gate](pre-release-quality-gate.md).
4. Run the live release gate twice:

```bash
bash tests/run_in_kay.bash SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
bash tests/run_in_kay.bash SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
```

5. Verify current-session/current-commit stage and live markers.
6. Resolve the literal current SHA:

```bash
git rev-parse HEAD
```

7. Create the release with explicit repository and target provenance:

```bash
gh release create vX.Y.Z \
  --repo alo-exp/sidekick \
  --title "Sidekick vX.Y.Z" \
  --notes-file <notes.md> \
  --target <current-sha> \
  --latest
```

8. Run post-release cleanup:

```bash
bash tests/post_release_cleanup.bash
```

## Release Checks

| Check | Command |
| --- | --- |
| Strict unit and integration | `bash tests/run_unit.bash` |
| Skip-safe local sweep | `bash tests/run_all.bash` |
| Live Codex release gate | `bash tests/run_in_kay.bash SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash` |
| Site homepage contract | `bash tests/test_homepage_sidekicks.bash` |
| Help-site contract | `bash tests/test_help_site_navigation.bash` |
| Docs contract | `bash tests/test_docs_contract.bash` |
| Preview contract | `bash tests/test_og_image.bash` |

## What CI Does Not Do

| Missing | Reason |
| --- | --- |
| Automated release publishing | Release notes and quality-gate evidence are maintainer-owned. |
| Live sidekick model calls | CI remains deterministic and cost-free. |
| Automatic manifest hash updates | Integrity drift must be explicit in the release commit. |
| Link checking | Current public content is guarded by repository tests; browser verification remains local. |

## If CI Fails

1. Read the failing suite and assertion in the GitHub Actions log.
2. Reproduce locally with `bash tests/<suite>.bash`.
3. Fix the source of truth, not generated output alone.
4. Refresh generated host surfaces if skill text changed.
5. Rerun `bash tests/run_unit.bash`.

## If Pages Deployment Fails

1. Confirm Pages is configured for GitHub Actions, not branch-based publishing.
2. Confirm `site/CNAME` contains `sidekick.alolabs.dev`.
3. Rerun the deployment workflow:

```bash
gh workflow run "Deploy to GitHub Pages"
```

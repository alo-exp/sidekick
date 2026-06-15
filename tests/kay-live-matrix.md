# Kay release live-test matrix

Reusable runner for Sidekick-hosted Kay live campaigns across **model profiles** and **task prompts** (same core suite as v0.9.27 / v0.9.30).

## One-liner (v0.9.31 core suite, parallel)

```bash
KAY_RELEASE=v0.9.31 KAY_MATRIX_PREFIX=v0931 KAY_MATRIX_PARALLEL=1 \
  bash tests/run_kay_release_matrix.bash
```

Requires: `kay`, `node`, `npm`, `gh` auth, keys in repo `.env.local` (`OPENCODE_GO_API_KEY`, optional `MINIMAX_API_KEY`).

## Script

`tests/run_kay_release_matrix.bash`

### Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `KAY_RELEASE` | (none) | e.g. `v0.9.31` — install via [official install.sh](https://github.com/alo-labs/kay) when local `kay` version differs |
| `KAY_MATRIX_PREFIX` | `v` + release digits | Log/report prefix (`v0931`) |
| `KAY_MATRIX_PROFILES` | 4 built-in rows | `profile_id:provider:model` per line |
| `KAY_MATRIX_TASKS` | `e2e task7 task8 task9 task10` | Task ids (see below) |
| `KAY_MATRIX_PARALLEL` | `0` | `1` — run all profile×task jobs in parallel |
| `KAY_MATRIX_SKIP_INSTALL` | `0` | `1` — skip release install |
| `KAY_MATRIX_REREPORT` | `0` | `1` — rebuild TSV + `gh` hooks from existing logs (no new jobs) |

Built-in profiles (v0.9.31 matrix):

| profile_id | provider | model |
|------------|----------|-------|
| ocg-minimax-m3 | opencode-go | minimax-m3 |
| ocg-mimo-pro | opencode-go | mimo-v2.5-pro |
| ocg-mimo | opencode-go | mimo-v2.5 |
| minimax-m3 | minimax | minimax/MiniMax-M3 |

### Tasks

| Task | Driver | Prompt / notes |
|------|--------|----------------|
| `e2e` | `tests/run_live_codex_e2e.bash` | Health-fix smoke on canonical `test-notes-app` |
| `task7` | `tests/run_kay_live_task.bash` | `kay-live-prompts/task7-retry2-closeout.txt`, export-import seed |
| `task8` | `tests/run_kay_live_task.bash` | `task8-bulk-archive.txt` |
| `task9` | `tests/run_kay_live_task.bash` | `task9-sort-ui.txt` |
| `task10` | `tests/run_kay_live_task.bash` | `task10-full-regression.txt`, export-import seed |

Per-job env: `KAY_LIVE_MODEL_PROVIDER`, `KAY_LIVE_MODEL` (set by matrix from profile row).

Harness reuse: `run_with_timeout … env "${KAY_ENV[@]}"` in `run_kay_live_task.bash` and `run_live_codex_e2e.bash`.


### Parent-issue dedupe (`gh`)

When a job **FAIL**s, `run_kay_release_matrix.bash` classifies log + `*-last-message.txt` into a **single parent** Kay issue and **`gh issue comment`**s there. It **does not** open a new matrix issue when a bucket matches.

| Signature (log / last message) | Parent issue |
|--------------------------------|--------------|
| `PORT=` treated as executable / `bash: PORT=` | [#52](https://github.com/alo-labs/kay/issues/52) |
| STATUS missing / incomplete / `Final status contract` / `did not start with STATUS` | [#42](https://github.com/alo-labs/kay/issues/42) |
| `apply_patch` / `Begin Patch` / bulk-archive verify fail / `verify-bulk` host_verify | [#46](https://github.com/alo-labs/kay/issues/46) |
| `kay_rc=124` / timeout / `exit 124` | [#49](https://github.com/alo-labs/kay/issues/49) |
| `apply_patch &&` / malformed shell (`bash -lc … apply_patch`) | [#55](https://github.com/alo-labs/kay/issues/55) (else [#39](https://github.com/alo-labs/kay/issues/39) for `cat -A`) |
| Invalid kill / trailing characters | [#54](https://github.com/alo-labs/kay/issues/54) |

Priority is **first match** in that order (one parent per matrix cell). Parent lookup uses `gh issue view <n>` (not search). **New issues** are filed only when status is FAIL/UNKNOWN and **no** bucket matches.

`KAY_MATRIX_REREPORT=1` rebuilds `*-issue-report.tsv` and re-runs comment hooks from existing logs (no new jobs). Actions appear as `comment#<parent>` in the TSV.

### Outputs

- `tests/.kay-live-logs/<prefix>-matrix-summary.tsv` — profile × test pass/fail
- `tests/.kay-live-logs/<prefix>-issue-report.tsv` — per job + `gh` action (comment on known Kay issues or file new)
- Per-job logs: `tests/.kay-live-logs/<profile_id>-<prefix>-<task>-*.log`

## Next release

1. Set `KAY_RELEASE=vX.Y.Z` and `KAY_MATRIX_PREFIX=vXYZ`.
2. Optionally trim `KAY_MATRIX_PROFILES` or `KAY_MATRIX_TASKS`.
3. Run matrix; append results to `docs/knowledge/YYYY-MM.md`.
4. Pointer: `site/pre-release-quality-gate.md` and `site/TESTING.md`.

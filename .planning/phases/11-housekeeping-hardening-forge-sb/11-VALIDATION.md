# Phase 11 Validation — Housekeeping, Hardening & forge-sb

**Framework:** Custom bash test runner
**Quick run:** `bash tests/test_forge_enforcer_hook.bash`
**Full suite:** `bash tests/run_all.bash`
**nyquist_compliant:** true

---

## Per-Task Verification Map

### Plan 11-01 — Hook Hardening (STRIP-01, RDRCT-01)

| Task | Automated Verification | Pass Condition |
|------|------------------------|----------------|
| Task 1: switch strip_ansi to slurp mode + extend sk- regex | `grep -q 'perl -0777 -pe' hooks/forge-progress-surface.sh` | Exit 0 |
| Task 1: sk- char class broadened | `grep -q 'sk-\[A-Za-z0-9_\\-\\.\\\/+\]' hooks/forge-progress-surface.sh` | Exit 0 |
| Task 1: old sk- pattern removed | `grep -q 'sk-\[A-Za-z0-9_-\]{16,}' hooks/forge-progress-surface.sh` | Exit 1 (absent) |
| Task 1: bash syntax | `bash -n hooks/forge-progress-surface.sh` | Exit 0 |
| Task 1: existing surface tests | `bash tests/test_forge_progress_surface.bash` | Exit 0 |

### Plan 11-02 — Test Coverage (TEST-RDRCT-01)

| Task | Automated Verification | Pass Condition |
|------|------------------------|----------------|
| Task 1: ghs_ token test added and passing | `bash tests/test_v12_coverage.bash 2>&1 \| grep 'PASS test_surface_redacts_ghs_token'` | Match found |
| Task 1: api-key colon form test added and passing | `bash tests/test_v12_coverage.bash 2>&1 \| grep 'PASS test_surface_redacts_api_key_colon_form'` | Match found |
| Task 1: full v12 coverage suite | `bash tests/test_v12_coverage.bash` | Exit 0 |

### Plan 11-03 — Help Site + SKILL.md + install.sh (SRI-01, SKILL-01, SKILL-02, DOCS-01, INST-01)

| Task | Automated Verification | Pass Condition |
|------|------------------------|----------------|
| Task 1: Lucide SRI on all 6 pages | `for f in docs/help/index.html docs/help/getting-started/index.html docs/help/concepts/index.html docs/help/workflows/index.html docs/help/reference/index.html docs/help/troubleshooting/index.html; do grep -q 'integrity="sha384-' "$f"; done` | All exit 0 |
| Task 1: favicon on all 6 pages | `for f in docs/help/*/index.html docs/help/index.html; do grep -q 'rel="icon"' "$f"; done` | All exit 0 |
| Task 1: search.js null guard | `grep -q 'if (!list \|\| !section) return' docs/help/search.js` | Exit 0 |
| Task 1: concepts table fix | `grep -q 'quality-gates + code-review' docs/help/concepts/index.html` | Exit 0 |
| Task 2: SKILL.md Level 3 CLAUDE_PROJECT_DIR | `grep -q 'CLAUDE_PROJECT_DIR' skills/forge/SKILL.md` | Exit 0 |
| Task 2: Security boundary before Corrections | python3 check (sec_pos < corrections_pos) | True |
| Task 2: governance note present | `grep -q 'SENTINEL audit' skills/forge/SKILL.md` | Exit 0 |
| Task 2: install.sh TMPDIR | `grep -q 'TMPDIR:-/tmp' install.sh` | Exit 0 |
| Task 2: .sh suffix removed | `grep -q 'forge-install.XXXXXX.sh' install.sh` | Exit 1 (absent) |
| Task 2: install.sh syntax | `bash -n install.sh` | Exit 0 |
| Task 2: install.sh unit tests | `bash tests/test_install_sh.bash` | Exit 0 |

### Plan 11-04 — SENTINEL Relocation + forge-sb + Integrity (HOUSE-01, FGSB-01)

| Task | Automated Verification | Pass Condition |
|------|------------------------|----------------|
| Task 1: root SENTINEL files absent | `ls SENTINEL-audit-forge*.md 2>/dev/null \| wc -l` | 0 |
| Task 1: sentinel dir has 14 files | `ls docs/internal/sentinel/SENTINEL-audit-forge*.md \| wc -l` | 14 |
| Task 1: git history preserved | `git log --follow docs/internal/sentinel/SENTINEL-audit-forge.md --oneline \| head -1` | Non-empty (shows rename commit) |
| Task 2: forge-sb install line present | `grep -q 'forge-sb-install.sh' install.sh` | Exit 0 |
| Task 2: install.sh syntax | `bash -n install.sh` | Exit 0 |
| Task 2: plugin.json surface hash matches | `[ "$(jq -r '._integrity.forge_progress_surface_sha256' .claude-plugin/plugin.json)" = "$(shasum -a 256 hooks/forge-progress-surface.sh \| awk '{print $1}')" ]` | Exit 0 |
| Task 2: plugin.json install hash matches | `[ "$(jq -r '._integrity.install_sh_sha256' .claude-plugin/plugin.json)" = "$(shasum -a 256 install.sh \| awk '{print $1}')" ]` | Exit 0 |
| Task 2: integrity test suite | `bash tests/test_plugin_integrity.bash` | Exit 0 |

---

## Full Suite Gate

Run after all 4 plans complete:

```bash
bash tests/run_all.bash
```

Expected: `ALL SUITES PASSED` — exit 0, zero suite failures.

---

## Requirement Traceability

| Requirement | Plan | Key Verification |
|-------------|------|-----------------|
| STRIP-01 | 11-01 | `grep -q 'perl -0777 -pe' hooks/forge-progress-surface.sh` |
| RDRCT-01 | 11-01 | `grep -q 'sk-\[A-Za-z0-9_\\-\\.\\\/+\]{10,' hooks/forge-progress-surface.sh` |
| TEST-RDRCT-01 | 11-02 | `bash tests/test_v12_coverage.bash` exits 0 with ghs_ and api-key tests passing |
| SRI-01 | 11-03 | All 6 HTML files have `integrity="sha384-..."` on Lucide script tag |
| SKILL-01 | 11-03 | `grep -q 'CLAUDE_PROJECT_DIR' skills/forge/SKILL.md` |
| SKILL-02 | 11-03 | Security boundary before Corrections bullet; SENTINEL audit governance sentence present |
| DOCS-01 | 11-03 | favicon on 6 pages; null guard in search.js; concepts table shows quality-gates + code-review |
| INST-01 | 11-03 | `grep -q 'TMPDIR:-/tmp' install.sh` and .sh suffix absent |
| HOUSE-01 | 11-04 | 14 files under docs/internal/sentinel/, root clean, git history via --follow |
| FGSB-01 | 11-04 | `grep -q 'forge-sb-install.sh' install.sh` |

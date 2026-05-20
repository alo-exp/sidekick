---
phase: 11-housekeeping-hardening-forge-sb
reviewed: 2026-05-15T05:52:53Z
depth: deep
files_reviewed: 29
files_reviewed_list:
  - .claude-plugin/plugin.json
  - CHANGELOG.md
  - README.md
  - context.md
  - docs/ARCHITECTURE.md
  - docs/CICD.md
  - docs/TESTING.md
  - docs/help/concepts/index.html
  - docs/help/reference/index.html
  - docs/help/search.js
  - docs/help/troubleshooting/index.html
  - docs/help/workflows/index.html
  - docs/index.html
  - docs/internal/pre-release-quality-gate.md
  - docs/pre-release-quality-gate.md
  - hooks/codex-delegation-enforcer.sh
  - hooks/forge-delegation-enforcer.sh
  - hooks/lib/sidekick-registry.sh
  - hooks/validate-release-gate.sh
  - skills/codex-delegate/SKILL.md
  - skills/codex-stop/SKILL.md
  - skills/forge/SKILL.md
  - skills/forge-stop/SKILL.md
  - tests/run_release.bash
  - tests/test_codex_enforcer_hook.bash
  - tests/test_codex_skill.bash
  - tests/test_forge_enforcer_hook.bash
  - tests/test_forge_skill.bash
  - tests/test_validate_release_gate_hook.bash
findings:
  critical: 2
  warning: 1
  info: 0
  total: 3
status: issues_found
---

# Phase 11: Code Review Report

**Reviewed:** 2026-05-15T05:52:53Z
**Depth:** deep
**Files Reviewed:** 29
**Status:** issues_found

## Summary

Reviewed the release gate, delegation hooks, shared registry helpers, skill docs, plugin manifest, and the updated release/test/documentation surfaces. The implementation is broadly coherent, but the new release gate still has two concrete safety gaps and one behavior regression.

## Critical Issues

### CR-01: Interpreter release-write detection is bypassable via aliasing and GraphQL

**File:** `hooks/validate-release-gate.sh:2288`
**Issue:** `language_payload_mentions_release_command()` only recognizes literal `requests.post` / `requests.request` / `urlopen` / `fetch` / `curl|wget` tokens plus `/repos/.../releases` or `/git/refs` URLs. Straightforward variants such as `from requests import post as p; p("https://api.github.com/repos/alo-exp/sidekick/releases", ...)` or a direct GraphQL release mutation `requests.post("https://api.github.com/graphql", json={"query":"mutation { createRelease(...) }"})` return no deny JSON and are allowed through when the gate is otherwise incomplete. That is a real release-safety bypass.
**Fix:**
```python
def direct_github_api_write(payload):
    # Parse the payload AST or resolve imported aliases before matching.
    # GraphQL release mutations must be treated as release writes too.
    if direct_github_release_api_url(payload):
        return True
    if re.search(r"\bapi\.github\.com/graphql\b", payload, re.I):
        return re.search(r"\bcreate(?:Release|Ref)\b", payload) is not None
    return False
```
Add regression cases in `tests/test_validate_release_gate_hook.bash` for aliased `requests.post` and direct GraphQL release mutations.

### CR-02: Live-pyramid markers ignore the recorded commit SHA

**File:** `hooks/validate-release-gate.sh:2831`
**Issue:** `tests/run_release.bash` records `quality-gate-live-pyramid session=<id> sha=<git-sha> at=<utc-timestamp>`, but the hook only counts lines that match the marker and session id. It never compares the stored `sha=` to the current checkout, so two markers from an earlier commit in the same session still authorize `gh release create` after later edits. The new `sha=` field is therefore inert and the release gate can be satisfied by stale validation.
**Fix:**
```bash
current_sha="$(git rev-parse HEAD)"
live_pyramid_runs=$(
  awk -v marker="$LIVE_PYRAMID_MARKER" -v sid="$QUALITY_GATE_SESSION_ID" -v sha="$current_sha" '
    $1 == marker {
      session_ok = 0
      sha_ok = 0
      for (i = 2; i <= NF; i++) {
        if ($i == "session=" sid) session_ok = 1
        if ($i == "sha=" sha) sha_ok = 1
      }
      if (session_ok && sha_ok) print $0
    }
  ' "$STATE_FILE" 2>/dev/null | sort -u | wc -l | tr -d ' '
)
```
Add a regression test that a mismatched `sha=` does not satisfy the release gate.

## Warnings

### WR-01: Unreadable curl/wget config files now block unrelated Bash commands

**File:** `hooks/validate-release-gate.sh:863`
**Issue:** `curl_release_write_command()` and `wget_release_write_command()` return `True` whenever a config/input file cannot be read, even if the command targets a non-GitHub URL. That means benign commands like `curl -K missing.cfg https://example.com` and `wget -i missing.txt https://example.com` are classified as release writes and denied whenever the gate is incomplete.
**Fix:** Only fail closed on unreadable config/input files after a GitHub release endpoint or mutation has already been identified; otherwise return `False` so ordinary `curl`/`wget` usage is not blocked. Add regression tests with non-GitHub URLs and missing config/input files.

---

_Reviewed: 2026-05-15T05:52:53Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: deep_

# Pre-Release Quality Gate

> Manual release gate for current Sidekick releases.

This gate runs after the release candidate commit exists and before a GitHub release or tag is published. The gate is scoped to the current host session and current git commit.

## Release State

State file:

- Claude/source installs: `~/.claude/.sidekick/quality-gate-state`
- Codex installs: `~/.codex/.sidekick/quality-gate-state`
- Cursor installs: `~/.cursor/.sidekick/quality-gate-state`

Marker format:

```text
quality-gate-stage-N session=<current-host-session-id> sha=<git-sha>
quality-gate-live-pyramid session=<current-host-session-id> sha=<git-sha> at=<utc-timestamp> run_id=<wrapper-run-id> source=kay-wrapper proof_sha256=<wrapper-proof-sha256> candidate_sha256=<candidate-sha256> command_sha256=<command-sha256>
```

Required release evidence:

- `quality-gate-stage-1`
- `quality-gate-stage-2`
- `quality-gate-stage-3`
- `quality-gate-stage-4`
- Two distinct `quality-gate-live-pyramid` markers written by successful Kay-hosted live runs of `tests/run_release.bash`

Resolve the release state path once in the release shell:

```bash
SIDEKICK_QG_DIR="${HOME}/.claude/.sidekick"
if [ -n "${CURSOR_PLUGIN_ROOT:-}" ] || [ -n "${CURSOR_VERSION:-}" ] || [ -n "${CURSOR_PROJECT_DIR:-}" ]; then
  SIDEKICK_QG_DIR="${HOME}/.cursor/.sidekick"
elif [ -n "${CODEX_PLUGIN_ROOT:-}" ] || [ -n "${CODEX_HOME:-}" ] || [ -n "${CODEX_THREAD_ID:-}" ]; then
  SIDEKICK_QG_DIR="${HOME}/.codex/.sidekick"
fi
SIDEKICK_QG_STATE="${SIDEKICK_QG_DIR}/quality-gate-state"
SIDEKICK_QG_SESSION="${SIDEKICK_SESSION_ID:-${CODEX_THREAD_ID:-${CLAUDE_SESSION_ID:-${SESSION_ID:-}}}}"
SIDEKICK_QG_SHA="$(git rev-parse --short=12 HEAD 2>/dev/null || true)"
test -n "$SIDEKICK_QG_SESSION" || { echo "No host session id found"; exit 1; }
test -n "$SIDEKICK_QG_SHA" || { echo "No git SHA found"; exit 1; }
mkdir -p "$SIDEKICK_QG_DIR"
printf '%s\n' "$SIDEKICK_QG_SESSION" > "${SIDEKICK_QG_DIR}/current-session"
```

## Stage 1 - Code Review

Goal: no accepted issues across release-changed files.

1. Run parallel code review using the available review workflows.
2. Triage findings.
3. Fix all accepted issues.
4. Repeat until two consecutive passes produce no accepted issues.
5. Invoke `/superpowers:verification-before-completion`.
6. Write the marker:

```bash
printf 'quality-gate-stage-1 session=%s sha=%s\n' "$SIDEKICK_QG_SESSION" "$SIDEKICK_QG_SHA" >> "$SIDEKICK_QG_STATE"
```

Review focus:

- Canonical skills under `skills/` match generated host bundles.
- Hooks enforce only the active Kay or Codex mode.
- Runtime commands match `sidekicks/registry.json`.
- Plugin manifest integrity hashes match changed artifacts.
- No temporary debug code, local-only paths, or untracked release assets remain.

## Stage 2 - System Consistency

Goal: the whole system is internally consistent.

Audit these dimensions:

1. Skill, hook, and registry consistency.
2. Test suite coverage and runner contracts.
3. Security posture for hook input, output, and command rewriting.
4. Plugin manifest and installer accuracy.
5. Public docs and help-site alignment.

Fix issues and repeat until two consecutive passes are clean. Then invoke `/superpowers:verification-before-completion` and write:

```bash
printf 'quality-gate-stage-2 session=%s sha=%s\n' "$SIDEKICK_QG_SESSION" "$SIDEKICK_QG_SHA" >> "$SIDEKICK_QG_STATE"
```

## Stage 3 - Public Content

Goal: everything users see reflects the current release.

Check:

- `README.md`
- `site/index.html`
- `site/help/`
- `site/ARCHITECTURE.md`
- `site/COMPATIBILITY.md`
- `site/GLOSSARY.md`
- `site/START-HERE.md`
- `site/TESTING.md`
- `site/CICD.md`
- `site/PRD-Overview.md`
- `CHANGELOG.md`

Run:

```bash
bash tests/test_homepage_sidekicks.bash
bash tests/test_help_site_navigation.bash
bash tests/test_docs_contract.bash
bash tests/test_og_image.bash
bash tests/run_unit.bash
```

After a clean pass, invoke `/superpowers:verification-before-completion` and write:

```bash
printf 'quality-gate-stage-3 session=%s sha=%s\n' "$SIDEKICK_QG_SESSION" "$SIDEKICK_QG_SHA" >> "$SIDEKICK_QG_STATE"
```

## Stage 4 - Security Audit

Goal: no blocking security issue remains in release-changed skills, hooks, installer paths, manifests, or site docs.

Check:

- Secrets are never logged, echoed, or copied into prompts.
- Hook output is bounded and redacted.
- Child-runtime commands cannot bypass the active-sidekick boundary.
- Release commands require explicit repository and target provenance.
- Generated host bundles are not edited by hand.
- Kay and Codex state roots stay isolated.

After fixes and verification, invoke `/superpowers:verification-before-completion` and write:

```bash
printf 'quality-gate-stage-4 session=%s sha=%s\n' "$SIDEKICK_QG_SESSION" "$SIDEKICK_QG_SHA" >> "$SIDEKICK_QG_STATE"
```

## Live Release Gate

Run the live release gate twice:

```bash
bash tests/run_in_kay.bash SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
bash tests/run_in_kay.bash SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
```

Each successful canonical run writes a candidate marker. The Kay wrapper promotes valid candidates into proof-bound `quality-gate-live-pyramid` markers.

## Final Check

Verify four stage markers and two live markers for the current session and commit:

```bash
count=$(awk -v sid="$SIDEKICK_QG_SESSION" -v sha="$SIDEKICK_QG_SHA" '$1 ~ /^quality-gate-stage-[1-4]$/ { has_session=0; has_sha=0; for(i=2;i<=NF;i++){ if($i=="session="sid)has_session=1; if($i=="sha="sha)has_sha=1 } if(has_session && has_sha)print $1 }' "$SIDEKICK_QG_STATE" | sort -u | wc -l | tr -d ' ')
[ "$count" -eq 4 ] || { echo "Quality gate incomplete: $count/4 stages present"; exit 1; }

live_count=$(awk -v sid="$SIDEKICK_QG_SESSION" -v sha="$SIDEKICK_QG_SHA" '$1=="quality-gate-live-pyramid"{has_session=0; has_sha=0; has_source=0; run_id=""; proof_sha=""; candidate_sha=""; command_sha=""; for(i=2;i<=NF;i++){ if($i=="session="sid)has_session=1; if($i=="sha="sha)has_sha=1; if($i=="source=kay-wrapper")has_source=1; if($i ~ /^run_id=.+/)run_id=substr($i,8); if($i ~ /^proof_sha256=[0-9a-f]{64}$/)proof_sha=substr($i,14); if($i ~ /^candidate_sha256=[0-9a-f]{64}$/)candidate_sha=substr($i,18); if($i ~ /^command_sha256=[0-9a-f]{64}$/)command_sha=substr($i,16) } if(has_session && has_sha && has_source && run_id!="" && proof_sha!="" && candidate_sha!="" && command_sha!="")print run_id }' "$SIDEKICK_QG_STATE" | sort -u | wc -l | tr -d ' ')
[ "$live_count" -ge 2 ] || { echo "Live gate incomplete: $live_count/2 runs present"; exit 1; }
```

Release commands must target the current trusted Sidekick `HEAD` explicitly:

```bash
git rev-parse HEAD
gh release create v<version> \
  --repo alo-exp/sidekick \
  --title "Sidekick v<version>" \
  --notes-file <notes.md> \
  --target <current-sha> \
  --latest
```

Skipping this gate is not permitted for a normal release.

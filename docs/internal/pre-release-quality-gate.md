# Pre-Release Quality Gate

Before ANY release, the following four-stage quality gate MUST be completed in order.

**IMPORTANT**: This gate runs AFTER normal workflow finalization and BEFORE creating a GitHub release.

---

## Enforcement

**State file**: `~/.claude/.sidekick/quality-gate-state`

**Required markers** (must all be present before release):
- `quality-gate-stage-1`
- `quality-gate-stage-2`
- `quality-gate-stage-3`
- `quality-gate-stage-4`

**Session reset**: All four markers are cleared at the start of each new Claude Code session. The gate must be completed in full during the session in which the release is being cut — markers from a previous session do not carry over.

Each stage is complete only when:
1. The work is done and verified
2. The `/superpowers:verification-before-completion` skill has been invoked (not just run manually)
3. The marker is written: `echo "quality-gate-stage-N" >> ~/.claude/.sidekick/quality-gate-state`

**Violating the verification rule is equivalent to skipping the stage.**

---

## Stage 1 — Code Review Triad

**Goal**: Zero accepted issues across all source files changed in this release.

The triad is three sequential passes: functionality, structure, and security. Each pass must be completed before moving to the next.

### Pass 1 — Functionality Review

Run `/engineering:code-review` on each of the following files. For each file, record findings, fix all accepted issues, and re-run until clean before moving to the next file.

**`skills/forge/SKILL.md`**
- Verify every step in the SKILL.md activation sequence is executable as written with no ambiguity
- Confirm the 5-field task prompt structure (OBJECTIVE, CONTEXT, DESIRED STATE, SUCCESS CRITERIA, INJECTED SKILLS) is complete and correctly described
- Confirm the fallback ladder L1/L2/L3 escalation conditions, retry counts, and exit criteria are unambiguous
- Verify the AGENTS.md three-tier write targets (`./AGENTS.md`, `~/forge/AGENTS.md`, `docs/sessions/YYYY-MM-DD-session.md`) are all present and correctly pathed
- Verify the token optimization section enforces the 2,000-token task prompt cap
- Verify the skill injection mapping table lists all 4 bootstrap skills with correct task-type mappings

**`tests/`**
- Run the full test suite: `bash tests/run_all.bash` (or project equivalent)
- Every test must pass — no failures, no skipped tests without documented reason
- If any test is marked pending or skipped, document the reason and track it as a known issue
- Verify test output matches expected output as described in each test's comments

**`hooks/`** (if present)
- Manually trigger each pre-commit and post-commit hook
- Verify each hook completes without error on a clean repo state
- Verify hook output and side effects match documented behavior

**`install.sh`**
- Trace through the install script step by step
- Verify the Forge binary download URL is current, uses HTTPS, and resolves to the canonical `forgecode.dev` domain
- Verify the script handles both macOS and Linux correctly (check any `uname` branches)
- Verify STEP 0A (credentials setup) creates `~/forge/.credentials.json` with `{ "api_key": "..." }` structure and `~/forge/.forge.toml` with correct `provider_id`/`model_id` structure
- Verify the install directory is correctly communicated to the user for PATH setup
- Verify the script uses `set -e` so it exits on first error

**`README.md`**
- Verify install commands are copy-pasteable and tested
- Verify `/forge` invocation examples match actual SKILL.md behavior
- Verify feature descriptions are accurate and complete
- Verify the prerequisites section lists the correct Forge binary version requirement

**`CHANGELOG.md`**
- Verify the new release entry is present, dated correctly, and uses the correct version
- Verify it accurately lists all Added, Changed, and Fixed items for this release
- Verify no placeholder text (no "TODO", "TBD", or template stubs) remains

**Final diff review**
- Read the full diff between this release and the previous tag: `git diff <prev-tag>...HEAD`
- Confirm no unintended changes are included
- Confirm all intended changes are present
- Confirm no debug code, commented-out experiments, or temporary workarounds were left in

### Pass 2 — Structure Review

1. **SKILL.md section order**: Confirm the 8 canonical sections are present in order: (1) Activation, (2) Delegation Protocol, (3) Deactivation, (4) Failure Detection, (5) Fallback Ladder, (6) Skill Injection, (7) AGENTS.md Mentoring Loop, (8) Token Optimization.

2. **Bootstrap skills**: Confirm all 4 are present at `.forge/skills/`: `testing-strategy/SKILL.md`, `code-review/SKILL.md`, `security/SKILL.md`, `quality-gates/SKILL.md`. Verify each file is non-empty and has correct frontmatter/structure.

3. **Docs directory structure**: Verify `docs/help/` contains all 5 subdirectories: `getting-started/`, `concepts/`, `workflows/`, `reference/`, `troubleshooting/`. Verify `docs/internal/` and `docs/sessions/` exist.

4. **Naming consistency**: Verify all internal references use consistent spelling and casing across `skills/forge/SKILL.md`, `README.md`, `docs/help/`, and `CHANGELOG.md`. Check: skill names, command names (`/forge`, `/forge-stop`), config key names (`provider_id`, `model_id`, `max_tokens`), and file paths.

5. **No orphaned files**: Check for files with no inbound references and no clear documented purpose. Flag each for removal or documentation.

### Pass 3 — Security Review (preliminary)

This is a quick pass — Stage 4 does the deep security audit. Here, check only the obvious issues:

1. **No hardcoded credentials**: Search all changed files for patterns matching API keys, tokens, or passwords: `grep -r "sk-or-" .`, `grep -r "api_key.*=.*[a-zA-Z0-9]" .` (excluding `.credentials.json` documentation examples).

2. **Gitignore correctness**: Verify `.gitignore` includes `.forge.toml` (project root) and that `docs/sessions/` is gitignored if session logs contain sensitive content.

3. **Credential file permissions**: Verify `install.sh` sets `chmod 600 ~/forge/.credentials.json` after writing it.

4. **SKILL.md credential scope**: Verify SKILL.md never instructs Claude to read or display the API key value from `~/forge/.credentials.json` — only to verify the file exists.

### Completion

After all three passes complete with no blocking issues:

1. Invoke `/superpowers:verification-before-completion` — evidence of a clean pass required before marking complete
2. Write the marker:
   ```bash
   echo "quality-gate-stage-1" >> ~/.claude/.sidekick/quality-gate-state
   ```

**Exit criteria**: Zero accepted code review findings across all three passes, fresh verification confirms clean, marker written.

---

## Stage 2 — Big-Picture Consistency Audit

**Goal**: All components are consistent and correct as a whole system. No dimension can have unresolved gaps.

Spawn 5 parallel audit agents, each examining one dimension. Collect all findings. Fix all issues. Re-run until **two consecutive clean passes** across all 5 dimensions.

### Dimension A — Skills Consistency

Audit `skills/forge/SKILL.md` against `README.md` and all help pages:

- **STEP 0A**: The exact commands in SKILL.md's activation STEP 0A match what `README.md` and `docs/help/getting-started/index.html` say to run during first-time setup. No divergence in file paths, key names, or command syntax.
- **Health check steps**: The health check verification items listed in SKILL.md match the troubleshooting page entries at `docs/help/troubleshooting/index.html`. Every check SKILL.md performs has a corresponding troubleshooting entry for what to do when it fails.
- **Fallback ladder**: L1/L2/L3 level names, escalation conditions, and retry counts in SKILL.md match the visual ladder diagram in `docs/help/concepts/index.html` exactly.
- **Skill injection table**: The 4 bootstrap skill names and their task-type mappings in SKILL.md match the tables in `docs/help/concepts/index.html` and `docs/help/reference/index.html` with identical spelling.
- **Token budget**: The 2,000-token task prompt cap appears consistently in SKILL.md, `docs/help/reference/index.html`, and `docs/help/concepts/index.html`.
- **No obsolete references**: Search SKILL.md for any mention of removed commands, deprecated config keys, or old file paths that no longer exist in the codebase.

### Dimension B — Tests Coverage

Audit `tests/` against README claims and SKILL.md behavior:

- Count the test files and verify the count matches any claim in `README.md` about test coverage
- Verify every major SKILL.md section has at least one corresponding test: activation, fallback ladder (L1, L2, L3), skill injection, AGENTS.md write, token optimization
- Check for orphaned test files — tests that reference functions, commands, or files that no longer exist in the codebase
- Verify the test runner command documented in `README.md` (`bash tests/run_all.bash` or equivalent) actually works on a clean checkout
- Verify the CI workflow at `.github/workflows/ci.yml` runs the same test command as `README.md` documents

### Dimension C — Config Files Consistency

Audit `.forge.toml`, `~/forge/.forge.toml` (example in docs), and AGENTS.md format:

- **Provider/model references**: The `provider_id` and `model_id` example values across all docs (concepts page, reference page, README) match the values in the actual example config in `install.sh` or STEP 0A
- **`max_tokens` value**: Is `16384` everywhere it appears — SKILL.md, reference page, concepts page, all config examples
- **Compaction defaults**: `token_threshold = 80000`, `eviction_window = 0.20`, `retention_window = 6` are consistent across all docs and code that references these values
- **AGENTS.md format**: The category headings (Code Style, Testing, Git Workflow, Forge Behavior, Project Conventions) match between SKILL.md's bootstrap template description and the AGENTS.md format section in `docs/help/reference/index.html`
- **No stale config keys**: Verify no config option documented anywhere has been removed from Forge's supported config schema. Cross-check against `https://forgecode.dev/schema.json` if accessible.

### Dimension D — Help Site Accuracy

Audit all `docs/help/*/index.html` pages:

- **Step counts**: The numbered steps in `docs/help/workflows/index.html` match the actual steps in SKILL.md's delegation protocol. No steps added or removed without being reflected in the workflow page.
- **Skill names**: The 4 bootstrap skill names (`testing-strategy`, `code-review`, `security`, `quality-gates`) are spelled identically on every help page where they appear.
- **Config paths**: Every file path mentioned in help pages exists or is correctly described: `~/forge/.credentials.json`, `~/forge/.forge.toml`, `~/.claude/.forge-delegation-active`, `.forge/skills/*/SKILL.md`, `docs/sessions/`
- **Command syntax**: `/forge`, `/forge-stop`, `/forge status` syntax is consistent across getting-started, workflows, reference, and troubleshooting pages
- **Troubleshooting coverage**: Every error condition mentioned in SKILL.md's failure detection section has a corresponding troubleshooting entry
- **Sidebar nav anchors**: Every anchor link in every sidebar nav (`sidebar-nav` elements) resolves to an actual `id` attribute on the same page — no dead links
- **Quick-links grid**: All 10 quick links in `docs/help/index.html` resolve to existing anchors on existing pages
- **Page-nav-bottom sequence**: The prev/next links form a correct linear sequence: getting-started → concepts → workflows → reference → troubleshooting

### Dimension E — AGENTS.md and Install Chain

Audit the full install and initialization path:

- **`install.sh` end-to-end**: Trace the install script on a simulated fresh machine. Verify the binary is placed at the expected path, PATH is updated correctly, and the script completes without interactive prompts (other than credential entry)
- **AGENTS.md bootstrap**: Verify SKILL.md's bootstrap template creates an AGENTS.md with the correct 5-category structure. Verify the bootstrap only runs when `./AGENTS.md` does not already exist — it must not overwrite an existing AGENTS.md
- **Three-tier write correctness**: Verify writes go to exactly three targets after each task: `./AGENTS.md`, `~/forge/AGENTS.md`, `docs/sessions/YYYY-MM-DD-session.md`. No other paths.
- **Deduplication**: Verify the two-phase dedup (exact substring + semantic similarity) is described consistently in SKILL.md and `docs/help/concepts/index.html`
- **`plugin.json`** (if present): Verify the SHA-256 or content hash of `skills/forge/SKILL.md` referenced in `plugin.json` matches the actual file

### Completion

After two consecutive clean passes across all 5 dimensions:

1. Invoke `/superpowers:verification-before-completion` — two-pass clean evidence required
2. Write the marker:
   ```bash
   echo "quality-gate-stage-2" >> ~/.claude/.sidekick/quality-gate-state
   ```

**Exit criteria**: Two consecutive clean passes from all 5 dimensions, no consistency gaps remain, marker written.

---

## Stage 3 — Public-Facing Content Refresh

**Goal**: Everything users see is accurate, complete, and reflects the current release. No user-facing content references old behavior, old version numbers, or removed features.

### Step 1 — GitHub Repository Metadata

- **Description**: Read the current GitHub repo description. Verify it accurately describes the current version of Sidekick (Forge delegation, fallback ladder, AGENTS.md mentoring). Update if stale.
- **Topics/tags**: Verify relevant topics are set. Recommended: `claude-code`, `ai-coding`, `forge`, `delegation`, `agents`, `sidekick`. Add any that are missing, remove any that are no longer accurate.
- **Homepage URL**: Verify the repo homepage field points to the correct docs landing page URL.
- **README preview**: Check how the README renders on the GitHub repo page — verify no images are broken, no badge URLs 404, no links are dead.

### Step 2 — README.md

Read `README.md` in full and verify/update:

- **Version badge**: The version badge at the top matches the release being cut. Update the badge URL and the badge text.
- **Sidekick description**: The description accurately reflects the current feature set. No features that were removed. No existing features missing from the description.
- **Provider options**: Both OpenRouter and MiniMax are listed. The model IDs shown (`qwen/qwen3-coder-plus` for OpenRouter, `MiniMax-M2.7` for MiniMax) are current.
- **Install command**: The install command is copy-pasteable, tested on a clean machine (or equivalent), and resolves to the correct URL.
- **Prerequisites**: The Forge binary version requirement and the Claude Code version requirement are current.
- **Benchmarks or metrics**: If any numbers are cited (task success rate, token savings, model performance, etc.), verify they reflect current observed behavior. Remove or update stale numbers.
- **License**: Correct license (MIT) and current year.
- **All links**: Every link in README.md resolves — GitHub links, docs links, external tool links.

### Step 3 — docs/index.html (Landing Page)

Read `docs/index.html` in full and verify/update:

- **Version badge**: Matches the release. Update badge text and any hardcoded version strings.
- **Feature section**: Each feature card or section accurately describes current behavior. Verify against SKILL.md — every feature described must be implemented, every implemented feature should be represented.
- **Install command**: Identical to README.md — no divergence in syntax or URL.
- **Benchmarks**: Same as README.md — any cited numbers are current. Do not leave stale performance claims.
- **Call-to-action links**: The primary CTA buttons (install, docs, GitHub) all resolve correctly.
- **No broken images or assets**: All `<img>` tags and CSS `background-image` references resolve. No 404 assets.
- **External links**: All external links (to forgecode.dev, openrouter.ai, GitHub) are current and resolve.

### Step 4 — All docs/help/*.html Pages

For each of the 5 help section pages, read the page in full and verify:

**`docs/help/getting-started/index.html`**
- Install command matches README.md and docs/index.html exactly
- STEP 0A credentials setup commands are current and correct
- Health check output example reflects current `/forge` activation behavior
- Plugin install command (`/plugin install alo-exp/sidekick` or current equivalent) is correct

**`docs/help/concepts/index.html`**
- Fallback ladder section (L1/L2/L3) matches SKILL.md exactly — same level names, same retry counts, same escalation conditions
- Skill injection table matches SKILL.md exactly — same 4 skills, same task-type mappings
- AGENTS.md three-tier write targets match SKILL.md
- Token optimization numbers (2,000-token cap, `.forge.toml` defaults) match SKILL.md and reference page
- Provider configuration section shows current model IDs

**`docs/help/workflows/index.html`**
- 7-step workflow matches the actual SKILL.md delegation protocol steps
- Task prompt code example shows current 5-field structure
- Fallback flow steps (L1/L2/L3) are accurate and consistent with concepts page
- AGENTS.md update section accurately describes the three-tier write and dedup behavior

**`docs/help/reference/index.html`**
- `/forge` commands table is complete and accurate
- Task prompt fields table matches SKILL.md exactly
- `.forge.toml` config examples show current key names and default values
- Bootstrap skills table lists all 4 skills with correct paths and task-type descriptions
- Output format section (STATUS, FILES_CHANGED, ASSUMPTIONS, PATTERNS_DISCOVERED) is accurate
- AGENTS.md format code example shows current category structure
- File structure table lists all current Sidekick-managed files with correct paths

**`docs/help/troubleshooting/index.html`**
- All required issues are covered: forge not found, health check failures, OpenRouter config, 429 rate limit, 402 payment required, forge stuck in loop, fallback not triggering, AGENTS.md issues, session recovery, reinstall/reset
- Fix steps are current and accurate for each issue
- Code examples in fix steps use current command syntax

**All 5 pages — common checks**:
- Internal cross-links between help pages resolve correctly
- External links (openrouter.ai, GitHub issues, forgecode.dev) are current and resolve
- The page-nav-bottom prev/next links form the correct sequence: getting-started → concepts → workflows → reference → troubleshooting
- The footer "Innovated at Ālo Labs" text and link are present

### Step 5 — CHANGELOG.md

Verify the new release entry:

- **Version**: Matches the tag being created (e.g., `## v1.2.0 — 2026-04-13`)
- **Date**: Correct release date
- **Added**: All new features listed with clear descriptions
- **Changed**: All breaking changes and behavior changes listed, with migration notes if needed
- **Fixed**: All bug fixes listed
- **No placeholder text**: No "TODO", "TBD", or unfilled template sections anywhere in the file
- **Previous releases intact**: Verify no previous release entries were accidentally modified

### Completion

After all five steps are complete and verified:

1. Push to main and wait for CI to pass:
   ```bash
   git push origin main
   gh run watch
   ```
2. Invoke `/superpowers:verification-before-completion` — evidence of clean content audit required
3. Write the marker:
   ```bash
   echo "quality-gate-stage-3" >> ~/.claude/.sidekick/quality-gate-state
   ```

**Exit criteria**: All public-facing content is accurate and current, CHANGELOG.md has a finalized release entry, CI passes on main, marker written.

---

## Stage 4 — Security Audit (SENTINEL)

**Goal**: No security issues in the skill instruction set, install chain, or help site. A compromised SKILL.md or install script is a high-severity risk — this stage must be thorough.

Run `/anthropic-skills:audit-security-of-skill` on `skills/forge/SKILL.md` as the primary automated check. Then perform the following manual checks.

### Target 1 — `skills/forge/SKILL.md`

This file controls Claude's behavior during every delegation session. A malformed or manipulated SKILL.md could cause Claude to exfiltrate data, bypass safety checks, or behave unpredictably in response to crafted Forge output.

1. **Prompt injection surface**: Review every section of SKILL.md for content that could be manipulated by Forge's output to alter Claude's behavior. The highest-risk surface is the DEBRIEF template (TASK, FORGE_FAILURE, LEARNED, AGENTS_UPDATE fields) — verify Claude treats the content of these fields as data to be recorded, not as instructions to be executed.

2. **AGENTS.md write scope**: Verify the AGENTS.md mentoring loop section in SKILL.md only writes to the three approved targets: `./AGENTS.md`, `~/forge/AGENTS.md`, `docs/sessions/YYYY-MM-DD-session.md`. There must be no code path that allows the mentoring loop to write to arbitrary paths based on content in Forge's output.

3. **Credential handling**: Verify SKILL.md never instructs Claude to read, display, log, transmit, or include in any prompt the contents of `~/forge/.credentials.json`. The activation health check should verify the file exists and has an `api_key` field — it must not read the key value into context.

4. **Delegation restriction bypass**: Verify the delegation restriction (Claude must not implement code directly while Forge delegation mode is active) can only be lifted by the L3 escalation path in the fallback ladder. There must be no instruction in SKILL.md that allows Forge's output content to trigger L3 directly, bypass L1/L2, or lift the restriction outside the defined escalation flow.

5. **Deactivation completeness**: Verify the deactivation sequence (triggered by `/forge-stop`) clears `~/.claude/.forge-delegation-active` and fully restores Claude's normal behavior. No residual delegation state should remain after deactivation — verify this is explicit in the deactivation section of SKILL.md.

6. **Scope of PATTERNS_DISCOVERED**: Verify that the PATTERNS_DISCOVERED output field from Forge is treated as documentation/hints for AGENTS.md, not as executable instructions. Claude must not run commands or modify files based solely on PATTERNS_DISCOVERED content.

### Target 2 — `install.sh`

This script runs with user-level permissions, modifies the user's home directory, and updates PATH. It is the highest-privilege file in the Sidekick codebase.

1. **Download integrity**: If the script downloads the Forge binary from a URL:
   - The URL must use HTTPS
   - The domain must be the canonical `forgecode.dev` domain — no redirects to third-party domains
   - A checksum verification step (SHA-256 or equivalent) must exist to verify the downloaded binary before execution
   - If checksum verification is missing, this is a **blocking security issue** — do not proceed to release

2. **No arbitrary code execution**: Verify the script does not `eval` or execute any content downloaded from the network beyond the Forge binary itself. No `curl | bash` from any URL other than the primary install script itself (and even that should be documented as a risk in README.md).

3. **File permissions**: Verify the script sets `chmod 600 ~/forge/.credentials.json` after writing credentials. The credentials file must not be world-readable (`644`) or group-readable (`640`).

4. **PATH modification safety**: Verify the PATH addition appended to `.zshrc`/`.bashrc` is scoped to `~/.forge/bin` only. The script must not prepend a broad directory, set `PATH` to a hardcoded value, or modify any system-level PATH configuration.

5. **Idempotency**: Verify the script can be run multiple times without:
   - Duplicating PATH entries in `.zshrc`/`.bashrc`
   - Overwriting a valid existing `~/forge/.credentials.json` without confirmation
   - Corrupting an existing working Forge install
   - Installing a downgraded version silently

6. **Error handling**: Verify the script uses `set -e` (or `set -euo pipefail`) so it exits immediately on any command failure. A partially completed install that silently continues is a security risk — the user could end up with a broken state they don't know about.

7. **Sensitive output suppression**: Verify the script never prints the contents of `~/forge/.credentials.json` to stdout or stderr, even in verbose or debug mode. API keys must not appear in terminal output or in any log file the script creates.

8. **Temp file cleanup**: If the script creates temporary files (e.g., for downloading the binary before verifying), verify it cleans them up on both success and failure paths (use `trap` for cleanup).

### Target 3 — `docs/help/**/*.html`

The help site loads external scripts (Lucide icons from unpkg.com). Verify the site's external resource loading is scoped and safe.

1. **External script sources**: Verify the only external scripts loaded are:
   - `https://unpkg.com/lucide@<version>/dist/umd/lucide.min.js` (icon library)
   - Google Fonts CSS (`https://fonts.googleapis.com` and `https://fonts.gstatic.com`)
   - No other external scripts, no analytics, no tracking pixels

2. **No inline event handlers with untrusted content**: Verify there are no `eval()` calls, no `innerHTML` assignments from URL parameters or query strings, and no `document.write()` calls in `search.js` or any inline script.

3. **Search functionality scope**: Verify `search.js` only reads from the local `SEARCH_INDEX` array — it must not fetch content from external URLs or execute content from search query strings.

4. **No form submissions to external endpoints**: Verify no `<form>` elements submit to external URLs.

5. **Subresource integrity**: Ideally, the Lucide script tag should include a `integrity` attribute (SRI hash). If it does not, flag this as a low-severity finding and add it if possible without breaking functionality.

### Completion

After all three targets are clean with no blocking issues:

1. Fix every finding. For blocking issues (missing binary checksum, world-readable credentials, prompt injection path), fix before proceeding — there is no acceptable risk threshold for these.
2. Invoke `/superpowers:verification-before-completion` — clean audit evidence required
3. Write the marker:
   ```bash
   echo "quality-gate-stage-4" >> ~/.claude/.sidekick/quality-gate-state
   ```

**Exit criteria**: Zero blocking security findings, all three targets pass clean, marker written.

---

## Release

After all 4 markers are written to `~/.claude/.sidekick/quality-gate-state`,
and after the full Forge/Codex live pyramid has been run twice, verify and
create the release:

```bash
# Verify all 4 markers are present
grep -c "quality-gate-stage-" ~/.claude/.sidekick/quality-gate-state
# Must output 4

# Create the GitHub release
gh release create v<version> \
  --title "Sidekick v<version>" \
  --notes-file CHANGELOG.md \
  --latest
```

**Skipping is not permitted.** No stage may be abbreviated or marked complete without performing the checks. If time pressure requires a release, document the skipped checks explicitly as known risks in the release notes and schedule a follow-up patch release after completing the audit.

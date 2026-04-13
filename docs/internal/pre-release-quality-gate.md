# Sidekick Pre-Release Quality Gate

4-stage mandatory gate before every `gh release create`. All 4 stage markers must exist or the release is blocked.

---

## Enforcement

```bash
# Completion audit — blocks release if any stage marker missing
~/.claude/.silver-bullet/completion-audit.sh

# Stage markers written to:
~/.claude/.silver-bullet/state
```

Each stage is complete only when:
1. The work is done and verified
2. `/superpowers:verification-before-completion` skill has been invoked (not just run manually)
3. The marker is written: `echo "quality-gate-stage-N" >> ~/.claude/.silver-bullet/state`

**Violating the verification rule is equivalent to skipping the stage.**

---

## Stage 1 — Code Review Triad

**Goal:** Zero accepted issues across all source files.

### Process

1. Run `/code-review` on all modified source files:
   - `skills/forge/SKILL.md`
   - `skills/forge.md` (read-only — verify not modified)
   - `.forge/skills/*/SKILL.md` (4 bootstrap skills)
   - `tests/*.bash` (8 test suites)
   - `install.sh`, `plugin.json`, `.forge.toml`
   - `docs/help/**/*.html` and `docs/help/search.js`

2. Run `/requesting-code-review` — prepare the review package

3. Run `/receiving-code-review` — process all findings

4. Fix every accepted item. Loop back to step 1 until zero accepted items remain.

5. Invoke `/superpowers:verification-before-completion` skill — evidence required before proceeding.

6. Record marker:
   ```bash
   echo "quality-gate-stage-1" >> ~/.claude/.silver-bullet/state
   ```

### Exit criteria
- Zero accepted code review findings
- Fresh verification run confirms zero findings
- Marker written

---

## Stage 2 — Big-Picture Consistency Audit

**Goal:** All components are consistent and correct as a whole system.

### Process

Spawn 5 parallel Explore agents, each examining one dimension:

| Agent | Focus |
|-------|-------|
| A — Skills consistency | `skills/forge/SKILL.md` vs `skills/forge.md` — no conflicts, no overlap, SKILL.md only extends |
| B — Tests coverage | All 8 test suites cover their target sections in SKILL.md; `tests/run_all.bash` includes all 8 |
| C — Config & plugin integrity | `.forge.toml` defaults match SKILL.md token optimization docs; `plugin.json` SHA-256 matches `skills/forge/SKILL.md` |
| D — Help site accuracy | `docs/help/**` content matches actual SKILL.md behavior; `search.js` index entries are accurate |
| E — AGENTS.md & install chain | `AGENTS.md` format matches SKILL.md mentoring loop expectations; `install.sh` installs correctly |

Collect findings. Fix all issues. Re-run until **two consecutive clean passes** across all 5 dimensions.

Invoke `/superpowers:verification-before-completion` — fresh two-pass evidence required.

Record marker:
```bash
echo "quality-gate-stage-2" >> ~/.claude/.silver-bullet/state
```

### Exit criteria
- Two consecutive clean passes from all 5 agents
- No consistency gaps between SKILL.md and help docs, tests, or plugin.json
- Marker written

---

## Stage 3 — Public-Facing Content Refresh

**Goal:** Everything users see is accurate, complete, and reflects the current release.

### Audit targets

| Item | Check |
|------|-------|
| `README.md` | Installation steps, feature list, badge links, ForgeCode version |
| `docs/index.html` | Feature descriptions match Phase 1–4 deliverables; no stale copy |
| `docs/help/index.html` | Card descriptions match actual sub-page content |
| `docs/help/getting-started/index.html` | Install flow is accurate; health check output is current |
| `docs/help/concepts/index.html` | Fallback ladder, skill injection, AGENTS.md sections match SKILL.md |
| `docs/help/reference/index.html` | Commands, .forge.toml options, file paths all correct |
| `docs/help/search.js` | Search index entries match actual page content; no dead anchors |
| `CHANGELOG.md` | Current release entry exists and is accurate |
| GitHub repo description | Reflects current capabilities (Forge delegation + AGENTS.md + fallback ladder) |

Fix all stale or inaccurate content.

Invoke `/superpowers:verification-before-completion` — evidence required.

Push to main and wait for CI to pass:
```bash
git push origin main
# Wait for GitHub Actions CI to pass
gh run watch
```

Record marker:
```bash
echo "quality-gate-stage-3" >> ~/.claude/.silver-bullet/state
```

### Exit criteria
- All public-facing content is accurate
- CHANGELOG.md has a current entry
- CI passes on main
- Marker written

---

## Stage 4 — Security Audit (SENTINEL)

**Goal:** No security issues in the skill, install chain, or help site.

### Process

1. Run `/anthropic-skills:audit-security-of-skill` on `skills/forge/SKILL.md`

2. Audit `install.sh` for:
   - No API keys or secrets embedded in bash transcript (use Write tool pattern, not Bash echo)
   - No command injection vectors in user-supplied config values
   - No world-writable files created

3. Audit `docs/help/**/*.html` for:
   - No inline scripts that execute untrusted content
   - No external resource loads from untrusted CDNs (only unpkg.com/lucide and fonts.googleapis.com)
   - No form submission to external endpoints

4. Fix every finding. Loop until clean.

5. Invoke `/superpowers:verification-before-completion` — evidence required.

6. Record marker:
   ```bash
   echo "quality-gate-stage-4" >> ~/.claude/.silver-bullet/state
   ```

### Exit criteria
- Zero SENTINEL findings
- No secrets in bash transcripts
- Help site loads only trusted external resources
- Marker written

---

## Release

After all 4 markers are recorded, run the completion audit and create the release:

```bash
# Verify all 4 markers present
~/.claude/.silver-bullet/completion-audit.sh

# Create release
gh release create v<version> \
  --title "Sidekick v<version>" \
  --notes-file CHANGELOG.md \
  --latest
```

The `completion-audit.sh` script will block `gh release create` if any stage marker is missing.

# Help Site Pre-Release Code Review

**Reviewed:** 2026-04-13  
**Scope:** `docs/help/**/*.html`, `docs/help/search.js`, `docs/help/tokens.css`, `docs/internal/pre-release-quality-gate.md` cross-referenced against `skills/forge/SKILL.md`  
**Reviewer:** Claude (gsd-code-reviewer)

---

## Summary

9 files reviewed. 3 HIGH issues (content inaccuracies where the help site contradicts the actual SKILL.md source of truth, and a CDN integrity gap), 3 MEDIUM issues (a latent JS null-dereference, a missing skill-injection task type, and absolute search URLs that break on subdirectory deployments), and 2 LOW issues. No CRITICAL bugs found. The most important class of issues is the content accuracy cluster — the help docs describe a different command syntax, session marker path, and credential config location than what SKILL.md actually implements.

---

## CRITICAL Issues

None.

---

## HIGH Issues

### H-01: Deactivation command syntax mismatch — help docs say `/forge deactivate`, SKILL.md uses `/forge:deactivate`

**Files:**
- `docs/help/concepts/index.html` line 156
- `docs/help/workflows/index.html` line 211
- `docs/help/reference/index.html` lines 139–140
- `docs/help/troubleshooting/index.html` line 197
- `docs/help/search.js` line 29

**Issue:** Every help page documents the deactivation command as `/forge deactivate` (space-separated) and `/forge off`. SKILL.md line 64 defines it as `/forge:deactivate` (colon-separated), matching Claude Code's skill invocation convention. If a user types `/forge deactivate` per the docs, it will not invoke the deactivation path in SKILL.md — it will be treated as a plain user message. This is a user-facing functional inaccuracy.

**Fix:** Either:
- Update `skills/forge/SKILL.md` line 64 (and the `## Deactivation` section header) to accept `/forge deactivate` as an alias, OR
- Update all help pages to use `/forge:deactivate` as the primary form, with `/forge off` documented as non-functional until a corresponding SKILL.md alias is added.

The safer fix is to add both forms as accepted triggers in SKILL.md and document both in the help site.

---

### H-02: Session state marker path mismatch — help docs say `.forge/.session`, SKILL.md uses `~/.claude/.forge-delegation-active`

**Files:**
- `docs/help/workflows/index.html` line 142
- `docs/help/search.js` line 52

**Issue:** The Delegation Workflow page states that session state is written to `.forge/.session` (a project-relative path). SKILL.md line 41 defines the actual marker as `~/.claude/.forge-delegation-active` (a user-global path). These are different files in different locations with different semantics. Users following the troubleshooting advice "deactivate by deleting the session marker" would delete the wrong file.

**Fix:** Update `docs/help/workflows/index.html` line 142 to read:

```
Session state is written to ~/.claude/.forge-delegation-active (a global marker; one active session at a time across all projects).
```

Update the search index entry in `search.js` line 52 to match.

---

### H-03: Health check config/credential paths mismatch — help docs imply project-root `.forge.toml`, SKILL.md checks `~/forge/.forge.toml` and `~/forge/.credentials.json`

**Files:**
- `docs/help/getting-started/index.html` lines 168, 173
- `docs/help/reference/index.html` lines 159, 163, 219
- `docs/help/troubleshooting/index.html` lines 143–144, 159, 162
- `docs/help/search.js` lines 18, 67–68

**Issue:** The help site consistently describes `.forge.toml` as being in the project root (e.g., Reference page: "Created in the project root on first `/forge` invocation"). SKILL.md health check section (lines 24–28) checks `~/forge/.forge.toml` and `~/forge/.credentials.json` — both in the user's home directory under `~/forge/`. The getting-started page also says Claude "prompts you for your OpenRouter API key and the Forge model to use ... These are saved to `.forge.toml` in the project root." This conflicts with SKILL.md's actual credential location.

Additionally, the help docs describe an OpenRouter API key flow, but SKILL.md checks `~/forge/.credentials.json` for an `api_key` field — suggesting Forge's own credential store, not an OpenRouter-specific `.forge.toml` key. The `openrouter_api_key` field documented in `.forge.toml` does not appear in SKILL.md at all.

**Fix:** Audit `skills/forge.md` (the underlying orchestration protocol referenced by SKILL.md) to determine the definitive credential and config locations. Then update the help site to match. The Reference page's `.forge.toml` code block and the File Structure table both need revision.

---

### H-04: Lucide CDN loaded without Subresource Integrity (SRI) attribute

**Files:** All 6 HTML files at lines:
- `docs/help/index.html` line 264
- `docs/help/getting-started/index.html` line 254
- `docs/help/concepts/index.html` line 284
- `docs/help/workflows/index.html` line 235
- `docs/help/reference/index.html` line 248
- `docs/help/troubleshooting/index.html` line 239

**Issue:** All pages load Lucide from `https://unpkg.com/lucide@0.469.0/dist/umd/lucide.min.js` without an `integrity` attribute. If unpkg.com is compromised or the package contents change (unpkg serves npm packages and a version re-publish could alter content), malicious JS would execute in users' browsers. The pre-release quality gate (Stage 4) explicitly audits for untrusted CDN loads — unpkg.com is not on the allowlist (which lists only `unpkg.com/lucide` and `fonts.googleapis.com`). Note: unpkg.com is the correct CDN for this, but it must have SRI.

**Fix:** Add an `integrity` attribute with the SHA-384 hash of the specific file. Generate it with:

```bash
curl -s https://unpkg.com/lucide@0.469.0/dist/umd/lucide.min.js | openssl dgst -sha384 -binary | openssl base64 -A
```

Then update each script tag:

```html
<script src="https://unpkg.com/lucide@0.469.0/dist/umd/lucide.min.js"
        integrity="sha384-<hash>"
        crossorigin="anonymous"></script>
```

---

## MEDIUM Issues

### M-01: Search index URLs are absolute paths — breaks on subdirectory GitHub Pages deployments

**File:** `docs/help/search.js` lines 7–95 (all `url` fields)

**Issue:** Every entry in the search index uses a root-relative URL (e.g., `url:'/help/getting-started/'`). If the site is deployed to a GitHub Pages project page (e.g., `https://alo-exp.github.io/sidekick/help/`), these paths resolve to `https://alo-exp.github.io/help/getting-started/` — which is a 404. The search results would all produce broken links.

**Fix:** Convert all URLs to paths relative to the search script's location, or introduce a `BASE_URL` constant:

```js
var BASE_URL = (typeof SIDEKICK_BASE === 'string') ? SIDEKICK_BASE : '';
// then use: BASE_URL + r.url + ...
```

Or use relative paths: `url:'getting-started/'`, `url:'concepts/'`, etc. (relative to `docs/help/`).

---

### M-02: `renderResults()` dereferences `main` without null check — latent crash risk

**File:** `docs/help/search.js` lines 125–131

**Issue:** `renderResults()` calls `main.style.display = 'none'` (line 131) without first checking whether `main` is non-null. `clearSearch()` (lines 146–151) correctly uses `if (main)` guards. `main` is `document.getElementById('main-help-content')` which only exists on `index.html`. The script is currently only included in `index.html`, so no crash occurs in practice. But if the script is ever included in a sub-page (e.g., to add per-page search), this will throw `Cannot read properties of null`.

**Fix:** Add the same null guard used in `clearSearch()`:

```js
function renderResults(results, query) {
  var list = document.getElementById('search-results-list');
  var section = document.getElementById('search-results-section');
  var main = document.getElementById('main-help-content');
  if (!list || !section) return;   // guard added
  if (!results.length) {
    section.style.display = 'block';
    if (main) main.style.display = 'none';   // guard added
    list.innerHTML = '<p class="sr-none">No results for "<strong>' + escHtml(query) + '</strong>"</p>';
    return;
  }
  section.style.display = 'block';
  if (main) main.style.display = 'none';   // guard added
  ...
```

---

### M-03: Skill injection mapping table in Concepts page omits the "Code change" task type

**File:** `docs/help/concepts/index.html` lines 211–221

**Issue:** SKILL.md lines 133–142 defines 5 task types and their skill mappings:

| Task Type | Injected Skills |
|---|---|
| Testing | `testing-strategy` |
| **Code change** | **`quality-gates`, `code-review`** |
| Security-sensitive | `security` |
| Review | `code-review` |
| Research/read-only | (none) |

The concepts page table omits the "Code change" row entirely, showing only 4 rows. This means users reading the docs will not know that `quality-gates` is injected for ordinary code changes — which is the most common task type.

**Fix:** Add the missing row to the table in `concepts/index.html`:

```html
<tr><td>code-change</td><td>Editing or writing implementation files (non-test)</td></tr>
```

And note that `quality-gates` and `code-review` are injected for this type. Update the search index entry for `skill-injection` in `search.js` line 41 accordingly.

---

## LOW Issues

### L-01: No favicon defined on any help page

**Files:** All 6 HTML files (`<head>` sections)

**Issue:** None of the help pages include a `<link rel="icon">` element. Browsers will request `/favicon.ico` and receive a 404, polluting server logs and potentially showing a broken icon in browser tabs.

**Fix:** Add to all `<head>` sections:

```html
<link rel="icon" href="../../favicon.ico">
```

(Adjust path depth per page level. Sub-pages need `../../`; index.html needs `./`.)

---

### L-02: `concepts/index.html` documents global AGENTS.md as `~/forge/AGENTS.md` but `troubleshooting/index.html` uses the same path inconsistently in prose

**Files:**
- `docs/help/concepts/index.html` line 239
- `docs/help/troubleshooting/index.html` line 191

**Issue:** Both pages correctly show `~/forge/AGENTS.md`. However, SKILL.md line 203 defines the global tier as `~/forge/AGENTS.md` (no dot prefix), while earlier in the file it references `~/forge/.forge.toml` and `~/forge/.credentials.json` (with dot prefixes for config files). This is consistent — AGENTS.md is not a dotfile. The help docs are accurate here. This is a low-priority note to confirm the `~/forge/` directory is created by the install script; if it is not, the first global write will silently fail.

**Fix:** Verify `install.sh` creates `~/forge/` on install, or add a `mkdir -p ~/forge` guard in the AGENTS.md mentoring loop section of SKILL.md.

---

## CSS Token Audit

All CSS custom properties referenced in the HTML files are defined in `tokens.css`. Both dark (`:root,[data-theme="dark"]`) and light (`[data-theme="light"]`) theme blocks cover the full set of tokens used. No undefined variable references found.

The light theme block does not redeclare `--radius`, `--radius-lg`, `--radius-sm`, `--font-sans`, `--font-mono` — this is correct behavior since these are declared on `:root` and are not theme-dependent.

---

## JavaScript Analysis (search.js)

- Syntax: valid, no parse errors. IIFE wrapper is correctly structured.
- `escHtml()`: properly escapes `&`, `<`, `>`, `"` — XSS safe for search result rendering.
- `DOMContentLoaded` listener: correctly guards with `if (!input) return` before attaching events.
- Debounce timer (180ms): appropriate.
- Score function: no division or index-out-of-bounds risks.
- Index data: all `url` values confirmed to correspond to real pages. All `anchor` values confirmed to match `id` attributes in the target HTML files.
- No `eval()`, no `innerHTML` with untrusted data (only `escHtml`-escaped strings), no external requests.

One latent issue: see M-02 above.

---

_Reviewed: 2026-04-13_  
_Reviewer: Claude (gsd-code-reviewer)_

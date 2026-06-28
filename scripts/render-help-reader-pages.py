#!/usr/bin/env python3
"""Render public HTML help pages for reader docs (no raw .md links)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELP = ROOT / "site" / "help"

DOC_STYLE = """*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
html{scroll-behavior:smooth;-webkit-font-smoothing:antialiased}
body{font-family:var(--font-sans);background:var(--bg-page);color:var(--text-primary);line-height:1.7;overflow-x:hidden}
h1,h2,h3,h4,h5,h6,.logo,.nav-logo,.section-title,.section-label,.tagline,.btn,.tag,.nav-cta,.hero-tagline-caps,.version-badge{font-family:var(--font-heading)}
.container{max-width:860px;margin:0 auto;padding:0 24px}
.page-hero{background:var(--bg-hero);padding-bottom:64px;padding-left:24px;padding-right:24px;position:relative;overflow:hidden}
.page-hero::before{content:'';position:absolute;top:-200px;right:-200px;width:500px;height:500px;border-radius:50%;background:radial-gradient(circle,var(--accent-faint) 0%,transparent 70%)}
.page-hero .container{position:relative;z-index:1}
.page-hero h1{font-size:clamp(1.8rem,3.5vw,2.8rem);font-weight:900;letter-spacing:0;margin-bottom:16px;line-height:1.1}
.page-hero p{font-size:1rem;color:var(--text-secondary);max-width:560px;line-height:1.7}
.doc-layout{padding:64px 0}
.doc-content h2{font-size:1.5rem;font-weight:800;letter-spacing:0;margin-bottom:16px;margin-top:48px;padding-top:16px}
.doc-content h2:first-child{margin-top:0}
.doc-content h3{font-size:1.1rem;font-weight:700;margin-bottom:12px;margin-top:32px;color:var(--text-primary)}
.doc-content p{margin-bottom:16px;color:var(--text-secondary);line-height:1.8}
.doc-content ul,.doc-content ol{margin-bottom:16px;padding-left:20px;color:var(--text-secondary)}
.doc-content li{margin-bottom:6px;line-height:1.7}
.doc-content strong{color:var(--text-primary)}
.doc-content a{color:var(--accent-light);text-decoration:none}
.doc-content a:hover{text-decoration:underline}
.callout{border-radius:var(--radius);padding:20px 24px;margin-bottom:24px;display:flex;gap:14px;align-items:flex-start}
.callout-info{background:var(--accent-faint);border:1px solid var(--accent-border)}
.callout-icon{font-size:1.1rem;flex-shrink:0;margin-top:1px}
.callout-body{font-size:.875rem;color:var(--text-secondary);line-height:1.7}
.callout-body strong{color:var(--text-primary)}
.code-block{background:var(--bg-code);border:1px solid var(--border);border-radius:var(--radius-sm);padding:20px 24px;font-family:var(--font-mono);font-size:1rem;line-height:1.9;color:var(--text-secondary);overflow-x:auto;white-space:pre-wrap;margin-bottom:20px}
.ref-table{width:100%;border-collapse:collapse;margin-bottom:24px;font-size:.85rem}
.ref-table th{text-align:left;padding:10px 16px;background:var(--bg-code);font-size:.75rem;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:var(--text-dim);border-bottom:1px solid var(--border)}
.ref-table td{padding:12px 16px;border-bottom:1px solid var(--border);color:var(--text-secondary);vertical-align:top}
.ref-table code{font-family:var(--font-mono);font-size:.88em;background:var(--bg-code);padding:2px 6px;border-radius:4px}
.page-nav-bottom{display:flex;justify-content:space-between;flex-wrap:wrap;gap:12px;padding-top:48px;border-top:1px solid var(--border);margin-top:48px}
.pnav-btn{display:flex;align-items:center;gap:8px;padding:12px 24px;border-radius:var(--radius);background:var(--bg-card);border:1px solid var(--border);text-decoration:none;color:var(--text-secondary);font-size:.875rem;font-weight:600;transition:all .2s}
.pnav-btn:hover{border-color:var(--accent);color:var(--accent-light)}
svg.lucide{display:inline-block;vertical-align:middle;width:1em;height:1em;stroke-width:1.5;stroke:currentColor;fill:none;stroke-linecap:round;stroke-linejoin:round}"""


def shell(slug: str, title: str, desc: str, breadcrumb: str, body: str, prev_link: str = "", next_link: str = "") -> str:
    nav_bottom = '<div class="page-nav-bottom">'
    if prev_link:
        nav_bottom += prev_link
    else:
        nav_bottom += '<span></span>'
    if next_link:
        nav_bottom += next_link
    else:
        nav_bottom += '<a href="../" class="pnav-btn">Help Center <i data-lucide="arrow-right"></i></a>'
    nav_bottom += "</div>"

    return f"""<!DOCTYPE html>
<html lang="en" data-neutral-variant="s3" data-theme-key="sidekick-theme" data-theme-key-legacy="sidekick-theme-v2">
<head>
<script>(function(){{try{{var t=localStorage.getItem('sidekick-theme')||localStorage.getItem('sidekick-theme-v2');document.documentElement.setAttribute('data-theme',t==='light'?'light':'dark');}}catch(e){{}}}})();</script>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="dark light">
<title>{title} — Sidekick Help</title>
<meta name="description" content="{desc}">
<link rel="stylesheet" href="../../tokens.css">
<link rel="stylesheet" href="../../neutral-variants.css?v=s3-home-icons">
<link rel="stylesheet" href="../../chrome.css?v=site-chrome-11">
<link rel="icon" href="../../og-image.png" type="image/png">
<style>
{DOC_STYLE}
</style>
</head>
<body class="has-help-subnav">

<nav>
  <div class="nav-inner">
    <a href="../../" class="nav-brand" aria-label="Sidekick home">
      <img src="../../og-image.png" alt="" class="nav-bullet" aria-hidden="true">
      <span class="nav-wordmark"><span class="logo gradient">Sidekick</span></span>
    </a>
    <button class="nav-toggle" onclick="document.querySelector('.nav-links').classList.toggle('active')" aria-label="Toggle menu"><i data-lucide="menu"></i></button>
    <ul class="nav-links">
      <li><a href="../../#problem">Problem</a></li>
      <li><a href="../../#future">What If</a></li>
      <li><a href="../../#mechanism">How It Works</a></li>
      <li><a href="../../#sidekicks">Sidekicks</a></li>
      <li><a href="../../#install">Install</a></li>
      <li class="mobile-only"><a href="https://github.com/alo-exp/sidekick" target="_blank" rel="noopener noreferrer">GitHub</a></li>
    </ul>
    <div class="nav-actions">
      <a href="../../help/" class="nav-help">Help Center</a>
      <button id="theme-toggle" type="button" aria-label="Toggle light/dark mode">
        <span id="icon-sun"><i data-lucide="sun"></i></span>
        <span id="icon-moon" style="display:none"><i data-lucide="moon"></i></span>
      </button>
      <a href="https://github.com/alo-exp/sidekick" class="nav-cta" target="_blank" rel="noopener noreferrer">GitHub</a>
    </div>
  </div>
</nav>

<div class="help-subnav" id="help-subnav">
  <div class="help-subnav-inner">
    <nav class="help-breadcrumb" aria-label="Help Center"><a href="../../">Home</a><span class="sep">/</span><a href="../">Help</a><span class="sep">/</span><span class="current">{breadcrumb}</span></nav>
    <div class="help-subnav-extra">
      <div class="help-subnav-links"><a href="../getting-started/">Getting Started</a><a href="../concepts/">Concepts</a><a href="../workflows/">Workflows</a><a href="../reference/">Reference</a><a href="../troubleshooting/">Troubleshooting</a></div>
      <div class="nav-search-wrap"><input type="text" class="nav-search-input" id="nav-search-input" placeholder="Search docs…" autocomplete="off"><div class="nav-search-results" id="nav-search-results"></div></div>
    </div>
  </div>
</div>

<div class="page-hero">
  <div class="container">
    <h1>{breadcrumb}</h1>
    <p>{desc}</p>
  </div>
</div>

<div class="container">
  <div class="doc-layout">
    <div class="doc-content">
{body}
{nav_bottom}
    </div>
  </div>
</div>

<footer>
  <div class="footer-inner">
    <div class="footer-brand-group">
      <span class="footer-credit"><a href="../../" class="footer-brand-link">Sidekick</a> &middot; Innovated at <a href="https://alolabs.dev" target="_blank" rel="noopener noreferrer" style="font-weight:700;text-decoration:none;color:inherit">&#256;lo Labs</a></span>
    </div>
    <div class="footer-copyright">&copy; 2026 Alo Labs. All rights reserved.</div>
    <div class="footer-links">
      <a href="../../help/">Help</a>
      <a href="../../terms/">Terms of Use</a>
      <a href="../../privacy/">Privacy Policy</a>
    </div>
  </div>
</footer>

<script src="https://unpkg.com/lucide@0.469.0/dist/umd/lucide.min.js"></script>
<script src="../search.js"></script>
<script src="../common.js"></script>
<script src="../../chrome.js?v=site-chrome-11"></script>
</body>
</html>
"""


PAGES = {
    "start-here": shell(
        "start-here",
        "Start Here",
        "The fastest path through current Sidekick docs — pick install, delegate, debug, or release.",
        "Start Here",
        """
      <p>The question-first entry point when you do not yet know which Sidekick doc to read.</p>

      <h2>Choose Your Task</h2>
      <h3>Install or refresh Sidekick</h3>
      <p>Start with <a href="../getting-started/">Getting Started</a>. If canonical skill text changed, refresh generated host bundles:</p>
      <div class="code-block">bash scripts/sync-host-surfaces.sh</div>

      <h3>Delegate a task to Kay</h3>
      <div class="code-block">/sidekick:kay
/sidekick:kay xiaomi
/sidekick:kay ocg</div>
      <p>Then read <a href="../workflows/">Workflows</a> for the review and retry loop.</p>

      <h3>Delegate a task to Codex</h3>
      <div class="code-block">/sidekick:codex</div>
      <p>The Codex sidekick runs through <code>codex exec</code> with <code>gpt-5.4-mini</code> and extra-high reasoning.</p>

      <h3>Stop or switch sidekicks</h3>
      <div class="code-block">/sidekick:kay-stop
/sidekick:codex-stop</div>

      <h3>Debug a failure</h3>
      <p>Use <a href="../troubleshooting/">Troubleshooting</a> first, then <a href="../reference/">Reference</a> for exact paths and commands.</p>

      <h3>Prepare a release</h3>
      <p>Use <a href="../testing/">Testing</a>, then run the current release checks that match your risk level.</p>

      <h2>Good First Reading Order</h2>
      <ol>
        <li><a href="../">Help Center</a></li>
        <li><a href="../getting-started/">Getting Started</a></li>
        <li><a href="../concepts/">Concepts</a></li>
        <li><a href="../workflows/">Workflows</a></li>
        <li><a href="../reference/">Reference</a></li>
        <li><a href="../troubleshooting/">Troubleshooting</a></li>
        <li><a href="../compatibility/">Compatibility</a></li>
        <li><a href="../glossary/">Glossary</a></li>
      </ol>

      <div class="callout callout-info">
        <span class="callout-icon"><i data-lucide="info"></i></span>
        <div class="callout-body"><strong>Remember:</strong> Sidekick delegates implementation. The host AI still owns correctness.</div>
      </div>
""",
        next_link='<a href="../getting-started/" class="pnav-btn">Getting Started <i data-lucide="arrow-right"></i></a>',
    ),
    "audience": shell(
        "audience",
        "Audience",
        "Who each Sidekick document is for, and where to start by role.",
        "Audience",
        """
      <h2>Reader Matrix</h2>
      <table class="ref-table">
        <thead><tr><th>Reader</th><th>Best first doc</th><th>Why</th></tr></thead>
        <tbody>
          <tr><td>New user</td><td><a href="../start-here/">Start Here</a></td><td>Shortest path from overview to first delegated task.</td></tr>
          <tr><td>Maintainer</td><td><a href="../testing/">Testing</a></td><td>System boundaries and verification.</td></tr>
          <tr><td>Release operator</td><td><a href="../testing/">Testing</a></td><td>Test runners, release markers, and live gate evidence.</td></tr>
          <tr><td>Plugin author</td><td><a href="../glossary/">Glossary</a>, <a href="../compatibility/">Compatibility</a></td><td>Terms, generated surfaces, and host/runtime boundaries.</td></tr>
          <tr><td>Claude Code user</td><td><a href="../getting-started/">Getting Started</a></td><td>How a Claude Code host activates Kay or Codex.</td></tr>
          <tr><td>Codex host user</td><td><a href="../getting-started/">Getting Started</a>, <a href="../compatibility/">Compatibility</a></td><td>How a Codex host activates Kay or Codex.</td></tr>
          <tr><td>Kay user</td><td><a href="../workflows/">Workflows</a>, <a href="../compatibility/">Compatibility</a></td><td>Kay runtime routing and provider selectors.</td></tr>
          <tr><td>Codex sidekick user</td><td><a href="../workflows/">Workflows</a>, <a href="../glossary/">Glossary</a></td><td>Local OpenAI Codex CLI delegation.</td></tr>
        </tbody>
      </table>

      <h2>How To Use This Matrix</h2>
      <ul>
        <li>Start with the row that matches your role.</li>
        <li>If you do not know your role, start with <a href="../start-here/">Start Here</a>.</li>
        <li>If you need exact terms, read <a href="../glossary/">Glossary</a>.</li>
        <li>If you need host/runtime differences, read <a href="../compatibility/">Compatibility</a>.</li>
      </ul>
""",
        prev_link='<a href="../start-here/" class="pnav-btn"><i data-lucide="arrow-left"></i> Start Here</a>',
        next_link='<a href="../glossary/" class="pnav-btn">Glossary <i data-lucide="arrow-right"></i></a>',
    ),
    "glossary": shell(
        "glossary",
        "Glossary",
        "Canonical terms for current Sidekick docs.",
        "Glossary",
        """
      <table class="ref-table">
        <thead><tr><th>Term</th><th>Meaning</th></tr></thead>
        <tbody>
          <tr><td><strong>Sidekick</strong></td><td>The Alo Labs plugin that gives Claude Code, Codex, and Cursor a shared delegation layer for supported coding sidekicks.</td></tr>
          <tr><td><strong>host AI</strong></td><td>The Claude Code, Codex, or Cursor session that plans, delegates, reviews, verifies, and communicates with the user.</td></tr>
          <tr><td><strong>sidekick</strong></td><td>A supported child runtime that performs bounded implementation work after activation. Current sidekicks are Kay and Codex.</td></tr>
          <tr><td><strong>Kay</strong></td><td>The Kay runtime installed and repaired through Sidekick. Kay tasks run through <code>kay exec</code>.</td></tr>
          <tr><td><strong>Codex sidekick</strong></td><td>The local OpenAI Codex CLI used as a child runtime through <code>codex exec</code>, pinned to <code>gpt-5.4-mini</code> with extra-high reasoning.</td></tr>
          <tr><td><strong>delegate</strong></td><td>To hand a bounded coding task from the host AI to the active sidekick.</td></tr>
          <tr><td><strong>active-sidekick</strong></td><td>The shared session selector at <code>~/.sidekick/sessions/&lt;session&gt;/active-sidekick</code>. It contains <code>kay</code> or <code>codex</code>.</td></tr>
          <tr><td><strong>marker</strong></td><td>A project-local file showing that a sidekick is active in the current host session.</td></tr>
          <tr><td><strong>Host verification</strong></td><td>The host-owned review pass that checks requirements, diffs, tests, integration behavior, assumptions, and failure classes before reporting completion.</td></tr>
          <tr><td><strong>generated host bundle</strong></td><td>A rendered skill surface under <code>agents/claude/</code>, <code>agents/codex/</code>, or <code>agents/cursor/</code>, produced from canonical files under <code>skills/</code>.</td></tr>
          <tr><td><strong>registry</strong></td><td><code>sidekicks/registry.json</code>, the shared metadata for runtime names, marker paths, commands, and install details.</td></tr>
          <tr><td><strong>release gate</strong></td><td>The test sequence that proves public docs, generated surfaces, manifests, hooks, and live sidekick paths are aligned.</td></tr>
        </tbody>
      </table>

      <h2>Canonical Rules</h2>
      <ul>
        <li>The host AI owns final correctness.</li>
        <li>Kay and Codex are mutually exclusive in a host session.</li>
        <li>Canonical workflow text lives under <code>skills/</code>.</li>
        <li>Generated host bundles are render outputs.</li>
        <li>Public docs should name only the supported sidekicks: Kay and Codex.</li>
      </ul>
""",
        prev_link='<a href="../audience/" class="pnav-btn"><i data-lucide="arrow-left"></i> Audience</a>',
        next_link='<a href="../compatibility/" class="pnav-btn">Compatibility <i data-lucide="arrow-right"></i></a>',
    ),
    "compatibility": shell(
        "compatibility",
        "Compatibility",
        "How the Sidekick contract maps across Claude Code, Codex, Cursor, Kay, and the Codex sidekick.",
        "Compatibility",
        """
      <h2>Matrix</h2>
      <table class="ref-table">
        <thead><tr><th>Concern</th><th>Claude Code host</th><th>Codex host</th><th>Cursor host</th><th>Kay sidekick</th><th>Codex sidekick</th></tr></thead>
        <tbody>
          <tr><td>Skill source</td><td>Rendered from <code>skills/</code> into <code>agents/claude/</code></td><td>Rendered into <code>agents/codex/</code></td><td>Rendered into <code>agents/cursor/</code></td><td><code>skills/kay-delegate/SKILL.md</code></td><td><code>skills/codex-delegate/SKILL.md</code></td></tr>
          <tr><td>Activation</td><td><code>/sidekick:kay</code> or <code>/sidekick:codex</code></td><td>Same</td><td>Same</td><td>Starts Kay mode</td><td>Starts Codex mode</td></tr>
          <tr><td>Stop command</td><td><code>/sidekick:kay-stop</code> or <code>/sidekick:codex-stop</code></td><td>Same</td><td>Same</td><td>Clears Kay mode</td><td>Clears Codex mode</td></tr>
          <tr><td>Child runtime</td><td>Host launches selected sidekick</td><td>Same</td><td>Same</td><td><code>kay exec</code></td><td><code>codex exec</code></td></tr>
          <tr><td>Model and provider</td><td>Host does not own sidekick model selection</td><td>Same</td><td>Same</td><td>OpenCode Go; <code>xiaomi</code>, <code>ocg</code>, <code>SIDEKICK_KAY_PROVIDER</code></td><td>Local Codex CLI, <code>gpt-5.4-mini</code>, extra-high reasoning</td></tr>
          <tr><td>Session state</td><td><code>CLAUDE_SESSION_ID</code></td><td><code>CODEX_THREAD_ID</code></td><td><code>SIDEKICK_SESSION_ID</code></td><td><code>.kay/sessions/&lt;session&gt;</code></td><td><code>.codex/sessions/&lt;session&gt;</code></td></tr>
          <tr><td>Hooks</td><td><code>hooks/hooks.json</code></td><td>Same</td><td><code>hooks/cursor-hooks.json</code></td><td>Through host hooks</td><td>Through host hooks</td></tr>
          <tr><td>Verification</td><td>Host-owned</td><td>Host-owned</td><td>Host-owned</td><td>Reviewed by host</td><td>Reviewed by host</td></tr>
        </tbody>
      </table>

      <h2>Kay compatibility aliases</h2>
      <p>Kay is the primary runtime identity. Public docs and new workflows should use Kay names:</p>
      <div class="code-block">/sidekick:kay
/sidekick:kay xiaomi
/sidekick:kay ocg
/sidekick:kay-stop</div>

      <h2>Codex sidekick compatibility</h2>
      <p>The Codex sidekick is the local OpenAI Codex CLI, not a Kay alias:</p>
      <div class="code-block">/sidekick:codex
/sidekick:codex-stop</div>

      <h2>Generated surface compatibility</h2>
      <p>Refresh generated host bundles from canonical skills:</p>
      <div class="code-block">bash scripts/sync-host-surfaces.sh</div>
""",
        prev_link='<a href="../glossary/" class="pnav-btn"><i data-lucide="arrow-left"></i> Glossary</a>',
        next_link='<a href="../testing/" class="pnav-btn">Testing <i data-lucide="arrow-right"></i></a>',
    ),
    "testing": shell(
        "testing",
        "Testing",
        "Current Sidekick test strategy for Kay and Codex delegation.",
        "Testing",
        """
      <p>Sidekick is a Shell/Bash and Markdown project. Tests are Bash scripts under <code>tests/</code>, and the public site has dedicated contract checks so docs stay aligned with supported sidekicks.</p>

      <h2>Main Commands</h2>
      <div class="code-block"># Strict non-live unit and integration suites
bash tests/run_unit.bash

# Skip-safe local sweep
bash tests/run_all.bash

# Live release gate for the local Codex sidekick path
bash tests/run_in_kay.bash SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash</div>

      <h2>Test Pyramid</h2>
      <table class="ref-table">
        <thead><tr><th>Tier</th><th>Script</th><th>Purpose</th></tr></thead>
        <tbody>
          <tr><td>Strict unit and integration</td><td><code>tests/run_unit.bash</code></td><td>Static, hook, installer, manifest, generated-surface, docs, and runner-contract checks.</td></tr>
          <tr><td>Skip-safe local sweep</td><td><code>tests/run_all.bash</code></td><td>Unit checks plus live wrappers in skip-safe mode when live env vars are absent.</td></tr>
          <tr><td>Live Codex release gate</td><td><code>tests/run_in_kay.bash SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash</code></td><td>Release-authorizing live path for delegated Codex work.</td></tr>
        </tbody>
      </table>

      <h2>Public Site Contract Tests</h2>
      <table class="ref-table">
        <thead><tr><th>Suite</th><th>Coverage</th></tr></thead>
        <tbody>
          <tr><td><code>tests/test_homepage_sidekicks.bash</code></td><td>Homepage names Kay, Codex, Cursor, activation commands, host verification, and release evidence.</td></tr>
          <tr><td><code>tests/test_help_site_navigation.bash</code></td><td>Help pages exist, share navigation, document Kay/Codex workflows.</td></tr>
          <tr><td><code>tests/test_docs_contract.bash</code></td><td>Public Markdown docs align with the current Sidekick contract.</td></tr>
        </tbody>
      </table>

      <h2>Host Verification Coverage</h2>
      <p>Verification should catch missed requirements, integration errors, regressions, wrong logic, syntax errors, wrong files, unverified assumptions, knowledge gaps, misunderstood task scope, incomplete trials, provider API failures, and external execution failures.</p>
""",
        prev_link='<a href="../compatibility/" class="pnav-btn"><i data-lucide="arrow-left"></i> Compatibility</a>',
        next_link='<a href="../decisions/" class="pnav-btn">Decisions <i data-lucide="arrow-right"></i></a>',
    ),
    "decisions": shell(
        "decisions",
        "Architecture Decisions",
        "Durable decision records for docs-system and plugin-architecture choices.",
        "Decisions",
        """
      <h2>Index</h2>
      <table class="ref-table">
        <thead><tr><th>ADR</th><th>Status</th><th>Notes</th></tr></thead>
        <tbody>
          <tr><td><a href="#adr-2026-05-08">2026-05-08 Docs System</a></td><td>Accepted</td><td>Reader model, taxonomy, start-here navigation, glossary, compatibility matrix, and docs verification layer.</td></tr>
        </tbody>
      </table>

      <h2 id="adr-2026-05-08">ADR 2026-05-08: Docs System Upgrade</h2>
      <p><strong>Status:</strong> Accepted · <strong>Date:</strong> 2026-05-08</p>

      <h3>Context</h3>
      <p>Sidekick's docs scheme kept the repository organized, but readers still needed a clearer path from role or task to the right document. The docs also needed a canonical glossary, compatibility matrix, and durable place for docs-system decisions.</p>

      <h3>Decision</h3>
      <p>Keep <code>site/doc-scheme.md</code> as the placement contract, then add a reader-first layer:</p>
      <ul>
        <li><a href="../start-here/">Start Here</a> for task-first navigation.</li>
        <li><a href="../audience/">Audience</a> for reader roles and entry points.</li>
        <li><a href="../glossary/">Glossary</a> for canonical terms.</li>
        <li><a href="../compatibility/">Compatibility</a> for host and sidekick differences.</li>
        <li>This decisions page for durable docs-system choices.</li>
      </ul>
      <p>The public Help section remains the task-oriented surface and links back to these docs.</p>

      <h3>Consequences</h3>
      <ul>
        <li>New readers have a single page that tells them where to begin.</li>
        <li>Canonical terms stop drifting across docs.</li>
        <li>Runtime differences are visible in one place.</li>
        <li>Important docs decisions have a stable home separate from knowledge notes.</li>
      </ul>

      <h2>Format</h2>
      <p>Each ADR should answer: what problem are we solving, what decision did we make, what alternatives did we reject, and what are the consequences. Keep ADRs short, dated, and specific.</p>
""",
        prev_link='<a href="../testing/" class="pnav-btn"><i data-lucide="arrow-left"></i> Testing</a>',
    ),
}


def main() -> None:
    for slug, html in PAGES.items():
        out = HELP / slug / "index.html"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(html, encoding="utf-8")
        print(f"wrote {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

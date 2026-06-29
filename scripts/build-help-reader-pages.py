#!/usr/bin/env python3
"""Generate help reader HTML pages using the pre-revamp Sidekick site shell."""

from __future__ import annotations

import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "site" / "help"

SHARED_STYLES = """
.ref-table{width:100%;border-collapse:collapse;margin-bottom:24px;font-size:.85rem}
.ref-table th{text-align:left;padding:10px 16px;background:var(--bg-code);font-size:.75rem;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:var(--text-dim);border-bottom:1px solid var(--border)}
.ref-table td{padding:12px 16px;border-bottom:1px solid var(--border);color:var(--text-secondary);vertical-align:top}
.ref-table code{font-family:var(--font-mono);font-size:.88em;background:var(--bg-code);padding:2px 6px;border-radius:4px}
""".strip()

PAGES = [
    {
        "slug": "start-here",
        "title": "Start Here",
        "description": "The fastest path through current Sidekick docs — pick install, delegate, debug, or release.",
        "hero": "The question-first entry point when you do not yet know which Sidekick doc to read.",
        "body": """
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
        "nav": '<div class="page-nav-bottom"><span></span><a href="../getting-started/" class="pnav-btn">Getting Started <i data-lucide="arrow-right"></i></a></div>',
    },
    {
        "slug": "audience",
        "title": "Audience",
        "description": "Who each current Sidekick document is for, and where to start.",
        "hero": "Reader matrix for new users, maintainers, release operators, and runtime-specific paths.",
        "body": """
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
        "nav": '<div class="page-nav-bottom"><a href="../start-here/" class="pnav-btn"><i data-lucide="arrow-left"></i> Start Here</a><a href="../glossary/" class="pnav-btn">Glossary <i data-lucide="arrow-right"></i></a></div>',
    },
    {
        "slug": "glossary",
        "title": "Glossary",
        "description": "Canonical terms for current Sidekick docs.",
        "hero": "Single source of truth for Sidekick, Kay, Codex sidekick, delegation, and verification terms.",
        "body": """
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
        "nav": '<div class="page-nav-bottom"><a href="../audience/" class="pnav-btn"><i data-lucide="arrow-left"></i> Audience</a><a href="../compatibility/" class="pnav-btn">Compatibility <i data-lucide="arrow-right"></i></a></div>',
    },
    {
        "slug": "compatibility",
        "title": "Compatibility",
        "description": "How the current Sidekick contract maps across Claude Code, Codex, Cursor, Kay, and the Codex sidekick.",
        "hero": "Host and sidekick differences in one matrix — activation, runtime routing, session state, and hooks.",
        "body": """
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
        "nav": '<div class="page-nav-bottom"><a href="../glossary/" class="pnav-btn"><i data-lucide="arrow-left"></i> Glossary</a><a href="../testing/" class="pnav-btn">Testing <i data-lucide="arrow-right"></i></a></div>',
    },
    {
        "slug": "testing",
        "title": "Testing",
        "description": "Current Sidekick test strategy for Kay and Codex delegation.",
        "hero": "Unit, integration, live release gates, and public site contract checks.",
        "body": """
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
        "nav": '<div class="page-nav-bottom"><a href="../compatibility/" class="pnav-btn"><i data-lucide="arrow-left"></i> Compatibility</a><a href="../decisions/" class="pnav-btn">Decisions <i data-lucide="arrow-right"></i></a></div>',
    },
    {
        "slug": "decisions",
        "title": "Decisions",
        "description": "Architecture decision records for important docs-system and plugin-architecture choices.",
        "hero": "Durable decision records for the docs reader model, glossary, and compatibility layer.",
        "body": """
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
        "nav": '<div class="page-nav-bottom"><a href="../testing/" class="pnav-btn"><i data-lucide="arrow-left"></i> Testing</a><a href="../" class="pnav-btn">Help Center <i data-lucide="arrow-right"></i></a></div>',
    },
]


def render(page: dict[str, str]) -> str:
    title = page["title"]
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="dark light">
<script>(()=>{{const theme=localStorage.getItem('sidekick-theme-v2');document.documentElement.setAttribute('data-theme',theme==='light'?'light':'dark');}})();</script>
<title>{title} — Sidekick Help</title>
<meta name="description" content="{page['description']}">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@300;400;500;600;700&family=Roboto:ital,wght@0,300;0,400;0,700;1,400&family=Roboto+Mono:wght@300;400;500;700&display=swap" rel="stylesheet">
<link rel="stylesheet" href="../tokens.css">
<link rel="icon" href="../../og-image.png" type="image/png">
<style>
*,*::before,*::after{{box-sizing:border-box;margin:0;padding:0}}
html{{scroll-behavior:smooth;-webkit-font-smoothing:antialiased}}
body{{font-family:var(--font-sans);background:var(--bg-page);color:var(--text-primary);line-height:1.7;overflow-x:hidden}}
h1,h2,h3,h4,h5,h6,.logo,.nav-logo,.section-title,.section-label,.tagline,.btn,.tag,.nav-cta,.hero-tagline-caps,.version-badge{{font-family:var(--font-heading)}}
.container{{max-width:860px;margin:0 auto;padding:0 24px}}
.container-wide{{max-width:1100px;margin:0 auto;padding:0 24px}}
nav{{position:fixed;top:0;left:0;right:0;z-index:100;background:var(--nav-bg);backdrop-filter:blur(20px);border-bottom:1px solid var(--border);padding:0 24px}}
nav .nav-inner{{max-width:1100px;margin:0 auto;display:flex;align-items:center;justify-content:space-between;height:64px}}
.nav-logo{{font-weight:800;font-size:1rem;color:var(--text-primary);text-decoration:none;letter-spacing:0}}
.nav-breadcrumb{{font-size:.85rem;color:var(--text-secondary);display:flex;align-items:center;gap:8px}}
.nav-breadcrumb a{{color:var(--text-secondary);text-decoration:none}}
.nav-breadcrumb a:hover{{color:var(--accent-light)}}
.nav-breadcrumb .sep{{color:var(--text-dim)}}
.nav-right{{display:flex;align-items:center;gap:16px}}
.theme-btn{{background:none;border:1px solid var(--border);border-radius:8px;cursor:pointer;color:var(--text-secondary);transition:all .2s;display:flex;align-items:center;justify-content:center;width:34px;height:34px}}
.theme-btn:hover{{border-color:var(--accent);color:var(--accent-light)}}
.page-hero{{background:var(--bg-hero);padding:120px 24px 64px;position:relative;overflow:hidden}}
.page-hero::before{{content:'';position:absolute;top:-200px;right:-200px;width:500px;height:500px;border-radius:50%;background:radial-gradient(circle,var(--accent-faint) 0%,transparent 70%)}}
.page-hero .container{{position:relative;z-index:1}}
.breadcrumb-nav{{font-size:.9rem;color:var(--text-dim);margin-bottom:24px;display:flex;align-items:center;gap:8px}}
.breadcrumb-nav a{{color:var(--text-dim);text-decoration:none}}
.breadcrumb-nav a:hover{{color:var(--accent-light)}}
.page-hero h1{{font-size:clamp(1.8rem,3.5vw,2.8rem);font-weight:900;letter-spacing:0;margin-bottom:16px;line-height:1.1}}
.page-hero p{{font-size:1rem;color:var(--text-secondary);max-width:560px;line-height:1.7}}
.doc-layout{{padding:64px 0}}
.doc-content h2{{font-size:1.5rem;font-weight:800;letter-spacing:0;margin-bottom:16px;margin-top:48px;padding-top:16px}}
.doc-content h2:first-child{{margin-top:0}}
.doc-content h3{{font-size:1.1rem;font-weight:700;margin-bottom:12px;margin-top:32px;color:var(--text-primary)}}
.doc-content p{{margin-bottom:16px;color:var(--text-secondary);line-height:1.8}}
.doc-content ul,.doc-content ol{{margin-bottom:16px;padding-left:20px;color:var(--text-secondary)}}
.doc-content li{{margin-bottom:6px;line-height:1.7}}
.doc-content strong{{color:var(--text-primary)}}
.doc-content a{{color:var(--accent-light);text-decoration:none}}
.doc-content a:hover{{text-decoration:underline}}
.callout{{border-radius:var(--radius);padding:20px 24px;margin-bottom:24px;display:flex;gap:14px;align-items:flex-start}}
.callout-info{{background:var(--accent-faint);border:1px solid var(--accent-border)}}
.callout-icon{{font-size:1.1rem;flex-shrink:0;margin-top:1px}}
.callout-body{{font-size:.875rem;color:var(--text-secondary);line-height:1.7}}
.callout-body strong{{color:var(--text-primary)}}
.code-block{{background:var(--bg-code);border:1px solid var(--border);border-radius:var(--radius-sm);padding:20px 24px;font-family:var(--font-mono);font-size:1rem;line-height:1.9;color:var(--text-secondary);overflow-x:auto;white-space:pre-wrap;margin-bottom:20px}}
{SHARED_STYLES}
footer{{border-top:1px solid var(--border);padding:40px 0;color:var(--text-dim);font-size:.85rem}}
.footer-inner{{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:16px}}
footer a{{color:var(--text-secondary);text-decoration:none}}
footer a:hover{{color:var(--accent-light)}}
.footer-links{{display:flex;gap:24px;flex-wrap:wrap}}
.page-nav-bottom{{display:flex;justify-content:space-between;flex-wrap:wrap;gap:12px;padding-top:48px;border-top:1px solid var(--border);margin-top:48px}}
.pnav-btn{{display:flex;align-items:center;gap:8px;padding:12px 24px;border-radius:var(--radius);background:var(--bg-card);border:1px solid var(--border);text-decoration:none;color:var(--text-secondary);font-size:.875rem;font-weight:600;transition:all .2s}}
.pnav-btn:hover{{border-color:var(--accent);color:var(--accent-light)}}
svg.lucide{{display:inline-block;vertical-align:middle;width:1em;height:1em;stroke-width:1.5;stroke:currentColor;fill:none;stroke-linecap:round;stroke-linejoin:round}}
</style>
</head>
<body>

<nav>
  <div class="nav-inner">
    <div style="display:flex;align-items:center;gap:16px">
      <a href="../../" class="nav-logo">Sidekick</a>
      <span class="nav-breadcrumb"><span class="sep">/</span><a href="../">Help</a><span class="sep">/</span>{title}</span>
    </div>
    <div class="nav-right">
      <button class="theme-btn" onclick="toggleTheme()" id="theme-btn" aria-label="Toggle theme">
        <span id="icon-sun" style="display:none"><svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M6.34 17.66l-1.41 1.41M19.07 4.93l-1.41 1.41"/></svg></span>
        <span id="icon-moon"><svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg></span>
      </button>
    </div>
  </div>
</nav>

<div class="page-hero">
  <div class="container">
    <div class="breadcrumb-nav"><a href="../">Help Center</a><span>/</span><span>{title}</span></div>
    <h1>{title}</h1>
    <p>{page['hero']}</p>
  </div>
</div>

<div class="container">
  <div class="doc-layout">
    <div class="doc-content">
{page['body'].rstrip()}
      {page['nav']}
    </div>
  </div>
</div>

<footer>
  <div class="container-wide">
    <div class="footer-inner">
      <div><span style="font-weight:700;color:var(--text-secondary)">Sidekick</span> Help Center</div>
      <div class="footer-links">
        <a href="../">Help Home</a>
        <a href="../getting-started/">Getting Started</a>
        <a href="../concepts/">Concepts</a>
        <a href="../workflows/">Workflows</a>
        <a href="../reference/">Reference</a>
        <a href="../troubleshooting/">Troubleshooting</a>
        <a href="../../">Sidekick Home</a>
        <a href="https://github.com/alo-exp/sidekick" target="_blank" rel="noopener noreferrer">GitHub</a>
      </div>
    </div>
  </div>
</footer>

<script src="https://unpkg.com/lucide@0.469.0/dist/umd/lucide.min.js" integrity="sha384-hJnF5AwidE18GSWTAGHv3ByzzvfNZ1Tcx5y1UUV3WkauuMCEzBJBMSwSt/PUPXnM" crossorigin="anonymous"></script>
<script>
function applyTheme(dark){{
  document.documentElement.setAttribute('data-theme',dark?'dark':'light');
  document.getElementById('icon-sun').style.display=dark?'none':'';
  document.getElementById('icon-moon').style.display=dark?'':'none';
  localStorage.setItem('sidekick-theme-v2',dark?'dark':'light');
  localStorage.removeItem('sidekick-theme');
}}
function toggleTheme(){{applyTheme(document.documentElement.getAttribute('data-theme')!=='dark')}}
(function(){{const s=localStorage.getItem('sidekick-theme-v2');applyTheme(s==='light'?false:true)}})();
lucide.createIcons();
</script>
</body>
</html>
"""


def main() -> None:
    for page in PAGES:
        dest = OUT / page["slug"] / "index.html"
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(render(page), encoding="utf-8")
        print(f"wrote {dest.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

/* Sidekick Help — full-text search */
'use strict';
(function () {

var IDX = [
  // ── DOCS NAVIGATION ───────────────────────────────────────────
  { page:'Start Here', url:'../START-HERE.md', anchor:'start-here',
    title:'Start Here — pick the right doc',
    text:'Question-first navigation for install, delegate, debug, release, extend, and migrate. Use this page when you do not know where to begin.' },
  { page:'Audience', url:'../AUDIENCE.md', anchor:'audience',
    title:'Audience — who each doc is for',
    text:'Reader matrix for new users, maintainers, release operators, plugin authors, Claude users, Kay users, and Kay operators.' },
  { page:'Glossary', url:'../GLOSSARY.md', anchor:'glossary',
    title:'Glossary — canonical terms',
    text:'Single source of truth for Sidekick, Forge, Kay, host Codex, delegate, skill, command, bridge, and wrapper.' },
  { page:'Compatibility', url:'../COMPATIBILITY.md', anchor:'compatibility',
    title:'Compatibility — Claude, Codex, and Kay',
    text:'Compatibility matrix covering shared vs agent-specific behavior, skill source of truth, command discoverability, and provider / execution identity.' },
  { page:'ADR', url:'../ADR/README.md', anchor:'adr',
    title:'ADR index — durable docs decisions',
    text:'Entry point for durable decision records about the docs system, taxonomy, glossary, compatibility, and verification model.' },
  { page:'Help Center', url:'../', anchor:'support',
    title:'Sidekick ships Forge and Kay',
    text:'Claude Code and Codex can both route work to either agent: use /forge for Forge mode or Kay through kay exec. The legacy code alias remains compatibility-only. OpenCode Go remains Kay multi-AI compatibility.' },

  // ── GETTING STARTED ───────────────────────────────────────────
  { page:'Getting Started', url:'getting-started/', anchor:'what-is-sidekick',
    title:'What is Sidekick?',
    text:'Sidekick is a Claude Code and Codex plugin that gives the active host two implementation agents. Claude Code and Codex can both route work to Forge or Kay; Kay uses the Every Code agent path with MiniMax M2.7 defaults and OpenCode Go compatibility.' },
  { page:'Getting Started', url:'getting-started/', anchor:'prerequisites',
    title:'Prerequisites — host and provider key',
    text:'Required: Claude Code or Codex host, provider key for MiniMax or Forge provider config, Node.js 18 or later for Claude Code. Forge and Kay readiness is checked when delegation starts for the current session.' },
  { page:'Getting Started', url:'getting-started/', anchor:'install',
    title:'Installing Sidekick',
    text:'Install Sidekick through the host plugin surface. Claude Code uses /plugin install alo-labs/sidekick. Codex / Kay uses codex plugin marketplace add alo-labs/sidekick. Restart the host so the hook surface loads before starting Forge or Kay delegation.' },
  { page:'Getting Started', url:'getting-started/', anchor:'health-check',
    title:'Forge readiness check — verify current session',
    text:'Run /forge to activate and run the current-session readiness check. It verifies the forge binary, forge info provider output, ~/forge/.credentials.json credential array, and ~/forge/.forge.toml provider_id/model_id. Kay users verify kay --version, kay exec --help, and MiniMax login.' },
  { page:'Getting Started', url:'getting-started/', anchor:'kay-path',
    title:'Your first Kay task',
    text:'Kay uses native execution. Use kay exec --full-auto as the primary path; older binary names are compatibility-only. Kay preserves .kay/conversations.idx lookup metadata.' },
  { page:'Getting Started', url:'getting-started/', anchor:'first-forge',
    title:'Your first /forge task — 4-step delegation',
    text:'1 Describe task in plain language. 2 The host composes 5-field prompt OBJECTIVE CONTEXT DESIRED STATE SUCCESS CRITERIA INJECTED SKILLS and submits to Forge. 3 The host monitors for error signal wrong output or stall. 4 Review confirmed output.' },
  { page:'Getting Started', url:'getting-started/', anchor:'agents-md-bootstrap',
    title:'AGENTS.md bootstrap on first /forge',
    text:'On first /forge if no non-empty AGENTS.md exists Sidekick creates one. Contains default Forge output format expectations STATUS FILES_CHANGED ASSUMPTIONS PATTERNS_DISCOVERED and delegation principles. Later mentoring writes only new deduplicated instructions; L3 AGENTS_UPDATE text is proposed for confirmation.' },

  // ── CORE CONCEPTS ─────────────────────────────────────────────
  { page:'Core Concepts', url:'concepts/', anchor:'delegation',
    title:'Forge delegation mode — host as advisor and mentor',
    text:'When you invoke /forge the host activates Forge delegation mode for the current session. The host does not write code directly. It composes structured prompts submits to Forge monitors output reviews results handles failures and turns corrections into AGENTS.md guidance. Persists until /forge-stop.' },
  { page:'Core Concepts', url:'concepts/', anchor:'kay-delegation',
    title:'Kay delegation model — native execution',
    text:"Kay is Sidekick's execution agent for the OSS Codex lineage. Primary path is kay exec --full-auto. Sidekick adds package wiring, a session-scoped .kay marker, .kay/conversations.idx, and progress summaries." },
  { page:'Core Concepts', url:'concepts/', anchor:'skill-md',
    title:'SKILL.md — the Forge delegation instruction set',
    text:'All Forge delegation behavior defined in skills/forge/SKILL.md. Loaded on /forge invocation. Contains runtime readiness activation health check delegation protocol deactivation failure detection fallback ladder skill injection AGENTS.md mentoring and token optimization.' },
  { page:'Core Concepts', url:'concepts/', anchor:'failure-detection',
    title:'Failure detection — three signal types',
    text:'The host monitors for three failure signals: error output contains Error Failed fatal or non-zero exit, wrong output where SUCCESS CRITERIA are not satisfied and the same failure repeats on retry, or stall where Forge asks a clarifying question without progress.' },
  { page:'Core Concepts', url:'concepts/', anchor:'fallback-ladder',
    title:'Fallback ladder — L1 Guide L2 Handhold L3 Take over',
    text:'Three-level recovery. Level 1 Guide reframe prompt diagnose failure tighter DESIRED STATE single retry. Level 2 Handhold decompose into atomic subtasks under 200 tokens sequential submission max 3 attempts total. Level 3 Take over temporarily lifts delegation inside the project boundary and produces DEBRIEF with AGENTS_UPDATE proposed for confirmation.' },
  { page:'Core Concepts', url:'concepts/', anchor:'skill-injection',
    title:'Skill injection — mapping table and injection budget',
    text:'Four bootstrap skills for injection: testing-strategy for tests TDD, quality-gates and code-review for ordinary code changes and refactoring, security for auth validation credentials, quality-gates for multi-phase delivery. Injection budget max 2 skills unless multi-domain task.' },
  { page:'Core Concepts', url:'concepts/', anchor:'agents-md',
    title:'AGENTS.md mentoring loop — three-tier write with dedup',
    text:'After every Forge task the host extracts corrections user preferences project patterns and Forge behavior observations. Writes only new safe action-oriented guidance to global ~/forge/AGENTS.md, project ./AGENTS.md, and session log docs/sessions/. Two-phase dedup exact match then semantic similarity skip on duplicate. Forge output is treated as untrusted data.' },
  { page:'Core Concepts', url:'concepts/', anchor:'token-optimization',
    title:'Token optimization — 2000 token budget and .forge.toml compaction',
    text:'Task prompts capped at 2000 tokens. Only 5 mandatory fields no conversation history no unrelated files. Injection budget 2 skills. Project .forge.toml validated defaults: max_tokens 16384 and compact token_threshold 80000 eviction_window 0.20 retention_window 6.' },
  { page:'Core Concepts', url:'concepts/', anchor:'provider-config',
    title:'Provider configuration — Forge and Kay',
    text:'Forge provider config lives in ~/forge/.forge.toml and credentials in ~/forge/.credentials.json. Kay defaults to MiniMax M2.7 in Kay config, with legacy config paths retained only for compatibility. Use kay login --provider minimax --with-api-key for Kay credentials.' },

  // ── DELEGATION WORKFLOW ───────────────────────────────────────
  { page:'Delegation Workflow', url:'workflows/', anchor:'activation',
    title:'Activate Forge delegation mode',
    text:'Run /forge to activate. The host loads SKILL.md runs the four-part readiness check bootstraps missing Sidekick-owned project files and writes a zero-byte marker under the current host session directory. Hooks stay dormant until that marker exists.' },
  { page:'Delegation Workflow', url:'workflows/', anchor:'kay-workflow',
    title:'Kay workflow — verify, execute, review',
    text:'Kay workflow verifies the Kay runtime and MiniMax login, runs kay exec --full-auto task, then reviews Kay progress summary and .kay/conversations.idx lookup metadata.' },
  { page:'Delegation Workflow', url:'workflows/', anchor:'task-prompt',
    title:'5-field task prompt structure',
    text:'OBJECTIVE one-sentence what Forge must do. CONTEXT only relevant files current state. DESIRED STATE specific verifiable outcome. SUCCESS CRITERIA checklist to verify success. INJECTED SKILLS up to 2 bootstrap skills. Total 2000 tokens max. The host composes from plain-language description.' },
  { page:'Delegation Workflow', url:'workflows/', anchor:'fallback',
    title:'Fallback ladder handling — L1 L2 L3 escalation',
    text:'L1 Guide diagnose rewrite prompt resubmit once. L2 Handhold decompose atomic subtasks submit sequentially up to 3 attempts total. L3 Take over host implements directly inside project boundary and produces DEBRIEF with TASK FORGE_FAILURE LEARNED AGENTS_UPDATE fields. AGENTS_UPDATE is proposed for confirmation.' },
  { page:'Delegation Workflow', url:'workflows/', anchor:'agents-update',
    title:'Post-task AGENTS.md update',
    text:'After every Forge task completion the host extracts learnings and writes only new deduplicated AGENTS.md guidance. Successful tasks can contribute preferences and project patterns. L3 takeovers produce DEBRIEF AGENTS_UPDATE text for confirmation. Session log written to docs/sessions/.' },

  // ── COMMAND REFERENCE ─────────────────────────────────────────
  { page:'Reference', url:'reference/', anchor:'forge-commands',
    title:'Delegation skills — forge and Kay lifecycle',
    text:'/forge activates Forge delegation mode for the current session and arms hooks after health check. /forge-stop removes the Forge marker. kay-delegate or sidekick:kay-delegate uses the Kay workflow for kay runtime tasks. /kay-stop removes the Kay marker.' },
  { page:'Reference', url:'reference/', anchor:'kay-commands',
    title:'Kay runtime commands',
    text:'kay exec --full-auto is the primary Kay execution command. kay login --provider minimax --with-api-key configures MiniMax credentials. Older binary names are compatibility-only.' },
  { page:'Reference', url:'reference/', anchor:'forge-toml',
    title:'.forge.toml config — model credentials compaction providers',
    text:'.forge.toml created on first /forge in project root if absent. Contains compaction settings only: max_tokens 16384, compact token_threshold 80000, eviction_window 0.20, retention_window 6. API credentials stored globally in ~/forge/.credentials.json as array entries with id and auth_details, and provider/model config lives in ~/forge/.forge.toml. Forge supports open_router with qwen/qwen3-coder-plus and minimax with MiniMax-M2.7.' },
  { page:'Getting Started', url:'getting-started/', anchor:'prerequisites',
    title:'MiniMax Coding provider — Forge direct provider path',
    text:'MiniMax Coding is a direct Forge provider path. Get an API key at https://platform.minimax.io/subscribe/token-plan. The host writes ~/forge/.credentials.json with id minimax and ~/forge/.forge.toml with provider_id minimax and model_id MiniMax-M2.7 during setup.' },
  { page:'Reference', url:'reference/', anchor:'bootstrap-skills',
    title:'Bootstrap skills catalog — testing-strategy code-review security quality-gates',
    text:'Four pre-installed skills at .forge/skills/. testing-strategy for tests TDD coverage. code-review for quality refactoring review-driven changes. security for auth input validation secrets. quality-gates for multi-phase delivery release prep.' },
  { page:'Reference', url:'reference/', anchor:'agents-md-format',
    title:'AGENTS.md format — categories and structure',
    text:'AGENTS.md uses action-oriented categorized format. Global instructions live in ~/forge/AGENTS.md, project instructions live in ./AGENTS.md, and session logs append to docs/sessions/YYYY-MM-DD-session.md when new guidance exists. Categories include Code Style, Testing, Git Workflow, Forge Behavior, Project Conventions, Task Patterns, and Forge Corrections. Plain markdown editable at any time.' },
  { page:'Reference', url:'reference/', anchor:'file-structure',
    title:'File structure — all Sidekick-managed files',
    text:'skills/forge/SKILL.md and skills/codex-delegate/SKILL.md instruction bodies. .forge.toml compaction config; credentials live in ~/forge/.credentials.json. .forge and .kay indexes preserve task lookup metadata. Kay config uses ~/.kay/config.toml, with legacy ~/.code and ~/.codex compatibility.' },

  // ── TROUBLESHOOTING ───────────────────────────────────────────
  { page:'Troubleshooting', url:'troubleshooting/', anchor:'health-check',
    title:'Readiness check failures — provider credentials, model unavailable',
    text:'Forge provider or credentials not valid: check forge binary, forge info, ~/forge/.credentials.json array of id and auth_details entries, and ~/forge/.forge.toml provider_id and model_id. Model not available: verify open_router qwen/qwen3-coder-plus or minimax MiniMax-M2.7 provider pair. Bootstrap skills not loaded: reinstall /plugin install alo-labs/sidekick.' },
  { page:'Troubleshooting', url:'troubleshooting/', anchor:'kay-runtime',
    title:'Kay runtime issues — kay exec unavailable or MiniMax login missing',
    text:'If kay exec is unavailable, check kay --version and kay exec --help. Reinstall Sidekick or the Kay runtime if the primary binary is unavailable. If MiniMax login is missing, run kay login --provider minimax --with-api-key.' },
  { page:'Troubleshooting', url:'troubleshooting/', anchor:'fallback',
    title:'Fallback ladder not triggering — escalation issues',
    text:'Failure signal not recognized describe to the host what went wrong manually trigger fallback. L1 retry same wrong output is expected L1 is single retry then escalates to L2. L3 takeover no DEBRIEF ask the host explicitly to produce DEBRIEF.' },
  { page:'Troubleshooting', url:'troubleshooting/', anchor:'agents-md',
    title:'AGENTS.md issues — dedup false positives, wrong bootstrap content',
    text:'Instructions not added: dedup found semantically similar entry correct behavior. Wrong bootstrap content: edit AGENTS.md directly plain markdown host uses edits on next /forge. Global ~/forge/AGENTS.md not found: optional created automatically on first cross-session write.' },
  { page:'Troubleshooting', url:'troubleshooting/', anchor:'recovery',
    title:'Session recovery — stuck session, L3 delegation not resuming',
    text:'Stuck session deactivate and reactivate: /forge-stop then /forge. After L3 takeover the Forge marker remains active for next task. If the host implements directly instead of delegating say re-enter Forge delegation mode.' },
  { page:'Troubleshooting', url:'troubleshooting/', anchor:'reinstall',
    title:'Reinstall and full reset — clean install, credentials reset',
    text:'Clean reinstall: /plugin install alo-labs/sidekick preserves AGENTS.md and docs/sessions/. Reset credentials: delete ~/forge/.credentials.json then /forge to guide through setup again. AGENTS.md and session logs always preserved.' },
];

function score(item, terms) {
  var text = (item.title + ' ' + item.text + ' ' + item.page).toLowerCase();
  var s = 0;
  terms.forEach(function(t) {
    if (text.indexOf(t) !== -1) {
      s += (item.title.toLowerCase().indexOf(t) !== -1) ? 3 : 1;
    }
  });
  return s;
}

function search(query) {
  if (!query || query.trim().length < 2) return [];
  var terms = query.toLowerCase().trim().split(/\s+/).filter(function(t){ return t.length > 1; });
  return IDX
    .map(function(item){ return { item: item, score: score(item, terms) }; })
    .filter(function(r){ return r.score > 0; })
    .sort(function(a, b){ return b.score - a.score; })
    .slice(0, 8)
    .map(function(r){ return r.item; });
}

function renderResults(results, query) {
  var list = document.getElementById('search-results-list');
  var section = document.getElementById('search-results-section');
  var main = document.getElementById('main-help-content');
  if (!list || !section) return;
  if (!results.length) {
    if (!section) return;
    section.style.display = 'block';
    if (main) main.style.display = 'none';
    list.innerHTML = '<p class="sr-none">No results for "<strong>' + escHtml(query) + '</strong>"</p>';
    return;
  }
  if (!section) return;
  section.style.display = 'block';
  if (main) main.style.display = 'none';
  list.innerHTML = results.map(function(r) {
    var excerpt = r.text.slice(0, 140) + '…';
    return '<a href="' + r.url + (r.anchor ? '#' + r.anchor : '') + '" class="sr-item">'
      + '<span class="sr-page">' + escHtml(r.page) + '</span>'
      + '<span class="sr-title">' + escHtml(r.title) + '</span>'
      + '<span class="sr-excerpt">' + escHtml(excerpt) + '</span>'
      + '</a>';
  }).join('');
}

function escHtml(s) {
  return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function clearSearch() {
  var section = document.getElementById('search-results-section');
  var main = document.getElementById('main-help-content');
  if (section) section.style.display = 'none';
  if (main) main.style.display = '';
}

document.addEventListener('DOMContentLoaded', function() {
  var input = document.getElementById('search-input');
  if (!input) return;
  var timer;
  input.addEventListener('input', function() {
    clearTimeout(timer);
    var q = input.value.trim();
    if (q.length < 2) { clearSearch(); return; }
    timer = setTimeout(function() {
      renderResults(search(q), q);
    }, 180);
  });
  input.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') { input.value = ''; clearSearch(); }
  });
});

})();

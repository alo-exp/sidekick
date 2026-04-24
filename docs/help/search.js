/* Sidekick Help — full-text search */
'use strict';
(function () {

var IDX = [
  // ── GETTING STARTED ───────────────────────────────────────────
  { page:'Getting Started', url:'/help/getting-started/', anchor:'what-is-sidekick',
    title:'What is Sidekick?',
    text:'Sidekick is a Claude Code plugin that gives Claude a team of specialized AI coding agents. Forge is the first sidekick — ForgeCode, the #2 ranked model on Terminal-Bench 2.0 with 81.8% score. Claude delegates entire coding tasks to Forge via structured prompts.' },
  { page:'Getting Started', url:'/help/getting-started/', anchor:'prerequisites',
    title:'Prerequisites — Claude Code, OpenRouter API key',
    text:'Required: Claude Code npm install -g anthropic claude-code. OpenRouter API key from openrouter.ai for Forge access. Node.js 18 or later. No separate Forge install needed — Sidekick auto-installs and configures ForgeCode.' },
  { page:'Getting Started', url:'/help/getting-started/', anchor:'install',
    title:'Installing Sidekick',
    text:'Install Sidekick inside Claude Code with /plugin install alo-exp/sidekick. Makes /forge skill available in all sessions. Works in any git repository. No project-specific setup required.' },
  { page:'Getting Started', url:'/help/getting-started/', anchor:'health-check',
    title:'Forge health check — verify connectivity',
    text:'Run /forge to activate and run health check. On first activation checks ~/forge/.credentials.json for API key and ~/forge/.forge.toml for provider config. Health check verifies Forge binary found, provider configured, credentials present, config valid, bootstrap skills loaded.' },
  { page:'Getting Started', url:'/help/getting-started/', anchor:'first-forge',
    title:'Your first /forge task — 4-step delegation',
    text:'1 Describe task in plain language. 2 Claude composes 5-field prompt OBJECTIVE CONTEXT DESIRED STATE SUCCESS CRITERIA INJECTED SKILLS and submits to Forge. 3 Claude monitors for error signal wrong output or stall. 4 Review confirmed output.' },
  { page:'Getting Started', url:'/help/getting-started/', anchor:'agents-md-bootstrap',
    title:'AGENTS.md bootstrap on first /forge',
    text:'On first /forge if no AGENTS.md exists Sidekick creates one. Contains default Forge output format expectations STATUS FILES_CHANGED ASSUMPTIONS PATTERNS_DISCOVERED and delegation principles. Edit at any time to add project-specific rules. Three tiers: global project session log.' },

  // ── CORE CONCEPTS ─────────────────────────────────────────────
  { page:'Core Concepts', url:'/help/concepts/', anchor:'delegation',
    title:'Forge delegation mode — Claude as task orchestrator',
    text:'When you invoke /forge Claude activates Forge delegation mode. Claude does not write code directly. Acts as task orchestrator composing structured prompts submitting to Forge monitoring output and handling failures. Persists until /forge:deactivate.' },
  { page:'Core Concepts', url:'/help/concepts/', anchor:'skill-md',
    title:'SKILL.md — the Forge delegation instruction set',
    text:'All Forge delegation behavior defined in skills/forge/SKILL.md. Loaded on /forge invocation. Contains activation health check delegation protocol deactivation failure detection fallback ladder skill injection AGENTS.md mentoring token optimization. 321 lines 8 sections.' },
  { page:'Core Concepts', url:'/help/concepts/', anchor:'failure-detection',
    title:'Failure detection — three signal types',
    text:'Claude monitors for three failure signals: error signal output contains Error Failed fatal or non-zero exit. Wrong output SUCCESS CRITERIA not satisfied on retry. Stall Forge asks clarifying question without making progress. Any signal triggers fallback ladder.' },
  { page:'Core Concepts', url:'/help/concepts/', anchor:'fallback-ladder',
    title:'Fallback ladder — L1 Guide L2 Handhold L3 Take over',
    text:'Three-level automatic recovery. Level 1 Guide reframe prompt diagnose failure tighter DESIRED STATE single retry. Level 2 Handhold decompose into atomic subtasks under 200 tokens sequential submission max 3 attempts. Level 3 Take over delegation restriction lifted Claude implements produces DEBRIEF.' },
  { page:'Core Concepts', url:'/help/concepts/', anchor:'skill-injection',
    title:'Skill injection — mapping table and injection budget',
    text:'Four bootstrap skills for injection: testing-strategy for tests TDD, code-review for quality refactoring, security for auth validation credentials, quality-gates for multi-phase delivery. Injection budget max 2 skills unless multi-domain task.' },
  { page:'Core Concepts', url:'/help/concepts/', anchor:'agents-md',
    title:'AGENTS.md mentoring loop — three-tier write with dedup',
    text:'After every Forge task Claude extracts corrections user preferences project patterns Forge behavior observations. Writes to three tiers: global ~/forge/AGENTS.md, project ./AGENTS.md, session log docs/sessions/. Two-phase dedup exact match then semantic similarity skip on duplicate.' },
  { page:'Core Concepts', url:'/help/concepts/', anchor:'token-optimization',
    title:'Token optimization — 2000 token budget and .forge.toml compaction',
    text:'Task prompts capped at 2000 tokens. Only 5 mandatory fields no conversation history no unrelated files. Injection budget 2 skills. .forge.toml validated defaults: token_threshold 80000 eviction_window 0.20 retention_window 6 max_tokens 16384.' },

  // ── DELEGATION WORKFLOW ───────────────────────────────────────
  { page:'Delegation Workflow', url:'/help/workflows/', anchor:'activation',
    title:'Activate Forge delegation mode',
    text:'Run /forge to activate. Claude loads SKILL.md runs health check bootstraps AGENTS.md if absent writes session state to ~/.claude/.forge-delegation-active and confirms activation. All subsequent tasks delegated to Forge.' },
  { page:'Delegation Workflow', url:'/help/workflows/', anchor:'task-prompt',
    title:'5-field task prompt structure',
    text:'OBJECTIVE one-sentence what Forge must do. CONTEXT only relevant files current state. DESIRED STATE specific verifiable outcome. SUCCESS CRITERIA checklist to verify success. INJECTED SKILLS up to 2 bootstrap skills. Total 2000 tokens max. Claude composes from plain-language description.' },
  { page:'Delegation Workflow', url:'/help/workflows/', anchor:'fallback',
    title:'Fallback ladder handling — L1 L2 L3 escalation',
    text:'L1 Guide diagnose rewrite prompt resubmit once. L2 Handhold decompose atomic subtasks submit sequentially up to 3 attempts. L3 Take over Claude implements directly produces DEBRIEF with TASK FORGE_FAILURE LEARNED AGENTS_UPDATE fields.' },
  { page:'Delegation Workflow', url:'/help/workflows/', anchor:'agents-update',
    title:'Post-task AGENTS.md update',
    text:'After every task success or L3 takeover Claude extracts learnings updates all three AGENTS.md tiers. Successful tasks preferences and project patterns. L3 takeovers DEBRIEF AGENTS_UPDATE applied. Duplicates detected and skipped. Session log written to docs/sessions/.' },

  // ── COMMAND REFERENCE ─────────────────────────────────────────
  { page:'Reference', url:'/help/reference/', anchor:'forge-commands',
    title:'/forge commands — activate deactivate status',
    text:'/forge activate Forge delegation mode runs health check. /forge:deactivate return to direct Claude implementation. /forge status show current activation state model and config summary.' },
  { page:'Reference', url:'/help/reference/', anchor:'forge-toml',
    title:'.forge.toml config — model API key compaction providers',
    text:'.forge.toml created on first /forge in project root. Contains compaction settings only: token_threshold 80000, eviction_window 0.20, retention_window 6, max_tokens 16384. API credentials stored globally in ~/forge/.credentials.json and ~/forge/.forge.toml. Two providers supported: open_router with qwen/qwen3-coder-plus and minimax with MiniMax-M2.7.' },
  { page:'Getting Started', url:'/help/getting-started/', anchor:'prerequisites',
    title:'MiniMax Coding provider — alternative to OpenRouter',
    text:'MiniMax Coding is an alternative provider to OpenRouter. Get an API key at platform.minimaxi.com. Claude writes ~/forge/.credentials.json with id minimax and ~/forge/.forge.toml with provider_id minimax and model_id MiniMax-M2.7 during setup.' },
  { page:'Reference', url:'/help/reference/', anchor:'bootstrap-skills',
    title:'Bootstrap skills catalog — testing-strategy code-review security quality-gates',
    text:'Four pre-installed skills at .forge/skills/. testing-strategy for tests TDD coverage. code-review for quality refactoring review-driven changes. security for auth input validation secrets. quality-gates for multi-phase delivery release prep.' },
  { page:'Reference', url:'/help/reference/', anchor:'agents-md-format',
    title:'AGENTS.md format — categories and structure',
    text:'AGENTS.md uses action-oriented categorized format. Categories: Code Style, Testing, Git Workflow, Forge Behavior, Project Conventions. Claude extracts and writes under these categories after each task. Plain markdown editable at any time.' },
  { page:'Reference', url:'/help/reference/', anchor:'file-structure',
    title:'File structure — all Sidekick-managed files',
    text:'skills/forge/SKILL.md delegation instruction set 321 lines. .forge.toml compaction config gitignored. ~/.claude/.forge-delegation-active active session state marker zero-byte. .forge/skills/ bootstrap skills. AGENTS.md project instructions. ~/forge/AGENTS.md global instructions. docs/sessions/ session logs.' },

  // ── TROUBLESHOOTING ───────────────────────────────────────────
  { page:'Troubleshooting', url:'/help/troubleshooting/', anchor:'health-check',
    title:'Health check failures — ForgeCode not reachable, model unavailable',
    text:'ForgeCode not reachable: invalid API key check ~/forge/.credentials.json api_key field verify at openrouter.ai/keys confirm ~/forge/.forge.toml has provider_id and model_id confirm credits. Model not available: check openrouter.ai/models for forge/forge-code availability. Bootstrap skills not loaded: reinstall /plugin install alo-exp/sidekick.' },
  { page:'Troubleshooting', url:'/help/troubleshooting/', anchor:'fallback',
    title:'Fallback ladder not triggering — escalation issues',
    text:'Failure signal not recognized describe to Claude what went wrong manually trigger fallback. L1 retry same wrong output is expected L1 is single retry auto-escalates to L2. L3 takeover no DEBRIEF ask Claude explicitly to produce DEBRIEF.' },
  { page:'Troubleshooting', url:'/help/troubleshooting/', anchor:'agents-md',
    title:'AGENTS.md issues — dedup false positives, wrong bootstrap content',
    text:'Instructions not added: dedup found semantically similar entry correct behavior. Wrong bootstrap content: edit AGENTS.md directly plain markdown Claude uses edits on next /forge. Global ~/forge/AGENTS.md not found: optional created automatically on first cross-session write.' },
  { page:'Troubleshooting', url:'/help/troubleshooting/', anchor:'recovery',
    title:'Session recovery — stuck session, L3 delegation not resuming',
    text:'Stuck session deactivate and reactivate: /forge:deactivate then /forge. After L3 takeover delegation resumes automatically for next task. If Claude implementing directly instead of delegating say re-enter Forge delegation mode.' },
  { page:'Troubleshooting', url:'/help/troubleshooting/', anchor:'reinstall',
    title:'Reinstall and full reset — clean install, credentials reset',
    text:'Clean reinstall: /plugin install alo-exp/sidekick preserves AGENTS.md and docs/sessions/. Reset credentials: delete ~/forge/.credentials.json then /forge to guide through setup again. AGENTS.md and session logs always preserved.' },
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

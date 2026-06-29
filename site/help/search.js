/* Sidekick Help - full-text search */
'use strict';
(function () {

var IDX = [
  // DOCS NAVIGATION
  { page:'Start Here', url:'start-here/', anchor:'start-here',
    title:'Start Here - pick the right doc',
    text:'Question-first navigation for install, delegate, debug, release, extend, and migrate. Use this page when you do not know where to begin.' },
  { page:'Audience', url:'audience/', anchor:'audience',
    title:'Audience - who each doc is for',
    text:'Reader matrix for new users, maintainers, release operators, plugin authors, Claude Code users, Codex host users, Kay users, and Codex sidekick users.' },
  { page:'Glossary', url:'glossary/', anchor:'glossary',
    title:'Glossary - canonical terms',
    text:'Single source of truth for Sidekick, Kay, Codex sidekick, Claude Code host, Codex host, delegate, skill, command, bridge, and wrapper.' },
  { page:'Compatibility', url:'compatibility/', anchor:'compatibility',
    title:'Compatibility - hosts and sidekicks',
    text:'Compatibility matrix covering Claude Code, Codex, and Cursor host surfaces, Kay and Codex execution sidekicks, skill source of truth, command discoverability, and runtime identity.' },
  { page:'Decisions', url:'decisions/', anchor:'adr',
    title:'ADR index - durable docs decisions',
    text:'Entry point for durable decision records about the docs system, taxonomy, glossary, compatibility, and verification model.' },
  { page:'Help Center', url:'../', anchor:'support',
    title:'Sidekick ships Kay and Codex',
    text:'Claude Code, Codex, and Cursor hosts can both activate Kay or Codex for the current session. Use /sidekick:kay for Kay mode and /sidekick:codex for Codex mode. The host plans, communicates, delegates, verifies, and owns final correctness.' },

  // GETTING STARTED
  { page:'Getting Started', url:'getting-started/', anchor:'what-is-sidekick',
    title:'What is Sidekick?',
    text:'Sidekick is a Claude Code, Codex, and Cursor plugin that gives the active host two implementation sidekicks. Kay routes work through the Kay runtime and kay exec. Codex routes work through the local OpenAI Codex CLI and codex exec.' },
  { page:'Getting Started', url:'getting-started/', anchor:'prerequisites',
    title:'Prerequisites - hosts and runtimes',
    text:'Required: Claude Code or Codex host, a working Kay runtime for Kay mode, and the real OpenAI Codex CLI for Codex mode. Sidekick checks runtime readiness when delegation starts for the current session.' },
  { page:'Getting Started', url:'getting-started/', anchor:'install',
    title:'Installing Sidekick',
    text:'Install Sidekick through the host plugin surface. Claude Code uses /plugin install alo-labs/sidekick. Codex uses codex plugin marketplace add alo-labs/codex-plugins. Cursor uses Settings → Plugins → Add marketplace with source https://github.com/alo-labs/alo-labs-cursor-marketplace, then installs sidekick from the marketplace list. Until Sidekick is listed there, add marketplace https://github.com/alo-exp/sidekick instead. Restart the host so the hook surface loads before starting Kay or Codex delegation.' },
  { page:'Getting Started', url:'getting-started/', anchor:'health-check',
    title:'Health check - verify current session',
    text:'Codex mode verifies that codex resolves to the real OpenAI Codex CLI and that codex exec supports the managed flags. Kay mode verifies kay --version, kay exec --help, and Kay provider readiness before routing work.' },
  { page:'Getting Started', url:'getting-started/', anchor:'codex-path',
    title:'Your first Codex task',
    text:'Start Codex mode with /sidekick:codex, then describe the implementation task. The host delegates through codex exec with gpt-5.4-mini, xhigh reasoning, workspace-write sandboxing, and no approval prompts.' },
  { page:'Getting Started', url:'getting-started/', anchor:'kay-path',
    title:'Your first Kay task',
    text:'Start Kay mode through /sidekick:kay, /sidekick:kay xiaomi, or /sidekick:kay ocg. Active Kay mode creates the session marker, writes active-sidekick=kay, and routes child execution through kay exec.' },
  { page:'Getting Started', url:'getting-started/', anchor:'agents-md-bootstrap',
    title:'AGENTS.md bootstrap',
    text:'Project AGENTS.md documents supported sidekicks, canonical workflows under skills, generated host bundles under agents, tests, integrity workflow, release discipline, and host-owned verification.' },

  // CORE CONCEPTS
  { page:'Core Concepts', url:'concepts/', anchor:'delegation',
    title:'Codex delegation mode',
    text:'When /sidekick:codex is active, implementation tasks route to the local OpenAI Codex CLI until /sidekick:codex-stop removes the current-session marker. The host remains accountable for planning and verification.' },
  { page:'Core Concepts', url:'concepts/', anchor:'kay-delegation',
    title:'Kay delegation model',
    text:'Kay is the Kay/OpenCode Go execution sidekick. Activation starts with /sidekick:kay; active Kay mode routes work through kay exec and records .kay/conversations.idx lookup metadata.' },
  { page:'Core Concepts', url:'concepts/', anchor:'skill-md',
    title:'SKILL.md - canonical workflows',
    text:'Canonical workflows live under skills: kay-delegate, kay-stop, codex-delegate, and codex-stop. Generated host bundles under agents/claude and agents/codex are rendered from those canonical sources.' },
  { page:'Core Concepts', url:'concepts/', anchor:'failure-detection',
    title:'Failure detection - host verification taxonomy',
    text:'The host checks for MISSED_REQUIREMENT, INTEGRATION_ERROR, REGRESSION, WRONG_LOGIC, SYNTAX_ERROR, WRONG_FILE, UNVERIFIED_ASSUMPTION, KNOWLEDGE_GAP, MISUNDERSTOOD_TASK, TRIAL_INCOMPLETE, API_FAILURE, and EXECUTION_ERROR_EXTERNAL.' },
  { page:'Core Concepts', url:'concepts/', anchor:'fallback-ladder',
    title:'The verification loop',
    text:'After every sidekick task, the host verifies the result against the original prompt and surrounding repository behavior. If verification fails, the host relaunches or guides the active sidekick for the missed subtask, then verifies again.' },
  { page:'Core Concepts', url:'concepts/', anchor:'skill-injection',
    title:'Hook boundary',
    text:'PreToolUse and PostToolUse hooks stay dormant until the user starts Kay or Codex delegation for the current session. The shared active-sidekick selector allows only one sidekick to enforce at a time.' },
  { page:'Core Concepts', url:'concepts/', anchor:'agents-md',
    title:'AGENTS.md',
    text:'AGENTS.md is the project instruction surface for hosts and sidekicks. It should stay aligned with the current Sidekick contract: Kay and Codex only, canonical skills, generated host bundles, tests, integrity, and release discipline.' },
  { page:'Core Concepts', url:'concepts/', anchor:'token-optimization',
    title:'Runtime flags',
    text:'Codex mode runs codex exec with -m gpt-5.4-mini, model_reasoning_effort=xhigh, workspace-write sandboxing, and --ask-for-approval never. Kay mode uses kay exec with default routing, xiaomi, ocg, or SIDEKICK_KAY_PROVIDER.' },
  { page:'Core Concepts', url:'concepts/', anchor:'provider-config',
    title:'Provider configuration',
    text:'Kay owns Kay provider routing through its runtime and optional SIDEKICK_KAY_PROVIDER override. Codex sidekick mode intentionally uses the local OpenAI Codex CLI with the pinned Sidekick model and reasoning flags.' },

  // DELEGATION WORKFLOW
  { page:'Delegation Workflow', url:'workflows/', anchor:'activation',
    title:'Activate Codex',
    text:'Run /sidekick:codex to activate Codex sidekick mode. The host verifies the real Codex CLI, clears any Kay marker, writes active-sidekick=codex, and routes implementation work through codex exec.' },
  { page:'Delegation Workflow', url:'workflows/', anchor:'kay-workflow',
    title:'Kay workflow - verify, execute, review',
    text:'Run /sidekick:kay, /sidekick:kay xiaomi, or /sidekick:kay ocg. The host verifies Kay readiness, writes active-sidekick=kay, delegates through kay exec, and reviews Kay progress summaries.' },
  { page:'Delegation Workflow', url:'workflows/', anchor:'task-prompt',
    title:'Kay exec and Codex exec',
    text:'After activation, Sidekick routes child implementation work through the selected runtime. Kay uses kay exec. Codex uses codex exec with gpt-5.4-mini, xhigh reasoning, workspace-write sandboxing, and no approval prompts.' },
  { page:'Delegation Workflow', url:'workflows/', anchor:'monitoring',
    title:'Monitor sidekick output',
    text:'PostToolUse surfaces bounded, redacted Kay and Codex subprocess summaries. The host treats progress as context, not proof, and still checks the final diff and commands.' },
  { page:'Delegation Workflow', url:'workflows/', anchor:'fallback',
    title:'Host verification',
    text:'The host compares the sidekick result against the original objective, checks integration points, runs meaningful verification commands, classifies failures, and relaunches the active sidekick when correction is needed.' },
  { page:'Delegation Workflow', url:'workflows/', anchor:'deactivation',
    title:'Deactivate sidekick mode',
    text:'Use /sidekick:kay-stop or /sidekick:codex-stop to remove the current-session marker and clear active-sidekick when it points at the stopped sidekick. Audit ledgers are preserved.' },

  // COMMAND REFERENCE
  { page:'Reference', url:'reference/', anchor:'codex-commands',
    title:'Delegation skills - Kay and Codex lifecycle',
    text:'/sidekick:kay activates Kay mode. /sidekick:kay-stop deactivates Kay mode. /sidekick:codex activates Codex mode. /sidekick:codex-stop deactivates Codex mode. Kay selectors include xiaomi and ocg.' },
  { page:'Reference', url:'reference/', anchor:'kay-commands',
    title:'Kay runtime commands',
    text:'kay exec is the native runtime command used after Kay mode is active. kay login --provider opencode-go --with-api-key configures OpenCode Go credentials. SIDEKICK_KAY_PROVIDER can override Kay provider routing.' },
  { page:'Reference', url:'reference/', anchor:'task-prompt',
    title:'Runtime commands',
    text:'Kay routes through kay exec. Codex routes through codex exec with gpt-5.4-mini, model_reasoning_effort=xhigh, workspace-write, and --ask-for-approval never.' },
  { page:'Reference', url:'reference/', anchor:'codex-toml',
    title:'Session state',
    text:'The shared active-sidekick selector lives under ~/.sidekick/sessions. Project-local .kay and .codex session markers activate matching hooks. .kay/conversations.idx and .codex/conversations.idx preserve lookup metadata.' },
  { page:'Reference', url:'reference/', anchor:'bootstrap-skills',
    title:'Verification tests',
    text:'Run bash tests/run_unit.bash for strict checks, bash tests/run_all.bash for the skip-safe aggregate suite, and the Kay-hosted live release gate with SIDEKICK_LIVE_CODEX=1 before release.' },
  { page:'Reference', url:'reference/', anchor:'output-format',
    title:'Progress surfaces',
    text:'Sidekick emits [KAY], [KAY-SUMMARY], [CODEX], and [CODEX-SUMMARY] blocks from child runtime output. These summaries are redacted and bounded but still require host verification.' },
  { page:'Reference', url:'reference/', anchor:'agents-md-format',
    title:'AGENTS.md format',
    text:'Project AGENTS.md should document project conventions, the delegation contract, host verification checks, integrity workflow, tests, and release discipline in plain markdown.' },
  { page:'Reference', url:'reference/', anchor:'file-structure',
    title:'File structure - all Sidekick-managed files',
    text:'Canonical workflows live at skills/kay-delegate, skills/kay-stop, skills/codex-delegate, and skills/codex-stop. Session markers live under .kay and .codex, with active-sidekick under ~/.sidekick/sessions.' },

  // TROUBLESHOOTING
  { page:'Troubleshooting', url:'troubleshooting/', anchor:'codex-not-found',
    title:'codex not found after install',
    text:'Check which codex, codex --version, and codex exec --help. The command must resolve to the real OpenAI Codex CLI and support --ask-for-approval before Codex mode can route work.' },
  { page:'Troubleshooting', url:'troubleshooting/', anchor:'kay-runtime',
    title:'Kay runtime issues',
    text:'If kay exec is unavailable, check kay --version and kay exec --help. If Kay provider credentials are missing, run kay login --provider opencode-go --with-api-key.' },
  { page:'Troubleshooting', url:'troubleshooting/', anchor:'health-check',
    title:'Health check failures',
    text:'Codex readiness can fail from a missing binary, Kay alias masquerading as Codex, unauthenticated CLI, unsupported options, network failure, or provider service issue. Kay readiness can fail from missing runtime or provider login.' },
  { page:'Troubleshooting', url:'troubleshooting/', anchor:'provider-config',
    title:'Provider routing',
    text:'For Kay, choose /sidekick:kay xiaomi, /sidekick:kay ocg, or SIDEKICK_KAY_PROVIDER. For Codex, Sidekick intentionally pins gpt-5.4-mini with extra-high reasoning.' },
  { page:'Troubleshooting', url:'troubleshooting/', anchor:'fallback',
    title:'Verification Fails',
    text:'If the sidekick claimed success but verification failed, the host relaunches the active sidekick with the original task, failure code, evidence, relevant files and tests, and exact success criteria.' },
  { page:'Troubleshooting', url:'troubleshooting/', anchor:'agents-md',
    title:'AGENTS.md issues',
    text:'If AGENTS.md has wrong content, edit ./AGENTS.md directly and keep it focused on current Sidekick: Kay and Codex only, canonical workflows under skills, generated host bundles under agents, and host-owned verification.' },
  { page:'Troubleshooting', url:'troubleshooting/', anchor:'recovery',
    title:'Session recovery',
    text:'If the wrong sidekick appears active, stop the current sidekick with /sidekick:kay-stop or /sidekick:codex-stop, then activate the desired one with /sidekick:kay or /sidekick:codex.' },
  { page:'Troubleshooting', url:'troubleshooting/', anchor:'reinstall',
    title:'Reinstall and full reset',
    text:'A clean plugin reinstall refreshes the host surface without deleting AGENTS.md or session logs. Runtime credentials and logins are reset through each runtime, then delegation is reactivated for the session.' },
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
    var excerpt = r.text.slice(0, 140) + '...';
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

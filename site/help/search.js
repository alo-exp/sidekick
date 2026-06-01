/* Sidekick Help search index */
'use strict';
(function () {
  var IDX = [
    { page: 'Sidekick Help', url: './', title: 'Sidekick Help', text: 'Current help for Sidekick 0.7.0, Kay sidekick, Codex sidekick, host verification, and release checks.' },
    { page: 'Getting Started', url: 'getting-started/', title: 'Install and activate a sidekick', text: 'Choose Kay with /sidekick:kay-delegate or Codex with /sidekick:codex-delegate. Stop with /sidekick:kay-stop or /sidekick:codex-stop.' },
    { page: 'Concepts', url: 'concepts/', title: 'Host, sidekick, and active-sidekick', text: 'The host AI plans, delegates, reviews, verifies, and owns correctness. active-sidekick contains kay or codex for the current session.' },
    { page: 'Workflows', url: 'workflows/', title: 'Kay exec and Codex exec workflows', text: 'Kay exec and Codex exec are the supported child runtime paths. Kay uses kay exec. Codex uses codex exec with gpt-5.4-mini and extra-high reasoning.' },
    { page: 'Reference', url: 'reference/', title: 'Commands, files, and tests', text: 'Reference for /sidekick:kay-delegate, /sidekick:codex-delegate, sidekicks/registry.json, generated host bundles, bash tests/run_unit.bash, and release checks.' },
    { page: 'Troubleshooting', url: 'troubleshooting/', title: 'Activation and Verification Fails', text: 'Fix stale active-sidekick state, Kay runtime issues, Codex CLI issues, stale generated bundles, and verification failures.' }
  ];

  function score(item, terms) {
    var text = (item.page + ' ' + item.title + ' ' + item.text).toLowerCase();
    return terms.reduce(function (sum, term) {
      if (text.indexOf(term) === -1) return sum;
      return sum + (item.title.toLowerCase().indexOf(term) !== -1 ? 3 : 1);
    }, 0);
  }

  function search(query) {
    if (!query || query.trim().length < 2) return [];
    var terms = query.toLowerCase().trim().split(/\s+/).filter(function (term) { return term.length > 1; });
    return IDX.map(function (item) { return { item: item, score: score(item, terms) }; })
      .filter(function (row) { return row.score > 0; })
      .sort(function (a, b) { return b.score - a.score; })
      .slice(0, 8)
      .map(function (row) { return row.item; });
  }

  window.sidekickHelpSearch = search;
})();

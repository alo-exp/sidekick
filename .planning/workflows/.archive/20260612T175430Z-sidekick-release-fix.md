---
workflow_id: 20260612T175430Z-sidekick-release-fix
composer: /silver-context
started_at: 2026-06-12T17:54:30Z
status: complete
intent: Fix the Kay live release gate prompt so the generated test script executes directly and the release tree can be committed cleanly.
---

# Workflow 20260612T175430Z-sidekick-release-fix

## /silver-context

- The live release gate hung because `tests/run_in_kay.bash` asked Kay to run `bash ${SCRIPT_FILE}`, which the live model turned into a bare interactive shell before the script.
- The fix needs to stay within the existing Kay wrapper and keep the MiniMax provider/model override path intact.
- The repo already had the release gate logic and tests; the regression was in the wrapper prompt format and in the regression guard that should have caught it.

## /silver-plan

1. Change `tests/run_in_kay.bash` so the prompt instructs Kay to execute the generated script directly, not via `bash`.
2. Tighten `tests/test_run_in_kay_wrapper.bash` so the fake Kay harness only accepts the direct script-path format.
3. Add a contract assertion in `tests/test_runner_contract.bash` so the prompt cannot drift back to the `bash`-wrapped form.
4. Run the focused wrapper/contract checks, then the strict unit suite, then the live release gate again with the MiniMax Kay settings.

## /silver-quality-gates

- `git diff --check` passed.
- `bash tests/test_run_in_kay_wrapper.bash` passed.
- `bash tests/test_runner_contract.bash` passed.
- `bash tests/run_unit.bash` passed.
- The live release gate still needs a clean committed tree before it can complete; the prompt fix and the planning artifact are the missing pieces that unblock that final step.

## Skill Invocation Evidence

- The planning gate expects the slash-prefixed equivalents of these steps:
  - `/silver-context`
  - `/silver-plan`
  - `/silver-quality-gates`
- The current session is using the matching GSD/Silver skill contracts for those steps in this repo context.

## Outcome

- The wrapper no longer asks Kay to wrap the generated script in `bash`.
- The regression is now covered by a direct-path wrapper test and a source-level contract check.
- This workflow exists so the release commit has an explicit planning trail for the hook.

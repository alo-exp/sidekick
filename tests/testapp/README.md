# Sidekick testapp — Live E2E target

Tiny Python package used by `tests/run_live_e2e.bash` and
`tests/run_live_codex_e2e.bash` to prove a full Claude → Forge or
Claude → Kay delegation round-trip succeeds against the real binary and
the real model.

## Shape

- `calc.py` — a two-function calculator with ONE intentional bug:
  `add(a, b)` returns `a - b`. The fix is a one-character change.
- `test_calc.py` — pure-stdlib `unittest` file. Three assertions:
  `add(2, 3) == 5`, `add(-1, 1) == 0`, `sub(5, 3) == 2`. With the bug,
  the first two fail.

The driver runs `python3 -m unittest tests.testapp.test_calc` (or its
sandboxed copy) to confirm the baseline fails, hands Forge a
5-field prompt to fix it, and then re-runs the tests to confirm the
repair actually worked.

## Why this file shape

- No third-party deps (no pytest, no venv): CI-neutral even though this
  driver never runs in CI.
- Small enough that a weaker model can solve it — the test is that the
  delegation harness works end-to-end, not that the model is smart.
- Fixable by a single line edit, so we can deterministically assert
  `FILES_CHANGED: [calc.py]`.

## Do NOT edit the testapp source to fix the bug

The bug is the driver's input. If you "fix" it in main, the live E2E
test no longer exercises anything. If you genuinely want to change the
scenario (e.g. harder bug, multi-file), swap the bug — don't remove it.

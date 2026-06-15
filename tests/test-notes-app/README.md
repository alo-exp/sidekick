# Test Notes App — Live E2E target

A small but real note-taking app used as the live validation target for Kay/Codex delegation in Sidekick.

## Why it exists

- Gives Kay a concrete Node.js project with persistence, CRUD, search, and UI work.
- Lives under `tests/test-notes-app/` so release operators can run the live E2E driver without a separate checkout.
- Replaces the retired Python `tests/testapp/` calculator fixture.

## Stack

- Node.js + Express
- better-sqlite3 for local persistence
- Vanilla HTML/CSS/JS for the UI

## Seeded E2E bug

The canonical `src/server.js` intentionally returns `status: "broken"` from `GET /api/health`.

`tests/run_live_codex_e2e.bash` copies this tree to `$TMPDIR`, runs `scripts/e2e-smoke.sh` (baseline must fail), delegates a fix through Kay, then re-runs the smoke script.

**Do not fix the seeded bug in the canonical source.** The driver copies to a sandbox before delegation.

## Local setup

```bash
cd tests/test-notes-app
npm install
npm start
```

Then open `http://localhost:3456`.

## Live smoke only

```bash
cd tests/test-notes-app
npm install
PORT=3457 bash scripts/e2e-smoke.sh
```

This expects the health handler to return `status: "ok"` (will fail on the seeded canonical tree).

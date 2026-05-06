---
name: codex-history
description: List recent Codex delegation sessions from this project. Prunes entries older than 30 days on each call.
---

# /codex-history

Show the 20 most recent Codex delegation sessions from this project. Also prune stale rows older than 30 days.

## Procedure

1. Resolve the Sidekick audit index:

   ```bash
   IDX="${CLAUDE_PROJECT_DIR:-$PWD}/.codex/conversations.idx"
   ```

   If the file does not exist, tell the user: "No Codex tasks recorded yet. Run `/codex` to activate delegation mode and then hand off a task." Stop.

2. **Prune stale rows.** Compute a cutoff timestamp 30 days ago in ISO 8601 UTC, then drop any row whose timestamp (column 1) is lexicographically less than the cutoff:

   ```bash
   CUTOFF="$(date -u -v-30d +%FT%TZ 2>/dev/null || date -u -d '30 days ago' +%FT%TZ)"
   awk -v cutoff="$CUTOFF" -F'\t' '$1 >= cutoff' "$IDX" > "$IDX.tmp" && mv "$IDX.tmp" "$IDX"
   ```

3. Read the last 20 rows after pruning:

   ```bash
   tail -n 20 "$IDX"
   ```

   Each row is tab-separated:
   `timestamp  conversation-id  sidekick-tag  task-hint`

4. Join rows with Codex’s native history when possible:

   - `codex` stores prompt text in `~/.code/history.jsonl`
   - legacy `~/.codex/history.jsonl` is also read
   - if the exact task hint matches a history entry, surface the associated `session_id`
   - otherwise render `—` in the session column

5. Render a compact markdown table to the user, newest first:

   | Timestamp (UTC) | Tag | Task hint | Session |
   |---|---|---|---|
   | 2026-04-18T02:15:00Z | codex-1729200000-a3f9c2b1 | Refactor utils.py | 0199a213-81c0-7800-8aa1-bbab2a035a53 |
   | 2026-04-18T01:02:13Z | codex-1729195333-d81a4c6e | Add tests for snapshot diff | — |

   Truncate task hints to 48 characters with `…` if longer.

6. If fewer than 20 rows remain after pruning, show however many remain. Do not pad.

## Failure modes

- Native history unavailable → render the table with `—` in the session column; do not abort.
- Index rows malformed → skip them silently and continue.
- `date -v-30d` unsupported → fall back to GNU `date -d '30 days ago'`; if both fail, skip pruning and warn the user inline.

## Notes

- `.codex/conversations.idx` is the Sidekick-owned audit ledger. The native `~/.code/history.jsonl` file stays separate and continues to be managed by Codex itself.
- `/codex-history` is read-only with respect to Codex state.

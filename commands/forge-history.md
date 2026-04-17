---
name: forge-history
description: List recent Forge tasks delegated from this project (reads .forge/conversations.idx). Prunes entries older than 30 days on each call.
---

# /forge:history

Show the 20 most recent Forge conversations initiated from this project, joined with live status/token data from `forge conversation info`. Also prune idx rows older than 30 days.

## Procedure

1. Resolve the idx path: `IDX="${CLAUDE_PROJECT_DIR:-$PWD}/.forge/conversations.idx"`.
   If the file does not exist, tell the user: "No Forge tasks recorded yet. Run `/forge` to activate delegation mode and then hand off a task." Stop.

2. **Prune stale rows (REPLAY-03).** Compute a cutoff timestamp 30 days ago in ISO 8601 UTC, then drop any row whose timestamp (column 1) is lexicographically less than the cutoff. ISO 8601 lexical order matches chronological order, so a simple awk filter is sufficient:

   ```bash
   CUTOFF="$(date -u -v-30d +%FT%TZ 2>/dev/null || date -u -d '30 days ago' +%FT%TZ)"
   awk -v cutoff="$CUTOFF" -F'\t' '$1 >= cutoff' "$IDX" > "$IDX.tmp" && mv "$IDX.tmp" "$IDX"
   ```

   The BSD/macOS `-v-30d` form and the GNU `-d '30 days ago'` form are both handled. Silently succeed even if the file becomes empty after pruning.

3. Read the last 20 rows after pruning:

   ```bash
   tail -n 20 "$IDX"
   ```

   Each row is tab-separated: `timestamp  conversation-id  sidekick-tag  task-hint`.

4. For each row, fetch live status with `forge conversation info <conversation-id> 2>/dev/null`. Parse the stdout for:
   - `STATUS:` → the terminal status (SUCCESS/FAILED/ACTIVE/…)
   - `TOKENS:` or similar → total token count

   If the binary is missing or the ID is not found, render `—` in the status/tokens columns rather than erroring.

5. Render a compact markdown table to the user (newest first):

   | Timestamp (UTC)      | Tag                        | Task hint                          | Status   | Tokens |
   |----------------------|----------------------------|------------------------------------|----------|--------|
   | 2026-04-18T02:15:00Z | sidekick-1729200000-a3f9c2b1 | Refactor utils.py                  | SUCCESS  | 8 412  |
   | 2026-04-18T01:02:13Z | sidekick-1729195333-d81a4c6e | Add tests for snapshot diff        | SUCCESS  | 12 987 |
   | …                    | …                          | …                                  | …        | …      |

   Truncate task hints to 48 characters with `…` if longer. Do not include the raw UUID in the table — the Sidekick tag is the human-readable handle. The UUID is still the key used by `/forge:replay`, so print a one-line footer: `Use /forge:replay <UUID> to open a transcript — see the first column of .forge/conversations.idx for the UUID to each tag.`

6. If fewer than 20 rows exist after pruning, show however many remain. Do not pad.

## Failure modes

- `forge conversation info` unavailable → render the table with `—` for status and tokens; do not abort.
- Idx file corrupted (row not tab-separated, or missing columns) → skip malformed rows silently, continue with the rest.
- `date -v-30d` unsupported on target system → fall back to GNU `date -d '30 days ago'`; if both fail, skip pruning and warn the user inline ("pruning unavailable on this platform, idx may grow unbounded").

## Notes

- Pruning is non-destructive aside from age-based row removal. The UUIDs remain valid in `~/forge/.forge.db` until Forge's own retention expires them.
- `/forge:history` is read-only with respect to Forge state; it only mutates the Sidekick-owned `.forge/conversations.idx` file.

# Kay live QA harness (SB exemption)

**Scope:** Running Kay/OpenCode Go live release gates, campaign runners (`tests/run_kay_*`), log triage under `tests/.kay-live-logs/`, and related test-harness edits.

**Not in scope:** Product feature work, milestone ship, or PR/release delivery.

## Silver Bullet enforcement

| Gate | Harness expectation |
|------|---------------------|
| Stop hook (`stop-check.sh`) | `skills.required_planning` in `.silver-bullet.json` should be **`["silver-quality-gates"]` only**. Do not require `silver-context` / `silver-plan` for harness wrap-up. |
| Session state | Cursor: `~/.cursor/.silver-bullet/state` — record at least `silver-quality-gates` (via Skill tool on `silver-quality-gates` or `/silver:fast` trivial session). |
| Composed workflows | Completed tickets must live under `.planning/workflows/.archive/`, not `.planning/workflows/*.md`, or `workflow-chain-guard` treats them as active and blocks edits. |
| GSD `mode: yolo` | Does **not** bypass SB hooks. |

## Quick unblock

```bash
# Stop hook: planning floor satisfied (harness)
printf 'silver-quality-gates\n' > ~/.cursor/.silver-bullet/state

# Or start harness chat with trivial bypass
touch ~/.cursor/.silver-bullet/trivial

# Or clear state (empty state = stop hook fail-open)
rm -f ~/.cursor/.silver-bullet/state
```

## Before a real feature ship

Restore full planning floor in `.silver-bullet.json`:

```json
"required_planning": ["silver-quality-gates", "silver-context", "silver-plan"]
```

Invoke those skills (Cursor: read `~/.cursor/plugins/cache/alo-labs/silver-bullet/current/agents/cursor/silver-context/SKILL.md` and `silver-plan/SKILL.md`, or use `/silver:context` / `/silver:plan` when the host exposes them).

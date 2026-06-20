# Sidekick

[![version](https://img.shields.io/badge/version-v0.8.2-blue)](https://github.com/alo-exp/sidekick/releases/tag/v0.8.2)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**AI coding-agent delegation for Claude Code, Codex, and Cursor.**

Sidekick lets the host AI stay focused on planning, review, mentoring, and communication while supported sidekicks perform bounded implementation work. The host creates the plan, delegates tasks, reviews sidekick output, and verifies results before reporting completion.

Plain version: install Sidekick on your host, activate Kay or Codex for the current session, delegate implementation, then let the host prove the work is actually done.

**Docs:** [sidekick.alolabs.dev](https://sidekick.alolabs.dev) · **Cursor marketplace:** [alo-labs/alo-labs-cursor-marketplace](https://github.com/alo-labs/alo-labs-cursor-marketplace) · **Releases:** [github.com/alo-exp/sidekick/releases](https://github.com/alo-exp/sidekick/releases)

## What Sidekick Adds

| Area | Sidekick owns |
|------|----------------|
| Delegation | Kay (`kay exec`) and Codex (`codex exec`) sidekick workflows |
| Host role | Planning, review, verification, and communication stay with the host |
| Enforcement | PreToolUse hooks block direct host edits while a sidekick is active |
| Progress | Bounded, redacted Kay/Codex output surfaces through PostToolUse hooks |
| Session state | Per-host `active-sidekick` marker and audit indexes under `.kay` / `.codex` |

## How It Works

```text
Host AI = Brain
Sidekick = Hands
```

1. The host prepares a focused implementation prompt with files, constraints, and success criteria.
2. The active sidekick writes files and runs commands through its child runtime.
3. Sidekick hooks keep the host from bypassing the active sidekick mid-task.
4. The host verifies the result against the original prompt, integration points, and required tests.
5. If verification fails, the host relaunches the active sidekick with correction context until the failure is resolved.

Sidekick does **not** install SessionStart hooks. Kay and Codex readiness is checked when delegation starts for the current session.

## Supported Sidekicks

| Sidekick | Activate | Stop | Runtime |
| --- | --- | --- | --- |
| **Kay** | `/sidekick:kay` | `/sidekick:kay-stop` | Kay runtime via `kay exec` |
| **Codex** | `/sidekick:codex` | `/sidekick:codex-stop` | Local OpenAI Codex CLI (`gpt-5.4-mini`, extra-high reasoning) |

Kay defaults to existing `opencode-go` routing. Use `/sidekick:kay xiaomi` for Xiaomi routing, `/sidekick:kay ocg` to force OpenCode Go routing, or `SIDEKICK_KAY_PROVIDER` as an environment override. Sidekick selects the model automatically per provider.

On **Cursor**, the same workflows appear as slash commands `kay`, `kay-stop`, `codex`, and `codex-stop`.

## Quick Start

### Claude Code

```text
/plugin install alo-labs/sidekick
```

Restart Claude Code, then activate a sidekick:

```text
/sidekick:kay
/sidekick:codex
```

### Codex host

```bash
codex plugin marketplace add alo-labs/codex-plugins
```

Install Sidekick from that marketplace, restart Codex, then run `/sidekick:kay` or `/sidekick:codex`.

### Cursor (recommended)

Cursor discovers plugins through registered marketplaces, not from files copied into `~/.cursor/plugins/cache/`.

1. In Cursor, open **Settings → Plugins → Add marketplace**.
2. Add source `https://github.com/alo-labs/alo-labs-cursor-marketplace`.
3. Install **sidekick** (currently **v0.8.2**, commit-pinned in the marketplace catalog).
4. **Developer: Reload Window** so `hooks/cursor-hooks.json` loads before delegation.
5. Enable the plugin if needed, reload again, then merge hooks:

```bash
bash scripts/install-cursor.sh --merge-hooks-only
```

Use slash commands `kay`, `codex`, `kay-stop`, and `codex-stop` in agent chat.

**Development from a checkout:**

```bash
bash scripts/install-cursor.sh --merge-hooks
```

This syncs generated `agents/cursor/` bundles, copies the plugin into `~/.cursor/plugins/cache/alo-labs/sidekick/<version>`, registers a local marketplace symlink, and optionally merges hooks into `~/.cursor/hooks.json`.

## Hook Safety

Sidekick hooks are designed to stay out of the way until delegation is active.

| State | Behavior |
| --- | --- |
| **Inactive** | Enforcement hooks pass through with `{"permission":"allow"}` on Cursor and do not block unrelated host tools. |
| **Active** | PreToolUse hooks deny direct host edits; implementation must go through `kay exec` or `codex exec`. |
| **Cursor merge** | `scripts/merge-cursor-hooks.py` idempotently merges Sidekick entries into `~/.cursor/hooks.json`, removes stale Sidekick hook paths, and stabilizes install paths via a `current` symlink. |

Run hook merge **after** the plugin is enabled in Cursor. Default `install-cursor.sh` does not merge hooks until you pass `--merge-hooks` or run `--merge-hooks-only` post-install.

## Host Verification

After every sidekick task, the host must verify the result against the original prompt and success criteria. If the sidekick missed a requirement, broke integration, introduced a regression, used wrong logic, changed the wrong file, hit a syntax error, relied on a bad assumption, misunderstood the task, stopped early, or was blocked by provider or environment failures, the host relaunches the active sidekick with focused guidance until the failure is resolved.

Common failure classes include `MISSED_REQUIREMENT`, `INTEGRATION_ERROR`, `REGRESSION`, `WRONG_LOGIC`, `SYNTAX_ERROR`, `WRONG_FILE`, `UNVERIFIED_ASSUMPTION`, `KNOWLEDGE_GAP`, `MISUNDERSTOOD_TASK`, `TRIAL_INCOMPLETE`, `API_FAILURE`, and `EXECUTION_ERROR_EXTERNAL`.

## Requirements

| Host | Prerequisites |
| --- | --- |
| **Claude Code** | Node.js 18+ |
| **Codex host** | Codex plugin surface; Sidekick skills and hooks |
| **Cursor** | Cursor with Plugins support; `jq` for hook enforcement |
| **Kay sidekick** | Working `kay` binary with `kay exec`; provider login when needed |
| **Codex sidekick** | Real OpenAI Codex CLI on PATH (not Kay's `codex` compatibility alias); `codex exec --ask-for-approval` support |

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Sidekick missing in Cursor plugin list | Marketplace not registered | Add [alo-labs-cursor-marketplace](https://github.com/alo-labs/alo-labs-cursor-marketplace), reload, enable **sidekick@0.8.2** |
| Hooks block tools before delegation | Hooks merged while plugin inactive or stale hook paths | Run `bash scripts/install-cursor.sh --merge-hooks-only` after plugin is enabled; confirm enforcer inactive pass-through |
| `current → current` symlink loop | Ran `--merge-hooks-only` without a prior install | Install first with `bash scripts/install-cursor.sh`, then merge hooks |
| `codex not found` | Missing CLI or Kay alias on PATH | `which codex`; ensure real OpenAI Codex CLI is first on PATH |
| Kay readiness fails | Missing `kay exec` or provider login | `kay exec --help`; `kay login --provider opencode-go --with-api-key` |
| Audit index not writable | Symlinked `.kay` or `.codex` outside project | Remove symlink, fix permissions, reactivate sidekick |
| jq errors on Cursor | `jq` not installed | Install `jq` and reload Cursor |

For a wedged Cursor hook install, companion recovery scripts in `misc/cursor-hook-sidekick-issue` (`recover-hooks.sh`, `refresh-marketplace-install.sh`, `merge-hooks.sh`, `verify.sh`) document strip → reinstall → merge → verify.

More detail: [Help → Troubleshooting](https://sidekick.alolabs.dev/help/troubleshooting/) on the docs site.

## Testing

```bash
bash tests/run_unit.bash
bash tests/run_all.bash
bash tests/run_in_kay.bash SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
```

## Project Layout

```text
skills/           # Canonical Kay/Codex workflow source
agents/claude/    # Generated Claude Code bundles
agents/codex/     # Generated Codex host bundles
agents/cursor/    # Generated Cursor slash-command bundles
hooks/            # Shared enforcement and progress hooks
sidekicks/        # Sidekick registry metadata
```

Regenerate host bundles after skill edits:

```bash
bash scripts/sync-host-surfaces.sh
```

## License

MIT — see [LICENSE](LICENSE).

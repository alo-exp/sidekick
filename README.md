# Sidekick

**AI coding-agent delegation for Claude Code, Codex, and Cursor.** Sidekick lets the host AI stay focused on planning, review, mentoring, and communication while supported sidekicks perform implementation work.

## Supported Sidekicks

| Sidekick | Activate | Runtime |
| --- | --- | --- |
| **Kay** | `/sidekick:kay-delegate` | Kay runtime installed and repaired through Sidekick |
| **Codex** | `/sidekick:codex-delegate` | Local OpenAI Codex CLI, using `gpt-5.4-mini` with extra-high reasoning |

Kay defaults to the existing `opencode-go` routing. Activate Kay with `/sidekick:kay-delegate xiaomi` to use Xiaomi routing, or `/sidekick:kay-delegate ocg` to force OpenCode Go routing for the session. `SIDEKICK_KAY_PROVIDER` remains supported as an environment override. Sidekick selects the model automatically per provider.

Stop commands:

| Sidekick | Stop |
| --- | --- |
| Kay | `/sidekick:kay-stop` |
| Codex | `/sidekick:codex-stop` |

## How It Works

```text
Host AI = Brain
Sidekick = Hands
```

The host AI creates the plan, delegates bounded implementation tasks, reviews the sidekick output, and verifies the final state before reporting completion. Sidekick hooks prevent direct host edits while a sidekick is active and route supported runtime commands through bounded, redacted progress surfaces.

## Host Verification

After every sidekick task, the host must verify the result against the original prompt and success criteria. If the sidekick missed a requirement, broke integration, introduced a regression, used wrong logic, changed the wrong file, hit a syntax error, relied on a bad assumption, misunderstood the task, stopped early, or was blocked by provider or environment failures, the host relaunches the active sidekick with focused guidance until the failure is resolved.

## Testing

```bash
bash tests/run_unit.bash
bash tests/run_all.bash
bash tests/run_in_kay.bash SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
```

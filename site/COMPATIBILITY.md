# Compatibility

> How the current Sidekick contract maps across Claude Code, Codex, Cursor, Kay, and the Codex sidekick.

## Matrix

| Concern | Claude Code host | Codex host | Cursor host | Kay sidekick | Codex sidekick |
| --- | --- | --- | --- | --- | --- |
| Skill source | Rendered from `skills/` into `agents/claude/` | Rendered from `skills/` into `agents/codex/` | Rendered from `skills/` into `agents/cursor/` | `skills/kay-delegate/SKILL.md` | `skills/codex-delegate/SKILL.md` |
| Activation | `/sidekick:kay` or `/sidekick:codex` | `/sidekick:kay` or `/sidekick:codex` | `/sidekick:kay` or `/sidekick:codex` | Starts Kay mode | Starts Codex mode |
| Stop command | `/sidekick:kay-stop` or `/sidekick:codex-stop` | `/sidekick:kay-stop` or `/sidekick:codex-stop` | `/sidekick:kay-stop` or `/sidekick:codex-stop` | Clears Kay mode | Clears Codex mode |
| Child runtime | Host launches the selected sidekick | Host launches the selected sidekick | Host launches the selected sidekick | `kay exec` | `codex exec` |
| Model and provider | Host does not own sidekick model selection | Host does not own sidekick model selection | Host does not own sidekick model selection | OpenCode Go by default; `xiaomi`, `ocg`, and `SIDEKICK_KAY_PROVIDER` are accepted selectors | Local OpenAI Codex CLI using `gpt-5.4-mini` with extra-high reasoning |
| Session state | `CLAUDE_SESSION_ID` | `CODEX_THREAD_ID` | `SIDEKICK_SESSION_ID` from Cursor `sessionStart` | `.kay/sessions/<session>` | `.codex/sessions/<session>` |
| Hooks | `hooks/hooks.json` | `hooks/hooks.json` | `hooks/cursor-hooks.json` | Enforced through host hooks | Enforced through host hooks |
| Verification | Host-owned | Host-owned | Host-owned | Output is reviewed by host | Output is reviewed by host |

## Kay compatibility aliases

Kay is the primary runtime identity. Sidekick installs and repairs the Kay runtime and treats `kay exec` as the current child execution path. Older command names can exist for installed-user compatibility, but public docs and new workflows should use Kay names.

Use these user-facing commands:

```text
/sidekick:kay
/sidekick:kay xiaomi
/sidekick:kay ocg
/sidekick:kay-stop
```

## Codex sidekick compatibility

The Codex sidekick is the local OpenAI Codex CLI, not a Kay alias. Sidekick activates it through `/sidekick:codex`, launches it with `codex exec`, and pins the sidekick mode to `gpt-5.4-mini` with extra-high reasoning.

Use these user-facing commands:

```text
/sidekick:codex
/sidekick:codex-stop
```

## Generated Surface Compatibility

Generated host bundles under `agents/claude/`, `agents/codex/`, and `agents/cursor/` must be refreshed from the canonical skills:

```bash
bash scripts/sync-host-surfaces.sh
```

Do not hand-edit generated copies unless the canonical source and renderer contract are updated in the same change set.

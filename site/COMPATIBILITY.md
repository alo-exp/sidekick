# Compatibility

> How the current Sidekick contract maps across Claude Code, Codex, Kay, and the Codex sidekick.

## Matrix

| Concern | Claude Code host | Codex host | Kay sidekick | Codex sidekick |
| --- | --- | --- | --- | --- |
| Skill source | Rendered from `skills/` into `agents/claude/` | Consumes canonical `skills/` and rendered parity artifacts | `skills/kay-delegate/SKILL.md` | `skills/codex-delegate/SKILL.md` |
| Activation | `/sidekick:kay-delegate` or `/sidekick:codex-delegate` | `/sidekick:kay-delegate` or `/sidekick:codex-delegate` | Starts Kay mode | Starts Codex mode |
| Stop command | `/sidekick:kay-stop` or `/sidekick:codex-stop` | `/sidekick:kay-stop` or `/sidekick:codex-stop` | Clears Kay mode | Clears Codex mode |
| Child runtime | Host launches the selected sidekick | Host launches the selected sidekick | `kay exec` | `codex exec` |
| Model and provider | Host does not own sidekick model selection | Host does not own sidekick model selection | OpenCode Go by default; `xiaomi`, `ocg`, and `SIDEKICK_KAY_PROVIDER` are accepted selectors | Local OpenAI Codex CLI using `gpt-5.4-mini` with extra-high reasoning |
| Session state | Reads shared selector | Reads shared selector | `.kay/sessions/<session>` | `.codex/sessions/<session>` |
| Verification | Host-owned | Host-owned | Output is reviewed by host | Output is reviewed by host |

## Kay compatibility aliases

Kay is the primary runtime identity. Sidekick installs and repairs the Kay runtime and treats `kay exec` as the current child execution path. Older command names can exist for installed-user compatibility, but public docs and new workflows should use Kay names.

Use these user-facing commands:

```text
/sidekick:kay-delegate
/sidekick:kay-delegate xiaomi
/sidekick:kay-delegate ocg
/sidekick:kay-stop
```

## Codex sidekick compatibility

The Codex sidekick is the local OpenAI Codex CLI, not a Kay alias. Sidekick activates it through `/sidekick:codex-delegate`, launches it with `codex exec`, and pins the sidekick mode to `gpt-5.4-mini` with extra-high reasoning.

Use these user-facing commands:

```text
/sidekick:codex-delegate
/sidekick:codex-stop
```

## Generated Surface Compatibility

Generated host bundles under `agents/claude/` and `agents/codex/` must be refreshed from the canonical skills:

```bash
bash scripts/sync-host-surfaces.sh
```

Do not hand-edit generated copies unless the canonical source and renderer contract are updated in the same change set.

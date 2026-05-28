# Compatibility

| Area | Kay | Codex |
| --- | --- | --- |
| Activation | `/sidekick:kay-delegate` | `/sidekick:codex-delegate` |
| Stop | `/sidekick:kay-stop` | `/sidekick:codex-stop` |
| Runtime | `kay exec` | local OpenAI `codex exec` |
| State root | `~/.kay` | `~/.codex` |
| Host support | Claude Code and Codex | Claude Code and Codex |

The `code` and `coder` names can be Kay compatibility aliases when they identify as Kay. The `codex` binary name is reserved for the real OpenAI Codex CLI, and Codex sidekick mode rejects Kay compatibility aliases.

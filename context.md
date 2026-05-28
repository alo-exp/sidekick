# Sidekick Context

Sidekick gives Claude Code and Codex a consistent delegation layer for supported coding sidekicks.

| Sidekick | Runtime | Activation | State Root |
| --- | --- | --- | --- |
| Kay | `kay exec` | `/sidekick:kay-delegate` | `.kay/sessions/<session>` |
| Codex | `codex exec` | `/sidekick:codex-delegate` | `.codex/sessions/<session>` |

Kay and Codex are mutually exclusive per host session. The shared selector lives at `~/.sidekick/sessions/<session>/active-sidekick` and contains either `kay` or `codex`.

The host AI owns planning, user communication, review, and verification. A sidekick result is never accepted only because it reports success; the host verifies the diff, tests, integration points, and task requirements first.

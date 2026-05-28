# Glossary

**Host AI**: The assistant coordinating the task, communicating with the user, and verifying results.

**Sidekick**: A delegated coding agent that performs implementation work for the host.

**Kay**: Supported Sidekick runtime launched through `kay exec`.

**Codex sidekick**: Supported Sidekick runtime launched through the local OpenAI Codex CLI.

**Active sidekick selector**: `~/.sidekick/sessions/<session>/active-sidekick`, containing `kay` or `codex`.

**Host verification**: The mandatory post-task audit where the host compares the result against the prompt, runs checks, classifies failures, and relaunches the active sidekick when needed.

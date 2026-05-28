# Start Here

Use `/sidekick:kay-delegate` when Kay should implement the task.

Use `/sidekick:codex-delegate` when the local OpenAI Codex CLI should implement the task with `gpt-5.4-mini` and extra-high reasoning.

Stop with `/sidekick:kay-stop` or `/sidekick:codex-stop`.

Run `bash tests/run_unit.bash`, then `bash tests/run_all.bash`, then the Kay-wrapped live release gate before publishing.

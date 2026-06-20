# Start Here

> The fastest path through current Sidekick docs.

## Choose Your Task

### Install or refresh Sidekick

Start with the [README](../README.md), then open [Getting Started](help/getting-started/). If canonical skill text changed, refresh generated host bundles:

```bash
bash scripts/sync-host-surfaces.sh
```

### Delegate a task to Kay

Use Kay when you want the Kay runtime:

```text
/sidekick:kay
/sidekick:kay xiaomi
/sidekick:kay ocg
```

Then read [Workflows](help/workflows/) for the review and retry loop.

### Delegate a task to Codex

Use Codex when you want the local OpenAI Codex CLI:

```text
/sidekick:codex
```

The Codex sidekick runs through `codex exec` with `gpt-5.4-mini` and extra-high reasoning.

### Stop or switch sidekicks

Stop the current sidekick before switching:

```text
/sidekick:kay-stop
/sidekick:codex-stop
```

### Debug a failure

Use [Troubleshooting](help/troubleshooting/) first, then [Reference](help/reference/) for exact paths and commands.

### Prepare a release

Use [Testing](TESTING.md), then run the current release checks that match your risk level.

## Good First Reading Order

1. [Help](help/)
2. [Getting Started](help/getting-started/)
3. [Concepts](help/concepts/)
4. [Workflows](help/workflows/)
5. [Reference](help/reference/)
6. [Troubleshooting](help/troubleshooting/)
7. [Architecture](ARCHITECTURE.md)
8. [Compatibility](COMPATIBILITY.md)
9. [Glossary](GLOSSARY.md)

## Remember This

Sidekick delegates implementation. The host AI still owns correctness.

# Testing

## Strict Local Tests

```bash
bash tests/run_unit.bash
```

## Skip-Safe Sweep

```bash
bash tests/run_all.bash
```

## Release Gate

```bash
bash tests/run_in_kay.bash SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
```

Release evidence must be produced inside Kay. The wrapper creates an isolated home, records proof-bound live markers, and refuses to promote markers after Kay failures.

# Phase 7 Summary — Live Visibility + Progress Surface + Output Style

**Status:** Shipped 2026-04-18
**Milestone:** v1.2 (Forge Delegation + Live Visibility)

## Scope delivered

1. **PostToolUse hook** (`hooks/forge-progress-surface.sh`) — fires on `Bash` tool calls, detects `forge -p` commands, extracts the STATUS block from the output, ANSI-strips, and emits a `hookSpecificOutput.additionalContext` envelope with `[FORGE-SUMMARY]`-prefixed lines plus a `/forge:replay <UUID>` hint keyed on the conversation-id injected in Phase 6.

2. **Output style** (`output-styles/forge.md`) — narration override for Claude's prose while Forge-first mode is active. Honest framing per the v1.2 corrections memo: Claude Code's output styles shape *assistant prose*, not raw tool output; the style documents the `[FORGE]` / `[FORGE-LOG]` / `[FORGE-SUMMARY]` markers as reference only and tells Claude to paraphrase + reference (not re-render) the hook-emitted summary block.

3. **SKILL.md lifts** (`skills/forge/SKILL.md` STEP 5 + 6) — documents the auto-injection of conversation-id + `--verbose` + output pipe, clarifies that Claude should not add these manually, and adds `run_in_background: true` + Monitor guidance for >10s tasks with a foreground fallback for Bedrock/Vertex/Foundry transports.

4. **Test suite** (`tests/test_forge_progress_surface.bash`) — 7 tests covering no-op gates (marker absent, non-Bash tool, command lacks `forge -p`, output lacks STATUS), successful summary emission, ANSI stripping, and graceful degradation when no UUID is present in the command.

## Design decisions

- **Hook pipeline hardening:** `set -euo pipefail` with `|| true` guards on UUID-extraction grep, `jq -r` output read, and status-block awk — each of these legitimately exits non-zero when there is no match, and we must not kill the hook mid-way. First seen as `test_noop_when_output_lacks_status` hanging during authoring; fixed and retested.
- **Output style honesty:** the spec draft claimed CLI-level coloring by prefix. That is not a feature Claude Code's output styles provide. Rather than silently shipping a lie, Phase 7 reframed the style as a narration contract and documented the markers as descriptive-only. This aligns with the `v12_claude_code_api_corrections.md` memory.
- **Replay hint fallback:** when no conversation-id is present on the command (unusual, but possible if a direct call bypassed the enforcer), the hook still emits a summary, just with a `(no conversation-id captured; replay unavailable)` footer instead of a `/forge:replay` hint.
- **ANSI stripping before parse:** `sed 's/\x1b\[[0-9;]*m//g'` runs before the STATUS-block extraction so `[FORGE] STATUS: SUCCESS` wrapped in color codes still parses.

## Handoffs

- Phase 8 registers the PostToolUse hook in `plugin.json` and refreshes `_integrity` hashes.
- Phase 9 drives this hook via the full E2E integration test.

## Deviations

None from the spec — all success criteria met in one execution round.

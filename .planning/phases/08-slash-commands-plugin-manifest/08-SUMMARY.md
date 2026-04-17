# Phase 8 Summary — Slash Commands + Plugin Manifest

**Status:** Shipped 2026-04-18
**Milestone:** v1.2 (Forge Delegation + Live Visibility)

## Scope delivered

1. **`/forge:replay <uuid>`** (`commands/forge-replay.md`) — validates the argument against RFC 4122 UUID regex, then pipes `forge conversation dump <uuid> --html` to `/tmp/forge-replay-<uuid>.html`, opens it via platform-appropriate browser (`open` on macOS, `xdg-open` on Linux), and renders `forge conversation stats <uuid> --porcelain` inline as a compact token/cost summary. Failure modes documented: unknown conversation id, browser-open failure, `forge` binary missing.

2. **`/forge:history`** (`commands/forge-history.md`) — reads `${CLAUDE_PROJECT_DIR}/.forge/conversations.idx`, prunes rows older than 30 days via ISO 8601 lexical comparison (BSD `date -v-30d` with GNU `date -d '30 days ago'` fallback), tails the last 20 rows, joins each against `forge conversation info <uuid>` for live STATUS / token counts (renders `—` when the binary is missing), and prints a compact markdown table with a footer reminding the user of the UUID-to-replay mapping.

3. **`plugin.json` bumped to v1.2.0** — directory-style `"commands": "./commands/"` and `"outputStyles": "./output-styles/"` registrations, `PostToolUse` hook entry added alongside the existing `PreToolUse`, `_integrity` refreshed with SHA-256 hashes for all new and modified artifacts: `skills/forge/SKILL.md`, `hooks/forge-delegation-enforcer.sh`, `hooks/forge-progress-surface.sh`, `output-styles/forge.md`, `commands/forge-replay.md`, `commands/forge-history.md`.

4. **Integrity test extension** (`tests/test_plugin_integrity.bash`) — added a v1.2 block that verifies each new hash key is present and matches the on-disk artifact, plus an assertion that `plugin.json` version is `1.2.x`.

5. **Commands test suite** (`tests/test_forge_commands.bash`, 12 tests) — structural assertions on both command docs (frontmatter, documented procedures, regex/command pipelines), execution test of the 30-day pruning awk filter using synthetic mixed-age rows, and manifest-registration checks for `commands`, `outputStyles`, and the `PostToolUse` hook.

## Design decisions

- **Directory registration over explicit arrays:** Claude Code auto-discovers commands and output styles when pointed at a directory. The explicit-array form in the v1.2 spec would force manual registration on every new command; the directory form handles future additions for free. Verified against the plugin schema.
- **History pruning via lexical compare:** ISO 8601 UTC strings sort chronologically as plain text, so a single `awk '$1 >= cutoff'` pass is sufficient and portable across BSD/GNU. No `date` parsing per row required.
- **Graceful degradation when `forge` is absent:** `/forge:history` renders `—` instead of failing when `forge conversation info` is unavailable so users in read-only / inspection contexts can still browse the idx.

## Handoffs

- Phase 9 drives both hooks end-to-end and verifies the UUID round-trip; commands are exercised via their doc contracts rather than live execution in the automated suite (replay requires a real Forge install and a browser).
- Release step consumes the bumped plugin version + refreshed integrity hashes verbatim.

## Deviations

None — plugin version, command documents, manifest registrations, and integrity hashes all landed in the same commit boundary.

# Project: Sidekick

## Project Conventions

- Shell/Bash + Markdown stack -- no compiled languages
- `skills/forge.md` is the core orchestration protocol (862 lines) -- NEVER modify
- `skills/forge/SKILL.md` is the user-invoked mode switch -- extends forge.md
- Tests live in `tests/` and run via `tests/run_all.bash`
- Plugin manifest at `.claude-plugin/plugin.json` -- update hashes when skill files change

## Forge Output Format

After every task, Forge must produce structured output:
- STATUS: success | partial | failed
- FILES_CHANGED: list of files created or modified
- ASSUMPTIONS: any assumptions made during execution
- PATTERNS_DISCOVERED: conventions or patterns noticed in the codebase

## Task Patterns

- Implementation tasks: delegate to Forge with 5-field prompt (OBJECTIVE, CONTEXT, DESIRED STATE, SUCCESS CRITERIA, INJECTED SKILLS)
- Testing tasks: inject testing-strategy skill
- Security-sensitive tasks: inject security skill
- Prompt transport: for prompts containing `$N` sequences, em-dashes (`—`), or backticks, pipe via stdin (`cat prompt.txt | forge`) or write to a tempfile; do NOT use `forge -p "..."` with complex content — zsh expansion mangles `$0` to `/bin/zsh`, em-dashes to `M-bM^@M^T`, and silently corrupts the prompt. Verified empirically in Phase 5.

## Forge Corrections

### Agent frontmatter must declare `tools`

Every Forge agent file under `.forge/agents/*.md` MUST include `tools: ["*"]` (or a more restrictive explicit list) in its YAML frontmatter. Without this field, Forge provisions the agent with **zero** tools. The model then emits XML/markdown text that looks like tool calls but is never executed — and the agent still returns `STATUS: SUCCESS`. This is the single highest-severity configuration pitfall in Forge.

Verification: `forge list tool <agent>` must show all tools with `[✓]` markers.


Source: Phase 5 / Bug 1 (commit 354d001). See `.planning/phases/05-.../05-CONTEXT.md`.

### OpenRouter model IDs must be verified before committing

Any model ID written to README, skill docs, `.forge.toml`, or agent files MUST be verified against the live OpenRouter catalog via `forge list model --porcelain | grep <candidate-id>`. Do NOT accept a model name from LLM output or memory without verification — hallucinated IDs (e.g., `qwen/qwen3.6-plus`) are silently accepted by Forge's config command but cause the OpenRouter API to omit tool schemas from the request, producing text-only responses that compound the "tools missing" failure mode (see prior entry).


Verified IDs as of v1.1.2: `qwen/qwen3-coder-plus` (1M ctx, tools), `qwen/qwen3-vl-235b-a22b-instruct` (262k ctx, tools + vision), `minimax/minimax-m2.7` (196k ctx, tools).


Source: Phase 5 / Bug 2 (commit 354d001).

### Plugin integrity manifest hashes must be synced with skill edits

When modifying any of these files, recompute the corresponding SHA256 in `.claude-plugin/plugin.json` in the SAME commit:
- `skills/forge.md` → `_integrity.forge_md_sha256`
- `install.sh` → `_integrity.install_sh_sha256`
- `hooks/hooks.json` (or equivalent) → `_integrity.hooks_json_sha256`

Recompute with: `shasum -a 256 <file> | awk '{print $1}'`. The CI plugin-integrity suite (`tests/test_plugin_integrity.bash`) compares manifest hashes against actual file content and FAILs on mismatch, blocking releases.

Source: Phase 5 CI failure on commit 0768bd8; fixed in 5f2225c.

### Phase orchestration artifacts commit separately from code

Planning artifacts under `.planning/phases/<NN>-<slug>/` (CONTEXT, PLANs, SUMMARYs) and `.planning/STATE.md` / `.planning/ROADMAP.md` updates should land in their own `chore(phase-N): ...` commit, separate from the fix and release-prep commits. This keeps code-change diffs reviewable without orchestration noise and keeps the fix commit's `files_modified` contract honest. Release commits (README badge, CHANGELOG) also stay separate so `/create-release` reads a clean history.


Source: Phase 5 commit structure — 354d001 (fix), 3eee7ce (release prep), 0768bd8 (orchestration), 5f2225c (CI fix), 0c6c640 (state closeout).

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

## Forge Corrections

(Initially empty -- populated by mentoring loop after each task)

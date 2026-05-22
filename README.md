# Sidekick — AI Coding Agents for Claude Code and Codex

**AI coding agents for Claude Code and Codex** — Sidekick lets the active host AI delegate implementation to Forge or Kay while the host stays focused on planning, review, mentoring, and communication.

## Sidekicks

| Sidekick | Activation surface | Agent | Status |
|----------|--------------------|-------|--------|
| **Forge** | `/forge` | [ForgeCode](https://forgecode.dev) — #7 Terminal-Bench 2.0 (81.8%) | ✅ v0.5.8 |
| **Kay** | `kay-delegate` | OSS Codex-lineage execution agent — Codex CLI #6 Terminal-Bench 2.0, `kay exec`, OpenCode Go provider routing, MiMo-V2.5-Pro for non-trivial and vision / visual reasoning work, MiniMax M2.7 for trivial work, and DeepSeek V4 Flash for verification/reporting work | ✅ v0.5.8 |

More sidekicks planned.

---

## Docs

If you want the docs in the right order, start here:

- [Start Here](site/START-HERE.md) — task-first navigation
- [Audience](site/AUDIENCE.md) — who each doc is for
- [Glossary](site/GLOSSARY.md) — canonical terminology
- [Compatibility](site/COMPATIBILITY.md) — Claude Code, Codex, Forge, and Kay runtime differences
- [ADR index](site/ADR/README.md) — durable docs-system decisions

For help-site workflows, use the [Help Center](site/help/).

## Installation

Install through the active host's plugin surface:

```bash
# Claude Code
/plugin install alo-labs/sidekick

# Codex
codex plugin marketplace add alo-labs-codex/sidekick
```

On the next host session, Sidekick performs the first-run bootstrap. Runtime readiness is checked when you start Forge or Kay delegation for the current session.

---

## Development Layout

Sidekick keeps host-agnostic workflow sources under `skills/`. Host-facing skill bundles are generated from that source tree:

```text
skills/           Canonical Forge and Kay workflow sources
agents/claude/    Generated Claude Code skill surface
agents/codex/     Generated Codex skill surface
scripts/          Host-surface renderer and maintenance helpers
```

Edit `skills/` first, then run:

```bash
bash scripts/sync-host-surfaces.sh
```

The plugin manifests point at the generated host bundle for each runtime, while tests keep the generated bundles synchronized with the renderer.

---

## Forge — ForgeCode Sidekick

### What it does
- **Auto-installs** ForgeCode on first session start and checks readiness when Forge delegation starts for the current session
- **Guides** Forge provider setup for MiniMax Coding without putting provider keys in the prompt
- **Turns the host into an orchestrator**: Claude Code or Codex plans and communicates, while Forge executes file changes, tests, and commits
- **Fallback ladder**: automatic 3-level recovery on failure — L1 Guide (reframe), L2 Handhold (decompose), L3 Take over (`sidekick forge-level3 start|stop`, project-scoped direct work + DEBRIEF)
- **AGENTS.md mentoring**: after every task, the host AI extracts learnings and writes them to a 3-tier instruction store (`~/forge/AGENTS.md`, `./AGENTS.md`, session logs) — delegation gets smarter over time
- **Skill injection**: 4 bootstrap skills (testing-strategy, code-review, security, quality-gates) auto-injected into task prompts based on task type
- **Token optimization**: task prompts capped at 2,000 tokens with validated `.forge.toml` compaction defaults

## Kay — OSS Codex-Lineage Sidekick

### What it does
- **Auto-installs** Kay from the pinned `alo-labs/kay` installer on first session start and keeps legacy `code`, `codex`, and `coder` aliases compatibility-only
- **Activates** Kay work through `kay-delegate`; active Kay mode launches `kay exec --full-auto` and Sidekick injects the OpenCode Go provider plus the task-appropriate model automatically
- **Uses** Kay's native agents, skills, subagents, and `AGENTS.md` support instead of recreating Forge-style prompt injection
- **Supports** Claude Code and Codex hosts by running Kay as a child execution process through the packaged `kay-delegate` skill
- **Defaults** to OpenCode Go at delegation time, with the model selected automatically from the task type
- **Keeps** a project-local audit index at `.kay/conversations.idx`; the canonical Kay workflows live in the delegate and stop skills, with the legacy flat alias preserved only as a hidden compatibility entry at `skills/codex-delegate.md`.

The website setup shortcuts `/forge:delegate` and `/kay:delegate` are shipped alias skills. They route to the canonical `/forge` and `kay-delegate` workflows.

### Kay flow

```
You → Claude Code or Codex (plan + communicate) → Kay (implement + commit) → host AI (review + report)
```

Host AI handles: architecture, explanations, research, code review
Kay handles: writing files, features, tests, git commits

### Forge flow

```
You → Claude Code or Codex (plan + communicate) → Forge (implement + commit) → host AI (review + report)
```

Host AI handles: architecture, explanations, research, code review
Forge handles: writing files, features, tests, git commits

### Forge provider setup

The host AI will guide you to:
1. Create MiniMax.io API access at https://platform.minimax.io/subscribe/token-plan.
2. Store the credential in Forge's native `~/forge/.credentials.json` array format.
3. Point Forge at MiniMax M2.7 through `~/forge/.forge.toml`.

The host configures Forge automatically and delegates coding work from that point.

### Providers & Models
| Provider | Model | Notes |
|----------|-------|-------|
| **OpenCode Go** | **MiMo-V2.5-Pro** `mimo-v2.5-pro` | Main workhorse path for planning, implementation, reviewing, vision / visual reasoning, and other non-trivial tasks |
| **OpenCode Go** | **MiniMax M2.7** `minimax-m2.7` | Trivial technical work |
| **OpenCode Go** | **DeepSeek V4 Flash** `deepseek-v4-flash` | Test running, issue reporting, and work completion verification, not review |

---

## Testing

`tests/run_release.bash` chains the strict non-live suites plus the live Forge/Kay install, smoke, E2E, and Kay marketplace-install gates.

| Tier | Script | Runs without Forge/Kay | Purpose |
|------|--------|:---:|---------|
| **Strict unit + integration** | `tests/run_unit.bash` | ✅ | 30 non-live suites — hook classifiers, generated host skill surfaces, idx audit, plugin integrity, docs contract, homepage/help-site navigation, social preview, post-release cleanup, clean reinstall bootstrap, runner contract, and Forge/Kay coverage gaps. |
| **Skip-safe local sweep** | `tests/run_all.bash` | ✅ | Delegates to `run_unit.bash`, then runs the skip-safe live-gated Forge E2E and Codex plugin/read probes. |
| **Forge smoke** | `tests/smoke/run_smoke.bash` | skip | `forge --version` + trivial `forge -p` round-trip against the real binary. |
| **Forge live E2E** | `tests/run_live_e2e.bash` | skip | Full host→Forge delegation on a seeded-buggy testapp (`tests/testapp/`) — proves the 5-field prompt shape, tool-use, and verification loop work end-to-end. |
| **Kay marketplace install** | `tests/run_live_codex_marketplace_install.bash` | skip | Installs Sidekick through the Codex marketplace path and verifies the installed Kay and Forge surfaces. |
| **Kay smoke** | `tests/smoke/run_codex_smoke.bash` | skip | `kay --version` + trivial `kay exec` round-trip against the real binary, with legacy names kept as compatibility aliases. |
| **Kay live E2E** | `tests/run_live_codex_e2e.bash` | skip | Full host→Kay delegation on the same seeded-buggy testapp — proves the 5-field prompt shape, edit, and verification loop work end-to-end. |

The live stages are gated behind `SIDEKICK_LIVE_FORGE=1` and `SIDEKICK_LIVE_CODEX=1` so they never run in CI. CI runs the strict non-live runner. Before tagging a new version:

```bash
SIDEKICK_LIVE_FORGE=1 SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash
```

Before any release, complete the 4-stage pre-release quality gate until it passes twice in a row, then run the full live Forge/Kay pyramid twice with both live env vars. Each full live run records a current-session `quality-gate-live-pyramid` marker; the release hook requires two markers before publishing.

After the release is published, run `bash tests/post_release_cleanup.bash` so the local repo returns to a clean post-release state.
This cleanup only removes transient build/cache artifacts; `.planning/`, site/specs, and site/design content stay in place.

Without those env vars the release gate still runs strict stage 1 and cleanly skips the live stages, but CI uses `tests/run_unit.bash` directly.

---

## License

MIT — Ālo Labs

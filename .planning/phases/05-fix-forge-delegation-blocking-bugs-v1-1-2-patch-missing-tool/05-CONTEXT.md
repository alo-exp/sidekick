# Phase 5 Context -- v1.1.2 Forge Delegation Fix

## Phase Goal

Ship v1.1.2 patch that restores Forge delegation from silent-failure to working end-to-end for all Sidekick users installing fresh.

## Background

In production use, Sidekick v1.1.1 exhibits a catastrophic silent-failure mode: delegated tasks report `STATUS: SUCCESS` but no files are created, no shell mutations occur, and no tools are actually invoked. Empirical debugging in the previous session traced this to two compounding root causes in shipped artifacts. A third related defect (vision agent) is present in user-local configuration but is not shipped by Sidekick, so it is excluded from this patch.

## In-Scope Bugs

### Bug 1 -- Missing `tools:` field in agent frontmatter (CRITICAL)

**Symptom:** Without `tools: ["*"]` in frontmatter, Forge grants the agent zero tools. Models then emit XML/markdown text that looks like tool calls but is never executed. Files are not created; agent still reports `STATUS: SUCCESS`. Silent failure for every Sidekick user on a fresh install.

**Shipped artifacts to fix:**
- `.planning/phases/01-spec-core-skill-and-forge-config/01-03-PLAN.md` -- the template that Plan 01-03 defines for `.forge/agents/forge.md` must include `tools: ["*"]` in the frontmatter block.
- `skills/forge/SKILL.md` -- any inline agent template example must show the `tools:` field.
- `.forge/agents/forge.md` in this repo (already patched in a prior session; must be committed as part of this phase).

**Verification:** After installation, `forge list tool forge` must show all tools with `[x]` markers.

### Bug 2 -- Invalid model ID in shipped docs and config (BLOCKING)

**Symptom:** Docs recommend `qwen/qwen3.6-plus`, which does not exist on OpenRouter. When set as the active model, the API call silently omits tool schemas, so even with tools enabled (Bug 1 resolved) the model generates text output only.

**Correct ID:** `qwen/qwen3-coder-plus` (verified on OpenRouter, 1M context, tool support confirmed).

**Shipped artifacts to fix (reference counts from discovery):**
- `README.md` -- 1 reference at line 72 (Providers and Models table).
- `skills/forge.md` -- 8 references at lines 219, 323, 730, 761, 903, 904, 913, 936.
- `.forge.toml` -- 1 reference at line 11.

**Verification:** `grep -r "qwen3.6-plus" .` in repo root must return zero hits after the fix.

## Out-of-Scope

- **Bug 3 (vision agent):** The vision agent template at `~/forge/agents/vision.md` is user-local, not installed by `install.sh`. Already fixed manually in the dev environment. Bundling a vision agent would be a new feature, not a bug fix. Deferred.
- **Deeper bootstrap-template gap:** The Phase 1 skill only references the agent template via a planning-doc path, rather than embedding it. End-users cannot follow this cleanly. Flagged for a future phase; not part of v1.1.2.

## Success Criteria

1. All three in-scope artifact groups are updated with correct model ID and tools frontmatter.
2. `grep -r "qwen3.6-plus" .` in the repo returns zero results.
3. `.forge/agents/forge.md` contains `tools: ["*"]` in frontmatter.
4. Post-install smoke test passes: running `forge -p "write 'test' to /tmp/sidekick-install-smoke.txt"` produces a real file with the expected content.
5. README version badge shows v1.1.2.
6. CHANGELOG entry describes the fix and both bugs.
7. A git tag `v1.1.2` is created and a GitHub release is published.

## Validation Commands

```
grep -rn "qwen3.6-plus" . --include="*.md" --include="*.toml"
grep -n "^tools:" .forge/agents/forge.md
forge list tool forge
forge -p "write hello to /tmp/sidekick-install-smoke.txt" && cat /tmp/sidekick-install-smoke.txt
```

## AGENTS.md Pattern to Capture

Forge agent frontmatter MUST include the `tools:` field (typically `tools: ["*"]`). Without it, the agent is provisioned with zero tools and any model -- no matter how capable -- will emit fake tool-call text that looks real but executes nothing. This is the single highest-severity configuration pitfall in Forge.
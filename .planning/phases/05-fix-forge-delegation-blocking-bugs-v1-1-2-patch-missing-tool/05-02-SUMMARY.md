# Plan 05-02 Summary — Release Prep v1.1.2

## Commit

**SHA:** `3eee7ce`
**Subject:** `release: prepare v1.1.2 (README badge + CHANGELOG entry)`
**Date:** 2026-04-17
**Files touched:** `README.md`, `CHANGELOG.md` (2 files, 7 insertions, 1 deletion)

## Verification Results

All 6 success criteria passed on first attempt:

| # | Check | Result |
|---|-------|--------|
| a | README.md has `v1.1.2`, zero `v1.1.1` | OK |
| b | CHANGELOG.md `## 1.1.2` is the top section | OK |
| c | CHANGELOG.md contains `qwen/qwen3-coder-plus` | OK |
| d | Commit subject matches `release: prepare v1.1.2` | OK |
| e | Commit touches exactly `CHANGELOG.md` + `README.md` | OK |
| f | No `v1.1.2` git tag exists | OK |

## Phase Commit History (last 3)

```
3eee7ce release: prepare v1.1.2 (README badge + CHANGELOG entry)
354d001 fix(forge-delegation): restore tool access and correct model ID (v1.1.2)
658d73c fix: correct forge credential-check to support current array schema
```

## Final CHANGELOG.md (head -12)

```
# Changelog

## 1.1.2 — 2026-04-17

- **Fix (CRITICAL)**: Forge agent template was missing the `tools: ["*"]` frontmatter field. Without it, Forge provisioned the agent with zero tools and any model — no matter how capable — emitted XML/markdown text that looked like tool calls but never executed. `/forge` delegation reported `STATUS: SUCCESS` while no files were actually created. Fixed in `.forge/agents/forge.md` and in the Plan 01-03 template so fresh installs inherit the correct configuration.
- **Fix (BLOCKING)**: Replaced the invalid OpenRouter model ID `qwen/qwen3.6-plus` (which does not exist) with the verified `qwen/qwen3-coder-plus` across README, `skills/forge.md` (8 references), `.forge.toml`, and internal planning artifacts. With the invalid ID set as the active model, the API silently omitted tool schemas, which compounded the Bug 1 symptom. After the fix, `grep -rn "qwen3.6-plus" .` returns only historical audit records.
- **Docs**: README Providers and Models table now shows `Qwen3 Coder Plus` (`qwen/qwen3-coder-plus`) as the recommended default; capability descriptor updated from "vision" to "tool-use" to match the model's actual feature set.

## 1.1.1 — 2026-04-17
...
```

## Final README.md Version Badge (grep output)

```
9:| **Forge** | `forge` | [ForgeCode](https://forgecode.dev) — #2 Terminal-Bench 2.0 (81.8%) | ✅ v1.1.2 |
```

## Deferred Items

### Post-install smoke test (CONTEXT.md Success Criterion 4)

Deferred. This test requires a clean environment with a fresh `install.sh` run, which can only be verified after the release is shipped and a user performs a clean install. The test cannot be run in-place because `.forge/agents/forge.md` is already patched in the current environment — it would pass regardless of whether the template fix from Plan 01-03 is correct.

Recommended procedure after `/create-release v1.1.2` ships:

```bash
cd "$(mktemp -d)"
curl -fsSL https://raw.githubusercontent.com/alo-exp/sidekick/v1.1.2/install.sh | bash
# then in a fresh Claude session:
forge -p "write hello to /tmp/sidekick-install-smoke.txt"
cat /tmp/sidekick-install-smoke.txt   # must print: hello
```

## Next Step

Invoke the `/create-release v1.1.2` skill to create the git tag and publish the GitHub release. This plan prepared all artifacts the release skill needs — Step 5 README freshness check will pass.

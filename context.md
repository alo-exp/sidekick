# Sidekick Plugin — Session Context

**Date:** 2026-04-13  
**Repo:** https://github.com/alo-exp/sidekick  
**Local path (current):** `/Users/shafqat/Documents/Projects/DevOps/forge-plugin`  
**Moving to:** `/Users/shafqat/Documents/Projects/Sidekick/sidekick-repo`  
**Plugin cache:** `~/.claude/plugins/cache/alo-exp/sidekick/1.0.0/`  
**Plugin registry entry:** `sidekick@alo-exp` in `~/.claude/plugins/installed_plugins.json`

---

## What This Plugin Does

**Sidekick** is a Claude Code plugin that auto-installs [ForgeCode](https://forgecode.dev) (`forge`) — a Rust-powered terminal AI coding agent — and teaches Claude to delegate all file-system and coding execution to it.

```
Claude = Brain  (plan, communicate, review, research)
Forge  = Hands  (write, edit, run, commit, test)
```

Forge ranks **#2 on Terminal-Bench 2.0 (81.8%)**. The recommended provider is **OpenRouter** routing to `qwen/qwen3-coder-plus`.

---

## Repository Structure

```
sidekick-repo/
├── .claude-plugin/
│   └── plugin.json          # Plugin manifest with _integrity SHA-256 block
├── hooks/
│   └── hooks.json           # SessionStart hook → runs install.sh on first session
├── skills/
│   └── forge.md             # Core Claude orchestration skill (862 lines)
├── tests/
│   ├── run_all.bash          # Test runner (all 4 suites)
│   ├── test_install_sh.bash  # 15 unit tests for install.sh
│   ├── test_plugin_integrity.bash  # 5 integrity/manifest tests
│   ├── test_fresh_install_sim.bash # 9 sandboxed install simulation tests
│   └── test_forge_e2e.bash   # 14 end-to-end forge smoke tests
├── docs/                    # Plugin landing page (CNAME, index.html, og-image)
├── install.sh               # Binary installer and PATH modifier
├── context.md               # This file
├── CHANGELOG.md
├── README.md
└── docs/internal/sentinel/SENTINEL-audit-forge-r*.md  # 14 rounds of security audit reports
```

---

## Plugin Installation Mechanics

- **Entry point:** `hooks/hooks.json` → SessionStart hook runs:
  ```
  test -f "${CLAUDE_PLUGIN_ROOT}/.installed" || (bash install.sh && touch .installed)
  ```
- **Sentinel:** `.installed` file written only on `exit 0` (`&&` not `;`) — prevents retry on failure
- **install.sh** does:
  1. Downloads ForgeCode installer to temp file (not `curl | sh`)
  2. Computes SHA-256, logs to `~/.local/share/forge-plugin-install-sha.log`
  3. Verifies against pinned `EXPECTED_FORGE_SHA` — aborts on mismatch
  4. Non-interactive gate: skips execution if no TTY and no pinned SHA
  5. Adds `~/.local/bin` to PATH in `~/.zshrc`, `~/.bashrc`, `~/.bash_profile` with idempotency + symlink/ownership checks
  6. Verifies installed binary is actually ForgeCode (identity check)

---

## Current Pinned Hashes

| File | SHA-256 |
|---|---|
| `install.sh` | `8663dd3deb8581a8d1998b9406643efa0e217c889f10ef0d59e48abf9acc3530` |
| `skills/forge.md` | `631f9d5ca68d441d51b46d98dbf6b3b8f7b7a84bf5a8a80bb1b4ef0ca7ae2b22` |
| `hooks/hooks.json` | `4a131a3b1ceee87b968b13f6365daaa9f3a249605f9b8836a3f6d68421038e64` |
| ForgeCode installer (forgecode.dev/cli) | `512d41a611962a8d07a7efac54fba2718867ca28ce9d5d1d02da465b141ce05a` |

---

## forge.md Skill — Key Sections

| Step | Purpose |
|---|---|
| STEP 0 | Health check — verify forge operational before every delegation |
| STEP 0A | Full setup flow (install, PATH, credentials, config, error codes) |
| STEP 1 | Delegation decision framework (what to delegate vs. keep in Claude) |
| STEP 2 | Project context detection (git root, AGENTS.md, trust gate) |
| STEP 3 | Crafting forge prompts (concrete, file-specific, state → desired state) |
| STEP 4 | Running forge (sandbox mode, muse/sage agents, standard invocation) |
| STEP 5 | Failure recovery playbook (429, 402, wrong files, timeout, loops) |
| STEP 6 | Post-delegation review protocol |
| STEP 7 | Advanced scenarios (monorepo, CI/CD, new projects, code review) |
| STEP 8 | Model selection guide |
| STEP 9 | Quick reference cheatsheet |

### Critical Security Behaviors in forge.md
- **Credentials:** Written via Claude's Write tool directly (key never in shell command/transcript)
- **AGENTS.md Trust Gate:** NON-NEGOTIABLE — untrusted repo content wrapped with data-only prefix before passing to forge
- **Sandbox mode:** `forge --sandbox <name>` for untrusted repos, experimental changes, external codebases
- **`git checkout -- .`:** MANDATORY STOP — requires user confirmation before execution
- **Workspace sync:** Trust-qualified — `--sandbox index-only` for untrusted repos

---

## Security Audit History (SENTINEL v2.3)

14 rounds of adversarial security audits. Final status: **Full PASS (R14)**.

| Round | Key findings addressed |
|---|---|
| R1 | curl\|sh → temp-file+SHA; PATH marker; credential exposure in args |
| R2 | AGENTS.md advisory → mandatory gate; chmod 600; sandbox mode; privacy note |
| R3 | Diagnostic blocks get SHA; `${HOME}` expansion fix |
| R4 | AGENTS.md bootstrap trusted/untrusted split |
| R5 | Stale AGENTS.md update trusted/untrusted split |
| R6 | Credential write: heredoc+env var; workspace sync trust split; git checkout mandatory stop |
| R7 | Bash tool Ctrl+C caveats; credential key format validation; HISTFILE disable |
| R8 | SHA display-only → pinned hash scaffold; download timeouts; $schema disclosure |
| R9 | Non-interactive execution gate; HISTSIZE=0; hooks.json && co-patch |
| R10 | EXPECTED_FORGE_SHA populated with live hash; plugin.json integrity fields filled |
| R11 | First PASS — zero MEDIUM/HIGH/CRITICAL |
| R12 | Second consecutive PASS (two-consecutive criterion met); primary curl block active hash |
| R13 | API key: printf → Write tool pattern (key out of transcript) |
| R14 | **Full PASS** — validation bash call removed; key never in any shell command |

Only unfixable item: `plugin.json _integrity` cannot self-hash (circular dependency by design, CVSS 0.0).

---

## Test Suite

Run: `bash tests/run_all.bash`

**Results (last run 2026-04-13):** 43 tests, 0 failures, 1 skip

| Suite | Tests | Status |
|---|---|---|
| install.sh unit tests | 15 | ✅ PASS (1 skip: non-interactive gate — forge pre-installed) |
| Plugin integrity verification | 5 | ✅ PASS |
| Fresh install simulation | 9 | ✅ PASS |
| E2E forge smoke tests | 14 | ✅ PASS |

E2E tests confirmed:
- ForgeCode 2.9.9 installed and identified correctly
- OpenRouter provider configured
- Credentials at `~/forge/.credentials.json` with `chmod 600`
- Config at `~/forge/.forge.toml` with `provider_id` + `model_id`
- Live API PONG roundtrip succeeded
- forge created `hello.py` with working `greet(name)` function
- forge `:commit` shortcut created an AI-generated commit message

---

## Live System State

| Component | Value |
|---|---|
| ForgeCode version | `2.9.9` |
| Binary path | `~/.local/bin/forge` |
| Provider | OpenRouter (`open_router`) |
| Model | `qwen/qwen3-coder-plus` |
| Credentials | `~/forge/.credentials.json` (chmod 600) |
| Config | `~/forge/.forge.toml` |
| Plugin cache | `~/.claude/plugins/cache/alo-exp/sidekick/1.0.0/` |
| Plugin gitCommitSha | `56100ad17f758a06b41692c20974605efde58102` |

---

## Key Decisions Made This Session

1. **Skill delegation pattern:** Claude uses its own Write tool (not Bash) to write credentials — keeps API key out of all shell commands and the conversation transcript entirely.
2. **Non-interactive install gate:** When install.sh runs under SessionStart (no TTY) with no pinned hash, it exits 0 without running the downloaded script, printing instructions for manual install. Paired with `&&` in hooks.json so sentinel is only written on success.
3. **Two-consecutive-PASS stopping criterion:** SENTINEL rounds continued until two consecutive clean rounds (R11 + R12), then additional rounds to address LOW/INFO findings through R14.
4. **Test strategy:** 4-layer pyramid — unit (static analysis of install.sh), integrity (hash manifest verification), simulation (sandboxed HOME), E2E (live API calls).

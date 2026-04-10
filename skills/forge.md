---
name: forge
description: >
  Core orchestration skill: Claude acts as the planner/communicator and delegates ALL
  coding, file, and git work to ForgeCode (forge). Trigger on ANY of: implement, build,
  create, write, fix, refactor, add, update, delete, rename, move, test, commit, run,
  install, configure, generate, scaffold — applied to code, files, or the project.
  Also trigger when the user asks to set up Forge, configure OpenRouter, switch models,
  check Forge status, or troubleshoot Forge errors.
---

# Forge — Claude Orchestration Protocol

ForgeCode (`forge`) is a Rust-powered terminal AI coding agent running independently
alongside this Claude session. It is #2 on Terminal-Bench 2.0 (81.8%) and #1 for
interactive developer workflows.

**Claude's role: Orchestrator + Communicator**
**Forge's role: Executor — all file-system and coding work**

---

## 0. First-Use Setup

Before delegating any task, verify Forge is configured. Run:

```bash
~/.local/bin/forge info 2>/dev/null || forge info 2>/dev/null
```

### If forge is not found
```bash
curl -fsSL https://forgecode.dev/cli | sh
export PATH="$HOME/.local/bin:$PATH"
```

### If forge shows no provider / Google AI Studio default
Guide the user through OpenRouter setup:

1. **Tell the user:**
   > "Forge needs an API key to work. The recommended provider is OpenRouter — it gives
   > access to Qwen 3.6 Plus (best free-tier coding model, $0.33/$1.95 per MTok).
   >
   > 1. Go to **openrouter.ai** and sign up (Google/GitHub OAuth, ~30 seconds)
   > 2. Go to **openrouter.ai/settings/credits** and add $5 (minimum, lasts weeks)
   > 3. Go to **openrouter.ai/keys** and create a new API key
   > 4. Paste the key here and I'll configure Forge."

2. **When user pastes the key**, configure Forge:

```bash
# Write credentials
FORGE_DIR="${HOME}/forge"
mkdir -p "${FORGE_DIR}"

cat > "${FORGE_DIR}/.credentials.json" << CREDS
[
  {
    "id": "open_router",
    "auth_details": {
      "api_key": "PASTE_KEY_HERE"
    }
  }
]
CREDS

# Write config with Qwen 3.6 Plus
cat > "${FORGE_DIR}/.forge.toml" << 'TOML'
"$schema" = "https://forgecode.dev/schema.json"
max_tokens = 16384

[session]
provider_id = "open_router"
model_id = "qwen/qwen3.6-plus"
TOML

# Verify
export PATH="${HOME}/.local/bin:${PATH}"
forge info
```

3. **Confirm** with: `forge -p "reply with just the word OK"`

### If forge is already configured
Proceed directly to delegation.

---

## 1. Core Delegation Rule

**Default: delegate to Forge. Only keep in Claude what cannot run in a terminal.**

| Delegate to Forge ✅ | Keep in Claude ✋ |
|---|---|
| Write / edit / create files | Architecture decisions |
| Implement features or functions | Explaining code or concepts |
| Refactor existing code | Research (web searches, docs) |
| Write tests | Reviewing forge's output |
| Fix failing tests | Non-coding tasks (email, calendar) |
| Run shell commands | Short answers (< 5 lines of code) |
| Rename / move / delete files | API calls (Gmail, Drive, etc.) |
| Git commits | Asking clarifying questions |
| Scaffold projects | Planning before implementation |
| Bulk changes across files | |
| Database migrations | |

---

## 2. How to Delegate

### Determine the project directory
Always run forge with `-C <project-root>` so it operates in the right context.
The project root is the `git` root or the directory the user has been working in.

```bash
# Detect project root
PROJECT_ROOT=$(git -C "${PWD}" rev-parse --show-toplevel 2>/dev/null || echo "${PWD}")
```

### Build the forge prompt
- Be specific and actionable. Forge works best with concrete instructions.
- Reference file paths relative to the project root when relevant.
- Include constraints (naming conventions, test requirements, etc.) from AGENTS.md if present.

### Run forge

**For implementation tasks:**
```bash
export PATH="${HOME}/.local/bin:${PATH}"
forge -C "${PROJECT_ROOT}" -p "TASK_DESCRIPTION"
```

**For complex features (plan first, then implement):**
```bash
# Step 1: plan
forge --agent muse -C "${PROJECT_ROOT}" -p "Design a plan for: FEATURE_DESCRIPTION"

# Step 2: implement
forge -C "${PROJECT_ROOT}" -p "Implement the plan in plans/"
```

**For research/analysis without file changes:**
```bash
forge --agent sage -C "${PROJECT_ROOT}" -p "ANALYSIS_QUESTION"
```

**For git commits:**
```bash
forge -C "${PROJECT_ROOT}" -p ":commit"
# OR non-interactively:
git -C "${PROJECT_ROOT}" add -A && forge -C "${PROJECT_ROOT}" -p "Generate and execute a git commit message for the staged changes"
```

### Attaching context files
When forge needs to understand specific files, include their paths in the prompt:

```
forge -C "${PROJECT_ROOT}" -p "Refactor the auth module in src/auth/index.ts — it currently does X, change it to do Y. Follow the patterns in src/utils/http.ts"
```

---

## 3. Context Continuity — AGENTS.md

For any project where forge will be used repeatedly, maintain an `AGENTS.md` at the
project root. Forge reads this automatically on every run.

When starting work on a new project, create or update AGENTS.md with:
- Tech stack and key dependencies
- Naming conventions and coding standards
- Test setup and how to run tests
- Key file locations and module structure
- Any project-specific rules

Example prompt to forge:
```bash
forge -C "${PROJECT_ROOT}" -p "Read the existing codebase and create/update AGENTS.md with the project conventions, tech stack, key file locations, and how to run tests."
```

---

## 4. Switching Models

**Qwen 3.6 Plus** (default, recommended for coding):
```bash
forge config set model open_router qwen/qwen3.6-plus
```

**Gemma 4 31B** (alternative, no vision):
```bash
forge config set model open_router google/gemma-4-31b-it
```

**Check current model:**
```bash
forge info
```

---

## 5. Troubleshooting

### `forge: command not found`
```bash
export PATH="$HOME/.local/bin:$PATH"
# If still missing: reinstall
curl -fsSL https://forgecode.dev/cli | sh
```

### `402 Payment Required` (OpenRouter)
Add credits at **openrouter.ai/settings/credits** ($5 minimum).

### `429 Too Many Requests` (OpenRouter)
Rate limit hit. Wait 30 seconds and retry, or switch to Gemma 4:
```bash
forge config set model open_router google/gemma-4-31b-it
```

### Forge completes but files not written
Re-prompt with explicit instruction: "Write the file now and save it to disk."

### Provider not configured
```bash
forge provider login   # interactive setup
# OR check: forge info
```

---

## 6. Workflow Pattern

The recommended flow for any coding request:

```
User → Claude (understand + plan) → Forge (execute) → Claude (review + report to user)
```

1. **Claude understands** the request and asks any clarifying questions
2. **Claude plans** the approach (briefly, in Claude's response)
3. **Claude delegates** to forge with a precise, scoped prompt
4. **Forge executes** autonomously (file changes, tests, commits)
5. **Claude reviews** forge's output and summarises the result to the user
6. **Claude asks** if the user wants further changes

Never do step 3 yourself (write files with Edit/Write tools) for tasks that qualify
for forge delegation — always prefer sending it to forge.

---

## 7. Quick Reference

```bash
# Run forge on a task
forge -C /path/to/project -p "description of task"

# Plan first, then implement
forge --agent muse -C /path/to/project -p "plan: feature description"
forge -C /path/to/project -p "implement the plan in plans/"

# Research without changes
forge --agent sage -C /path/to/project -p "how does X work in this codebase?"

# Commit
forge -C /path/to/project -p ":commit"

# Check status
forge info

# Switch model
forge config set model open_router qwen/qwen3.6-plus
```

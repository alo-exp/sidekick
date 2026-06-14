#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RENDERER="${SCRIPT_DIR}/render-agent-bundle.py"

python3 "${RENDERER}" render --agent claude --source-root "${REPO_ROOT}/skills" --dest-root "${REPO_ROOT}/agents/claude" --force
python3 "${RENDERER}" render --agent codex --source-root "${REPO_ROOT}/skills" --dest-root "${REPO_ROOT}/agents/codex" --force
python3 "${RENDERER}" render --agent cursor --source-root "${REPO_ROOT}/skills" --dest-root "${REPO_ROOT}/agents/cursor" --force

printf '[sidekick-sync] Generated agents/claude, agents/codex, and agents/cursor from skills/\n'

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RENDERER="${SCRIPT_DIR}/render-agent-bundle.py"

python3 "${RENDERER}" render --agent claude --source-root "${REPO_ROOT}/skills" --dest-root "${REPO_ROOT}/agents/claude"
python3 "${RENDERER}" render --agent codex --source-root "${REPO_ROOT}/skills" --dest-root "${REPO_ROOT}/agents/codex"

printf '[sidekick-sync] Generated agents/claude and agents/codex from skills/\n'

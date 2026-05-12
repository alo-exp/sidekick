#!/usr/bin/env bash
# Pre-release quality gate enforcer
# Intercepts Bash tool calls containing "gh release create" and denies them
# (via the Claude Code PreToolUse permissionDecision envelope) unless all
# quality-gate stage markers are present in Sidekick's state file.
#
# Stage count and marker names are defined in docs/pre-release-quality-gate.md.
# Each stage in that document ends with:
#   mkdir -p ~/.sidekick
#   echo "quality-gate-stage-N" >> ~/.sidekick/quality-gate-state
# If stages are added or removed from that document, update STAGE_COUNT below
# and commit both files together.
#
# NOTE: we deliberately do NOT use ~/.claude/.silver-bullet/state here —
# Silver Bullet's dev-cycle-check.sh hook blocks direct writes to that path
# and the markers would never land.

set -euo pipefail

STAGE_COUNT=4
STATE_FILE="$HOME/.sidekick/quality-gate-state"

# Fail closed if jq is absent — mirrors the sibling hook contract.
if ! command -v jq >/dev/null 2>&1; then
  echo "validate-release-gate: jq is required but not found in PATH" >&2
  exit 2
fi

INPUT=$(cat)

# Only act when tool_name == "Bash". A raw substring match against any payload
# (e.g. Read of a file that contains the phrase) would produce false blocks.
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

# Substring match is advisory — it blocks the canonical invocation. A
# determined operator can still reach the GitHub REST API (gh api
# repos/.../releases); humans remain the last line of defence.
case "$COMMAND" in
  *"gh release create"*) ;;
  *) exit 0 ;;
esac

missing=()
for stage in $(seq 1 "$STAGE_COUNT"); do
  # Anchored whole-line fixed-string match so quality-gate-stage-10 does
  # not satisfy stage 1.
  if ! grep -qxF "quality-gate-stage-${stage}" "$STATE_FILE" 2>/dev/null; then
    missing+=("${stage}")
  fi
done

if [ ${#missing[@]} -eq 0 ]; then
  exit 0
fi

missing_list=$(IFS=, ; echo "${missing[*]}")
reason="Pre-release quality gate not complete. Missing stage(s): ${missing_list}. Run all ${STAGE_COUNT} stages in docs/pre-release-quality-gate.md before cutting a release."

# Emit the canonical PreToolUse deny envelope. exit 0 — the harness reads the
# decision from stdout, not from the exit code.
jq -cn --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
exit 0

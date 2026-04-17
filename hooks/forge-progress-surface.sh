#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Forge Progress Surface (PostToolUse hook)
# =============================================================================
# Phase 7 (v1.2): runs after Bash tool calls. If the command contained a
# `forge -p …` invocation and the output contains a STATUS: block, emit a
# compact [FORGE-SUMMARY] additionalContext so the user (and Claude) see
# the result distilled in the transcript, including a /forge:replay hint
# keyed on the conversation-id UUID.
#
# Behavior contract:
#   * No-op when ~/.claude/.forge-delegation-active is absent.
#   * No-op when tool_name != "Bash".
#   * No-op when tool_input.command does NOT contain `forge -p`.
#   * No-op when output does NOT contain a `STATUS:` block.
#   * Otherwise: emit a `hookSpecificOutput.additionalContext` JSON envelope.
#
# Canonical PostToolUse success shape used by Claude Code:
#   { "hookSpecificOutput": {
#       "hookEventName": "PostToolUse",
#       "additionalContext": "<text>"
#   } }
#
# ANSI escapes in tool_response.output are stripped before STATUS parsing.
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

MARKER_FILE="${HOME}/.claude/.forge-delegation-active"

# -----------------------------------------------------------------------------
# strip_ansi — strip ANSI SGR color escapes from stdin.
# Regex: \x1b\[[0-9;]*m
# -----------------------------------------------------------------------------
strip_ansi() {
  sed $'s/\x1b\\[[0-9;]*m//g'
}

# -----------------------------------------------------------------------------
# extract_status_block — read the STATUS block from a Forge output stream.
# The block starts at the first line containing "STATUS:" and ends at the
# line containing "PATTERNS_DISCOVERED:" (inclusive). Capped at 20 lines.
# Input: stdin (ANSI-stripped text). Output: stdout (raw block).
# -----------------------------------------------------------------------------
extract_status_block() {
  awk '
    /^[[:space:]]*\[FORGE\][[:space:]]+STATUS:/ { inblk=1 }
    /^[[:space:]]*STATUS:/ && !inblk { inblk=1 }
    inblk { print; count++ }
    /PATTERNS_DISCOVERED:/ { if (inblk) { exit } }
    count >= 20 { exit }
  '
}

# -----------------------------------------------------------------------------
# main
# -----------------------------------------------------------------------------
main() {
  if ! command -v jq >/dev/null 2>&1; then
    # jq missing is a precondition failure but not fatal for a PostToolUse
    # that is supposed to be side-effect-free. Exit 0 silently.
    exit 0
  fi

  # Silent no-op if marker not present.
  [[ -f "$MARKER_FILE" ]] || exit 0

  local input tool_name cmd output
  input="$(cat)"
  tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
  [[ "$tool_name" = "Bash" ]] || exit 0

  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  [[ -n "$cmd" ]] || exit 0

  # Must be a forge -p invocation.
  [[ "$cmd" == *"forge "* ]] || exit 0
  [[ "$cmd" == *" -p"* ]] || exit 0

  # Pull the UUID we injected (if any) from the command for the replay hint.
  # grep returns 1 when no match — guard with `|| true` so set -e doesn't trip.
  local uuid
  uuid="$(printf '%s' "$cmd" | grep -oE -- '--conversation-id [0-9a-f-]{36}' 2>/dev/null | awk '{print $2}' | head -n 1 || true)"

  # Extract the tool output. Claude Code PostToolUse payloads put the raw
  # stdout under tool_response.output (string) or tool_response.stdout.
  output="$(printf '%s' "$input" | jq -r '.tool_response.output // .tool_response.stdout // empty' 2>/dev/null || true)"
  [[ -n "$output" ]] || exit 0

  # Strip ANSI + extract STATUS block. Guard against pipefail on empty awk.
  local status_block
  status_block="$(printf '%s' "$output" | strip_ansi | extract_status_block || true)"
  [[ -n "$status_block" ]] || exit 0

  # Build additionalContext payload.
  local header body footer payload
  header="[FORGE-SUMMARY] === Forge task complete ==="
  # Prefix each line of the block with [FORGE-SUMMARY] so it renders
  # alongside the output style's [FORGE] markers in the transcript.
  body="$(printf '%s' "$status_block" | sed 's/^/[FORGE-SUMMARY] /')"
  if [[ -n "$uuid" ]]; then
    footer="[FORGE-SUMMARY] Replay: /forge:replay $uuid"
  else
    footer="[FORGE-SUMMARY] (no conversation-id captured; replay unavailable for this call)"
  fi

  payload="$(printf '%s\n%s\n%s' "$header" "$body" "$footer")"

  jq -cn \
    --arg ctx "$payload" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
}

# Source-guard so tests can source the file to exercise helpers.
if [[ "${BASH_SOURCE[0]}" == "${0:-}" ]]; then
  main "$@"
fi

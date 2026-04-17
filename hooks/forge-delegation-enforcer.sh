#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Forge Delegation Enforcer (PreToolUse hook)
# =============================================================================
# Phase 6 (v1.2) foundation: parses PreToolUse JSON from stdin, checks the
# ~/.claude/.forge-delegation-active marker, and dispatches to per-tool
# decision logic. Decision branches are filled in by plans 06-02 and 06-03.
#
# Exit-code contract (canonical Claude Code PreToolUse hook):
#   0 + empty stdout  → pass-through (no decision)
#   0 + JSON stdout   → decision applied (hookSpecificOutput envelope)
#   2 + stderr        → hard precondition failure (malformed input, jq missing)
#
# Canonical decision JSON shape (spec correction from 06-RESEARCH.md §1):
#   { "hookSpecificOutput": {
#       "hookEventName": "PreToolUse",
#       "permissionDecision": "allow"|"deny",
#       "permissionDecisionReason": "<reason>",
#       "updatedInput": { "command": "<rewritten>" }  # optional
#   } }
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

MARKER_FILE="${HOME}/.claude/.forge-delegation-active"

# -----------------------------------------------------------------------------
# gen_uuid — produce a lowercase RFC 4122 UUID.
#
# Honors the SIDEKICK_TEST_UUID_OVERRIDE env var as a TEST-ONLY injection
# contract (see .planning/phases/06-.../06-01-hook-foundation.md
# <test_injection_contract>). When set and non-empty, the helper echoes that
# value verbatim and skips uuidgen. Consumed by 06-03's
# test_idx_append_idempotent_by_uuid to exercise the idx-dedup branch.
# Production callers never set this variable.
# -----------------------------------------------------------------------------
gen_uuid() {
  if [[ -n "${SIDEKICK_TEST_UUID_OVERRIDE:-}" ]]; then
    echo "$SIDEKICK_TEST_UUID_OVERRIDE"
    return 0
  fi
  uuidgen | tr 'A-Z' 'a-z'
}

# -----------------------------------------------------------------------------
# emit_decision — print a canonical hookSpecificOutput JSON envelope on stdout.
#   $1 = "allow" | "deny"
#   $2 = human-readable reason
#   $3 = (optional) rewritten Bash command; when non-empty, wrapped into
#        updatedInput.command.
# Always uses jq to build JSON (never string-concat, to survive arbitrary
# user input in commands).
# -----------------------------------------------------------------------------
emit_decision() {
  local decision="$1"
  local reason="$2"
  local updated_cmd="${3:-}"

  if [[ -n "$updated_cmd" ]]; then
    jq -cn \
      --arg d "$decision" \
      --arg r "$reason" \
      --arg c "$updated_cmd" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r, updatedInput: {command: $c}}}'
  else
    jq -cn \
      --arg d "$decision" \
      --arg r "$reason" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  fi
}

# -----------------------------------------------------------------------------
# Decision stubs — pass-through in this plan. Real logic lands in 06-02/06-03.
# -----------------------------------------------------------------------------
decide_write_edit() { return 0; }     # 06-02 Task 1: deny branch
decide_notebook_edit() { return 0; }  # 06-02 Task 1: deny branch
decide_bash() { return 0; }           # 06-02 Task 2 + 06-03: classifier + rewrite

# -----------------------------------------------------------------------------
# main — entry point. Gated so tests can `source` the file without triggering
# stdin read.
# -----------------------------------------------------------------------------
main() {
  # Hard precondition: jq must be available.
  if ! command -v jq >/dev/null 2>&1; then
    echo "forge-delegation-enforcer: jq not found on PATH" >&2
    exit 2
  fi

  # Read all of stdin.
  local input
  input="$(cat)"

  # Parse tool_name; empty/null/parse-fail → exit 2.
  local tool_name tool_input
  if ! tool_name="$(printf '%s' "$input" | jq -er '.tool_name // empty' 2>/dev/null)"; then
    echo "forge-delegation-enforcer: malformed PreToolUse JSON on stdin" >&2
    exit 2
  fi
  if [[ -z "$tool_name" ]]; then
    echo "forge-delegation-enforcer: malformed PreToolUse JSON on stdin" >&2
    exit 2
  fi
  tool_input="$(printf '%s' "$input" | jq -c '.tool_input // {}')"

  # Marker-file check: inactive → silent no-op.
  if [[ ! -f "$MARKER_FILE" ]]; then
    exit 0
  fi

  # Dispatch. Stubs pass-through; real logic added in 06-02 and 06-03.
  case "$tool_name" in
    Write|Edit)     decide_write_edit "$tool_input" ;;
    NotebookEdit)   decide_notebook_edit "$tool_input" ;;
    Bash)           decide_bash "$tool_input" ;;
    *)              exit 0 ;;
  esac
}

# Source-guard: run main() only when executed directly, not when sourced by
# tests. Uses ${0:-} defensively in case the file is piped via `bash <(...)`.
if [[ "${BASH_SOURCE[0]}" == "${0:-}" ]]; then
  main "$@"
fi

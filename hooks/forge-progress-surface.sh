#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Forge Progress Surface (PostToolUse hook)
# =============================================================================
# Phase 7 (v1.2): runs after Bash tool calls. If the command contained a
# `forge -p …` invocation and the output contains a STATUS: block, emit a
# compact [FORGE-SUMMARY] additionalContext so the user (and Claude) see
# the result distilled in the transcript with a stop-mode hint.
#
# Behavior contract:
#   * No-op when the current session marker is absent.
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

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib/sidekick-registry.sh
source "${HOOK_DIR}/lib/sidekick-registry.sh"

SIDEKICK_NAME="forge"
MARKER_FILE="$(sidekick_session_marker_file "$SIDEKICK_NAME" 2>/dev/null || true)"

# -----------------------------------------------------------------------------
# strip_ansi — strip a broad set of terminal control sequences from stdin.
# Covers:
#   - CSI sequences  \x1b[...  terminated by @–~ (includes SGR colors, cursor
#     moves, erase, etc.)
#   - OSC sequences  \x1b]... terminated by BEL or ST
#   - Other C1 escape introducers (\x1b followed by a single letter)
#   - Backspace, CR, and the other C0 control chars except TAB (0x09) and
#     newline (0x0a). This prevents fake-prompt / line-overwrite tricks from
#     attacker-controlled output landing in the transcript.
# SENTINEL v2.3 FINDING-R15-M6: previous SGR-only strip let CSI cursor moves
# and OSC title-set sequences pass through additionalContext.
# -----------------------------------------------------------------------------
strip_ansi() {
  # perl is portable across macOS and Linux; sed bracket-class handling
  # differs between BSD and GNU for the `[ -/]` range. The single perl call
  # is simpler and consistently strips:
  #   CSI   \x1b[ ... (any intermediate bytes) final byte @-~
  #   OSC   \x1b] ... terminated by BEL or ESC-\
  #   7-bit C1 single-char escapes (\x1b[@-Z\\-_])
  #   C0 controls except TAB(09) and LF(0a)
  perl -0777 -pe '
    s/\x1b\[[0-9;?]*[ -\/]*[@-~]//g;
    s/\x1b\][^\x07\x1b]*(\x07|\x1b\\)//g;
    s/\x1b[@-Z\\-_]//g;
    s/[\x00-\x08\x0b-\x1f\x7f]//g;
  '
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
  [[ -n "$MARKER_FILE" ]] || exit 0
  [[ -f "$MARKER_FILE" ]] || exit 0

  local input tool_name cmd output
  # SENTINEL v2.3 FINDING-R15-M5: cap stdin at 2 MiB so a malicious / runaway
  # Forge subprocess cannot force the hook to buffer hundreds of megabytes
  # in shell memory. The STATUS block is capped at 20 lines downstream;
  # 2 MiB is ~10× the largest plausible legitimate payload.
  input="$(head -c 2097152)"
  tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
  [[ "$tool_name" = "Bash" ]] || exit 0

  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  [[ -n "$cmd" ]] || exit 0

  # Must be a forge -p invocation.
  [[ "$cmd" == *"forge "* ]] || exit 0
  [[ "$cmd" == *" -p"* ]] || exit 0

  # Pull the UUID we injected (if any) from the command for diagnostics.
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

  # SENTINEL v2.3 FINDING-R16-I1: defensive secret redaction. Forge's STATUS
  # block should never contain credentials, but a misbehaving task could echo
  # an auth header, API key, or bearer token into stdout that we're about to
  # splice into the transcript via additionalContext. Scrub obvious patterns
  # before the surface so a leaked secret never survives to the user-visible
  # envelope.
  # NOTE: perl interpolates `$1[...]` as array subscript (@1 with literal
  # subscript), producing an empty expansion and wiping the line. Use
  # `${1}[...]` to force capture-group interpolation.
  status_block="$(printf '%s' "$status_block" | perl -pe '
    s/(?i)(authorization:\s*)(?:bearer\s+)?\S+.*$/${1}[REDACTED]/g;
    s/(?i)("authorization"\s*:\s*")((?:bearer\s+)?[^"]+)(")/${1}[REDACTED]${3}/g;
    s/(?i)("api[_-]?key"\s*:\s*")([^"]+)(")/${1}[REDACTED]${3}/g;
    s/(?i)((?<!")authorization:\s*)(?:bearer\s+)?\S+.*$/${1}[REDACTED]/g;
    s/(?i)((?<!")api[_-]?key\s*[:=]\s*)\S+/${1}[REDACTED]/g;
    s/sk-[A-Za-z0-9_\-\.\/+]{10,}(?=\s|['"'"'">},]|$)/[REDACTED-SK-TOKEN]/g;
    s/\bgh[pousra]_[A-Za-z0-9]{20,}\b/[REDACTED-GH-TOKEN]/g;
    s/\bgithub_pat_[A-Za-z0-9_]{20,}\b/[REDACTED-GH-TOKEN]/g;
    s/\bxox[abprse]-[A-Za-z0-9-]{10,}\b/[REDACTED-SLACK-TOKEN]/g;
  ')"

  # Build additionalContext payload.
  local header body footer payload
  header="[FORGE-SUMMARY] [UNTRUSTED] === Forge task complete ==="
  # Prefix each line of the block with an explicit untrusted-data marker so
  # downstream context readers do not mistake Forge output for authoritative
  # instructions.
  body="$(printf '%s' "$status_block" | sed 's/^/[FORGE-SUMMARY] [UNTRUSTED] /')"
  if [[ -n "$uuid" ]]; then
    footer="[FORGE-SUMMARY] [UNTRUSTED] Stop delegation: /forge-stop"
  else
    footer="[FORGE-SUMMARY] [UNTRUSTED] Stop delegation: /forge-stop (no conversation-id captured)"
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

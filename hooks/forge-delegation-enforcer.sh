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
# Canonical deny reason for direct file edits (shared by Write/Edit/Notebook).
# -----------------------------------------------------------------------------
DENY_EDIT_REASON='Sidekick /forge mode is active: direct file edits are delegated to Forge. Use: Bash { command: "forge -p \"<your task description>\"" }. To temporarily bypass for Level 3 takeover, set FORGE_LEVEL_3=1 in the Bash environment.'

deny_direct_edit() {
  emit_decision "deny" "$DENY_EDIT_REASON" ""
}

decide_write_edit()    { deny_direct_edit; }
decide_notebook_edit() { deny_direct_edit; }

# -----------------------------------------------------------------------------
# Audit index + activation-lifecycle helpers (Plan 06-03).
# -----------------------------------------------------------------------------

# resolve_forge_dir — prints the `.forge/` directory path, preferring
# CLAUDE_PROJECT_DIR when set (Claude Code populates this to the project root).
resolve_forge_dir() {
  printf '%s/.forge' "${CLAUDE_PROJECT_DIR:-$PWD}"
}

# ensure_forge_dir_and_idx — idempotent lazy init of .forge/ and
# .forge/conversations.idx. Called only after a successful db_precheck.
ensure_forge_dir_and_idx() {
  local dir
  dir="$(resolve_forge_dir)"
  mkdir -p "$dir" 2>/dev/null || return 1
  touch -a "$dir/conversations.idx" 2>/dev/null || return 1
  return 0
}

# db_precheck — one-shot `forge conversation list` health check gated by a
# sentinel file. Sentinel mtime is compared against the marker file via the
# portable bash built-in `-nt` operator (works on bash 3.2+ across macOS/Linux
# — avoids the GNU `stat -c %Y` vs BSD `stat -f %m` divergence).
# Returns 0 if DB writable (or sentinel still fresh), 1 if forge invocation
# failed.
db_precheck() {
  local dir sentinel
  dir="$(resolve_forge_dir)"
  sentinel="$dir/.db_check_ok"
  # If sentinel exists AND marker is NOT newer than sentinel → short-circuit.
  # The -nt test returns false when sentinel is missing (arg2 missing), which
  # is why we check existence first.
  if [[ -f "$sentinel" ]] && ! [[ "$MARKER_FILE" -nt "$sentinel" ]]; then
    return 0
  fi
  # Either sentinel missing or marker newer → run the health check.
  if forge conversation list >/dev/null 2>&1; then
    mkdir -p "$dir" 2>/dev/null || true
    touch "$sentinel" 2>/dev/null || true
    return 0
  fi
  return 1
}

# extract_task_hint — derive the `-p` argument from a Bash command, using
# python3 shlex (non-eval, injection-safe). Falls back to the literal string
# `(task hint unavailable)` if python3 is missing. The eval-based bash parser
# from the research draft was REJECTED on security grounds — $cmd is
# untrusted input from Claude Code.
# See <task_hint_extraction_design> in 06-03-audit-index-and-activation.md.
extract_task_hint() {
  local cmd="$1"
  local hint=""
  if command -v python3 >/dev/null 2>&1; then
    hint="$(python3 -c '
import shlex, sys
try:
    toks = shlex.split(sys.argv[1])
    if "-p" in toks:
        i = toks.index("-p")
        if i + 1 < len(toks):
            sys.stdout.write(toks[i+1])
except Exception:
    pass
' "$cmd" 2>/dev/null || true)"
  fi
  if [[ -z "$hint" ]]; then
    hint="(task hint unavailable)"
  fi
  # Replace tabs/newlines with spaces; truncate to 80 chars.
  hint="${hint//$'\t'/ }"
  hint="${hint//$'\n'/ }"
  printf '%s' "${hint:0:80}"
}

# append_idx_row — write one tab-separated line to .forge/conversations.idx.
# Dedupes on UUID (grep -qF matches the exact UUID anywhere in the file).
# All file I/O is wrapped in `|| true` so a filesystem hiccup never causes
# the hook to exit non-zero AFTER emit_decision has already printed.
append_idx_row() {
  local uuid hint dir idx
  uuid="$1"
  hint="$2"
  dir="$(resolve_forge_dir)"
  idx="$dir/conversations.idx"

  # Dedup: if this UUID is already in the idx, skip.
  if [[ -f "$idx" ]] && grep -qF "$uuid" "$idx" 2>/dev/null; then
    return 0
  fi

  # Portable sidekick-tag (bash 3.2+): take the UUID's last dash-delimited
  # segment, then the first 8 chars. DO NOT use `${uuid: -8}` — negative-offset
  # substring requires bash 4+ and fails on macOS stock /bin/bash (3.2).
  local tag_suffix sidekick_tag
  tag_suffix="${uuid##*-}"
  tag_suffix="${tag_suffix:0:8}"
  sidekick_tag="sidekick-$(date +%s)-$tag_suffix"

  {
    printf '%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$uuid" "$sidekick_tag" "$hint" >> "$idx"
  } 2>/dev/null || true
  return 0
}

# -----------------------------------------------------------------------------
# Bash classifier + forge -p rewrite (Plan 06-02).
#
# Returns one of five classifications by dispatching to emit_decision or
# exiting silently for pass-through:
#   FORGE_P_REWRITE            - inject UUID + --verbose + output pipes
#   FORGE_P_IDEMPOTENT         - already has --conversation-id → pass-through
#   READ_ONLY                  - Brain-role inspection → pass-through
#   MUTATING (deny)            - deny unless FORGE_LEVEL_3=1
#   MUTATING_LEVEL3 (bypass)   - pass-through
# -----------------------------------------------------------------------------

# Strip leading `FOO=bar BAZ=qux ` env-var assignments; echo the remainder.
strip_env_prefix() {
  local cmd="$1"
  # Loop removing leading `WORD=VALUE ` tokens. Values may be unquoted single
  # words; complex quoted values aren't common in Bash tool_input.command.
  while [[ "$cmd" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+ ]]; do
    cmd="${cmd#"${BASH_REMATCH[0]}"}"
  done
  printf '%s' "$cmd"
}

# Extract first "word" — the command token after env-var prefix. Supports
# two-token prefixes (e.g. `git status`, `forge conversation`).
first_token() {
  local cmd stripped
  cmd="$1"
  stripped="$(strip_env_prefix "$cmd")"
  # Print up to 2 tokens joined by a single space for two-word prefix matching.
  printf '%s' "$stripped" | awk '{ if (NF>=2) { print $1" "$2 } else { print $1 } }'
}

has_conversation_id() {
  [[ "$1" =~ (^|[[:space:]])--conversation-id([[:space:]]|=) ]]
}

is_forge_p() {
  # Matches `forge … -p …` where `forge` is the command (possibly preceded by
  # env-var assignments, possibly followed by `-C <dir>`/`--cwd <dir>`).
  local cmd stripped
  cmd="$1"
  stripped="$(strip_env_prefix "$cmd")"
  [[ "$stripped" =~ ^forge([[:space:]]|$) ]] || return 1
  [[ "$stripped" =~ (^|[[:space:]])-p([[:space:]]|$) ]] || return 1
  return 0
}

is_read_only() {
  local cmd first
  cmd="$1"
  # A command with a write redirect is never read-only, regardless of its
  # first token (e.g. `echo hi > /tmp/out` is mutating).
  if has_write_redirect "$cmd"; then
    return 1
  fi
  # `sed -i` and `awk -i inplace` mutate files even though sed/awk are in
  # the single-word read-only list below. Reject them here so decide_bash's
  # ordered dispatch (read-only check before mutating check) still denies.
  if [[ "$cmd" =~ (^|[[:space:]])sed[[:space:]]+-i ]] || [[ "$cmd" =~ (^|[[:space:]])awk[[:space:]]+-i[[:space:]]+inplace ]]; then
    return 1
  fi
  first="$(first_token "$cmd")"
  case "$first" in
    "git status"|"git log"|"git diff"|"git show"|"git branch"|"git remote"|"git rev-parse"|"git ls-files"|"git stash list") return 0 ;;
    "forge conversation"|"forge --version"|"forge --help"|"forge info") return 0 ;;
  esac
  case "${first%% *}" in
    ls|la|ll|pwd|cd|echo|printf|cat|head|tail|wc|file|stat|tree|diff|cmp) return 0 ;;
    grep|egrep|fgrep|rg|ag|ack|find|fd|locate|which|whereis|type|command) return 0 ;;
    test|'[') return 0 ;;
    env|printenv|whoami|id|hostname|date|uname) return 0 ;;
    jq|awk|sort|uniq|column|tr|cut|sed|xargs) return 0 ;;
  esac
  return 1
}

# Unquoted `>` or `>>` redirect to a path other than /dev/null → mutating.
has_write_redirect() {
  local cmd="$1"
  # Quick reject if no redirect chars at all.
  [[ "$cmd" == *">"* ]] || return 1
  # Accept redirects to /dev/null as non-mutating.
  # Remove all occurrences of `> /dev/null` / `>> /dev/null` / `2>/dev/null` / `2>&1`
  local pruned="$cmd"
  pruned="${pruned//>\/dev\/null/}"
  pruned="${pruned//> \/dev\/null/}"
  pruned="${pruned//>> \/dev\/null/}"
  pruned="${pruned//>>\/dev\/null/}"
  pruned="${pruned//2>&1/}"
  pruned="${pruned//2>\/dev\/null/}"
  pruned="${pruned//2> \/dev\/null/}"
  # Any remaining > or >> means a write redirect to something else.
  [[ "$pruned" == *">"* ]]
}

is_mutating() {
  local cmd first
  cmd="$1"
  first="$(first_token "$cmd")"
  # Two-word git mutators.
  case "$first" in
    "git add"|"git commit"|"git push"|"git pull"|"git fetch"|"git checkout"|"git reset"|"git rebase"|"git merge"|"git cherry-pick"|"git restore"|"git rm"|"git mv"|"git tag"|"git clean"|"git stash") return 0 ;;
  esac
  case "${first%% *}" in
    rm|rmdir|mv|cp|ln|chmod|chown|chgrp|touch|mkdir) return 0 ;;
    npm|pnpm|yarn|bundle|pip|gem|cargo|go) return 0 ;;
    tar|zip|unzip|gunzip|gzip) return 0 ;;
    systemctl|service|launchctl|brew|apt|apt-get|yum|dnf) return 0 ;;
    curl|wget) return 0 ;;
  esac
  # Write-redirect anywhere in the command.
  if has_write_redirect "$cmd"; then
    return 0
  fi
  # `sed -i` and `awk -i inplace` are mutating.
  if [[ "$cmd" =~ (^|[[:space:]])sed[[:space:]]+-i ]] || [[ "$cmd" =~ (^|[[:space:]])awk[[:space:]]+-i[[:space:]]+inplace ]]; then
    return 0
  fi
  return 1
}

# Rewrite a `forge … -p …` command with UUID + --verbose and output pipes.
# Single call to gen_uuid per invocation.
rewrite_forge_p() {
  local cmd uuid injected
  cmd="$1"
  uuid="$(gen_uuid)"
  # Inject `--conversation-id <uuid> --verbose ` after the first `forge ` token.
  injected="${cmd/forge /forge --conversation-id $uuid --verbose }"
  # Append output prefix pipes. Single quotes inside the command must be
  # preserved verbatim; jq --arg handles the final string escape for JSON.
  local pipes=" 2> >(sed 's/^/[FORGE-LOG] /' >&2) | sed 's/^/[FORGE] /'"
  printf '%s%s' "$injected" "$pipes"
}

decide_bash() {
  local tool_input_json cmd
  tool_input_json="$1"
  cmd="$(printf '%s' "$tool_input_json" | jq -r '.command // empty')"
  [[ -z "$cmd" ]] && return 0

  # 1. forge -p rewrite / idempotent passthrough.
  if is_forge_p "$cmd"; then
    if has_conversation_id "$cmd"; then
      return 0  # idempotent passthrough
    fi
    # Strict execution order (see <activation_lifecycle_design> in
    # 06-03-audit-index-and-activation.md):
    #   (a) db_precheck — if fails, deny and RETURN. Nothing under .forge/
    #       is created on this code path.
    #   (b) ensure_forge_dir_and_idx — lazy init of .forge/ and idx.
    #   (c) generate UUID + build rewritten command.
    #   (d) emit_decision.
    #   (e) append_idx_row.
    if ! db_precheck; then
      emit_decision "deny" "Sidekick: Forge DB not writable ('forge conversation list' failed). Deactivate via /forge:deactivate, resolve the Forge state, and re-activate." ""
      return 0
    fi
    ensure_forge_dir_and_idx || true
    local uuid rewritten pipes hint
    uuid="$(gen_uuid)"
    rewritten="${cmd/forge /forge --conversation-id $uuid --verbose }"
    pipes=" 2> >(sed 's/^/[FORGE-LOG] /' >&2) | sed 's/^/[FORGE] /'"
    rewritten="${rewritten}${pipes}"
    emit_decision "allow" "Sidekick: injected --conversation-id + --verbose + output prefixing." "$rewritten"
    hint="$(extract_task_hint "$cmd")"
    append_idx_row "$uuid" "$hint"
    return 0
  fi

  # 2. read-only passthrough.
  if is_read_only "$cmd"; then
    return 0
  fi

  # 3. mutating command handling.
  if is_mutating "$cmd"; then
    if [[ "${FORGE_LEVEL_3:-}" == "1" ]]; then
      return 0  # Level-3 passthrough
    fi
    emit_decision "deny" "Sidekick /forge mode: mutating command denied. Delegate via forge -p, or set FORGE_LEVEL_3=1 to bypass for a Level 3 takeover." ""
    return 0
  fi

  # 4. Unclassified → conservative deny.
  emit_decision "deny" "Sidekick /forge mode: command could not be classified. Delegate via forge -p or set FORGE_LEVEL_3=1." ""
}

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

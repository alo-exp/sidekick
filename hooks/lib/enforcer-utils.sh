#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Enforcer Utility Library
# =============================================================================
# Sourced by hooks/forge-delegation-enforcer.sh at startup.
# Safe to source independently in tests — no side effects at source time,
# no main() call, no exit statements.
#
# Functions exported (in definition order):
#   strip_env_prefix         — strip leading FOO=bar env-var tokens from cmd
#   export_env_prefix        — export leading env-var tokens into shell env (ENF-04)
#   has_write_redirect       — detect unquoted write-redirect (bug-fixed: ENF-01/02/03)
#   first_token              — extract first 1-2 command tokens after env prefix
#   is_allowed_doc_path      — return 0 if path is under .planning/ or docs/ (PATH-01)
#   is_read_only             — return 0 if command is known read-only (includes gh ENF-05)
#   is_mutating              — return 0 if command is known mutating (includes gh ENF-05)
#   has_mutating_chain_segment — return 0 if any && or ; segment is mutating (ENF-06)
#   has_mutating_pipe_segment  — return 0 if any | segment is mutating (ENF-08)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# Source-guard — prevent double-sourcing.
[[ -n "${_SIDEKICK_ENFORCER_UTILS_LOADED:-}" ]] && return 0
_SIDEKICK_ENFORCER_UTILS_LOADED=1

# -----------------------------------------------------------------------------
# strip_env_prefix
# Strip leading `FOO=bar BAZ=qux ` env-var assignments; echo the remainder.
# -----------------------------------------------------------------------------
strip_env_prefix() {
  local cmd="$1"
  # Loop removing leading `WORD=VALUE ` tokens. Values may be unquoted single
  # words; complex quoted values aren't common in Bash tool_input.command.
  while [[ "$cmd" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+ ]]; do
    cmd="${cmd#"${BASH_REMATCH[0]}"}"
  done
  printf '%s' "$cmd"
}

# -----------------------------------------------------------------------------
# export_env_prefix  (ENF-04)
# Export leading `FOO=bar BAZ=qux ` env-var assignments into the shell
# environment so that the delegated command can read them.
#
# Security note: only [A-Za-z_][A-Za-z0-9_]* names are accepted (anchored
# regex); shell metacharacters cannot appear in the variable name. Values are
# exported as literals — they are not evaluated or interpreted by the shell.
# This runs inside the short-lived hook subprocess, so exported vars do not
# persist beyond the hook invocation.
# -----------------------------------------------------------------------------
export_env_prefix() {
  local cmd="$1"
  while [[ "$cmd" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=([^[:space:]]*)([[:space:]]+) ]]; do
    export "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
    cmd="${cmd#"${BASH_REMATCH[0]}"}"
  done
}

# -----------------------------------------------------------------------------
# has_write_redirect  (bug-fixed: ENF-01, ENF-02, ENF-03)
# Return 0 (true) if the command contains an unquoted write-redirect to a
# destination other than /dev/null.
#
# ENF-01: Process-substitution >(cmd) is a write path — detect it explicitly
#         before any pruning, because pruning may remove the > character.
# ENF-02: fd-redirect forms (>&1, >&2, >&-, N>&M) are NOT file writes — strip
#         them with explicit bash 3.2-compatible substitutions before checking.
# ENF-03: > inside double- or single-quoted strings is not a redirect — strip
#         quoted regions via sed before the final check.
#         Known limitation: heredoc bodies (<<EOF...EOF) are not stripped.
# -----------------------------------------------------------------------------
has_write_redirect() {
  local cmd="$1"

  # Quick reject: no > character at all → definitely not a write redirect.
  [[ "$cmd" == *">"* ]] || return 1

  # ENF-01: Explicit process-substitution check. >(cmd) is a write path.
  # Use regex matching which is more portable across bash 3.2+.
  # Store regex in variable to avoid [[ parser misinterpreting literal ')'.
  local _proc_sub_re='>[(][^)]*[)]'
  [[ "$cmd" =~ $_proc_sub_re ]] && return 0

  # ENF-03: Strip quoted regions to avoid false-positives from > inside strings.
  # Note: heredoc bodies (<<EOF...EOF) are not stripped — known limitation.
  local unquoted
  unquoted="$(printf '%s' "$cmd" | sed "s/\"[^\"]*\"//g; s/'[^']*'//g")"
  local pruned="$unquoted"

  # Accept common non-mutating redirect forms — remove them before final check.
  # /dev/null redirects (output suppression):
  pruned="${pruned//>\/dev\/null/}"
  pruned="${pruned//> \/dev\/null/}"
  pruned="${pruned//>> \/dev\/null/}"
  pruned="${pruned//>>\/dev\/null/}"
  pruned="${pruned//2>&1/}"
  pruned="${pruned//2>\/dev\/null/}"
  pruned="${pruned//2> \/dev\/null/}"

  # ENF-02: fd-redirect forms — bash 3.2 compatible explicit substitutions.
  # These redirect between file descriptors, not to files.
  pruned="${pruned//>&0/}"
  pruned="${pruned//>&1/}"
  pruned="${pruned//>&2/}"
  pruned="${pruned//>&3/}"
  pruned="${pruned//>&-/}"
  pruned="${pruned//0>&1/}"
  pruned="${pruned//1>&2/}"
  pruned="${pruned//2>&0/}"

  # Any remaining > or >> means a write redirect to a real file.
  [[ "$pruned" == *">"* ]]
}

# -----------------------------------------------------------------------------
# first_token
# Extract first "word" — the command token after env-var prefix. Returns up
# to 2 tokens joined by a single space for two-word prefix matching.
# -----------------------------------------------------------------------------
first_token() {
  local cmd stripped
  cmd="$1"
  stripped="$(strip_env_prefix "$cmd")"
  # Print up to 2 tokens joined by a single space for two-word prefix matching.
  printf '%s' "$stripped" | awk '{ if (NF>=2) { print $1" "$2 } else { print $1 } }'
}

# first_three_tokens
# Like first_token but returns up to 3 tokens for three-word prefix matching
# (e.g. "gh issue list", "gh pr view"). Used by is_read_only/is_mutating for
# gh sub-commands where the meaningful verb is the third token.
# -----------------------------------------------------------------------------
first_three_tokens() {
  local cmd stripped
  cmd="$1"
  stripped="$(strip_env_prefix "$cmd")"
  printf '%s' "$stripped" | awk '{ if (NF>=3) { print $1" "$2" "$3 } else if (NF==2) { print $1" "$2 } else { print $1 } }'
}

# -----------------------------------------------------------------------------
# is_allowed_doc_path  (PATH-01)
# Return 0 (allow) if the given path is under .planning/ or docs/.
# Strips a single leading "./" prefix to normalize "./planning/..." etc.
#
# Examples:
#   ".planning/PLAN.md"   → .planning/ match → 0 (allow)
#   "./.planning/PLAN.md" → strip ./ → ".planning/PLAN.md" → 0 (allow)
#   "docs/index.html"     → docs/ match → 0 (allow)
#   "./planning/PLAN.md"  → strip ./ → "planning/PLAN.md" → no match → 1 (deny)
#   "hooks/enforcer.sh"   → no match → 1 (deny)
#   ""                    → empty → 1 (deny)
# -----------------------------------------------------------------------------
is_allowed_doc_path() {
  local path="$1"
  [[ -z "$path" ]] && return 1
  # Normalize: strip a single leading "./" prefix.
  path="${path#./}"
  [[ "$path" == .planning/* ]] && return 0
  [[ "$path" == docs/* ]] && return 0
  return 1
}

# -----------------------------------------------------------------------------
# is_read_only
# Return 0 (true) if the command is known to be read-only (non-mutating).
# Includes gh read-only sub-commands (ENF-05).
# -----------------------------------------------------------------------------
is_read_only() {
  local cmd first first3
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
  # ENF-05: gh read-only sub-commands require 3-token matching (gh <noun> <verb>).
  first3="$(first_three_tokens "$cmd")"
  case "$first3" in
    "gh issue list"|"gh issue view"|"gh pr list"|"gh pr view"|"gh pr status"|"gh pr checks"\
    |"gh label list"|"gh release list"|"gh repo view"|"gh project list"\
    |"gh run list"|"gh run view"|"gh workflow list") return 0 ;;
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

# -----------------------------------------------------------------------------
# is_mutating
# Return 0 (true) if the command is known to be mutating (writes, deletes,
# network calls, package installs, etc.).
# Includes gh mutating sub-commands (ENF-05).
# -----------------------------------------------------------------------------
is_mutating() {
  local cmd first first3
  cmd="$1"
  first="$(first_token "$cmd")"
  # Two-word git mutators.
  case "$first" in
    "git add"|"git commit"|"git push"|"git pull"|"git fetch"|"git checkout"|"git reset"|"git rebase"|"git merge"|"git cherry-pick"|"git restore"|"git rm"|"git mv"|"git tag"|"git clean"|"git stash") return 0 ;;
  esac
  # ENF-05: gh mutating sub-commands require 3-token matching (gh <noun> <verb>).
  first3="$(first_three_tokens "$cmd")"
  case "$first3" in
    "gh issue create"|"gh issue edit"|"gh issue close"|"gh issue delete"\
    |"gh pr create"|"gh pr merge"|"gh pr close"|"gh pr edit"\
    |"gh release create"|"gh release delete"|"gh release upload"\
    |"gh project item-add"|"gh project item-edit"\
    |"gh repo clone"|"gh repo fork") return 0 ;;
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

# -----------------------------------------------------------------------------
# has_mutating_chain_segment  (ENF-06)
# Return 0 (true) if any && or ; separated segment of the command is mutating.
# Splits the command on && and ; delimiters using awk, then tests each segment
# with is_mutating.
# -----------------------------------------------------------------------------
has_mutating_chain_segment() {
  local cmd="$1" seg
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[! ]*}"}"  # ltrim whitespace
    [[ -z "$seg" ]] && continue
    if is_mutating "$seg"; then return 0; fi
  done < <(printf '%s' "$cmd" | awk '{gsub(/&&|;/, "\n"); print}')
  return 1
}

# -----------------------------------------------------------------------------
# has_mutating_pipe_segment  (ENF-08)
# Return 0 (true) if any | separated segment of the command is mutating.
# Splits the command on | delimiters using awk, then tests each segment
# with is_mutating.
# -----------------------------------------------------------------------------
has_mutating_pipe_segment() {
  local cmd="$1" seg
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[! ]*}"}"  # ltrim whitespace
    [[ -z "$seg" ]] && continue
    if is_mutating "$seg"; then return 0; fi
  done < <(printf '%s' "$cmd" | awk '{gsub(/\|/, "\n"); print}')
  return 1
}

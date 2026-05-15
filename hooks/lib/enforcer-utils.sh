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
#   export_env_prefix        — consume leading env-var tokens from cmd text (ENF-04)
#   has_write_redirect       — detect unquoted write-redirect (bug-fixed: ENF-01/02/03)
#   first_token              — extract first 1-2 command tokens after env prefix
#   is_allowed_doc_path      — return 0 if path is under .planning/ or docs/ (PATH-01)
#   is_within_project_root    — return 0 if path resolves inside CLAUDE_PROJECT_DIR
#   is_read_only             — return 0 if command is known read-only (includes gh ENF-05)
#   is_mutating              — return 0 if command is known mutating (includes gh ENF-05)
#   has_non_readonly_chain_segment — return 0 if any &&/;/|| segment is not explicitly read-only (ENF-06)
#   has_non_readonly_pipe_segment  — return 0 if any | segment is not explicitly read-only (ENF-08)
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
# Consume leading `FOO=bar BAZ=qux ` env-var assignments from the command
# text without propagating them into the hook process or delegated command.
# Command-text env prefixes are untrusted input and must not be able to
# re-root the project, self-activate bypasses, or poison helper subprocesses.
# -----------------------------------------------------------------------------
export_env_prefix() {
  local cmd="$1"
  while [[ "$cmd" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=([^[:space:]]*)([[:space:]]+) ]]; do
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
# wrapper_is_read_only
# Return 0 when a shell wrapper command is being used in a read-only way.
# This keeps benign wrapper forms pass-through while still denying shell
# execution wrappers and mutating xargs targets.
# -----------------------------------------------------------------------------
wrapper_is_read_only() {
  local cmd="$1"
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$cmd" <<'PY'
import re
import shlex
import sys

cmd = sys.argv[1]
try:
    tokens = shlex.split(cmd)
except Exception:
    raise SystemExit(1)

SAFE_SIMPLE = {
    "ls", "la", "ll", "pwd", "cd", "echo", "printf", "cat", "head",
    "tail", "wc", "file", "stat", "tree", "diff", "cmp", "grep",
    "egrep", "fgrep", "rg", "ag", "ack", "find", "fd", "locate",
    "which", "whereis", "type", "printenv", "whoami", "id", "hostname",
    "date", "uname", "jq", "sort", "uniq", "column", "tr", "cut",
}
SAFE_GIT_SIMPLE = {"status", "log", "diff", "show", "rev-parse", "ls-files"}
SAFE_GH = {
    "gh issue list", "gh issue view", "gh pr list", "gh pr view",
    "gh pr status", "gh pr checks", "gh label list",
    "gh release list", "gh repo view", "gh project list",
    "gh run list", "gh run view", "gh workflow list",
}
SHELL_WRAPPERS = {"sh", "bash", "zsh", "fish", "dash", "ksh"}


def sed_is_inplace(seq):
    for tok in seq[1:]:
        if tok == "--":
            break
        if tok == "-i" or tok.startswith("-i.") or tok.startswith("-i"):
            return True
        if tok == "--in-place" or tok.startswith("--in-place="):
            return True
        if tok.startswith("-") and not tok.startswith("--") and "i" in tok[1:]:
            return True
    return False


def awk_is_inplace(seq):
    for i, tok in enumerate(seq[1:], start=1):
        if tok == "--":
            break
        nxt = seq[i + 1] if i + 1 < len(seq) else ""
        if tok == "-i" and nxt == "inplace":
            return True
        if tok == "-iinplace":
            return True
        if tok == "--include" and nxt == "inplace":
            return True
        if tok == "--include=inplace":
            return True
    return False


def has_inplace_mutation(seq):
    if not seq:
        return False
    if seq[0] == "sed":
        return sed_is_inplace(seq)
    if seq[0] == "awk":
        return awk_is_inplace(seq)
    return False


def sed_script_is_mutating(script):
    if re.search(r"(^|[;\n{])\s*(?:[0-9,$!]+|/[^/\n]+/)?\s*[we]\b", script):
        return True
    if re.search(r"s(.).*?\1.*?\1[0-9gp]*[we]\b", script):
        return True
    return False


def sed_is_read_only(seq):
    if sed_is_inplace(seq):
        return False
    index = 1
    saw_expression = False
    while index < len(seq):
        tok = seq[index]
        if tok == "--":
            index += 1
            break
        if tok in {"-f", "--file"} or tok.startswith("--file="):
            return False
        if tok == "-e" or tok == "--expression":
            if index + 1 >= len(seq) or sed_script_is_mutating(seq[index + 1]):
                return False
            saw_expression = True
            index += 2
            continue
        if tok.startswith("--expression="):
            if sed_script_is_mutating(tok.split("=", 1)[1]):
                return False
            saw_expression = True
            index += 1
            continue
        if tok.startswith("-") and tok != "-":
            index += 1
            continue
        if not saw_expression:
            if sed_script_is_mutating(tok):
                return False
            saw_expression = True
            index += 1
            continue
        break
    return saw_expression


def awk_program_is_mutating(program):
    return bool(re.search(r"\bsystem\s*\(", program) or re.search(r">>|>|\|", program))


def awk_is_read_only(seq):
    if awk_is_inplace(seq):
        return False
    index = 1
    saw_program = False
    while index < len(seq):
        tok = seq[index]
        if tok == "--":
            index += 1
            break
        if tok in {"-f", "--file"}:
            return False
        if tok in {"-F", "-v"}:
            index += 2
            continue
        if tok.startswith("-F") and tok != "-F":
            index += 1
            continue
        if tok.startswith("-v") and tok != "-v":
            index += 1
            continue
        if tok.startswith("-"):
            index += 1
            continue
        if awk_program_is_mutating(tok):
            return False
        saw_program = True
        break
    return saw_program


def git_is_read_only(seq):
    if len(seq) < 2 or seq[0] != "git":
        return False
    verb = seq[1]
    if verb in SAFE_GIT_SIMPLE:
        return True
    if verb == "stash":
        return len(seq) >= 3 and seq[2] in {"list", "show"}
    if verb == "remote":
        if len(seq) == 2:
            return True
        if seq[2] == "-v":
            return len(seq) == 3
        if seq[2] in {"show", "get-url"}:
            return len(seq) >= 4
        return False
    if verb == "branch":
        mutating_flags = {
            "-d", "-D", "-m", "-M", "-c", "-C", "--delete", "--move",
            "--copy", "--set-upstream-to", "--unset-upstream", "--edit-description",
        }
        value_flags = {
            "--contains", "--no-contains", "--merged", "--no-merged",
            "--points-at", "--format", "--sort", "--column", "--color",
            "--no-color", "--abbrev",
        }
        i = 2
        while i < len(seq):
            tok = seq[i]
            if tok == "--":
                return i + 1 >= len(seq)
            if tok in mutating_flags:
                return False
            if tok in value_flags:
                i += 2
                continue
            if any(tok.startswith(flag + "=") for flag in value_flags):
                i += 1
                continue
            if tok.startswith("-"):
                i += 1
                continue
            return False
        return True
    return False


def classify(seq):
    if not seq:
        return False

    head = seq[0]

    if head == "env":
        i = 1
        while i < len(seq):
            tok = seq[i]
            if tok == "|":
                return True
            if tok.startswith("-") or ("=" in tok and not tok.startswith("=")):
                i += 1
                continue
            break
        rest = seq[i:]
        if not rest:
            return True
        return classify(rest)

    if head == "command":
        if len(seq) == 1:
            return True
        if seq[1] in {"-v", "-V"}:
            return True
        if seq[1] == "-p":
            return classify(seq[2:])
        return False

    if head == "xargs":
        i = 1
        while i < len(seq) and seq[i].startswith("-"):
            i += 1
        return classify(seq[i:])

    if head in SHELL_WRAPPERS and len(seq) >= 2 and seq[1] == "-c":
        return False

    if has_inplace_mutation(seq):
        return False

    if head == "sed":
        return sed_is_read_only(seq)

    if head == "awk":
        return awk_is_read_only(seq)

    if head == "find" and any(tok in {"-exec", "-execdir", "-ok", "-okdir", "-delete"} for tok in seq[1:]):
        return False

    if head in SAFE_SIMPLE:
        return True

    if head == "git":
        return git_is_read_only(seq)

    if head == "gh":
        return len(seq) >= 3 and " ".join(seq[:3]) in SAFE_GH

    return False

raise SystemExit(0 if classify(tokens) else 1)
PY
}

# -----------------------------------------------------------------------------
# command_has_inplace_mutation
# Return 0 when the command's executable is sed/awk in a file-mutating in-place
# mode. The detection is token-aware so reordered option lists like
# `sed -E -i ...`, `sed --in-place ...`, and `awk '{...}' -i inplace file`
# are not accidentally classified as read-only.
# -----------------------------------------------------------------------------
command_has_inplace_mutation() {
  local cmd="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$cmd" <<'PY'
from pathlib import Path
import shlex
import sys

cmd = sys.argv[1]
try:
    tokens = shlex.split(cmd)
except Exception:
    raise SystemExit(1)

ENV_VALUE_OPTIONS = {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"}
SUDO_VALUE_OPTIONS = {
    "-u", "--user", "-g", "--group", "-h", "--host", "-p", "--prompt",
    "-C", "--close-from", "-D", "--chdir", "-T", "--command-timeout",
    "-r", "--role", "-t", "--type",
}
ASSIGNMENT_CHARS = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_")


def is_assignment(tok):
    if "=" not in tok or tok.startswith("="):
        return False
    name = tok.split("=", 1)[0]
    return bool(name) and name[0] in ASSIGNMENT_CHARS and all(
        ch.isalnum() or ch == "_" for ch in name
    )


def skip_env(seq, i):
    i += 1
    while i < len(seq):
        tok = seq[i]
        if tok == "--":
            return i + 1
        if tok in ENV_VALUE_OPTIONS:
            i += 2
            continue
        if any(tok.startswith(opt + "=") for opt in ENV_VALUE_OPTIONS if opt.startswith("--")):
            i += 1
            continue
        if tok.startswith("-"):
            i += 1
            continue
        if is_assignment(tok):
            i += 1
            continue
        break
    return i


def skip_sudo(seq, i):
    i += 1
    while i < len(seq):
        tok = seq[i]
        if tok == "--":
            return i + 1
        if tok in SUDO_VALUE_OPTIONS:
            i += 2
            continue
        if any(tok.startswith(opt + "=") for opt in SUDO_VALUE_OPTIONS if opt.startswith("--")):
            i += 1
            continue
        if tok.startswith("-"):
            i += 1
            continue
        break
    return i


def command_index(seq):
    i = 0
    while i < len(seq):
        while i < len(seq) and is_assignment(seq[i]):
            i += 1
        if i >= len(seq):
            return i
        head = Path(seq[i]).name
        if head == "env":
            i = skip_env(seq, i)
            continue
        if head in {"command", "exec", "noglob", "!"}:
            i += 1
            if i < len(seq) and seq[i] == "--":
                i += 1
            continue
        if head == "sudo":
            i = skip_sudo(seq, i)
            continue
        if head in {"time", "gtime"}:
            i += 1
            if i < len(seq) and seq[i] == "-p":
                i += 1
            continue
        if head == "xargs":
            i += 1
            while i < len(seq) and seq[i].startswith("-"):
                i += 1
            continue
        return i
    return i


def sed_is_inplace(seq):
    for tok in seq[1:]:
        if tok == "--":
            break
        if tok == "-i" or tok.startswith("-i.") or tok.startswith("-i"):
            return True
        if tok == "--in-place" or tok.startswith("--in-place="):
            return True
        if tok.startswith("-") and not tok.startswith("--") and "i" in tok[1:]:
            return True
    return False


def awk_is_inplace(seq):
    for i, tok in enumerate(seq[1:], start=1):
        if tok == "--":
            break
        nxt = seq[i + 1] if i + 1 < len(seq) else ""
        if tok == "-i" and nxt == "inplace":
            return True
        if tok == "-iinplace":
            return True
        if tok == "--include" and nxt == "inplace":
            return True
        if tok == "--include=inplace":
            return True
    return False


idx = command_index(tokens)
if idx >= len(tokens):
    raise SystemExit(1)
head = Path(tokens[idx]).name
rest = tokens[idx:]
if (head == "sed" and sed_is_inplace(rest)) or (head == "awk" and awk_is_inplace(rest)):
    raise SystemExit(0)
raise SystemExit(1)
PY
    return $?
  fi

  if [[ "$cmd" =~ (^|[[:space:]])sed[[:space:]].*(^|[[:space:]])(-i|--in-place)([[:space:].=]|$) ]] || [[ "$cmd" =~ (^|[[:space:]])awk[[:space:]].*(-i[[:space:]]+inplace|--include[=[:space:]]+inplace) ]]; then
    return 0
  fi
  return 1
}

# -----------------------------------------------------------------------------
# command_text_filter_is_read_only
# Return 0 for common read-only sed/awk inspection forms while still denying
# in-place edits, sed write/execute commands, awk system calls, and awk redirects.
# -----------------------------------------------------------------------------
command_text_filter_is_read_only() {
  local cmd="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$cmd" <<'PY'
from pathlib import Path
import re
import shlex
import sys

cmd = sys.argv[1]
try:
    tokens = shlex.split(cmd)
except Exception:
    raise SystemExit(1)

ENV_VALUE_OPTIONS = {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"}
SUDO_VALUE_OPTIONS = {
    "-u", "--user", "-g", "--group", "-h", "--host", "-p", "--prompt",
    "-C", "--close-from", "-D", "--chdir", "-T", "--command-timeout",
    "-r", "--role", "-t", "--type",
}
ASSIGNMENT_CHARS = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_")


def is_assignment(tok):
    if "=" not in tok or tok.startswith("="):
        return False
    name = tok.split("=", 1)[0]
    return bool(name) and name[0] in ASSIGNMENT_CHARS and all(
        ch.isalnum() or ch == "_" for ch in name
    )


def skip_env(seq, i):
    i += 1
    while i < len(seq):
        tok = seq[i]
        if tok == "--":
            return i + 1
        if tok in ENV_VALUE_OPTIONS:
            i += 2
            continue
        if any(tok.startswith(opt + "=") for opt in ENV_VALUE_OPTIONS if opt.startswith("--")):
            i += 1
            continue
        if tok.startswith("-"):
            i += 1
            continue
        if is_assignment(tok):
            i += 1
            continue
        break
    return i


def skip_sudo(seq, i):
    i += 1
    while i < len(seq):
        tok = seq[i]
        if tok == "--":
            return i + 1
        if tok in SUDO_VALUE_OPTIONS:
            i += 2
            continue
        if any(tok.startswith(opt + "=") for opt in SUDO_VALUE_OPTIONS if opt.startswith("--")):
            i += 1
            continue
        if tok.startswith("-"):
            i += 1
            continue
        break
    return i


def command_index(seq):
    i = 0
    while i < len(seq):
        while i < len(seq) and is_assignment(seq[i]):
            i += 1
        if i >= len(seq):
            return i
        head = Path(seq[i]).name
        if head == "env":
            i = skip_env(seq, i)
            continue
        if head in {"command", "exec", "noglob", "!"}:
            i += 1
            if i < len(seq) and seq[i] == "--":
                i += 1
            continue
        if head == "sudo":
            i = skip_sudo(seq, i)
            continue
        if head in {"time", "gtime"}:
            i += 1
            if i < len(seq) and seq[i] == "-p":
                i += 1
            continue
        return i
    return i


def sed_is_inplace(seq):
    for tok in seq[1:]:
        if tok == "--":
            break
        if tok == "-i" or tok.startswith("-i.") or tok.startswith("-i"):
            return True
        if tok == "--in-place" or tok.startswith("--in-place="):
            return True
        if tok.startswith("-") and not tok.startswith("--") and "i" in tok[1:]:
            return True
    return False


def awk_is_inplace(seq):
    for i, tok in enumerate(seq[1:], start=1):
        if tok == "--":
            break
        nxt = seq[i + 1] if i + 1 < len(seq) else ""
        if tok == "-i" and nxt == "inplace":
            return True
        if tok == "-iinplace":
            return True
        if tok == "--include" and nxt == "inplace":
            return True
        if tok == "--include=inplace":
            return True
    return False


def sed_script_is_mutating(script):
    if re.search(r"(^|[;\n{])\s*(?:[0-9,$!]+|/[^/\n]+/)?\s*[we]\b", script):
        return True
    if re.search(r"s(.).*?\1.*?\1[0-9gp]*[we]\b", script):
        return True
    return False


def sed_is_read_only(seq):
    if sed_is_inplace(seq):
        return False
    index = 1
    saw_expression = False
    while index < len(seq):
        tok = seq[index]
        if tok == "--":
            index += 1
            break
        if tok in {"-f", "--file"} or tok.startswith("--file="):
            return False
        if tok == "-e" or tok == "--expression":
            if index + 1 >= len(seq) or sed_script_is_mutating(seq[index + 1]):
                return False
            saw_expression = True
            index += 2
            continue
        if tok.startswith("--expression="):
            if sed_script_is_mutating(tok.split("=", 1)[1]):
                return False
            saw_expression = True
            index += 1
            continue
        if tok.startswith("-") and tok != "-":
            index += 1
            continue
        if not saw_expression:
            if sed_script_is_mutating(tok):
                return False
            saw_expression = True
            index += 1
            continue
        break
    return saw_expression


def awk_program_is_mutating(program):
    return bool(re.search(r"\bsystem\s*\(", program) or re.search(r">>|>|\|", program))


def awk_is_read_only(seq):
    if awk_is_inplace(seq):
        return False
    index = 1
    saw_program = False
    while index < len(seq):
        tok = seq[index]
        if tok == "--":
            index += 1
            break
        if tok in {"-f", "--file"}:
            return False
        if tok in {"-F", "-v"}:
            index += 2
            continue
        if tok.startswith("-F") and tok != "-F":
            index += 1
            continue
        if tok.startswith("-v") and tok != "-v":
            index += 1
            continue
        if tok.startswith("-"):
            index += 1
            continue
        if awk_program_is_mutating(tok):
            return False
        saw_program = True
        break
    return saw_program


idx = command_index(tokens)
if idx >= len(tokens):
    raise SystemExit(1)
head = Path(tokens[idx]).name
rest = tokens[idx:]
if head == "sed":
    raise SystemExit(0 if sed_is_read_only(rest) else 1)
if head == "awk":
    raise SystemExit(0 if awk_is_read_only(rest) else 1)
raise SystemExit(1)
PY
    return $?
  fi
  return 1
}

# -----------------------------------------------------------------------------
# split_shell_segments
# Split a shell command into top-level segments while respecting quotes.
# `mode=chain` splits on && / ; / ||. `mode=pipe` splits on single | only.
# Returns one segment per line. If parsing fails, exits non-zero.
# -----------------------------------------------------------------------------
split_shell_segments() {
  local mode="$1"
  local cmd="$2"
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$mode" "$cmd" <<'PY'
import sys

mode, cmd = sys.argv[1:3]
if mode not in {"chain", "pipe"}:
    raise SystemExit(1)

segments = []
start = 0
i = 0
in_single = False
in_double = False
escaped = False

while i < len(cmd):
    ch = cmd[i]

    if escaped:
        escaped = False
        i += 1
        continue

    if ch == "\\" and not in_single:
        escaped = True
        i += 1
        continue

    if ch == "'" and not in_double:
        in_single = not in_single
        i += 1
        continue

    if ch == '"' and not in_single:
        in_double = not in_double
        i += 1
        continue

    if not in_single and not in_double:
        if mode == "chain":
            if cmd.startswith("&&", i) or cmd.startswith("||", i):
                seg = cmd[start:i]
                if seg.strip():
                    segments.append(seg)
                i += 2
                start = i
                continue
            if ch in ";\n":
                seg = cmd[start:i]
                if seg.strip():
                    segments.append(seg)
                i += 1
                start = i
                continue
        elif mode == "pipe":
            if cmd.startswith("||", i):
                i += 2
                continue
            if ch == "|":
                seg = cmd[start:i]
                if seg.strip():
                    segments.append(seg)
                i += 1
                start = i
                continue

    i += 1

tail = cmd[start:]
if tail.strip():
    segments.append(tail)

for seg in segments:
    print(seg)
PY
}

# -----------------------------------------------------------------------------
# has_top_level_shell_separator
# Return 0 when a command contains a top-level chain or pipe separator. This is
# used before line-oriented segment scanning so quoted multiline prompts do not
# look like multiple shell segments just because they contain newline bytes.
# -----------------------------------------------------------------------------
has_top_level_shell_separator() {
  local mode="$1"
  local cmd="$2"
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$mode" "$cmd" <<'PY'
import sys

mode, cmd = sys.argv[1:3]
if mode not in {"chain", "pipe"}:
    raise SystemExit(1)

in_single = False
in_double = False
escaped = False
depth = 0
i = 0

while i < len(cmd):
    ch = cmd[i]

    if escaped:
        escaped = False
        i += 1
        continue

    if ch == "\\" and not in_single:
        escaped = True
        i += 1
        continue

    if ch == "'" and not in_double:
        in_single = not in_single
        i += 1
        continue

    if ch == '"' and not in_single:
        in_double = not in_double
        i += 1
        continue

    if not in_single and not in_double:
        if ch in "([{":
            depth += 1
        elif ch in ")]}" and depth > 0:
            depth -= 1

        if depth == 0:
            if mode == "chain":
                if cmd.startswith("&&", i) or cmd.startswith("||", i) or ch in ";\n":
                    raise SystemExit(0)
            elif mode == "pipe":
                if cmd.startswith("||", i):
                    i += 2
                    continue
                if ch == "|":
                    raise SystemExit(0)

    i += 1

raise SystemExit(1)
PY
}

# -----------------------------------------------------------------------------
# has_unquoted_command_substitution
# Return 0 if the command contains active nested execution syntax outside single
# quotes: `$()`, backticks, or process substitution `<(...)` / `>(...)`.
# Double-quoted substitutions are still active and therefore count as mutating.
# -----------------------------------------------------------------------------
has_unquoted_command_substitution() {
  local cmd="$1"
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$cmd" <<'PY'
import sys

cmd = sys.argv[1]
in_single = False
in_double = False
escaped = False
i = 0

while i < len(cmd):
    ch = cmd[i]

    if escaped:
        escaped = False
        i += 1
        continue

    if ch == "\\" and not in_single:
        escaped = True
        i += 1
        continue

    if ch == "'" and not in_double:
        in_single = not in_single
        i += 1
        continue

    if ch == '"' and not in_single:
        in_double = not in_double
        i += 1
        continue

    if not in_single:
        if ch == "`":
            raise SystemExit(0)
        if ch == "$" and i + 1 < len(cmd) and cmd[i + 1] == "(":
            raise SystemExit(0)
        if ch in "<>" and i + 1 < len(cmd) and cmd[i + 1] == "(":
            raise SystemExit(0)

    i += 1

raise SystemExit(1)
PY
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
  local root
  [[ -z "$path" ]] && return 1

  root="$(sidekick_project_root)" || return 1

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$root" "$path" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
raw = Path(sys.argv[2])
if not raw.is_absolute():
    raw = root / raw

real = raw.resolve(strict=False)
for subdir in (root / ".planning", root / "docs"):
    try:
        real.relative_to(subdir.resolve(strict=False))
    except ValueError:
        continue
    else:
        sys.exit(0)
sys.exit(1)
PY
    return $?
  fi
  return 1
}

# -----------------------------------------------------------------------------
# is_within_project_root
# Return 0 when the supplied path resolves inside CLAUDE_PROJECT_DIR.
# Used to scope L3 takeover direct file tools to the current project tree.
# -----------------------------------------------------------------------------
is_within_project_root() {
  local path="$1"
  local root
  [[ -z "$path" ]] && return 1

  root="$(sidekick_project_root)" || return 1

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$root" "$path" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
raw = Path(sys.argv[2])
if not raw.is_absolute():
    raw = root / raw

real = raw.resolve(strict=False)
try:
    real.relative_to(root)
except ValueError:
    sys.exit(1)
sys.exit(0)
PY
    return $?
  fi
  return 1
}

# -----------------------------------------------------------------------------
# git_read_only_command
# Return 0 when a git command is token-aware read-only. Broad noun-level matching
# is unsafe because `git branch`, `git remote`, and `git stash` all contain
# mutating subcommands/options.
# -----------------------------------------------------------------------------
git_read_only_command() {
  local cmd="$1"
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$cmd" <<'PY'
import shlex
import sys

try:
    seq = shlex.split(sys.argv[1])
except Exception:
    raise SystemExit(1)

SAFE_SIMPLE = {"status", "log", "diff", "show", "rev-parse", "ls-files"}


def is_read_only_git(seq):
    if len(seq) < 2 or seq[0] != "git":
        return False
    verb = seq[1]
    if verb in SAFE_SIMPLE:
        return True
    if verb == "stash":
        return len(seq) >= 3 and seq[2] in {"list", "show"}
    if verb == "remote":
        if len(seq) == 2:
            return True
        if seq[2] == "-v":
            return len(seq) == 3
        if seq[2] in {"show", "get-url"}:
            return len(seq) >= 4
        return False
    if verb == "branch":
        mutating_flags = {
            "-d", "-D", "-m", "-M", "-c", "-C", "--delete", "--move",
            "--copy", "--set-upstream-to", "--unset-upstream", "--edit-description",
        }
        value_flags = {
            "--contains", "--no-contains", "--merged", "--no-merged",
            "--points-at", "--format", "--sort", "--column", "--color",
            "--no-color", "--abbrev",
        }
        i = 2
        while i < len(seq):
            tok = seq[i]
            if tok == "--":
                return i + 1 >= len(seq)
            if tok in mutating_flags:
                return False
            if tok in value_flags:
                i += 2
                continue
            if any(tok.startswith(flag + "=") for flag in value_flags):
                i += 1
                continue
            if tok.startswith("-"):
                i += 1
                continue
            return False
        return True
    return False


raise SystemExit(0 if is_read_only_git(seq) else 1)
PY
}

# -----------------------------------------------------------------------------
# is_read_only
# Return 0 (true) if the command is known to be read-only (non-mutating).
# Includes gh read-only sub-commands (ENF-05).
# -----------------------------------------------------------------------------
is_read_only() {
  local cmd first first3 backtick=$'\x60'
  cmd="$1"
  # A command with a write redirect is never read-only, regardless of its
  # first token (e.g. `echo hi > /tmp/out` is mutating).
  if has_write_redirect "$cmd"; then
    return 1
  fi
  # Nested shell execution constructs are treated as mutating because they can
  # hide arbitrary writes inside an otherwise harmless-looking outer command.
  if has_unquoted_command_substitution "$cmd"; then
    return 1
  fi
  first="$(first_token "$cmd")"
  case "${first%% *}" in
    env|command|xargs)
      wrapper_is_read_only "$cmd" && return 0
      return 1
      ;;
  esac
  if [[ "${first%% *}" = "find" ]] && [[ "$cmd" =~ (^|[[:space:]])find[[:space:]].*(-exec|-execdir|-ok|-okdir|-delete)([[:space:]]|$) ]]; then
    return 1
  fi
  if command_has_inplace_mutation "$cmd"; then
    return 1
  fi
  case "$first" in
    "forge --version"|"forge --help"|"forge info") return 0 ;;
  esac
  git_read_only_command "$cmd" && return 0
  command_text_filter_is_read_only "$cmd" && return 0
  first3="$(first_three_tokens "$cmd")"
  case "$first3" in
    "forge conversation list"|"forge conversation info"|"forge conversation stats"|"forge conversation show"|"forge conversation dump") return 0 ;;
  esac
  # ENF-05: gh read-only sub-commands require 3-token matching (gh <noun> <verb>).
  case "$first3" in
    "gh issue list"|"gh issue view"|"gh pr list"|"gh pr view"|"gh pr status"|"gh pr checks"\
    |"gh label list"|"gh release list"|"gh repo view"|"gh project list"\
    |"gh run list"|"gh run view"|"gh workflow list") return 0 ;;
  esac
  case "${first%% *}" in
    ls|la|ll|pwd|cd|echo|printf|cat|head|tail|wc|file|stat|tree|diff|cmp) return 0 ;;
    grep|egrep|fgrep|rg|ag|ack|find|fd|locate|which|whereis|type|command) return 0 ;;
    test|'[') return 0 ;;
    printenv|whoami|id|hostname|date|uname) return 0 ;;
    jq|sort|uniq|column|tr|cut) return 0 ;;
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
  local cmd first first3 backtick=$'\x60'
  cmd="$1"
  # Nested shell execution is mutating because it can execute arbitrary code
  # that the outer token classifier would otherwise miss.
  if has_unquoted_command_substitution "$cmd"; then
    return 0
  fi
  # Shell execution wrappers are mutating when they are asked to run code.
  if [[ "$cmd" =~ (^|[[:space:]])(sh|bash|zsh|fish|dash|ksh)[[:space:]]+-c([[:space:]]|$) ]]; then
    return 0
  fi
  first="$(first_token "$cmd")"
  # Two-word git mutators.
  case "$first" in
    "git add"|"git commit"|"git push"|"git pull"|"git fetch"|"git checkout"|"git reset"|"git rebase"|"git merge"|"git cherry-pick"|"git restore"|"git rm"|"git mv"|"git tag"|"git clean"|"git stash") return 0 ;;
  esac
  first3="$(first_three_tokens "$cmd")"
  case "$first3" in
    "forge conversation delete"|"forge conversation rename"|"forge conversation compact"|"forge conversation clone"|"forge conversation new") return 0 ;;
  esac
  # ENF-05: gh mutating sub-commands require 3-token matching (gh <noun> <verb>).
  case "$first3" in
    "gh issue create"|"gh issue edit"|"gh issue close"|"gh issue delete"\
    |"gh pr create"|"gh pr merge"|"gh pr close"|"gh pr edit"\
    |"gh release create"|"gh release delete"|"gh release upload"\
    |"gh project item-add"|"gh project item-edit"\
    |"gh repo clone"|"gh repo fork") return 0 ;;
  esac
  case "${first%% *}" in
    rm|rmdir|mv|cp|ln|chmod|chown|chgrp|touch|mkdir|tee) return 0 ;;
    npm|pnpm|yarn|bundle|pip|gem|cargo|go) return 0 ;;
    tar|zip|unzip|gunzip|gzip) return 0 ;;
    systemctl|service|launchctl|brew|apt|apt-get|yum|dnf) return 0 ;;
    curl|wget) return 0 ;;
  esac
  if [[ "${first%% *}" = "find" ]] && [[ "$cmd" =~ (^|[[:space:]])find[[:space:]].*(-exec|-execdir|-ok|-okdir|-delete)([[:space:]]|$) ]]; then
    return 0
  fi
  # Write-redirect anywhere in the command.
  if has_write_redirect "$cmd"; then
    return 0
  fi
  # `sed -i` and `awk -i inplace` option variants are mutating.
  if command_has_inplace_mutation "$cmd"; then
    return 0
  fi
  return 1
}

# -----------------------------------------------------------------------------
# has_non_readonly_chain_segment  (ENF-06)
# Return 0 (true) if a top-level &&, ||, or ; chain contains any segment that is
# not explicitly read-only. This denies both known mutators and unclassified
# shell tails such as `pwd && python3 ...`.
# -----------------------------------------------------------------------------
has_non_readonly_chain_segment() {
  local cmd="$1" seg count=0 bad=0
  if command -v python3 >/dev/null 2>&1; then
    has_top_level_shell_separator chain "$cmd" || return 1
    while IFS= read -r seg; do
      seg="${seg#"${seg%%[! ]*}"}"  # ltrim whitespace
      [[ -z "$seg" ]] && continue
      count=$((count + 1))
      if ! is_read_only "$seg"; then bad=1; fi
    done < <(split_shell_segments chain "$cmd") || return 1
    if [ "$count" -gt 1 ] && [ "$bad" -eq 1 ]; then return 0; fi
    return 1
  fi

  case "$cmd" in
    *'&&'*|*';'*|*'||'*) return 0 ;;
  esac
  return 1
}

# -----------------------------------------------------------------------------
# has_non_readonly_pipe_segment  (ENF-08)
# Return 0 (true) if a top-level pipe contains any segment that is not
# explicitly read-only. Standalone sidekick delegation commands are handled by
# host-specific rewrite branches before this generic pipe gate runs.
# -----------------------------------------------------------------------------
has_non_readonly_pipe_segment() {
  local cmd="$1" seg count=0 bad=0
  if command -v python3 >/dev/null 2>&1; then
    has_top_level_shell_separator pipe "$cmd" || return 1
    while IFS= read -r seg; do
      seg="${seg#"${seg%%[! ]*}"}"  # ltrim whitespace
      [[ -z "$seg" ]] && continue
      count=$((count + 1))
      if ! is_read_only "$seg"; then bad=1; fi
    done < <(split_shell_segments pipe "$cmd") || return 1
    if [ "$count" -gt 1 ] && [ "$bad" -eq 1 ]; then return 0; fi
    return 1
  fi

  [[ "$cmd" == *"|"* ]] && return 0
  return 1
}

# Backward-compatible aliases for older tests/docs. The active hooks use the
# stricter non-read-only variants above.
has_mutating_chain_segment() {
  has_non_readonly_chain_segment "$1"
}

has_mutating_pipe_segment() {
  has_non_readonly_pipe_segment "$1"
}

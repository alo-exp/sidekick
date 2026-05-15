#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Forge Delegation Enforcer (PreToolUse hook)  v1.3
# =============================================================================
# Sources hooks/lib/enforcer-utils.sh. Adds path allowlist (PATH-01/02/03),
# MCP filesystem dispatch (ENF-07), chain/pipe denial (ENF-06/08), and a
# session-scoped Level 3 marker for bounded host takeover.
#
# Exit-code contract: 0+empty=pass-through; 0+JSON=decision; 2+stderr=fatal.
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hooks/lib/enforcer-utils.sh
source "${HOOK_DIR}/lib/enforcer-utils.sh"
# shellcheck source=hooks/lib/sidekick-registry.sh
source "${HOOK_DIR}/lib/sidekick-registry.sh"

SIDEKICK_NAME="forge"
MARKER_FILE="$(sidekick_session_marker_file "$SIDEKICK_NAME" 2>/dev/null || true)"
LEVEL3_MARKER_FILE=""
if [[ -n "$MARKER_FILE" ]]; then
  LEVEL3_MARKER_FILE="$(dirname "$MARKER_FILE")/.forge-level3-active"
fi

# gen_uuid — lowercase RFC 4122 UUID. Honors SIDEKICK_TEST_UUID_OVERRIDE (tests only).
gen_uuid() {
  if [[ -n "${SIDEKICK_TEST_UUID_OVERRIDE:-}" ]]; then
    echo "$SIDEKICK_TEST_UUID_OVERRIDE"
    return 0
  fi
  uuidgen | tr 'A-Z' 'a-z'
}

# validate_uuid — 8-4-4-4-12 lowercase hex check; prevents metacharacter injection.
validate_uuid() {
  [[ "$1" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

# emit_decision — print hookSpecificOutput JSON. $1=allow|deny $2=reason $3=rewritten-cmd(opt).
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

# Level 3 is activated by an explicit session marker, not by command-text env
# prefixes. The FORGE_LEVEL_3 process env remains test/operator-only.
marker_identity() {
  local path token ident
  path="$1"
  [[ -n "$path" && -f "$path" ]] || return 1

  token=""
  IFS= read -r token < "$path" 2>/dev/null || token=""
  if [[ -n "$token" ]]; then
    printf 'content:%s\n' "$token"
    return 0
  fi

  ident="$(stat -f '%d:%i' "$path" 2>/dev/null || stat -c '%d:%i' "$path" 2>/dev/null || true)"
  ident="${ident%%$'\n'*}"
  [[ -n "$ident" ]] || return 1
  printf 'stat:%s\n' "$ident"
}

level3_active() {
  local current_identity level3_identity
  [[ "${FORGE_LEVEL_3:-}" == "1" ]] && return 0
  [[ -n "$LEVEL3_MARKER_FILE" && -f "$LEVEL3_MARKER_FILE" ]] || return 1
  [[ -n "$MARKER_FILE" && -f "$MARKER_FILE" ]] || return 1
  current_identity="$(marker_identity "$MARKER_FILE")" || return 1
  IFS= read -r level3_identity < "$LEVEL3_MARKER_FILE" 2>/dev/null || return 1
  [[ "$level3_identity" == "$current_identity" ]]
}

shell_quote() {
  printf '%q' "$1"
}

level3_control_command() {
  local cmd stripped
  cmd="$1"
  stripped="$(strip_env_prefix "$cmd")"
  case "$stripped" in
    "sidekick forge-level3 start"|"sidekick-forge-level3 start") return 0 ;;
    "sidekick forge-level3 stop"|"sidekick-forge-level3 stop") return 0 ;;
    *) return 1 ;;
  esac
}

level3_control_rewrite() {
  local cmd stripped marker_dir marker_q active_marker_q dir_q
  cmd="$1"
  stripped="$(strip_env_prefix "$cmd")"
  [[ -n "$LEVEL3_MARKER_FILE" && -n "$MARKER_FILE" ]] || return 1
  marker_dir="$(dirname "$LEVEL3_MARKER_FILE")"
  marker_q="$(shell_quote "$LEVEL3_MARKER_FILE")"
  active_marker_q="$(shell_quote "$MARKER_FILE")"
  dir_q="$(shell_quote "$marker_dir")"
  case "$stripped" in
    "sidekick forge-level3 start"|"sidekick-forge-level3 start")
      printf 'marker=%s; level3=%s; dir=%s; token=""; IFS= read -r token < "$marker" 2>/dev/null || token=""; if [ -n "$token" ]; then id="content:$token"; else raw="$(stat -f %%d:%%i "$marker" 2>/dev/null || stat -c %%d:%%i "$marker" 2>/dev/null || true)"; if [ -n "$raw" ]; then id="stat:$raw"; else id=""; fi; fi; if [ -z "$id" ]; then printf %%s\\\\n %s >&2; exit 1; fi; mkdir -p "$dir" && printf %%s\\\\n "$id" > "$level3" && printf %%s\\\\n %s' \
        "$active_marker_q" "$marker_q" "$dir_q" \
        "$(shell_quote "Sidekick Forge Level 3 takeover could not bind to the active /forge marker.")" \
        "$(shell_quote "Sidekick Forge Level 3 takeover enabled for this session.")"
      ;;
    "sidekick forge-level3 stop"|"sidekick-forge-level3 stop")
      printf 'rm -f %s && printf %%s\\\\n %s' \
        "$marker_q" "$(shell_quote "Sidekick Forge Level 3 takeover disabled for this session.")"
      ;;
    *) return 1 ;;
  esac
}

level3_bash_within_project_root() {
  local cmd project_root
  cmd="$1"
  project_root="$(sidekick_project_root)"
  [[ -n "$project_root" ]] || return 1
  command -v python3 >/dev/null 2>&1 || return 1

  python3 - "$cmd" "$project_root" <<'PY'
from pathlib import Path
import re
import shlex
import sys

cmd, root_arg = sys.argv[1:3]
root = Path(root_arg).resolve(strict=False)

try:
    lexer = shlex.shlex(cmd, posix=True, punctuation_chars=";&|()<>")
    lexer.whitespace_split = True
    tokens = list(lexer)
except Exception:
    raise SystemExit(1)

if not tokens:
    raise SystemExit(1)

CONTROL = {";", "&&", "||", "|", "&", "(", ")"}
REDIRECTS = {">", ">>", ">|", "<>"}
PATH_VALUE_FLAGS = {
    "-C",
    "-t",
    "--target-directory",
    "--target-directory=",
    "--backup-dir",
    "--backup-dir=",
}
ABS_PATH_RE = re.compile(r"(?<![A-Za-z0-9+.-])/(?:[^\s'\";&|()<>]+)")
SHELL_EXPANSION_RE = re.compile(r"\$|`|<\(|>\(|(?<![A-Za-z0-9_./'\"\\\\-])~[A-Za-z0-9_.-]*(?=$|[/\s;&|()<>])")

if SHELL_EXPANSION_RE.search(cmd):
    raise SystemExit(1)


def strip_fd_prefix(token):
    return re.sub(r"^[0-9]+", "", token)


def is_fd_redirect(token):
    return re.fullmatch(r"[0-9]*>&[-0-9]+", token or "") is not None


def normalize_candidate(raw):
    value = (raw or "").strip()
    if not value or value in {"-", "/dev/null"}:
        return None
    if "://" in value:
        return None
    value = value.rstrip(".,:;)]}")
    if not value or value in {"-", "/dev/null"}:
        return None
    return value


def outside_project(raw):
    value = normalize_candidate(raw)
    if value is None:
        return False
    path = Path(value)
    if not path.is_absolute():
        path = root / path
    resolved = path.resolve(strict=False)
    try:
        resolved.relative_to(root)
        return False
    except ValueError:
        return True


def token_contains_outside_absolute_path(token):
    if "://" in token:
        return False
    for match in ABS_PATH_RE.finditer(token):
        if outside_project(match.group(0)):
            return True
    return False


def token_is_pathlike(token):
    if not token or token in CONTROL:
        return False
    if token.startswith("-") and "/" not in token:
        return False
    return token.startswith(("/", ".", "~")) or "/" in token or token == ".."


def next_value(index):
    nxt = index + 1
    while nxt < len(tokens) and tokens[nxt] in {">"}:
        nxt += 1
    if nxt >= len(tokens) or tokens[nxt] in CONTROL:
        return None
    return tokens[nxt]


ENV_ASSIGN_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=.*$")
WRAPPER_COMMANDS = {"env", "command", "xargs", "parallel", "sudo", "doas"}
GLOBAL_MUTATOR_COMMANDS = {
    "curl", "wget", "brew", "apt", "apt-get", "yum", "dnf", "systemctl",
    "service", "launchctl",
}
SHELL_WRAPPERS = {"sh", "bash", "zsh", "fish", "dash", "ksh"}
INTERPRETER_EVAL_FLAGS = {
    "python": {"-c"},
    "python3": {"-c"},
    "node": {"-e", "--eval"},
    "ruby": {"-e"},
    "perl": {"-e"},
    "php": {"-r"},
    "osascript": {"-e"},
}
GIT_EXTERNAL_VERBS = {"push", "pull", "fetch", "clone", "ls-remote"}
PACKAGE_EXTERNAL_VERBS = {
    "npm": {"install", "i", "add", "uninstall", "remove", "rm", "ci", "publish", "login", "logout", "config", "cache", "link", "unlink"},
    "pnpm": {"install", "i", "add", "remove", "rm", "publish", "login", "logout", "config", "store", "link", "unlink"},
    "yarn": {"install", "add", "remove", "publish", "login", "logout", "config", "cache", "link", "unlink"},
    "pip": {"install", "uninstall", "download", "wheel", "cache", "config"},
    "pip3": {"install", "uninstall", "download", "wheel", "cache", "config"},
    "gem": {"install", "uninstall", "update", "push", "yank", "owner", "signin", "signout"},
    "bundle": {"install", "update", "config", "cache", "exec"},
    "cargo": {"install", "publish", "login", "logout", "owner", "yank"},
    "go": {"install", "get"},
}


def command_segments():
    current = []
    for token in tokens:
        if token in CONTROL:
            if current:
                yield current
                current = []
            continue
        current.append(token)
    if current:
        yield current


def unwrap_env_assignments(segment):
    index = 0
    while index < len(segment) and ENV_ASSIGN_RE.match(segment[index]):
        index += 1
    return segment[index:]


def git_external_verb(segment):
    index = 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            return segment[index + 1] if index + 1 < len(segment) else ""
        if token in {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"}:
            index += 2
            continue
        if token.startswith("--git-dir=") or token.startswith("--work-tree=") or token.startswith("--namespace=") or token.startswith("--config-env="):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        return token
    return ""


def level3_unbounded_command(segment):
    seq = unwrap_env_assignments(segment)
    if not seq:
        return False
    command = seq[0]
    if command in WRAPPER_COMMANDS or command in GLOBAL_MUTATOR_COMMANDS:
        return True
    if command in SHELL_WRAPPERS and any(tok == "-c" or tok.startswith("-c") for tok in seq[1:]):
        return True
    if command in INTERPRETER_EVAL_FLAGS:
        flags = INTERPRETER_EVAL_FLAGS[command]
        if any(tok in flags or any(tok.startswith(flag) and tok != flag for flag in flags) for tok in seq[1:]):
            return True
    if command == "git" and git_external_verb(seq) in GIT_EXTERNAL_VERBS:
        return True
    if command == "gh":
        return True
    verbs = PACKAGE_EXTERNAL_VERBS.get(command)
    if verbs:
        verb = seq[1] if len(seq) > 1 else ""
        if verb in verbs:
            return True
    return False


for segment in command_segments():
    if level3_unbounded_command(segment):
        raise SystemExit(1)


for i, token in enumerate(tokens):
    token_no_fd = strip_fd_prefix(token)

    if is_fd_redirect(token):
        continue

    if token_no_fd in REDIRECTS:
        target = next_value(i)
        if target is None or outside_project(target):
            raise SystemExit(1)
        continue

    if token_no_fd.startswith((">>", ">|", ">")) and token_no_fd not in {">", ">>", ">|"}:
        target = token_no_fd.lstrip(">")
        if not target or outside_project(target):
            raise SystemExit(1)
        continue

    if token_contains_outside_absolute_path(token):
        raise SystemExit(1)

    if token in PATH_VALUE_FLAGS:
        target = next_value(i)
        if target is None or outside_project(target):
            raise SystemExit(1)
        continue

    matched_prefix_flag = False
    for flag in PATH_VALUE_FLAGS:
        if flag.endswith("=") and token.startswith(flag):
            matched_prefix_flag = True
            if outside_project(token.split("=", 1)[1]):
                raise SystemExit(1)
            break
    if matched_prefix_flag:
        continue

    if token in {"cd", "pushd"}:
        target = next_value(i)
        if target is not None and outside_project(target):
            raise SystemExit(1)
        continue

    if token_is_pathlike(token) and outside_project(token):
        raise SystemExit(1)

raise SystemExit(0)
PY
}

allow_level3_bash_or_deny() {
  local cmd="$1"
  level3_active || return 1
  if level3_bash_within_project_root "$cmd"; then
    return 0
  fi
  emit_decision "deny" "Sidekick /forge Level 3: Bash command denied because it targets a path outside the current project tree." ""
  return 2
}

# Canonical deny reason for direct file edits.
DENY_EDIT_REASON='Sidekick /forge mode is active: direct file edits are delegated to Forge. Use: Bash { command: "forge -p \"<your task description>\"" }. For Level 3 takeover after the fallback ladder is exhausted, run `sidekick forge-level3 start`; direct tools stay limited to the current project tree.'

deny_direct_edit() {
  emit_decision "deny" "$DENY_EDIT_REASON" ""
}

# PATH-01/02/03: .planning/** and docs/** edits pass through when /forge is active.
# L3 takeover extends direct file tools to the current project tree only.
decide_write_edit() {
  local tool_input_json="$1"
  local file_path
  file_path="$(printf '%s' "$tool_input_json" | jq -r '.file_path // .path // empty')"
  if level3_active && is_within_project_root "$file_path"; then
    return 0
  fi
  if is_allowed_doc_path "$file_path"; then
    return 0
  fi
  deny_direct_edit
}

decide_notebook_edit() {
  local tool_input_json="$1"
  local file_path
  file_path="$(printf '%s' "$tool_input_json" | jq -r '.file_path // .path // empty')"
  if level3_active && is_within_project_root "$file_path"; then
    return 0
  fi
  deny_direct_edit
}

# ENF-07: deny mcp__filesystem__* write tools (with path allowlist).
decide_mcp_write() {
  local tool_input_json="$1"
  local file_path
  file_path="$(printf '%s' "$tool_input_json" | jq -r '.path // .file_path // empty')"
  if level3_active && is_within_project_root "$file_path"; then
    return 0
  fi
  if is_allowed_doc_path "$file_path"; then
    return 0
  fi
  deny_direct_edit
}

# Audit index + activation-lifecycle helpers.
resolve_forge_dir() {
  local dir real_dir
  dir="$(sidekick_project_root)/.forge"
  if [[ -e "$dir" || -L "$dir" ]]; then
    if [[ -L "$dir" ]]; then
      return 1
    fi
    real_dir="$(realpath "$dir" 2>/dev/null || readlink -f "$dir" 2>/dev/null || true)"
    [[ "$real_dir" = "$dir" ]] || return 1
  fi
  printf '%s' "$dir"
}

ensure_forge_dir_and_idx() {
  local dir real_dir
  dir="$(resolve_forge_dir)" || return 1
  [[ -n "$dir" ]] || return 1
  mkdir -p "$dir" 2>/dev/null || return 1
  real_dir="$(realpath "$dir" 2>/dev/null || readlink -f "$dir" 2>/dev/null || true)"
  [[ -n "$real_dir" ]] || return 1
  [[ "$real_dir" = "$dir" ]] || return 1
  [[ -L "$dir/conversations.idx" ]] && return 1
  touch -a "$dir/conversations.idx" 2>/dev/null || return 1
  return 0
}

# db_precheck — sentinel-gated health check. Returns 0 if DB writable.
db_precheck() {
  local dir sentinel
  dir="$(resolve_forge_dir)" || return 1
  [[ -n "$dir" ]] || return 1
  sentinel="$dir/.db_check_ok"
  if [[ -f "$sentinel" ]] && ! [[ "$MARKER_FILE" -nt "$sentinel" ]]; then
    return 0
  fi
  if env -i \
    HOME="${HOME:-}" \
    PATH="${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}" \
    PWD="${PWD:-}" \
    USER="${USER:-}" \
    LOGNAME="${LOGNAME:-}" \
    SHELL="${SHELL:-/bin/sh}" \
    TERM="${TERM:-dumb}" \
    TMPDIR="${TMPDIR:-/tmp}" \
    LANG="${LANG:-C}" \
    LC_ALL="${LC_ALL:-}" \
    forge conversation list >/dev/null 2>&1; then
    mkdir -p "$dir" 2>/dev/null || true
    touch "$sentinel" 2>/dev/null || true
    return 0
  fi
  return 1
}

# extract_task_hint — derive -p argument from command via python3 shlex.
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
  [[ -z "$hint" ]] && hint="(task hint unavailable)"
  sidekick_sanitize_idx_hint "$hint"
}

# append_idx_row — write one tab-separated line to .forge/conversations.idx.
append_idx_row() {
  local uuid hint dir idx
  uuid="$1"
  hint="$(sidekick_sanitize_idx_hint "$2")"
  ensure_forge_dir_and_idx || return 1
  dir="$(resolve_forge_dir)" || return 1
  [[ -n "$dir" ]] || return 1
  idx="$dir/conversations.idx"
  [[ -L "$idx" ]] && return 1
  if [[ -f "$idx" ]] && grep -qF "$uuid" "$idx" 2>/dev/null; then
    return 0
  fi
  local tag_suffix sidekick_tag
  tag_suffix="${uuid##*-}"
  tag_suffix="${tag_suffix:0:8}"
  sidekick_tag="sidekick-$(date +%s)-$tag_suffix"
  printf '%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$uuid" "$sidekick_tag" "$hint" >> "$idx" 2>/dev/null || return 1
  return 0
}

# Enforcer-specific helpers (not in lib).
has_conversation_id() {
  local cmd="$1"
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$cmd" <<'PY'
import shlex
import sys

cmd = sys.argv[1]
try:
    tokens = shlex.split(cmd, posix=True)
except Exception:
    raise SystemExit(1)

if len(tokens) < 2 or tokens[0] != "forge":
    raise SystemExit(1)

for token in tokens[1:]:
    if token == "-p":
        break
    if token == "--conversation-id" or token.startswith("--conversation-id="):
        sys.exit(0)

sys.exit(1)
PY
}

extract_conversation_id() {
  local cmd="$1"
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$cmd" <<'PY'
import shlex
import sys

cmd = sys.argv[1]
try:
    tokens = shlex.split(cmd, posix=True)
except Exception:
    raise SystemExit(1)

if len(tokens) < 2 or tokens[0] != "forge":
    raise SystemExit(1)

for index, token in enumerate(tokens[1:], start=1):
    if token == "-p":
        break
    if token == "--conversation-id":
        if index + 1 < len(tokens):
            print(tokens[index + 1])
        raise SystemExit(0)
    if token.startswith("--conversation-id="):
        print(token.split("=", 1)[1])
        raise SystemExit(0)

raise SystemExit(1)
PY
}

is_forge_p() {
  local cmd stripped
  cmd="$1"
  stripped="$(strip_env_prefix "$cmd")"
  [[ "$stripped" =~ ^forge([[:space:]]|$) ]] || return 1
  [[ "$stripped" =~ (^|[[:space:]])-p([[:space:]]|$) ]] || return 1
  return 0
}

# decide_bash — Bash tool classifier + forge -p rewrite.
decide_bash() {
  local tool_input_json cmd
  tool_input_json="$1"
  cmd="$(printf '%s' "$tool_input_json" | jq -r '.command // empty')"
  [[ -z "$cmd" ]] && return 0

  if level3_control_command "$cmd"; then
    local level3_rewrite
    level3_rewrite="$(level3_control_rewrite "$cmd")" || {
      emit_decision "deny" "Sidekick /forge mode: cannot resolve the Level 3 session marker path." ""
      return 0
    }
    emit_decision "allow" "Sidekick /forge mode: Level 3 session marker command accepted." "$level3_rewrite"
    return 0
  fi

  # Command-text env prefixes are intentionally consumed without import; they
  # must not self-activate Level 3 or poison helper subprocesses.
  export_env_prefix "$cmd"

  # 1b. ENF-06: Chain bypass — deny if any &&/;/|| segment is not
  # explicitly read-only.
  # This runs before the forge -p rewrite so a shell tail like `; rm -rf`
  # cannot ride along behind an otherwise valid delegation request.
  if has_non_readonly_chain_segment "$cmd"; then
    if allow_level3_bash_or_deny "$cmd"; then return 0; elif [[ "$?" -eq 2 ]]; then return 0; fi
    emit_decision "deny" "Sidekick /forge mode: command chain contains a non-read-only segment. Use forge -p, or run sidekick forge-level3 start after the Level 3 fallback is reached." ""
    return 0
  fi

  # 1. forge -p rewrite / safe idempotent normalization.
  local stripped
  stripped="$(strip_env_prefix "$cmd")"
	  if is_forge_p "$stripped"; then
	    local uuid existing_uuid
	    if ! db_precheck; then
	      emit_decision "deny" "Sidekick: Forge DB not writable ('forge conversation list' failed). Deactivate via /forge-stop, resolve the Forge state, and re-activate." ""
	      return 0
	    fi
	    if has_conversation_id "$stripped"; then
	      existing_uuid="$(extract_conversation_id "$stripped" || true)"
	      if [[ -z "$existing_uuid" ]] || ! validate_uuid "$existing_uuid"; then
	        emit_decision "deny" "Sidekick: --conversation-id value is not a valid lowercase RFC 4122 UUID. Supply a valid UUID or omit --conversation-id to let the hook auto-generate one." ""
	        return 0
	      fi
	      uuid="$existing_uuid"
	    else
	      uuid="$(gen_uuid)"
	    fi
	    if ! ensure_forge_dir_and_idx; then
	      emit_decision "deny" "Sidekick: Forge audit index is not writable or is outside the project. Remove any symlinked .forge path and re-run /forge." ""
	      return 0
	    fi
    local rewritten hint safe_rewrite project_root runner_path
    if ! validate_uuid "$uuid"; then
      emit_decision "deny" "Sidekick: refusing to inject malformed UUID (check SIDEKICK_TEST_UUID_OVERRIDE)." ""
      return 0
    fi
    project_root="$(sidekick_project_root)"
    runner_path="${HOOK_DIR}/lib/sidekick-safe-runner.sh"
    safe_rewrite="$(python3 - "$uuid" "$stripped" "$project_root" "$runner_path" <<'PY'
import shlex
import sys
from pathlib import Path

uuid, cmd, root_arg, runner_path = sys.argv[1:5]
root = Path(root_arg).resolve()
try:
    lexer = shlex.shlex(cmd, posix=True, punctuation_chars='|;&()<>')
    lexer.whitespace_split = True
    tokens = list(lexer)
except Exception:
    raise SystemExit(1)

if len(tokens) < 3 or tokens[0] != "forge":
    raise SystemExit(1)

tail = None
if "|" in tokens:
    pipe_index = tokens.index("|")
    left = tokens[:pipe_index]
    tail = tokens[pipe_index + 1:]
    if not tail or "|" in tail:
        raise SystemExit(1)
else:
    left = tokens

if len(left) < 3 or left[0] != "forge":
    raise SystemExit(1)

for tok in left:
    if tok in {";", "&&", "||", "|", "&", ">", "<", "(", ")"}:
        raise SystemExit(1)

prompt_start = None
index = 1
while index < len(left):
    tok = left[index]
    if tok == "--conversation-id":
        if index + 1 >= len(left) or left[index + 1] != uuid:
            raise SystemExit(1)
        index += 2
        continue
    if tok.startswith("--conversation-id="):
        if tok.split("=", 1)[1] != uuid:
            raise SystemExit(1)
        index += 1
        continue
    if tok == "--verbose":
        index += 1
        continue
    if tok == "-p":
        prompt_start = index + 1
        break
    raise SystemExit(1)

if prompt_start is None:
    raise SystemExit(1)

prompt = " ".join(left[prompt_start:])
if not prompt:
    raise SystemExit(1)

rewritten_args = [
    "bash",
    runner_path,
    "forge",
    "forge",
    "--conversation-id",
    uuid,
    "--verbose",
    "-p",
    prompt,
]
rewritten = " ".join(shlex.quote(tok) for tok in rewritten_args)

if tail is not None:
    if tail[0] != "tee":
        raise SystemExit(1)
    for tok in tail[1:]:
        if tok in {";", "&&", "||", "|", "&", ">", "<", "(", ")"}:
            raise SystemExit(1)
    file_args = [tok for tok in tail[1:] if not tok.startswith("-")]
    if not file_args:
        raise SystemExit(1)
    for arg in file_args:
        raw = Path(arg)
        if not raw.is_absolute():
            raw = root / raw
        resolved = raw.resolve(strict=False)
        allowed = False
        for sub in (root / ".planning", root / "docs"):
            try:
                resolved.relative_to(sub.resolve(strict=False))
            except ValueError:
                continue
            else:
                allowed = True
                break
        if not allowed:
            raise SystemExit(1)
    pipeline = rewritten + " | " + " ".join(shlex.quote(tok) for tok in tail)
    rewritten = "bash -o pipefail -c " + shlex.quote(pipeline)

print(rewritten)
PY
)" || {
      emit_decision "deny" "Sidekick: refusing to rewrite malformed forge -p invocation." ""
      return 0
	    }
	    rewritten="${safe_rewrite}"
	    hint="$(extract_task_hint "$cmd")"
	    if ! append_idx_row "$uuid" "$hint"; then
	      emit_decision "deny" "Sidekick: Forge audit index could not record the delegated task. Check .forge/conversations.idx permissions and re-run /forge." ""
	      return 0
	    fi
	    emit_decision "allow" "Sidekick: validated --conversation-id + --verbose + safe output surface." "$rewritten"
	    return 0
	  fi

  # 1c. ENF-08: Pipe bypass — deny if any | segment is not explicitly read-only.
  # forge -p is handled above so its safe output runner can remain intact.
  if has_non_readonly_pipe_segment "$cmd"; then
    if allow_level3_bash_or_deny "$cmd"; then return 0; elif [[ "$?" -eq 2 ]]; then return 0; fi
    emit_decision "deny" "Sidekick /forge mode: pipe chain contains a non-read-only segment. Use forge -p, or run sidekick forge-level3 start after the Level 3 fallback is reached." ""
    return 0
  fi

  # 2. read-only passthrough.
  if is_read_only "$cmd"; then
    return 0
  fi

  # 3. mutating command handling.
  if is_mutating "$cmd"; then
    if allow_level3_bash_or_deny "$cmd"; then return 0; elif [[ "$?" -eq 2 ]]; then return 0; fi
    emit_decision "deny" "Sidekick /forge mode: mutating command denied. Delegate via forge -p, or run sidekick forge-level3 start after the Level 3 fallback is reached." ""
    return 0
  fi

  # 4. Unclassified → conservative deny unless explicit Level 3 is active and
  # the shell command is still bounded to the current project tree.
  if level3_active; then
    if level3_bash_within_project_root "$cmd"; then
      return 0
    fi
    emit_decision "deny" "Sidekick /forge Level 3: Bash command denied because it targets a path outside the current project tree." ""
    return 0
  fi
  emit_decision "deny" "Sidekick /forge mode: command could not be classified. Delegate via forge -p or run sidekick forge-level3 start after the Level 3 fallback is reached." ""
}

# main — entry point.
main() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "forge-delegation-enforcer: jq not found on PATH" >&2
    exit 2
  fi

  local input
  input="$(cat)"

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

  if [[ -z "$MARKER_FILE" ]] || [[ ! -f "$MARKER_FILE" ]]; then
    exit 0
  fi

  case "$tool_name" in
    Write|Edit)     decide_write_edit "$tool_input" ;;
    NotebookEdit)   decide_notebook_edit "$tool_input" ;;
    Bash)           decide_bash "$tool_input" ;;
    mcp__filesystem__write_file|mcp__filesystem__edit_file|\
    mcp__filesystem__move_file|mcp__filesystem__create_directory)
                    decide_mcp_write "$tool_input" ;;
    *)              exit 0 ;;
  esac
}

# Source-guard: run main() only when executed directly, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "${0:-}" ]]; then
  main "$@"
fi

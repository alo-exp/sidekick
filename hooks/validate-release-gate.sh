#!/usr/bin/env bash
# Pre-release quality gate enforcer
# Intercepts Bash tool calls that publish GitHub releases or release tags and
# denies them (via the Claude Code PreToolUse permissionDecision envelope)
# unless all current-session, current-commit quality-gate stage markers and two
# current-session, current-commit live-pyramid run markers are present in
# Sidekick's state file.
#
# Stage count and marker names are defined in site/pre-release-quality-gate.md.
# Each stage in that document resolves host-specific state, invokes
# /superpowers:verification-before-completion, then writes:
#   mkdir -p "$(dirname "$SIDEKICK_QG_STATE")"
#   SIDEKICK_QG_SHA="$(git rev-parse --short=12 HEAD)"
#   printf 'quality-gate-stage-N session=%s sha=%s\n' "$SIDEKICK_QG_SESSION" "$SIDEKICK_QG_SHA" >> "$SIDEKICK_QG_STATE"
# A successful live `tests/run_release.bash` run with Codex live enabled
# appends:
#   quality-gate-live-pyramid session=<id> sha=<git-sha> at=<utc-timestamp>
# If stages are added or removed from that document, update STAGE_COUNT below
# and commit both files together.
#
# NOTE: we deliberately do NOT use ~/.claude/.silver-bullet/state here —
# Silver Bullet's dev-cycle-check.sh hook blocks direct writes to that path
# and the markers would never land.

set -euo pipefail

STAGE_COUNT=4
LIVE_PYRAMID_REQUIRED_RUNS=2
LIVE_PYRAMID_MARKER="quality-gate-live-pyramid"
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HOOK_DIR}/.." && pwd)"
SIDEKICK_QG_DIR="$HOME/.claude/.sidekick"
if [ -n "${CODEX_PLUGIN_ROOT:-}" ] || [ -n "${CODEX_HOME:-}" ] || [ -n "${CODEX_THREAD_ID:-}" ]; then
  SIDEKICK_QG_DIR="$HOME/.codex/.sidekick"
fi
STATE_FILE="${SIDEKICK_QG_STATE:-${SIDEKICK_QG_DIR}/quality-gate-state}"
QUALITY_GATE_SESSION_ID="${SIDEKICK_SESSION_ID:-${CODEX_THREAD_ID:-${CLAUDE_SESSION_ID:-${SESSION_ID:-}}}}"

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

if ! command -v python3 >/dev/null 2>&1; then
  echo "validate-release-gate: python3 is required to classify Bash release commands" >&2
  exit 2
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

is_gh_release_create() {
  python3 - "$1" <<'PY'
from pathlib import Path
import base64
import binascii
import codecs
import os
import re
import shlex
import sys
import urllib.parse

UNRESOLVABLE = "__UNRESOLVABLE__"
CONTROL = {";", "&&", "||", "|", "&"}
CONTROL_PREFIXES = {"if", "then", "elif", "while", "until", "do", "else"}
GROUP_PREFIXES = {"(", "{"}
SHELLS = {"sh", "bash", "zsh"}
SOURCE_LOADERS = {"source", "."}
EXEC_WRAPPERS = {"command", "exec"}
PREFIX_WRAPPERS = {"!", "noglob"}
TIME_WRAPPERS = {"time", "gtime"}
PRIVILEGE_WRAPPERS = {"sudo", "doas"}
LAUNCH_WRAPPERS = {"nice", "nohup", "setsid"}
ENV_VALUE_OPTIONS = {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"}
ENV_SPLIT_OPTIONS = {"-S", "--split-string"}
TIME_VALUE_OPTIONS = {"-f", "--format", "-o", "--output"}
TIME_FLAG_OPTIONS = {"-p", "-a", "--append", "-v", "--verbose"}
GH_VALUE_GLOBALS = {"-R", "--repo", "--hostname", "--config-dir"}
GH_FLAG_GLOBALS = {"--paginate", "--no-pager"}
GH_KNOWN_SUBCOMMANDS = {
    "alias", "api", "auth", "browse", "cache", "codespace", "completion",
    "config", "extension", "gpg-key", "gist", "issue", "label", "org",
    "pr", "project", "release", "repo", "ruleset", "run", "search",
    "secret", "ssh-key", "status", "variable", "workflow", "help",
}
GITHUB_API_WRITE_METHODS = {"POST", "PUT", "PATCH", "DELETE"}
GITHUB_RELEASE_API_RE = re.compile(
    r"(?:https?://[^/\s\"']+/)?(?:api/v3/)?repos/[^/\s\"']+/[^/\s\"']+/"
    r"(?:releases(?:[/\?#\"'\s]|$)|git/refs/tags(?:[/\?#\"'\s]|$))",
    re.I,
)
GITHUB_REFS_API_RE = re.compile(
    r"(?:https?://[^/\s\"']+/)?(?:api/v3/)?repos/[^/\s\"']+/[^/\s\"']+/git/refs(?:[/\?#\"'\s]|$)",
    re.I,
)
STATIC_BASE64_RE = re.compile(r"(?<![A-Za-z0-9+/=])([A-Za-z0-9+/]{16,}={0,2})(?![A-Za-z0-9+/=])")
STATIC_BASE64_HINT_RE = re.compile(r"\b(?:base64|b64decode|atob|fromBase64|Buffer\.from)\b", re.I)
STATIC_STRING_CONCAT_RE = re.compile(
    r"('(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\")\s*\+\s*"
    r"('(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\")",
    re.DOTALL,
)
SUDO_VALUE_OPTIONS = {
    "-u", "--user",
    "-g", "--group",
    "-h", "--host",
    "-p", "--prompt",
    "-C", "--close-from",
    "-D", "--chdir",
    "-T", "--command-timeout",
    "-r", "--role",
    "-t", "--type",
}
NICE_VALUE_OPTIONS = {"-n", "--adjustment"}
SETSID_FLAG_OPTIONS = {"-f", "-w", "-c", "--fork", "--wait", "--ctty"}
ASSIGNMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
ASSIGNMENT_FULL_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$")
INDEXED_ASSIGNMENT_FULL_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\[([0-9]+)\]=(.*)$")
POSITIONAL_ARG_RE = re.compile(r"^\$(?:[@*]|[0-9]+|\{(?:[@*]|[0-9]+)\})$")
POSITIONAL_FRAGMENT_RE = re.compile(r"\$(?:([0-9])|([@*])|\{([0-9]+|[@*])\})")
ARRAY_EXPANSION_RE = re.compile(r"^\$\{([A-Za-z_][A-Za-z0-9_]*)\[[*@]\]\}$")
EXPANSION_RE = re.compile(r"(?:\$[A-Za-z_][A-Za-z0-9_]*|\$\{|\$\(|`)")
VARIABLE_TOKEN_RE = re.compile(r"^\$(?:([A-Za-z_][A-Za-z0-9_]*)|\{([A-Za-z_][A-Za-z0-9_]*)\})$")
ENV_REFERENCE_RE = re.compile(r"\$(?:([A-Za-z_][A-Za-z0-9_]*)|\{([A-Za-z_][A-Za-z0-9_]*)\})")
PRINTF_SPEC_RE = re.compile(r"%(?:[-+#0 ']*\d*(?:\.\d+)?[hlLzjt]*)?([A-Za-z%])")
SHELL_VALUE_OPTIONS = {"--init-file", "--rcfile"}
GH_API_VALUE_OPTIONS = {
    "-H", "--header",
    "-X", "--method",
    "-f", "--field",
    "-F", "--raw-field",
    "--input",
    "--preview",
    "--cache",
}
GH_API_WRITE_METHODS = {"POST", "PUT", "PATCH", "DELETE"}
GIT_PROVENANCE_ENV_NAMES = {
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_NAMESPACE",
    "GIT_CONFIG_COUNT",
    "GIT_CONFIG_PARAMETERS",
    "GIT_CONFIG_GLOBAL",
    "GIT_CONFIG_SYSTEM",
    "GIT_CONFIG_NOSYSTEM",
}
GIT_VALUE_GLOBALS = {
    "-C", "-c",
    "--git-dir", "--work-tree", "--namespace",
    "--exec-path", "--super-prefix",
}
GIT_FLAG_GLOBALS = {
    "--bare", "--no-pager", "--paginate",
    "--literal-pathspecs", "--glob-pathspecs",
    "--noglob-pathspecs", "--icase-pathspecs",
}
GIT_KNOWN_SUBCOMMANDS = {
    "add", "am", "apply", "archive", "bisect", "blame", "branch", "bundle",
    "cat-file", "checkout", "cherry", "cherry-pick", "clean", "clone",
    "commit", "config", "describe", "diff", "fetch", "format-patch", "fsck",
    "gc", "grep", "init", "log", "merge", "mv", "notes", "pull", "push",
    "range-diff", "rebase", "reflog", "remote", "reset", "restore", "revert",
    "rev-list", "rev-parse", "rm", "shortlog", "show", "show-ref", "stash",
    "status", "submodule", "switch", "tag", "worktree", "help",
}
GIT_PUSH_VALUE_OPTIONS = {
    "-o", "--push-option",
    "--receive-pack", "--exec",
    "--recurse-submodules",
}
GIT_PUSH_RELEASE_TAG_OPTIONS = {"--tags", "--follow-tags", "--mirror"}
RELEASE_TAG_RE = re.compile(r"^v?[0-9]+[.][0-9]+[.][0-9]+(?:[-+][A-Za-z0-9._-]+)?$")
RELEASE_TAG_TEXT_RE = re.compile(r"\bv?[0-9]+[.][0-9]+[.][0-9]+(?:[-+][A-Za-z0-9._-]+)?\b")
DYNAMIC_RELEASE_TAG_HINT_RE = re.compile(r"(?:TAG|VERSION|RELEASE)", re.IGNORECASE)
DYNAMIC_BRANCH_HINT_RE = re.compile(r"(?:BRANCH|HEADS?)", re.IGNORECASE)
DYNAMIC_RELEASE_ENDPOINT_HINT_RE = re.compile(r"(?:RELEASE|TAG|VERSION).*(?:URL|ENDPOINT|API)|(?:URL|ENDPOINT|API).*(?:RELEASE|TAG|VERSION)", re.IGNORECASE)
TAG_REF_TEXT_RE = re.compile(r"refs/tags/", re.IGNORECASE)
SCRIPT_PATH_HINT_RE = re.compile(r"(?:release|tag|publish)", re.IGNORECASE)
SCRIPT_READ_MAX_BYTES = 256 * 1024
SCRIPT_EXTENSIONS = {
    ".sh", ".bash", ".zsh",
    ".py", ".pyw",
    ".js", ".mjs", ".cjs",
    ".rb", ".pl",
}
INTERPRETER_PAYLOAD_OPTIONS = {
    "python": {"-c"},
    "python3": {"-c"},
    "pypy": {"-c"},
    "pypy3": {"-c"},
    "perl": {"-e"},
    "ruby": {"-e"},
    "node": {"-e", "--eval"},
    "deno": {"eval"},
    "bun": {"-e"},
}
KNOWN_EXECUTABLE_COMMANDS = (
    {"gh", "git", "curl", "wget"}
    | SHELLS
    | EXEC_WRAPPERS
    | PREFIX_WRAPPERS
    | TIME_WRAPPERS
    | PRIVILEGE_WRAPPERS
    | LAUNCH_WRAPPERS
    | set(INTERPRETER_PAYLOAD_OPTIONS)
)
GRAPHQL_RELEASE_MUTATION_RE = re.compile(
    r"\b(?:create|update|delete)Release\b",
    re.IGNORECASE,
)
GRAPHQL_REF_MUTATION_RE = re.compile(
    r"\b(?:create|update|delete)Ref\b",
    re.IGNORECASE,
)
GRAPHQL_RELEASE_ENDPOINT_RE = re.compile(
    r"(?:https?://[^/\s\"']+/)?(?:api/)?graphql\b",
    re.IGNORECASE,
)
GIT_PUSH_RELEASE_TEXT_RE = re.compile(
    r"\bgit\s+push\b[^\n;&|`]*?(?:refs/tags/|(?:^|[\s'\"=:/])v?[0-9]+[.][0-9]+[.][0-9]+(?:[-+][A-Za-z0-9._-]+)?(?:$|[\s'\";,&|)]))",
    re.IGNORECASE,
)
GH_RELEASE_MUTATING_RE = re.compile(
    r"\bgh\s+release\s+(?:create|edit|delete|delete-asset|upload)\b",
    re.IGNORECASE,
)
REQUESTS_SESSION_WRITE_RE = re.compile(
    r"\b(?:requests|httpx)\.Session\(\)\.(?:request|post|put|patch|delete)\s*\(",
    re.IGNORECASE,
)
REQUESTS_IMPORTED_WRITE_RE = re.compile(
    r"from\s+(?:requests|httpx)\s+import\s+(request|post|put|patch|delete)"
    r"(?:\s+as\s+([A-Za-z_][A-Za-z0-9_]*))?",
    re.IGNORECASE,
)
PERSISTENT_GH_ALIASES = {}
PERSISTENT_GIT_ALIASES = {}


def tokenize(command):
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()<>{}")
    lexer.whitespace_split = True
    return list(lexer)


def segments(tokens):
    segment = []
    for token in tokens:
        if token in CONTROL:
            if segment:
                yield segment
                segment = []
            continue
        segment.append(token)
    if segment:
        yield segment


def segments_with_controls(tokens):
    segment = []
    incoming_control = None
    pending_control = None
    for token in tokens:
        if token in CONTROL:
            if segment:
                yield segment, incoming_control
                segment = []
            incoming_control = token
            pending_control = token
            continue
        if not segment:
            incoming_control = pending_control
        segment.append(token)
    if segment:
        yield segment, incoming_control


def decode_backslash_escapes(value):
    try:
        return codecs.decode(value, "unicode_escape")
    except Exception:
        return value


def decode_quoted_literal(value):
    if len(value) < 2 or value[0] not in {"'", '"'} or value[-1] != value[0]:
        return None
    return decode_backslash_escapes(value[1:-1])


def collapse_static_string_concats(value):
    text = str(value)
    for _ in range(16):
        def replace(match):
            left = decode_quoted_literal(match.group(1))
            right = decode_quoted_literal(match.group(2))
            if left is None or right is None:
                return match.group(0)
            return repr(left + right)

        updated = STATIC_STRING_CONCAT_RE.sub(replace, text)
        if updated == text:
            return text
        text = updated
    return text


def decoded_base64_payloads(value):
    text = str(value)
    if not STATIC_BASE64_HINT_RE.search(text):
        return []
    decoded = []
    candidates = set(STATIC_BASE64_RE.findall(text))
    candidates.update(
        literal.strip() for literal in quoted_string_literals(text)
        if STATIC_BASE64_RE.fullmatch(literal.strip())
    )
    for candidate in candidates:
        padded = candidate + ("=" * ((4 - len(candidate) % 4) % 4))
        try:
            raw = base64.b64decode(padded, validate=True)
        except (binascii.Error, ValueError):
            continue
        if not raw or b"\x00" in raw:
            continue
        try:
            rendered = raw.decode("utf-8")
        except UnicodeDecodeError:
            continue
        if rendered.strip():
            decoded.append(rendered)
    return decoded


def decoded_payload_mentions_release_command(value):
    for decoded in decoded_base64_payloads(value):
        if (
            GH_RELEASE_MUTATING_RE.search(decoded)
            or GIT_PUSH_RELEASE_TEXT_RE.search(decoded)
            or direct_github_release_api_url(decoded)
            or literal_argv_mentions_release_command(decoded)
        ):
            return True
    return False


def render_printf(format_string, args):
    output = []
    index = 0
    consumed = 0
    while index < len(format_string):
        if format_string[index] != "%":
            output.append(format_string[index])
            index += 1
            continue
        match = PRINTF_SPEC_RE.match(format_string, index)
        if not match:
            output.append(format_string[index])
            index += 1
            continue
        conversion = match.group(1)
        if conversion == "%":
            output.append("%")
        else:
            value = args[consumed] if consumed < len(args) else ""
            consumed += 1
            if conversion == "b":
                value = decode_backslash_escapes(value)
            output.append(value)
        index = match.end()
    rendered = decode_backslash_escapes("".join(output))
    if consumed < len(args):
        rendered = " ".join([rendered] + args[consumed:]).strip()
    return rendered


def static_producer_payload(segment):
    producer_start = command_index_from(segment)
    if producer_start >= len(segment):
        return None
    command_name = Path(segment[producer_start]).name
    if command_name == "printf":
        index = producer_start + 1
        while index < len(segment) and segment[index].startswith("-") and segment[index] != "--":
            index += 1
        if index < len(segment) and segment[index] == "--":
            index += 1
        if index < len(segment):
            return render_printf(segment[index], segment[index + 1:])
        return None
    if command_name == "echo":
        index = producer_start + 1
        decode_escapes = False
        while index < len(segment):
            token = segment[index]
            if token == "--":
                index += 1
                break
            if token.startswith("-") and len(token) > 1 and all(ch in "neE" for ch in token[1:]):
                for ch in token[1:]:
                    if ch == "e":
                        decode_escapes = True
                    elif ch == "E":
                        decode_escapes = False
                index += 1
                continue
            break
        if index < len(segment):
            payload = " ".join(segment[index:])
            return decode_backslash_escapes(payload) if decode_escapes else payload
    return None


REDIRECT_WRITE_TOKENS = {">", ">>", ">|", "<>"}


def generated_file_keys(source):
    keys = set()
    if not source:
        return keys
    keys.add(source)
    if source.startswith("./"):
        keys.add(source[2:])
    elif "/" not in source and not release_source_is_uninspectable(source):
        keys.add("./" + source)
    if release_source_is_uninspectable(source) or EXPANSION_RE.search(source):
        return keys
    try:
        path = Path(source).expanduser()
        if not path.is_absolute():
            path = Path(os.environ.get("PWD") or os.getcwd()) / path
        keys.add(str(path.resolve(strict=False)))
    except OSError:
        pass
    return keys


def record_generated_file(generated_files, source, payload):
    for key in generated_file_keys(source):
        generated_files[key] = payload


def generated_file_lookup(generated_files, source):
    if not generated_files:
        return False, None
    for key in generated_file_keys(source):
        if key in generated_files:
            return True, generated_files[key]
    return False, None


def generated_file_write(segment):
    for index, token in enumerate(segment):
        if token not in REDIRECT_WRITE_TOKENS:
            continue
        if index + 1 >= len(segment):
            continue
        target = segment[index + 1]
        if release_source_is_uninspectable(target) or EXPANSION_RE.search(target):
            return target, None
        payload = static_producer_payload(segment[:index])
        if payload is not None and EXPANSION_RE.search(payload):
            payload = None
        return target, payload
    return None


def tee_generated_file_writes(segment, payload):
    if not segment:
        return []
    start = command_index_from(segment)
    if start >= len(segment) or Path(segment[start]).name != "tee":
        return []
    targets = []
    index = start + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            targets.extend(segment[index + 1:])
            break
        if token in {"-a", "--append", "-i", "--ignore-interrupts", "-p", "--output-error"}:
            index += 1
            continue
        if token.startswith("--output-error="):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        targets.append(token)
        index += 1
    return [
        (target, None if release_source_is_uninspectable(target) or EXPANSION_RE.search(target) else payload)
        for target in targets
    ]


def heredoc_generated_file_writes(command):
    writes = []
    for receiver, payload in heredoc_payloads(command):
        try:
            tokens = tokenize(receiver)
        except Exception:
            continue
        for segment in segments(tokens):
            generated = generated_file_write(segment)
            if generated is not None:
                writes.append((generated[0], payload))
            writes.extend(tee_generated_file_writes(segment, payload))
    return writes


def strip_heredoc_bodies(command):
    lines = command.splitlines()
    output = []
    index = 0
    changed = False
    while index < len(lines):
        line = lines[index]
        match = re.search(r"<<-?\s*(?:'([^']+)'|\"([^\"]+)\"|([A-Za-z_][A-Za-z0-9_]*))", line)
        if not match:
            output.append(line)
            index += 1
            continue
        changed = True
        output.append(line[:match.start()].rstrip())
        delimiter = match.group(1) or match.group(2) or match.group(3)
        cursor = index + 1
        while cursor < len(lines):
            if lines[cursor].strip() == delimiter:
                break
            cursor += 1
        index = cursor + 1 if cursor < len(lines) else index + 1
    return "\n".join(output) if changed else command


def heredoc_generated_file_used_for_release(command, depth):
    stripped = strip_heredoc_bodies(command)
    if stripped == command:
        return False
    for target, payload in heredoc_generated_file_writes(command):
        if payload is None:
            payload_needs_gate = True
        else:
            payload_needs_gate = (
                language_payload_mentions_release_command(payload)
                or contains_release_create(payload, depth + 1)
                or curl_config_mentions_release_write(payload, True)
            )
        if not payload_needs_gate:
            continue
        for key in generated_file_keys(target):
            if key and stripped.count(key) > 1:
                return True
    return False


def render_static_command(command):
    token_command = strip_heredoc_bodies(command)
    if token_command != command:
        token_command = normalize_statement_newlines(token_command)
    try:
        tokens = tokenize(token_command)
    except Exception:
        return None
    for segment in segments(tokens):
        return static_producer_payload(segment)
    return None


def normalize_command(command):
    normalized = command.replace("\\\r\n", "").replace("\\\n", "")
    if "<<" not in normalized:
        normalized = normalize_statement_newlines(normalized)
    normalized = re.sub(r"\)(?=;)", ") ", normalized)
    normalized = expand_ansi_c_quotes(normalized)
    normalized = expand_parameter_expansions(normalized)
    normalized = expand_static_substitutions(normalized)
    return normalized


def normalize_statement_newlines(command):
    output = []
    in_single = False
    in_double = False
    escaped = False
    for ch in command:
        if escaped:
            output.append(ch)
            escaped = False
            continue
        if ch == "\\" and not in_single:
            output.append(ch)
            escaped = True
            continue
        if ch == "'" and not in_double:
            in_single = not in_single
            output.append(ch)
            continue
        if ch == '"' and not in_single:
            in_double = not in_double
            output.append(ch)
            continue
        if ch == "\n" and not in_single and not in_double:
            output.append(";")
            continue
        output.append(ch)
    return "".join(output)


def expand_ansi_c_quotes(command):
    def replace(match):
        return decode_backslash_escapes(match.group(1))
    return re.sub(r"\$'((?:\\.|[^'])*)'", replace, command)


def expand_parameter_expansions(command):
    command = re.sub(r"\$\{IFS\}", " ", command)
    command = re.sub(
        r"\$\{[A-Za-z_][A-Za-z0-9_]*:?-([^{}$`]+)\}",
        lambda match: match.group(1),
        command,
    )
    return command


def expand_static_substitutions(command):
    output = []
    i = 0
    in_single = False
    escaped = False
    while i < len(command):
        ch = command[i]
        if escaped:
            output.append(ch)
            escaped = False
            i += 1
            continue
        if ch == "\\" and not in_single:
            output.append(ch)
            escaped = True
            i += 1
            continue
        if ch == "'":
            in_single = not in_single
            output.append(ch)
            i += 1
            continue
        if not in_single and ch == "$" and i + 1 < len(command) and command[i + 1] == "(":
            payload, end = read_balanced_payload(command, i + 2, "(", ")")
            if payload is not None:
                rendered = render_static_command(payload)
                if rendered is not None:
                    output.append(rendered)
                    i = end + 1
                    continue
        if not in_single and ch == "`":
            end = i + 1
            payload = []
            backtick_escaped = False
            while end < len(command):
                current = command[end]
                if backtick_escaped:
                    payload.append(current)
                    backtick_escaped = False
                    end += 1
                    continue
                if current == "\\":
                    backtick_escaped = True
                    end += 1
                    continue
                if current == "`":
                    rendered = render_static_command("".join(payload))
                    if rendered is not None:
                        output.append(rendered)
                        i = end + 1
                        break
                    output.append(command[i:end + 1])
                    i = end + 1
                    break
                payload.append(current)
                end += 1
            else:
                output.append(ch)
                i += 1
            continue
        output.append(ch)
        i += 1
    return "".join(output)


def _skip_env(segment, index):
    index += 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            return index + 1
        if token in ENV_VALUE_OPTIONS:
            index += 2
            continue
        if any(
            token.startswith(option + "=")
            for option in ENV_VALUE_OPTIONS
            if option.startswith("--")
        ):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        if ASSIGNMENT_RE.match(token):
            index += 1
            continue
        break
    return index


def env_split_payloads(segment, index):
    payloads = []
    if Path(segment[index]).name != "env":
        return payloads
    index += 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            break
        if token in ENV_SPLIT_OPTIONS:
            if index + 1 < len(segment):
                payloads.append(segment[index + 1])
            index += 2
            continue
        for option in ENV_SPLIT_OPTIONS:
            if option.startswith("--") and token.startswith(option + "="):
                payloads.append(token.split("=", 1)[1])
        if token in ENV_VALUE_OPTIONS:
            index += 2
            continue
        if any(
            token.startswith(option + "=")
            for option in ENV_VALUE_OPTIONS
            if option.startswith("--")
        ):
            index += 1
            continue
        if token.startswith("-") or ASSIGNMENT_RE.match(token):
            index += 1
            continue
        break
    return payloads


def _skip_sudo(segment, index):
    index += 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            return index + 1
        if token in SUDO_VALUE_OPTIONS:
            index += 2
            continue
        if any(
            token.startswith(option + "=")
            for option in SUDO_VALUE_OPTIONS
            if option.startswith("--")
        ):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        break
    while index < len(segment) and ASSIGNMENT_RE.match(segment[index]):
        index += 1
    return index


def _skip_time(segment, index):
    index += 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            return index + 1
        if token in TIME_VALUE_OPTIONS:
            index += 2
            continue
        if any(
            token.startswith(option + "=")
            for option in TIME_VALUE_OPTIONS
            if option.startswith("--")
        ):
            index += 1
            continue
        if token in TIME_FLAG_OPTIONS:
            index += 1
            continue
        break
    return index


def _skip_launch_wrapper(segment, index):
    wrapper = Path(segment[index]).name
    index += 1
    if wrapper == "nice":
        while index < len(segment):
            token = segment[index]
            if token == "--":
                return index + 1
            if token in NICE_VALUE_OPTIONS:
                index += 2
                continue
            if any(token.startswith(option + "=") for option in NICE_VALUE_OPTIONS if option.startswith("--")):
                index += 1
                continue
            if re.fullmatch(r"-[0-9]+", token):
                index += 1
                continue
            if token.startswith("-"):
                index += 1
                continue
            break
        return index
    if wrapper == "setsid":
        while index < len(segment):
            token = segment[index]
            if token == "--":
                return index + 1
            if token in SETSID_FLAG_OPTIONS:
                index += 1
                continue
            if token.startswith("-"):
                index += 1
                continue
            break
        return index
    return index


def command_index_from(segment, index=0):
    while index < len(segment) and ASSIGNMENT_RE.match(segment[index]):
        index += 1
    if index < len(segment) and Path(segment[index]).name == "env":
        index = _skip_env(segment, index)
    while index < len(segment):
        wrapper = Path(segment[index]).name
        if wrapper == "env":
            index = _skip_env(segment, index)
            continue
        if wrapper in PREFIX_WRAPPERS:
            index += 1
            continue
        if wrapper in TIME_WRAPPERS:
            index = _skip_time(segment, index)
            continue
        if wrapper in PRIVILEGE_WRAPPERS:
            index = _skip_sudo(segment, index)
            continue
        if wrapper in LAUNCH_WRAPPERS:
            index = _skip_launch_wrapper(segment, index)
            continue
        if wrapper == "builtin" and index + 1 < len(segment) and Path(segment[index + 1]).name in EXEC_WRAPPERS:
            index += 1
            continue
        if wrapper not in EXEC_WRAPPERS:
            break
        index += 1
        if wrapper == "command":
            while index < len(segment):
                token = segment[index]
                if token == "--":
                    index += 1
                    break
                if token == "-p":
                    index += 1
                    continue
                if token.startswith("-"):
                    return len(segment)
                break
        elif wrapper == "exec":
            while index < len(segment):
                token = segment[index]
                if token == "--":
                    index += 1
                    break
                if token == "-a":
                    index += 2
                    continue
                if token in {"-c", "-l"}:
                    index += 1
                    continue
                if token.startswith("-"):
                    return len(segment)
                break
        while index < len(segment) and ASSIGNMENT_RE.match(segment[index]):
            index += 1
    return index


def is_relative_file_source(value):
    if not value or value in {"-", "@-"}:
        return False
    if value.startswith("@"):
        value = value[1:]
    if release_source_is_uninspectable(value) or EXPANSION_RE.search(value):
        return True
    try:
        return not Path(value).expanduser().is_absolute()
    except Exception:
        return True


def segment_has_env_chdir(segment, start):
    for token in segment[:start]:
        if token in {"-C", "--chdir"} or token.startswith("--chdir="):
            return True
    return False


def curl_has_relative_file_operand(segment, start):
    index = start + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            break
        if token in {"-K", "--config"}:
            if index + 1 < len(segment) and is_relative_file_source(segment[index + 1]):
                return True
            index += 2
            continue
        if token.startswith("--config="):
            if is_relative_file_source(token.split("=", 1)[1]):
                return True
            index += 1
            continue
        if token.startswith("-K") and token != "-K":
            if is_relative_file_source(token[2:]):
                return True
            index += 1
            continue
        index += 1
    return False


def wget_has_relative_file_operand(segment, start):
    index = start + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            break
        if token in {"-i", "--input-file", "--post-file", "--body-file"}:
            if index + 1 < len(segment) and is_relative_file_source(segment[index + 1]):
                return True
            index += 2
            continue
        if token.startswith(("--input-file=", "--post-file=", "--body-file=")):
            if is_relative_file_source(token.split("=", 1)[1]):
                return True
            index += 1
            continue
        if token.startswith("-i") and token != "-i":
            if is_relative_file_source(token[2:]):
                return True
            index += 1
            continue
        index += 1
    return False


def local_script_relative_operand(segment, start, generated_files=None):
    operands = []
    for probe in (
        source_script_operand(segment, start),
        shell_script_operand(segment, start),
        interpreter_script_operand(segment, start),
        direct_script_operand(segment, start),
    ):
        if probe:
            operands.append(probe)
    if start < len(segment):
        token = segment[start]
        found, _ = generated_file_lookup(generated_files, token)
        if found:
            operands.append(token)
        if Path(token).name not in KNOWN_EXECUTABLE_COMMANDS and "/" in token:
            operands.append(token)
    return any(is_relative_file_source(operand) for operand in operands)


def release_sensitive_relative_file_carrier(segment, start, generated_files=None):
    command_name = Path(segment[start]).name if start < len(segment) else ""
    if command_name == "curl":
        return curl_has_relative_file_operand(segment, start)
    if command_name == "wget":
        return wget_has_relative_file_operand(segment, start)
    return local_script_relative_operand(segment, start, generated_files)


def gh_context_switches_alias_source(segment, start, scoped_env):
    if any(key in scoped_env for key in {"GH_CONFIG_DIR", "XDG_CONFIG_HOME", "HOME"}):
        return True
    return gh_config_dir_option(segment, start) is not None


def git_context_switches_alias_source(segment, start, scoped_env):
    if any(key in scoped_env for key in {"GIT_CONFIG_GLOBAL", "XDG_CONFIG_HOME", "HOME"}):
        return True
    index = start + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            break
        if token == "-C" or token in {"--git-dir", "--work-tree"}:
            return True
        if token.startswith("-C") and token != "-C":
            return True
        if token.startswith(("--git-dir=", "--work-tree=")):
            return True
        if token in GIT_VALUE_GLOBALS:
            index += 2
            continue
        if token.startswith("-c") and token != "-c":
            index += 1
            continue
        if any(
            token.startswith(option + "=")
            for option in GIT_VALUE_GLOBALS
            if option.startswith("--")
        ):
            index += 1
            continue
        if token in GIT_FLAG_GLOBALS:
            index += 1
            continue
        break
    return False


def skip_gh_globals(segment, index):
    while index < len(segment):
        token = segment[index]
        if token == "--":
            index += 1
            break
        if token in GH_VALUE_GLOBALS:
            index += 2
            continue
        if token.startswith("-R") and token != "-R":
            index += 1
            continue
        if any(
            token.startswith(option + "=")
            for option in GH_VALUE_GLOBALS
            if option.startswith("--")
        ):
            index += 1
            continue
        if token in GH_FLAG_GLOBALS:
            index += 1
            continue
        break
    return index


def gh_subcommand_index(segment, gh_index):
    return skip_gh_globals(segment, gh_index + 1)


def gh_config_dir_option(segment, gh_index):
    index = gh_index + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            break
        if token == "--config-dir":
            return segment[index + 1] if index + 1 < len(segment) else None
        if token.startswith("--config-dir="):
            return token.split("=", 1)[1]
        if token in GH_VALUE_GLOBALS:
            index += 2
            continue
        if token.startswith("-R") and token != "-R":
            index += 1
            continue
        if any(
            token.startswith(option + "=")
            for option in GH_VALUE_GLOBALS
            if option.startswith("--")
        ):
            index += 1
            continue
        if token in GH_FLAG_GLOBALS:
            index += 1
            continue
        break
    return None


def gh_release_mutating_command(segment, gh_index):
    subcommand_index = gh_subcommand_index(segment, gh_index)
    if subcommand_index >= len(segment) or segment[subcommand_index] != "release":
        return False
    if any(token in {"-h", "--help"} for token in segment[subcommand_index + 1:]):
        return False
    release_action_index = skip_gh_globals(segment, subcommand_index + 1)
    if release_action_index >= len(segment):
        return False
    action = segment[release_action_index]
    if action in {"view", "list", "download", "verify-asset", "help"}:
        return False
    return True


def git_subcommand_index(segment, git_index):
    index = git_index + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            index += 1
            break
        if token in GIT_VALUE_GLOBALS:
            index += 2
            continue
        if token.startswith("-c") and token != "-c":
            index += 1
            continue
        if token.startswith("--") and any(
            token.startswith(option + "=")
            for option in GIT_VALUE_GLOBALS
            if option.startswith("--")
        ):
            index += 1
            continue
        if token in GIT_FLAG_GLOBALS:
            index += 1
            continue
        break
    return index


def git_global_alias_assignments(segment, git_index):
    aliases = {}
    index = git_index + 1
    while index < len(segment):
        token = segment[index]
        config_value = None
        if token == "--":
            break
        if token == "-c":
            if index + 1 < len(segment):
                config_value = segment[index + 1]
            index += 2
        elif token.startswith("-c") and token != "-c":
            config_value = token[2:]
            index += 1
        elif token in GIT_VALUE_GLOBALS:
            index += 2
            continue
        elif token.startswith("--") and any(
            token.startswith(option + "=")
            for option in GIT_VALUE_GLOBALS
            if option.startswith("--")
        ):
            index += 1
            continue
        elif token in GIT_FLAG_GLOBALS:
            index += 1
            continue
        else:
            break

        if config_value:
            match = re.match(r"^alias\.([A-Za-z0-9_.-]+)=(.*)$", config_value)
            if match and match.group(2).strip():
                aliases[match.group(1)] = match.group(2).strip()
    return aliases

def git_config_alias_assignment(segment, git_index):
    subcommand_index = git_subcommand_index(segment, git_index)
    if subcommand_index >= len(segment) or segment[subcommand_index] != "config":
        return None
    index = subcommand_index + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            index += 1
            break
        if token in {"--add", "--replace-all", "--global", "--system", "--local", "--worktree", "--fixed-value"}:
            index += 1
            continue
        if token in {"-f", "--file", "--blob", "--type"}:
            index += 2
            continue
        if token.startswith(("--file=", "--blob=", "--type=")):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        break
    if index >= len(segment):
        return None
    key = segment[index]
    if not key.startswith("alias.") or index + 1 >= len(segment):
        return None
    name = key[len("alias."):]
    expansion = segment[index + 1]
    if not re.match(r"^[A-Za-z0-9_.-]+$", name) or not expansion.strip():
        return None
    return name, expansion


def token_is_release_tag_ref(token):
    token = token.lstrip("+")
    if token.startswith("refs/tags/"):
        return True
    return bool(RELEASE_TAG_RE.match(token))


def refspec_is_dynamic(refspec):
    return "$" in refspec or "`" in refspec or bool(EXPANSION_RE.search(refspec))


def refspec_targets_release_tag(refspec):
    if not refspec:
        return False
    parts = [part for part in refspec.split(":") if part]
    if any(token_is_release_tag_ref(part) for part in parts):
        return True
    if not refspec_is_dynamic(refspec):
        return False
    if DYNAMIC_BRANCH_HINT_RE.search(refspec) or "refs/heads/" in refspec:
        return False
    return True


def git_push_refspecs_target_release_tag(refspecs):
    for token in refspecs:
        if token == "tag":
            return True
        if refspec_targets_release_tag(token):
            return True
    return False


def git_push_release_tag_command(segment, git_index):
    subcommand_index = git_subcommand_index(segment, git_index)
    if subcommand_index >= len(segment) or segment[subcommand_index] != "push":
        return False

    index = subcommand_index + 1
    operands = []
    while index < len(segment):
        token = segment[index]
        if token == "--":
            operands.extend(segment[index + 1:])
            break
        if token in GIT_PUSH_RELEASE_TAG_OPTIONS:
            return True
        if token in GIT_PUSH_VALUE_OPTIONS:
            index += 2
            continue
        if token.startswith("--") and any(
            token.startswith(option + "=")
            for option in GIT_PUSH_VALUE_OPTIONS
            if option.startswith("--")
        ):
            index += 1
            continue
        if token.startswith("-o") and token != "-o":
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        operands.append(token)
        index += 1

    if not operands:
        return False

    refspecs = operands[1:] if len(operands) > 1 else []
    return git_push_refspecs_target_release_tag(refspecs)


def referenced_env_names(value):
    return [
        match.group(1) or match.group(2)
        for match in ENV_REFERENCE_RE.finditer(str(value))
    ]


def expand_inherited_env_refs(value, env_map=None):
    text = str(value)
    env_map = env_map or {}

    def replace(match):
        name = match.group(1) or match.group(2)
        if name in env_map:
            return env_map[name]
        return os.environ.get(name, match.group(0))

    return ENV_REFERENCE_RE.sub(replace, text)


def dynamic_release_endpoint_hint(value):
    return any(
        DYNAMIC_RELEASE_ENDPOINT_HINT_RE.search(name)
        for name in referenced_env_names(value)
    )


def endpoint_variants(endpoint, env_map=None):
    text = str(endpoint).strip()
    variants = {text}
    expanded = expand_inherited_env_refs(text, env_map)
    if expanded != text:
        variants.add(expanded)
    for value in list(variants):
        collapsed = collapse_static_string_concats(value)
        if collapsed != value:
            variants.add(collapsed)
    return variants


def github_api_path_parts(endpoint):
    endpoint = endpoint.strip()
    parsed = urllib.parse.urlparse(endpoint)
    if parsed.scheme and parsed.netloc:
        path = parsed.path
    else:
        endpoint = re.sub(r"^https?://api\.github\.com/?", "", endpoint, flags=re.I)
        path = endpoint.split("?", 1)[0]
    path = path.strip("/")
    if path.startswith("api/v3/"):
        path = path[len("api/v3/"):]
    return [part for part in path.split("/") if part]


def is_releases_api_endpoint(endpoint):
    if dynamic_release_endpoint_hint(endpoint):
        return True
    for candidate in endpoint_variants(endpoint):
        parts = github_api_path_parts(candidate)
        if len(parts) >= 4 and parts[0] == "repos" and parts[3] == "releases":
            return True
    return False


def is_git_refs_api_endpoint(endpoint):
    if dynamic_release_endpoint_hint(endpoint):
        return True
    for candidate in endpoint_variants(endpoint):
        parts = github_api_path_parts(candidate)
        if len(parts) >= 5 and parts[0] == "repos" and parts[3:5] == ["git", "refs"]:
            return True
    return False


def is_git_tag_refs_api_endpoint(endpoint):
    if dynamic_release_endpoint_hint(endpoint):
        return True
    for candidate in endpoint_variants(endpoint):
        parts = github_api_path_parts(candidate)
        if len(parts) >= 6 and parts[0] == "repos" and parts[3:6] == ["git", "refs", "tags"]:
            return True
    return False


def normalized_payload_text(payload):
    if not payload:
        return ""
    text = str(payload)
    decoded = urllib.parse.unquote_plus(text)
    variants = {text, decoded, expand_inherited_env_refs(text), expand_inherited_env_refs(decoded)}
    for value in list(variants):
        variants.add(collapse_static_string_concats(value))
    for value in list(variants):
        variants.add(value.replace("\\/", "/"))
    for value in list(variants):
        variants.add(
            re.sub(
                r"\\u([0-9a-fA-F]{4})",
                lambda match: chr(int(match.group(1), 16)),
                value,
            )
        )
    for value in list(variants):
        variants.add(value.replace("\\/", "/"))
    return "\n".join(variants)


def payload_mentions_tag_ref(payload):
    return bool(TAG_REF_TEXT_RE.search(normalized_payload_text(payload)))


def payload_has_dynamic_ref(payload):
    text = normalized_payload_text(payload)
    if re.search(r"[\"']?\bref\b[\"']?\s*[:=]\s*[\"']?v?[0-9]+[.][0-9]+[.][0-9]+", text, re.IGNORECASE):
        return True
    if not EXPANSION_RE.search(text):
        return False
    if "refs/heads/" in text or DYNAMIC_BRANCH_HINT_RE.search(text):
        return False
    return re.search(r"[\"']?\bref\b[\"']?\s*[:=]", text, re.IGNORECASE) is not None or "git/refs" in text


def is_release_api_endpoint(endpoint):
    return is_releases_api_endpoint(endpoint) or is_git_tag_refs_api_endpoint(endpoint)


def is_graphql_endpoint(endpoint):
    for candidate in endpoint_variants(endpoint):
        parts = github_api_path_parts(candidate)
        if parts == ["graphql"] or parts == ["api", "graphql"]:
            return True
    return False


def graphql_release_mutation_text(value):
    text = normalized_payload_text(value)
    if GRAPHQL_RELEASE_MUTATION_RE.search(text):
        return True
    if GRAPHQL_REF_MUTATION_RE.search(text) and payload_mentions_tag_ref(text):
        return True
    if "=" in text:
        _, _, tail = text.partition("=")
        return graphql_release_mutation_text(tail)
    return False


def graphql_query_file_source(value):
    for prefix in ("query:=@", "query=@", "query:@", "query@"):
        if value.startswith(prefix):
            source = value[len(prefix):]
            return source or "-"
    return None


def graphql_file_backed_query(value):
    return graphql_query_file_source(value) is not None


def graphql_dynamic_query(value):
    if not (value.startswith("query=") or value.startswith("query:=")):
        return False
    _, _, query_value = value.partition("=")
    return bool(EXPANSION_RE.search(query_value))


def graphql_payload_needs_gate(value):
    if graphql_dynamic_query(value) or graphql_release_mutation_text(value):
        return True
    query_source = graphql_query_file_source(value)
    if query_source is not None:
        if release_source_is_uninspectable(query_source):
            return True
        source_text = read_release_source_text(query_source)
        if source_text is None:
            return True
        return graphql_release_mutation_text(source_text)
    if value in {"-", "@-"}:
        return True
    source = value[1:] if value.startswith("@") else None
    if source:
        if release_source_is_uninspectable(source):
            return True
        source_text = read_release_source_text(source)
        if source_text is None:
            return True
        return graphql_release_mutation_text(source_text)
    return False


def gh_api_release_write_command(segment, gh_index, generated_files=None):
    subcommand_index = gh_subcommand_index(segment, gh_index)
    if subcommand_index >= len(segment) or segment[subcommand_index] != "api":
        return False
    method = None
    has_write_fields = False
    graphql_payloads = []
    endpoint = None
    index = subcommand_index + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            index += 1
            continue
        if token in {"-X", "--method"}:
            if index + 1 < len(segment):
                method = segment[index + 1].upper()
            index += 2
            continue
        if token.startswith("-X") and token != "-X":
            method = token[2:].upper()
            index += 1
            continue
        if token.startswith("--method="):
            method = token.split("=", 1)[1].upper()
            index += 1
            continue
        if token in {"-f", "--field", "-F", "--raw-field"}:
            has_write_fields = True
            if index + 1 < len(segment):
                graphql_payloads.append(segment[index + 1])
            index += 2
            continue
        if token == "--input":
            has_write_fields = True
            if index + 1 < len(segment):
                graphql_payloads.append("@" + segment[index + 1])
            index += 2
            continue
        if token.startswith("--field=") or token.startswith("--raw-field="):
            has_write_fields = True
            payload = token.split("=", 1)[1]
            graphql_payloads.append(payload)
            index += 1
            continue
        if token.startswith("--input="):
            has_write_fields = True
            graphql_payloads.append("@" + token.split("=", 1)[1])
            index += 1
            continue
        if (token.startswith("-f") or token.startswith("-F")) and token not in {"-f", "-F"}:
            has_write_fields = True
            payload = token[2:]
            graphql_payloads.append(payload)
            index += 1
            continue
        if token in GH_API_VALUE_OPTIONS:
            index += 2
            continue
        if any(token.startswith(option + "=") for option in GH_API_VALUE_OPTIONS if option.startswith("--")):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        if endpoint is None:
            endpoint = token
        index += 1
    if not endpoint:
        return False
    effective_method = method or ("POST" if has_write_fields else "GET")
    if is_graphql_endpoint(endpoint):
        if effective_method not in GH_API_WRITE_METHODS and not has_write_fields:
            return False
        return any(graphql_payload_needs_gate(payload) for payload in graphql_payloads)
    command_has_write_semantics = effective_method in GH_API_WRITE_METHODS or has_write_fields
    if is_release_api_endpoint(endpoint):
        return command_has_write_semantics
    if not is_git_refs_api_endpoint(endpoint) or not command_has_write_semantics:
        return False
    return rest_tag_ref_payloads_need_gate(graphql_payloads, generated_files)


def direct_github_release_api_url(value):
    if dynamic_release_endpoint_hint(value):
        return True
    for candidate in endpoint_variants(value):
        if (
            GITHUB_RELEASE_API_RE.search(candidate)
            or (GITHUB_REFS_API_RE.search(candidate) and payload_mentions_tag_ref(candidate))
            or is_releases_api_endpoint(candidate)
            or is_git_tag_refs_api_endpoint(candidate)
            or (is_git_refs_api_endpoint(candidate) and payload_mentions_tag_ref(candidate))
        ):
            return True
    return False


def file_text_mentions_release_write(text, command_has_write_semantics=False):
    if not text:
        return False
    if language_payload_mentions_release_command(text):
        return True
    if command_has_write_semantics and direct_github_release_api_url(text):
        return True
    return False


def curl_config_has_write_semantics(text):
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        key, separator, value = stripped.partition("=")
        if separator:
            key = key.strip().lstrip("-").lower().replace("_", "-")
            value = value.strip().strip("'\"")
        else:
            parts = stripped.split(None, 1)
            key = parts[0].strip().lstrip("-").lower().replace("_", "-")
            value = parts[1].strip().strip("'\"") if len(parts) > 1 else ""
        if key in {
            "data", "data-raw", "data-binary", "data-urlencode",
            "json", "form", "form-string", "upload-file",
        }:
            return True
        if key in {"request", "custom-request"} and value.upper() in GITHUB_API_WRITE_METHODS:
            return True
    return False


def curl_config_mentions_release_write(text, command_has_write_semantics=False):
    return file_text_mentions_release_write(
        text,
        command_has_write_semantics or curl_config_has_write_semantics(text),
    )


def read_release_source_text(source):
    try:
        path = Path(source)
    except Exception:
        return None
    if not path.is_file():
        return None
    try:
        return path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return None


def generated_source_text(source, generated_files=None):
    found, text = generated_file_lookup(generated_files, source)
    if found:
        return text
    return None


def payload_file_source(payload):
    if payload in {"-", "@-"}:
        return "-"
    value = payload
    if "=" in value:
        _, _, value = value.partition("=")
    if value in {"-", "@-"}:
        return "-"
    if value.startswith("@"):
        return value[1:]
    return None


def payload_or_source_mentions_tag_ref(payload, generated_files=None):
    if payload_mentions_tag_ref(payload):
        return True
    if payload_has_dynamic_ref(payload):
        return None
    source = payload_file_source(payload)
    if source is None:
        return False
    if release_source_is_uninspectable(source):
        return None
    found, generated_text = generated_file_lookup(generated_files, source)
    if found:
        source_text = generated_text
        if source_text is None:
            return None
        return payload_mentions_tag_ref(source_text)
    source_text = read_release_source_text(source)
    if source_text is None:
        return None
    return payload_mentions_tag_ref(source_text)


def rest_tag_ref_payloads_need_gate(payloads, generated_files=None):
    for payload in payloads:
        result = payload_or_source_mentions_tag_ref(payload, generated_files)
        if result is True or result is None:
            return True
    return False


def read_bounded_script_text(source):
    try:
        path = Path(source).expanduser()
    except Exception:
        return None
    if not path.is_file():
        return None
    try:
        with path.open("r", encoding="utf-8", errors="ignore") as handle:
            return handle.read(SCRIPT_READ_MAX_BYTES)
    except OSError:
        return None


def release_source_is_uninspectable(source):
    return source == "-" or source.startswith("<(") or source.startswith("/dev/fd/")


def release_payload_matches_git_endpoint(payload):
    text = normalized_payload_text(payload)
    return bool(
        re.search(r"api\.github\.com", text, re.IGNORECASE)
        and (
            re.search(r"repos/[^/\s\"']+/[^/\s\"']+/releases\b", text)
            or re.search(r"repos/[^/\s\"']+/[^/\s\"']+/git/refs/tags\b", text)
            or (
                re.search(r"repos/[^/\s\"']+/[^/\s\"']+/git/refs\b", text)
                and payload_mentions_tag_ref(text)
            )
            or graphql_release_mutation_text(text)
        )
    )


def release_payload_import_aliases(payload):
    aliases = []
    for method, alias in REQUESTS_IMPORTED_WRITE_RE.findall(payload):
        aliases.append(alias or method)
    return aliases


def curl_release_write_command(segment, start, generated_files=None):
    method = None
    has_write_body = False
    urls = []
    config_files = []
    config_texts = []
    body_payloads = []
    index = start + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            urls.extend(segment[index + 1:])
            break
        if token in {"-X", "--request"}:
            if index + 1 < len(segment):
                method = segment[index + 1].upper()
            index += 2
            continue
        if token.startswith("-X") and token != "-X":
            method = token[2:].upper()
            index += 1
            continue
        if token.startswith("--request="):
            method = token.split("=", 1)[1].upper()
            index += 1
            continue
        if token in {
            "-d", "--data", "--data-raw", "--data-binary", "--data-urlencode",
            "--json", "-F", "--form", "--form-string",
        }:
            has_write_body = True
            if index + 1 < len(segment):
                body_payloads.append(segment[index + 1])
            index += 2
            continue
        if token.startswith("-d") and token != "-d":
            has_write_body = True
            body_payloads.append(token[2:])
            index += 1
            continue
        if token.startswith("-F") and token != "-F":
            has_write_body = True
            body_payloads.append(token[2:])
            index += 1
            continue
        if token.startswith(("--data=", "--data-raw=", "--data-binary=", "--data-urlencode=", "--json=", "--form=", "--form-string=")):
            has_write_body = True
            body_payloads.append(token.split("=", 1)[1])
            index += 1
            continue
        if token in {"--url"}:
            if index + 1 < len(segment):
                urls.append(segment[index + 1])
            index += 2
            continue
        if token.startswith("--url="):
            urls.append(token.split("=", 1)[1])
            index += 1
            continue
        if token in {"-K", "--config"}:
            if index + 1 < len(segment):
                if segment[index + 1] == "<(":
                    depth = 1
                    cursor = index + 2
                    payload = []
                    while cursor < len(segment):
                        if segment[cursor] == "(":
                            depth += 1
                        elif segment[cursor] == ")":
                            depth -= 1
                            if depth == 0:
                                break
                        payload.append(segment[cursor])
                        cursor += 1
                    producer_payload = static_producer_payload(payload)
                    if producer_payload is None:
                        return True
                    config_texts.append(producer_payload)
                    index = cursor + 1
                else:
                    config_files.append(segment[index + 1])
                    index += 2
            continue
        if token.startswith("--config="):
            config_files.append(token.split("=", 1)[1])
            index += 1
            continue
        if token.startswith("-K") and token != "-K":
            config_files.append(token[2:])
            index += 1
            continue
        if token in {"-H", "--header", "-u", "--user", "-o", "--output", "-A", "--user-agent", "--connect-to", "--resolve"}:
            index += 2
            continue
        if token.startswith("-"):
            index += 1
            continue
        urls.append(token)
        index += 1
    command_has_write_semantics = (method or ("POST" if has_write_body else "GET")) in GITHUB_API_WRITE_METHODS or has_write_body
    release_url_present = any(direct_github_release_api_url(url) for url in urls)
    config_write_semantics = False
    for config_text in config_texts:
        if curl_config_has_write_semantics(config_text):
            config_write_semantics = True
        if curl_config_mentions_release_write(config_text, command_has_write_semantics or release_url_present):
            return True
    for config_file in config_files:
        config_text = None
        found, generated_text = generated_file_lookup(generated_files, config_file)
        if found:
            config_text = generated_text
            if config_text is None:
                return True
        elif release_source_is_uninspectable(config_file):
            if release_url_present or config_file in {"-", "@-"}:
                return True
        else:
            config_text = read_release_source_text(config_file)
        if config_text is None:
            if release_url_present:
                return True
            continue
        if curl_config_has_write_semantics(config_text):
            config_write_semantics = True
        if curl_config_mentions_release_write(config_text, command_has_write_semantics or release_url_present):
            return True
    command_has_write_semantics = command_has_write_semantics or config_write_semantics
    if release_url_present:
        return command_has_write_semantics
    if any(is_git_refs_api_endpoint(url) for url in urls) and command_has_write_semantics:
        if any(is_git_tag_refs_api_endpoint(url) for url in urls):
            return True
        if rest_tag_ref_payloads_need_gate(body_payloads, generated_files):
            return True
    if any(is_graphql_endpoint(url) for url in urls) and command_has_write_semantics:
        if not body_payloads:
            return False
        return any(graphql_payload_needs_gate(payload) for payload in body_payloads)
    return False


def wget_release_write_command(segment, start, generated_files=None):
    method = None
    has_write_body = False
    urls = []
    input_files = []
    body_payloads = []
    index = start + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            urls.extend(segment[index + 1:])
            break
        if token == "--method":
            if index + 1 < len(segment):
                method = segment[index + 1].upper()
            index += 2
            continue
        if token.startswith("--method="):
            method = token.split("=", 1)[1].upper()
            index += 1
            continue
        if token in {"--post-data", "--body-data"}:
            has_write_body = True
            if index + 1 < len(segment):
                body_payloads.append(segment[index + 1])
            index += 2
            continue
        if token in {"--post-file", "--body-file"}:
            has_write_body = True
            if index + 1 < len(segment):
                body_payloads.append("@" + segment[index + 1])
            index += 2
            continue
        if token.startswith("--post-data=") or token.startswith("--body-data="):
            has_write_body = True
            body_payloads.append(token.split("=", 1)[1])
            index += 1
            continue
        if token.startswith("--post-file=") or token.startswith("--body-file="):
            has_write_body = True
            body_payloads.append("@" + token.split("=", 1)[1])
            index += 1
            continue
        if token in {"-i", "--input-file"}:
            if index + 1 < len(segment):
                input_files.append(segment[index + 1])
            index += 2
            continue
        if token.startswith("--input-file="):
            input_files.append(token.split("=", 1)[1])
            index += 1
            continue
        if token.startswith("-i") and token != "-i":
            input_files.append(token[2:])
            index += 1
            continue
        if token in {"-O", "--output-document", "--header", "--user", "--password"}:
            index += 2
            continue
        if token.startswith("-"):
            index += 1
            continue
        urls.append(token)
        index += 1
    if any(direct_github_release_api_url(url) for url in urls):
        return (method or ("POST" if has_write_body else "GET")) in GITHUB_API_WRITE_METHODS or has_write_body
    command_has_write_semantics = (method or ("POST" if has_write_body else "GET")) in GITHUB_API_WRITE_METHODS or has_write_body
    if any(is_git_refs_api_endpoint(url) for url in urls) and command_has_write_semantics:
        if any(is_git_tag_refs_api_endpoint(url) for url in urls):
            return True
        if rest_tag_ref_payloads_need_gate(body_payloads, generated_files):
            return True
    if any(is_graphql_endpoint(url) for url in urls) and command_has_write_semantics:
        if not body_payloads:
            return False
        return any(graphql_payload_needs_gate(payload) for payload in body_payloads)
    for input_file in input_files:
        file_text = read_release_source_text(input_file)
        if file_text is None:
            if release_source_is_uninspectable(input_file):
                return True
            continue
        if file_text_mentions_release_write(file_text, command_has_write_semantics):
            return True
    return False


def command_start_candidates(segment):
    candidates = {0}
    if segment:
        if segment[0] in CONTROL_PREFIXES:
            candidates.add(1)
        if segment[0] in GROUP_PREFIXES:
            candidates.add(1)
    for index in range(len(segment) - 1):
        if segment[index] == "(" and (index == 0 or segment[index - 1] == "$"):
            candidates.add(index + 1)
    return sorted(candidate for candidate in candidates if candidate < len(segment))


def xargs_payload(segment, start):
    if start >= len(segment) or Path(segment[start]).name != "xargs":
        return None
    tokens = xargs_static_tokens(segment, start)
    return " ".join(shlex.quote(t) for t in tokens) or None


def xargs_static_tokens(segment, start):
    if start >= len(segment) or Path(segment[start]).name != "xargs":
        return []
    value_options = {
        "-a", "--arg-file",
        "-d", "--delimiter",
        "-E", "--eof",
        "-I", "--replace",
        "-L", "--max-lines",
        "-l",
        "-n", "--max-args",
        "-P", "--max-procs",
        "-s", "--max-chars",
    }
    flag_options = {
        "-0", "--null",
        "-o", "--open-tty",
        "-p", "--interactive",
        "-r", "--no-run-if-empty",
        "-t", "--verbose",
        "-x", "--exit",
    }
    index = start + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            return tokens_before_redirection(segment[index + 1:])
        if token in flag_options:
            index += 1
            continue
        if token in value_options:
            index += 2
            continue
        if any(
            token.startswith(option + "=")
            for option in {
                "--arg-file", "--delimiter", "--replace", "--eof",
                "--max-lines", "--max-procs", "--max-args", "--max-chars",
            }
        ):
            index += 1
            continue
        if any(
            token.startswith(option) and len(token) > len(option)
            for option in {"-a", "-d", "-E", "-I", "-L", "-l", "-n", "-P", "-s"}
        ):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        break
    return tokens_before_redirection(segment[index:])


def tokens_before_redirection(tokens):
    redirections = {"<", "<<<", ">", ">>", ">|", "<>", "<<", ">&", "<&"}
    result = []
    index = 0
    while index < len(tokens):
        token = tokens[index]
        if token in redirections:
            break
        result.append(token)
        index += 1
    return result


def xargs_replacement_placeholder(segment, start):
    if start >= len(segment) or Path(segment[start]).name != "xargs":
        return None
    index = start + 1
    value_options = {
        "-a", "--arg-file",
        "-d", "--delimiter",
        "-E", "--eof",
        "-L", "--max-lines",
        "-l",
        "-n", "--max-args",
        "-P", "--max-procs",
        "-s", "--max-chars",
    }
    flag_options = {
        "-0", "--null",
        "-o", "--open-tty",
        "-p", "--interactive",
        "-r", "--no-run-if-empty",
        "-t", "--verbose",
        "-x", "--exit",
    }
    while index < len(segment):
        token = segment[index]
        if token == "--":
            return None
        if token in {"-I", "--replace"}:
            return segment[index + 1] if index + 1 < len(segment) else "{}"
        if token.startswith("--replace="):
            return token.split("=", 1)[1] or "{}"
        if token == "-i":
            return "{}"
        if token.startswith("-I") and token != "-I":
            return token[2:] or "{}"
        if token.startswith("-i") and token != "-i":
            return token[2:] or "{}"
        if token in flag_options:
            index += 1
            continue
        if token in value_options:
            index += 2
            continue
        if any(
            token.startswith(option + "=")
            for option in {
                "--arg-file", "--delimiter", "--eof",
                "--max-lines", "--max-procs", "--max-args", "--max-chars",
            }
        ):
            index += 1
            continue
        if any(
            token.startswith(option) and len(token) > len(option)
            for option in {"-a", "-d", "-E", "-L", "-l", "-n", "-P", "-s"}
        ):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        return None
    return None


def xargs_stdin_can_complete_release(segment, start):
    tokens = xargs_static_tokens(segment, start)
    if not tokens:
        return False
    command_start = command_index_from(tokens)
    if command_start >= len(tokens):
        return False
    command_name = Path(tokens[command_start]).name
    if command_name == "gh":
        subcommand_index = gh_subcommand_index(tokens, command_start)
        suffix = tokens[subcommand_index:]
        if suffix == []:
            return True
        if suffix and suffix[0] == "release":
            create_index = skip_gh_globals(tokens, subcommand_index + 1)
            return create_index >= len(tokens)
        return False
    if command_name in SHELLS:
        for index, token in enumerate(tokens[command_start + 1:], command_start + 1):
            if token in {"-c", "-lc", "-cl"} or (token.startswith("-") and "c" in token):
                if index + 1 >= len(tokens):
                    return True
                return shell_payload_positional_can_complete_release(tokens[index + 1])
    return False


def is_positional_arg(token):
    return bool(POSITIONAL_ARG_RE.match(token))


def positional_replacement(token, positionals, argv0=None):
    if token in {"$@", "${@}", "$*", "${*}"}:
        return list(positionals)
    match = re.match(r"^\$([0-9]+)$", token) or re.match(r"^\$\{([0-9]+)\}$", token)
    if match:
        number = int(match.group(1))
        if number == 0:
            return [argv0] if argv0 is not None else []
        if number <= len(positionals):
            return [positionals[number - 1]]
        return []
    return None


def positional_fragment_replacement(token, positionals, argv0=None):
    if "$" not in token:
        return None
    changed = False

    def replace(match):
        nonlocal changed
        changed = True
        spec = match.group(1) or match.group(2) or match.group(3)
        if spec in {"@", "*"}:
            return " ".join(positionals)
        number = int(spec)
        if number == 0:
            return argv0 or ""
        if number <= len(positionals):
            return positionals[number - 1]
        return ""

    result = POSITIONAL_FRAGMENT_RE.sub(replace, token)
    return result if changed else None


def payload_with_positionals_can_complete_release(payload, positionals, depth=0, argv0=None):
    if depth > 3 or (not positionals and argv0 is None):
        return False
    try:
        tokens = tokenize(payload)
    except Exception:
        return False
    for segment in segments(tokens):
        expanded = []
        changed = False
        for token in segment:
            replacement = positional_replacement(token, positionals, argv0)
            if replacement is None:
                fragment_replacement = positional_fragment_replacement(token, positionals, argv0)
                if fragment_replacement is not None:
                    expanded.append(fragment_replacement)
                    changed = True
                    continue
                expanded.append(token)
                continue
            expanded.extend(replacement)
            changed = True
        if not changed:
            continue
        probe = " ".join(shlex.quote(token) for token in expanded)
        if contains_release_create(probe, depth + 1):
            return True
    return False


def shell_payload_positional_can_complete_release(payload, depth=0):
    if depth > 3:
        return False
    try:
        tokens = tokenize(payload)
    except Exception:
        return False
    for segment in segments(tokens):
        for candidate in command_start_candidates(segment):
            start = command_index_from(segment, candidate)
            if start >= len(segment):
                continue
            command_name = Path(segment[start]).name
            if is_positional_arg(segment[start]):
                return True
            if command_name == "gh":
                subcommand_index = gh_subcommand_index(segment, start)
                if subcommand_index < len(segment) and is_positional_arg(segment[subcommand_index]):
                    return True
                if subcommand_index < len(segment) and segment[subcommand_index] == "release":
                    create_index = skip_gh_globals(segment, subcommand_index + 1)
                    if create_index < len(segment) and is_positional_arg(segment[create_index]):
                        return True
            eval_candidate = eval_payload(segment, start)
            if eval_candidate and shell_payload_positional_can_complete_release(eval_candidate, depth + 1):
                return True
    return False


def xargs_replacement_can_complete_release(segment, start):
    placeholder = xargs_replacement_placeholder(segment, start)
    if not placeholder:
        return False
    tokens = xargs_static_tokens(segment, start)
    if not tokens:
        return False
    command_start = command_index_from(tokens)
    if command_start >= len(tokens):
        return False
    command_name = Path(tokens[command_start]).name
    if tokens[command_start] == placeholder:
        return True
    if command_name in SHELLS:
        payload = shell_payload(tokens)
        return bool(payload and placeholder in payload)
    if command_name != "gh":
        return False
    subcommand_index = gh_subcommand_index(tokens, command_start)
    if subcommand_index >= len(tokens):
        return True
    if tokens[subcommand_index] == placeholder:
        return True
    if tokens[subcommand_index] != "release":
        return False
    create_index = skip_gh_globals(tokens, subcommand_index + 1)
    return create_index >= len(tokens) or tokens[create_index] == placeholder


def is_dynamic_expansion(token):
    return bool(EXPANSION_RE.search(token))


def dynamic_expansion_end(segment, index):
    if index >= len(segment):
        return None
    token = segment[index]
    if is_dynamic_expansion(token):
        return index + 1
    if token == "$" and index + 1 < len(segment) and segment[index + 1] == "(":
        depth = 1
        cursor = index + 2
        while cursor < len(segment):
            if segment[cursor] == "(":
                depth += 1
            elif segment[cursor] == ")":
                depth -= 1
                if depth == 0:
                    return cursor + 1
            cursor += 1
        return len(segment)
    return None


def dynamic_expansion_can_complete_release(segment, start):
    if start >= len(segment):
        return False
    dynamic_end = dynamic_expansion_end(segment, start)
    if dynamic_end is not None and dynamic_end + 1 < len(segment):
        second_dynamic_end = dynamic_expansion_end(segment, dynamic_end)
        if second_dynamic_end is not None:
            if second_dynamic_end < len(segment) and segment[second_dynamic_end] == "create":
                return True
            if second_dynamic_end < len(segment) and dynamic_expansion_end(segment, second_dynamic_end) is not None:
                return True
        return segment[dynamic_end] == "release" and segment[dynamic_end + 1] == "create"
    command_name = Path(segment[start]).name
    if command_name != "gh":
        return False
    subcommand_index = gh_subcommand_index(segment, start)
    dynamic_end = dynamic_expansion_end(segment, subcommand_index)
    if dynamic_end is not None:
        if dynamic_end < len(segment) and segment[dynamic_end] == "create":
            return True
        return dynamic_end < len(segment) and dynamic_expansion_end(segment, dynamic_end) is not None
    if subcommand_index < len(segment) and segment[subcommand_index] == "release":
        create_index = skip_gh_globals(segment, subcommand_index + 1)
        return dynamic_expansion_end(segment, create_index) is not None
    return False


def find_exec_payloads(segment, start):
    if start >= len(segment) or Path(segment[start]).name != "find":
        return []
    payloads = []
    index = start + 1
    exec_tokens = {"-exec", "-execdir", "-ok", "-okdir"}
    while index < len(segment):
        if segment[index] not in exec_tokens:
            index += 1
            continue
        index += 1
        payload = []
        while index < len(segment):
            token = segment[index]
            if token in {";", "+"}:
                break
            payload.append(token)
            index += 1
        if payload:
            payloads.append(" ".join(shlex.quote(t) for t in payload if t != "{}"))
        index += 1
    return payloads


def newline_payloads(command):
    payloads = []
    in_single = False
    in_double = False
    escaped = False
    start = 0

    for i, ch in enumerate(command):
        if escaped:
            escaped = False
            continue
        if ch == "\\" and not in_single:
            escaped = True
            continue
        if ch == "'" and not in_double:
            in_single = not in_single
            continue
        if ch == '"' and not in_single:
            in_double = not in_double
            continue
        if ch == "\n" and not in_single and not in_double:
            fragment = command[start:i].strip()
            if fragment:
                payloads.append(fragment)
            start = i + 1

    if payloads:
        fragment = command[start:].strip()
        if fragment:
            payloads.append(fragment)
    return payloads


def backtick_payloads(command):
    payloads = []
    in_single = False
    in_double = False
    in_backtick = False
    escaped = False
    payload = []

    for ch in command:
        if escaped:
            if in_backtick:
                payload.append(ch)
            escaped = False
            continue

        if ch == "\\" and not in_single:
            escaped = True
            if in_backtick:
                payload.append(ch)
            continue

        if in_backtick:
            if ch == "`":
                payloads.append("".join(payload))
                payload = []
                in_backtick = False
                continue
            payload.append(ch)
            continue

        if ch == "'" and not in_double:
            in_single = not in_single
            continue

        if ch == '"' and not in_single:
            in_double = not in_double
            continue

        if ch == "`" and not in_single:
            in_backtick = True
            payload = []

    return payloads


def brace_payloads(command):
    payloads = []
    in_single = False
    in_double = False
    escaped = False
    i = 0

    while i < len(command):
        ch = command[i]

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

        if not in_single and not in_double and ch == "{" and (i == 0 or command[i - 1] != "$"):
            payload, end = read_balanced_payload(command, i + 1, "{", "}")
            if payload is not None:
                payloads.append(payload)
                i = end + 1
                continue

        i += 1

    return payloads


def process_substitution_payloads(command):
    payloads = []
    in_single = False
    in_double = False
    escaped = False
    i = 0

    while i < len(command):
        ch = command[i]

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

        if not in_single and not in_double and ch in "<>" and i + 1 < len(command) and command[i + 1] == "(":
            payload, end = read_balanced_payload(command, i + 2, "(", ")")
            if payload is not None:
                payloads.append(payload)
                i = end + 1
                continue

        i += 1

    return payloads


def command_substitution_payloads(command):
    payloads = []
    in_single = False
    in_double = False
    escaped = False
    i = 0

    while i < len(command):
        ch = command[i]

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

        if not in_single and ch == "$" and i + 1 < len(command) and command[i + 1] == "(":
            payload, end = read_balanced_payload(command, i + 2, "(", ")")
            if payload is not None:
                payloads.append(payload)
                i = end + 1
                continue

        i += 1

    return payloads


def read_balanced_payload(command, start, opener, closer):
    depth = 1
    in_single = False
    in_double = False
    escaped = False
    payload = []
    i = start

    while i < len(command):
        ch = command[i]

        if escaped:
            payload.append(ch)
            escaped = False
            i += 1
            continue

        if ch == "\\" and not in_single:
            payload.append(ch)
            escaped = True
            i += 1
            continue

        if ch == "'" and not in_double:
            in_single = not in_single
            payload.append(ch)
            i += 1
            continue

        if ch == '"' and not in_single:
            in_double = not in_double
            payload.append(ch)
            i += 1
            continue

        if not in_single and not in_double:
            if ch == opener:
                depth += 1
            elif ch == closer:
                depth -= 1
                if depth == 0:
                    return "".join(payload), i

        payload.append(ch)
        i += 1

    return None, len(command)


def shell_payload(segment):
    parts = shell_payload_parts(segment)
    return parts[0] if parts else None


def shell_payload_parts(segment):
    start = command_index_from(segment)
    if start >= len(segment) or Path(segment[start]).name not in SHELLS:
        return None
    index = start + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            return None
        if token == "-c" or (token.startswith("-") and not token.startswith("--") and "c" in token[1:]):
            if index + 1 < len(segment):
                return segment[index + 1], segment[index + 2:]
            return None
        if token in SHELL_VALUE_OPTIONS:
            index += 2
            continue
        if any(token.startswith(option + "=") for option in SHELL_VALUE_OPTIONS):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        break
    return None


def shell_reads_stdin(segment, start):
    index = start + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            return index + 1 >= len(segment)
        if token == "-c" or (token.startswith("-") and not token.startswith("--") and "c" in token[1:]):
            return False
        if token in SHELL_VALUE_OPTIONS:
            index += 2
            continue
        if any(token.startswith(option + "=") for option in SHELL_VALUE_OPTIONS):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        return False
    return True


def static_shell_stdin_payload(previous_segment, incoming_control, shell_segment):
    start = command_index_from(shell_segment)
    if start >= len(shell_segment) or Path(shell_segment[start]).name not in SHELLS:
        return None
    if shell_payload(shell_segment):
        return None
    if not shell_reads_stdin(shell_segment, start):
        return None
    if incoming_control != "|" or previous_segment is None:
        return None
    return static_producer_payload(previous_segment)


def process_substitution_script_payloads(segment, start):
    if start >= len(segment):
        return []
    command_name = "." if segment[start] == "." else Path(segment[start]).name
    is_interpreter = command_name in INTERPRETER_PAYLOAD_OPTIONS
    if command_name not in SHELLS and command_name not in SOURCE_LOADERS and not is_interpreter:
        return []
    if command_name in SHELLS and shell_payload(segment):
        return []
    index = start + 1
    if command_name in SHELLS:
        while index < len(segment):
            token = segment[index]
            if token == "--":
                index += 1
                break
            if token in SHELL_VALUE_OPTIONS:
                index += 2
                continue
            if any(token.startswith(option + "=") for option in SHELL_VALUE_OPTIONS):
                index += 1
                continue
            if token.startswith("-"):
                index += 1
                continue
            break
    payloads = []
    while index < len(segment):
        if segment[index] != "<(":
            index += 1
            continue
        depth = 1
        cursor = index + 1
        payload = []
        while cursor < len(segment):
            if segment[cursor] == "(":
                depth += 1
            elif segment[cursor] == ")":
                depth -= 1
                if depth == 0:
                    break
            payload.append(segment[cursor])
            cursor += 1
        producer_payload = static_producer_payload(payload)
        if producer_payload:
            payloads.append(producer_payload)
        elif payload:
            payloads.append("gh release create")
        index = cursor + 1
    return payloads


def stdin_payload(segment, start):
    payloads = []
    index = start + 1
    while index < len(segment):
        token = segment[index]
        if token == "<<<":
            if index + 1 < len(segment):
                payloads.append(segment[index + 1])
            index += 2
            continue
        if token == "<" and index + 1 < len(segment):
            if segment[index + 1] == "<(":
                depth = 1
                cursor = index + 2
                payload = []
                while cursor < len(segment):
                    if segment[cursor] == "(":
                        depth += 1
                    elif segment[cursor] == ")":
                        depth -= 1
                        if depth == 0:
                            break
                    payload.append(segment[cursor])
                    cursor += 1
                producer_payload = static_producer_payload(payload)
                if producer_payload:
                    payloads.append(producer_payload)
                elif payload:
                    payloads.append(" ".join(payload))
                index = cursor + 1
                continue
        index += 1
    return payloads


def variable_name(token):
    match = VARIABLE_TOKEN_RE.match(token)
    if not match:
        return None
    return match.group(1) or match.group(2)


def literal_assignment(token):
    match = ASSIGNMENT_FULL_RE.match(token)
    if not match:
        return None
    name, value = match.groups()
    if re.search(r"[$`]", value):
        return None
    return name, value


def indexed_literal_assignment(token):
    match = INDEXED_ASSIGNMENT_FULL_RE.match(token)
    if not match:
        return None
    name, index, value = match.groups()
    if re.search(r"[$`]", value):
        return None
    return name, int(index), value


def standalone_literal_assignments(segment):
    assignments = {}
    for token in segment:
        parsed = literal_assignment(token)
        if parsed is None:
            return None
        assignments[parsed[0]] = parsed[1]
    return assignments


def exported_literal_assignments(segment):
    if not segment:
        return None
    start = command_index_from(segment)
    if start >= len(segment):
        return None
    command = Path(segment[start]).name
    if command not in {"export", "declare", "typeset"}:
        return None
    index = start + 1
    export_seen = command == "export"
    assignments = {}
    while index < len(segment):
        token = segment[index]
        if token == "--":
            index += 1
            break
        if token == "-x" or ("x" in token[1:] if token.startswith("-") and not token.startswith("--") else False):
            export_seen = True
            index += 1
            continue
        if token in {"-a", "-A", "-g", "-r"} or token.startswith("--"):
            index += 1
            continue
        break
    if not export_seen:
        return None
    while index < len(segment):
        parsed = literal_assignment(segment[index])
        if parsed is not None:
            assignments[parsed[0]] = parsed[1]
        index += 1
    return assignments or None


def indexed_array_assignment(segment):
    if len(segment) != 1:
        return None
    parsed = indexed_literal_assignment(segment[0])
    if parsed is None:
        return None
    return parsed


def split_expansion_words(value):
    try:
        words = shlex.split(value)
    except Exception:
        words = value.split()
    return words or [value]


def inherited_env_value_needs_resolution(name, value):
    if DYNAMIC_RELEASE_ENDPOINT_HINT_RE.search(name):
        return True
    if token_is_release_tag_ref(value):
        return True
    lowered = value.lower()
    return (
        "api.github.com" in lowered
        or "repos/" in lowered
        or "refs/tags/" in lowered
        or "graphql" in lowered
    )


def combine_braced_expansion_tokens(segment):
    combined = []
    index = 0
    while index < len(segment):
        if (
            segment[index] == "$"
            and index + 3 < len(segment)
            and segment[index + 1] == "{"
            and segment[index + 3] == "}"
        ):
            combined.append("${" + segment[index + 2] + "}")
            index += 4
            continue
        combined.append(segment[index])
        index += 1
    return combined


def embedded_variable_substitution(token, variables):
    def replace_braced(match):
        name = match.group(1)
        return variables.get(name, match.group(0))

    def replace_plain(match):
        name = match.group(1)
        return variables.get(name, match.group(0))

    token = re.sub(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}", replace_braced, token)
    token = re.sub(r"\$([A-Za-z_][A-Za-z0-9_]*)", replace_plain, token)
    return token


def resolve_variables(segment, variables, positionals=None, arrays=None):
    positionals = positionals or []
    arrays = arrays or {}
    resolved = []
    for token in combine_braced_expansion_tokens(segment):
        if token in {"$@", "${@}", "$*", "${*}"}:
            resolved.extend(positionals)
            continue
        array_match = ARRAY_EXPANSION_RE.match(token)
        if array_match and array_match.group(1) in arrays:
            resolved.extend(arrays[array_match.group(1)])
            continue
        name = variable_name(token)
        if name and name in variables:
            resolved.extend(split_expansion_words(variables[name]))
        elif (
            name
            and name in os.environ
            and inherited_env_value_needs_resolution(name, os.environ[name])
        ):
            resolved.extend(split_expansion_words(os.environ[name]))
        else:
            resolved.append(embedded_variable_substitution(token, variables))
    return resolved


def positional_assignment(segment):
    if not segment or segment[0] != "set":
        return None
    index = 1
    if index < len(segment) and segment[index] not in {"--"} and not segment[index].startswith("-"):
        return segment[index:]
    while index < len(segment):
        token = segment[index]
        if token == "--":
            return segment[index + 1:]
        if token.startswith("-"):
            index += 1
            continue
        return None
    return None


def array_assignment(segment):
    tokens = list(segment)
    if tokens and Path(tokens[0]).name in {"declare", "typeset"}:
        index = 1
        saw_array = False
        while index < len(tokens):
            token = tokens[index]
            if token == "--":
                index += 1
                break
            if token in {"-a", "-A"} or ("a" in token[1:] if token.startswith("-") and not token.startswith("--") else False):
                saw_array = True
                index += 1
                continue
            if token.startswith("-"):
                index += 1
                continue
            break
        if saw_array:
            tokens = tokens[index:]
    if len(tokens) < 4 or tokens[1] != "(":
        return None
    if tokens[-1] == ");":
        tokens[-1] = ")"
    if tokens[-1] != ")":
        return None
    if not tokens[0].endswith("="):
        return None
    name = tokens[0][:-1]
    if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", name):
        return None
    return name, tokens[2:-1]


def alias_assignments(segment):
    start = command_index_from(segment)
    if start >= len(segment) or Path(segment[start]).name != "alias":
        return {}
    aliases = {}
    for token in segment[start + 1:]:
        match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", token)
        if match and not re.search(r"[$`]", match.group(2)):
            aliases[match.group(1)] = match.group(2)
    return aliases


def command_scoped_assignments(segment, start):
    assignments = {}
    for token in segment[:start]:
        parsed = ASSIGNMENT_FULL_RE.match(token)
        if parsed:
            value = parsed.group(2)
            assignments[parsed.group(1)] = UNRESOLVABLE if re.search(r"[$`]", value) else value
    return assignments


def gh_alias_assignment(segment, gh_index):
    subcommand_index = gh_subcommand_index(segment, gh_index)
    if subcommand_index >= len(segment) or segment[subcommand_index] != "alias":
        return None
    action_index = skip_gh_globals(segment, subcommand_index + 1)
    if action_index >= len(segment) or segment[action_index] != "set":
        return None
    index = action_index + 1
    shell_alias = False
    while index < len(segment):
        token = segment[index]
        if token == "--":
            index += 1
            break
        if token in {"--shell", "-s"}:
            shell_alias = True
            index += 1
            continue
        if token.startswith("--shell="):
            shell_alias = token.split("=", 1)[1].lower() not in {"0", "false", "no"}
            index += 1
            continue
        if token == "--clobber" or token.startswith("--clobber="):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        break
    if index + 1 >= len(segment):
        return None
    name = segment[index]
    if not re.match(r"^[A-Za-z][A-Za-z0-9_-]*$", name):
        return None
    expansion_tokens = []
    index += 1
    while index < len(segment):
        token = segment[index]
        if token in {"--shell", "-s"}:
            shell_alias = True
            index += 1
            continue
        if token.startswith("--shell="):
            shell_alias = token.split("=", 1)[1].lower() not in {"0", "false", "no"}
            index += 1
            continue
        if token == "--clobber" or token.startswith("--clobber="):
            index += 1
            continue
        expansion_tokens.append(token)
        index += 1
    expansion = " ".join(expansion_tokens).strip()
    if shell_alias and expansion and not expansion.startswith("!"):
        expansion = "!" + expansion
    return name, expansion


def gh_alias_import_command(segment, gh_index):
    subcommand_index = gh_subcommand_index(segment, gh_index)
    if subcommand_index >= len(segment) or segment[subcommand_index] != "alias":
        return False
    action_index = skip_gh_globals(segment, subcommand_index + 1)
    return action_index < len(segment) and segment[action_index] == "import"


def gh_alias_payload(expansion, args=None):
    args = args or []
    expansion = expansion.strip()
    if expansion.startswith("!"):
        payload = expansion[1:].strip()
    elif expansion.startswith("gh "):
        payload = expansion
    else:
        payload = "gh " + expansion
    if args:
        payload = " ".join([payload] + [shlex.quote(arg) for arg in args])
    return payload


def unquote_gh_alias_expansion(expansion):
    expansion = expansion.strip()
    if len(expansion) < 2 or expansion[0] not in {"'", '"'} or expansion[-1] != expansion[0]:
        return expansion
    try:
        parts = shlex.split(expansion)
    except ValueError:
        return expansion
    return parts[0] if len(parts) == 1 else expansion


def parse_gh_alias_list(output):
    aliases = {}
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if "\t" in line:
            name, expansion = line.split("\t", 1)
        elif ":" in line:
            name, expansion = line.split(":", 1)
        else:
            parts = re.split(r"\s{2,}", line, maxsplit=1)
            if len(parts) == 1:
                parts = line.split(None, 1)
            if len(parts) != 2:
                continue
            name, expansion = parts
        name = name.strip()
        expansion = unquote_gh_alias_expansion(expansion)
        if re.match(r"^[A-Za-z][A-Za-z0-9_-]*$", name) and expansion:
            aliases[name] = expansion
    return aliases


def parse_gh_alias_config(output):
    aliases = parse_gh_alias_list(output)
    in_aliases_block = False
    for raw_line in output.splitlines():
        line = raw_line.rstrip()
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if re.match(r"^aliases\s*:\s*$", stripped):
            in_aliases_block = True
            continue
        if in_aliases_block and line == stripped and not stripped.startswith("-"):
            in_aliases_block = False
        if not in_aliases_block:
            continue
        match = re.match(r"^\s+([A-Za-z][A-Za-z0-9_-]*)\s*:\s*(.+?)\s*$", line)
        if not match:
            continue
        name = match.group(1).strip()
        expansion = unquote_gh_alias_expansion(match.group(2).strip())
        if expansion:
            aliases[name] = expansion
    return aliases


def gh_alias_config_paths(gh_config_dir=None):
    dirs = []
    if gh_config_dir:
        dirs.append(Path(gh_config_dir))
    else:
        env_config_dir = os.environ.get("GH_CONFIG_DIR")
        if env_config_dir:
            dirs.append(Path(env_config_dir))
        xdg_config_home = os.environ.get("XDG_CONFIG_HOME")
        if xdg_config_home:
            dirs.append(Path(xdg_config_home) / "gh")
        home = os.environ.get("HOME")
        if home:
            dirs.append(Path(home) / ".config" / "gh")

    seen = set()
    for directory in dirs:
        if not directory:
            continue
        for filename in ("aliases.yml", "aliases.yaml", "config.yml", "config.yaml"):
            path = directory / filename
            key = str(path)
            if key in seen:
                continue
            seen.add(key)
            yield path


def persistent_gh_aliases(gh_config_dir=None):
    cache_key = gh_config_dir or "__default__"
    if cache_key in PERSISTENT_GH_ALIASES:
        return PERSISTENT_GH_ALIASES[cache_key]
    alias_fixture = os.environ.get("SIDEKICK_GH_ALIAS_LIST")
    if alias_fixture is not None and gh_config_dir is None:
        PERSISTENT_GH_ALIASES[cache_key] = parse_gh_alias_list(alias_fixture)
        return PERSISTENT_GH_ALIASES[cache_key]

    aliases = {}
    for path in gh_alias_config_paths(gh_config_dir):
        try:
            if not path.is_file():
                continue
            aliases.update(parse_gh_alias_config(path.read_text(encoding="utf-8")))
        except OSError:
            continue
    PERSISTENT_GH_ALIASES[cache_key] = aliases
    return PERSISTENT_GH_ALIASES[cache_key]


def unquote_git_alias_expansion(expansion):
    expansion = expansion.strip()
    if len(expansion) < 2 or expansion[0] not in {"'", '"'} or expansion[-1] != expansion[0]:
        return expansion
    try:
        parts = shlex.split(expansion)
    except ValueError:
        return expansion
    return parts[0] if len(parts) == 1 else expansion


def parse_git_alias_config(output):
    aliases = {}
    in_alias_block = False
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            in_alias_block = line.lower() == "[alias]"
            continue
        if not in_alias_block:
            continue
        if "=" in line:
            name, expansion = line.split("=", 1)
        else:
            parts = line.split(None, 1)
            if len(parts) != 2:
                continue
            name, expansion = parts
        name = name.strip()
        expansion = unquote_git_alias_expansion(expansion)
        if re.match(r"^[A-Za-z0-9_.-]+$", name) and expansion:
            aliases[name] = expansion
    return aliases


def git_alias_config_paths():
    paths = []
    global_config = os.environ.get("GIT_CONFIG_GLOBAL")
    if global_config:
        paths.append(Path(global_config))
    home = os.environ.get("HOME")
    if home:
        paths.append(Path(home) / ".gitconfig")
    xdg_config_home = os.environ.get("XDG_CONFIG_HOME")
    if xdg_config_home:
        paths.append(Path(xdg_config_home) / "git" / "config")

    try:
        cwd = Path(os.environ.get("PWD") or os.getcwd()).resolve()
        for parent in (cwd, *cwd.parents):
            local_config = parent / ".git" / "config"
            if local_config.is_file():
                paths.append(local_config)
                break
    except OSError:
        pass

    seen = set()
    for path in paths:
        key = str(path)
        if key in seen:
            continue
        seen.add(key)
        yield path


def persistent_git_aliases():
    cache_key = "__default__"
    if cache_key in PERSISTENT_GIT_ALIASES:
        return PERSISTENT_GIT_ALIASES[cache_key]
    alias_fixture = os.environ.get("SIDEKICK_GIT_ALIAS_CONFIG")
    if alias_fixture is not None:
        PERSISTENT_GIT_ALIASES[cache_key] = parse_git_alias_config(alias_fixture)
        return PERSISTENT_GIT_ALIASES[cache_key]

    aliases = {}
    for path in git_alias_config_paths():
        try:
            if not path.is_file():
                continue
            aliases.update(parse_git_alias_config(path.read_text(encoding="utf-8")))
        except OSError:
            continue
    PERSISTENT_GIT_ALIASES[cache_key] = aliases
    return PERSISTENT_GIT_ALIASES[cache_key]


def git_alias_payload(expansion, args=None):
    args = args or []
    expansion = expansion.strip()
    if expansion.startswith("!"):
        payload = expansion[1:].strip()
    elif expansion.startswith("git "):
        payload = expansion
    else:
        payload = "git " + expansion
    if args:
        payload = " ".join([payload] + [shlex.quote(arg) for arg in args])
    return payload


def git_alias_payload_with_aliases(alias_name, args, aliases):
    seen = set()
    current_name = alias_name
    current_args = list(args or [])
    for _ in range(8):
        if current_name in seen or current_name not in aliases:
            break
        seen.add(current_name)
        expansion = aliases[current_name].strip()
        if expansion.startswith("!"):
            return git_alias_payload(expansion, current_args)
        try:
            tokens = shlex.split(expansion)
        except ValueError:
            return git_alias_payload(expansion, current_args)
        if tokens and tokens[0] in aliases:
            current_name = tokens[0]
            current_args = tokens[1:] + current_args
            continue
        return git_alias_payload(expansion, current_args)
    return git_alias_payload(aliases.get(alias_name, alias_name), current_args)


def enables_alias_expansion(segment):
    start = command_index_from(segment)
    if start >= len(segment) or Path(segment[start]).name != "shopt":
        return False
    return "-s" in segment[start + 1:] and "expand_aliases" in segment[start + 1:]


def interpreter_payloads(segment, start):
    return [payload for payload, _args in interpreter_payloads_with_args(segment, start)]


def interpreter_payloads_with_args(segment, start):
    if start >= len(segment):
        return []
    command_name = Path(segment[start]).name
    options = INTERPRETER_PAYLOAD_OPTIONS.get(command_name)
    if not options:
        return []
    payloads = []
    index = start + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            index += 1
            continue
        if token in options:
            if index + 1 < len(segment):
                payloads.append((segment[index + 1], segment[index + 2:]))
            index += 2
            continue
        matched_inline = False
        for option in options:
            if option.startswith("-") and token.startswith(option) and token != option:
                payloads.append((token[len(option):], segment[index + 1:]))
                matched_inline = True
                break
            if option.startswith("--") and token.startswith(option + "="):
                payloads.append((token.split("=", 1)[1], segment[index + 1:]))
                matched_inline = True
                break
        if matched_inline:
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        if command_name == "deno" and token == "eval" and index + 1 < len(segment):
            payloads.append((segment[index + 1], segment[index + 2:]))
        break
    return payloads


def interpreter_reads_stdin(segment, start):
    if start >= len(segment):
        return False
    command_name = Path(segment[start]).name
    options = INTERPRETER_PAYLOAD_OPTIONS.get(command_name)
    if not options:
        return False
    index = start + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            index += 1
            continue
        if token in options:
            return False
        for option in options:
            if option.startswith("-") and token.startswith(option) and token != option:
                return False
            if option.startswith("--") and token.startswith(option + "="):
                return False
        if command_name == "deno" and token == "eval":
            return False
        if token == "-":
            return True
        if token.startswith("-"):
            index += 1
            continue
        return False
    return True


def script_operand_has_release_hint(token):
    return bool(SCRIPT_PATH_HINT_RE.search(token or "") or DYNAMIC_RELEASE_TAG_HINT_RE.search(token or ""))


def script_operand_needs_gate(token, depth, generated_files=None):
    if not token or token == "-":
        return script_operand_has_release_hint(token)
    found, text = generated_file_lookup(generated_files, token)
    if found:
        if text is None:
            return True
        return language_payload_mentions_release_command(text) or contains_release_create(text, depth + 1)
    if release_source_is_uninspectable(token) or EXPANSION_RE.search(token):
        return script_operand_has_release_hint(token)
    text = read_bounded_script_text(token)
    if text is None:
        return script_operand_has_release_hint(token)
    return language_payload_mentions_release_command(text) or contains_release_create(text, depth + 1)


def shell_script_operand(segment, start):
    if start >= len(segment) or Path(segment[start]).name not in SHELLS:
        return None
    index = start + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            index += 1
            break
        if token == "-c" or token.startswith("-c"):
            return None
        if token.startswith("-") and not token.startswith("--") and "c" in token[1:]:
            return None
        if token in SHELL_VALUE_OPTIONS:
            index += 2
            continue
        if any(token.startswith(option + "=") for option in SHELL_VALUE_OPTIONS):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        break
    if index < len(segment):
        return segment[index]
    return None


def interpreter_script_operand(segment, start):
    if start >= len(segment):
        return None
    command_name = Path(segment[start]).name
    payload_options = INTERPRETER_PAYLOAD_OPTIONS.get(command_name)
    if not payload_options:
        return None
    value_options = {
        "python": {"-m", "-W", "-X"},
        "python3": {"-m", "-W", "-X"},
        "pypy": {"-m", "-W", "-X"},
        "pypy3": {"-m", "-W", "-X"},
        "node": {"-r", "--require", "--loader", "--import"},
        "bun": {"--preload"},
        "ruby": {"-I", "-r"},
        "perl": {"-I", "-M"},
    }.get(command_name, set())
    index = start + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            index += 1
            break
        if token in payload_options:
            return None
        for option in payload_options:
            if option.startswith("-") and token.startswith(option) and token != option:
                return None
            if option.startswith("--") and token.startswith(option + "="):
                return None
        if command_name == "deno" and token == "eval":
            return None
        if token in value_options:
            if command_name in {"python", "python3", "pypy", "pypy3"} and token == "-m":
                return None
            index += 2
            continue
        if any(token.startswith(option + "=") for option in value_options if option.startswith("--")):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        break
    if index < len(segment):
        return segment[index]
    return None


def source_script_operand(segment, start):
    if start >= len(segment) or Path(segment[start]).name not in SOURCE_LOADERS:
        return None
    if start + 1 < len(segment):
        return segment[start + 1]
    return None


def direct_script_operand(segment, start):
    if start >= len(segment):
        return None
    token = segment[start]
    if Path(token).name in KNOWN_EXECUTABLE_COMMANDS:
        return None
    if token in CONTROL or token in GROUP_PREFIXES:
        return None
    try:
        path = Path(token).expanduser()
    except Exception:
        return token if script_operand_has_release_hint(token) else None
    has_shebang = False
    if path.is_file():
        try:
            with path.open("rb") as handle:
                has_shebang = handle.read(2) == b"#!"
        except OSError:
            has_shebang = False
    if path.is_file() and (
        path.suffix in SCRIPT_EXTENSIONS
        or script_operand_has_release_hint(token)
        or os.access(path, os.X_OK)
        or has_shebang
    ):
        return token
    if "/" in token and script_operand_has_release_hint(token):
        return token
    return None


def local_script_operand_needs_gate(segment, start, depth, generated_files=None):
    operands = []
    for probe in (
        source_script_operand(segment, start),
        shell_script_operand(segment, start),
        interpreter_script_operand(segment, start),
        direct_script_operand(segment, start),
    ):
        if probe:
            operands.append(probe)
    found, _ = generated_file_lookup(generated_files, segment[start] if start < len(segment) else None)
    if found:
        operands.append(segment[start])
    return any(script_operand_needs_gate(operand, depth, generated_files) for operand in operands)


def static_interpreter_stdin_payload(previous_segment, incoming_control, interpreter_segment):
    start = command_index_from(interpreter_segment)
    if start >= len(interpreter_segment) or not interpreter_reads_stdin(interpreter_segment, start):
        return None
    if interpreter_payloads(interpreter_segment, start):
        return None
    if incoming_control != "|" or previous_segment is None:
        return None
    return static_producer_payload(previous_segment)


def heredoc_payloads(command):
    payloads = []
    lines = command.splitlines()
    index = 0
    while index < len(lines):
        line = lines[index]
        match = re.search(r"<<-?\s*(?:'([^']+)'|\"([^\"]+)\"|([A-Za-z_][A-Za-z0-9_]*))", line)
        if not match:
            index += 1
            continue
        delimiter = match.group(1) or match.group(2) or match.group(3)
        receiver = line[:match.start()].strip()
        body = []
        cursor = index + 1
        while cursor < len(lines):
            if lines[cursor].strip() == delimiter:
                break
            body.append(lines[cursor])
            cursor += 1
        if cursor < len(lines):
            payloads.append((receiver, "\n".join(body)))
            index = cursor + 1
            continue
        index += 1
    return payloads


def heredoc_receiver_runs_script(receiver):
    if not receiver:
        return False
    try:
        tokens = tokenize(receiver)
    except Exception:
        return False
    for segment in segments(tokens):
        start = command_index_from(segment)
        if start >= len(segment):
            continue
        command_name = Path(segment[start]).name
        if command_name in SHELLS:
            return shell_reads_stdin(segment, start)
        if interpreter_reads_stdin(segment, start):
            return True
    return False


def quoted_string_literals(value):
    literals = []
    for match in re.finditer(r"'((?:\\.|[^'\\])*)'|\"((?:\\.|[^\"\\])*)\"", value, re.DOTALL):
        content = match.group(1) if match.group(1) is not None else match.group(2)
        literals.append(decode_backslash_escapes(content))
    return literals


def literal_argv_mentions_release_command(payload):
    literals = [literal.strip() for literal in quoted_string_literals(payload) if literal.strip()]
    for index, literal in enumerate(literals):
        if GH_RELEASE_MUTATING_RE.search(literal):
            return True
        if GIT_PUSH_RELEASE_TEXT_RE.search(literal):
            return True
        if literal == "git":
            args = literals[index + 1:]
            if args and args[0] == "push" and git_push_release_tag_command(["git"] + args, 0):
                return True
        if literal != "gh":
            continue
        args = literals[index + 1:]
        if len(args) >= 2 and args[0] == "release" and args[1] not in {"view", "list", "download", "verify-asset"}:
            return True
        if args and args[0] == "api":
            command_text = " ".join(["gh"] + args)
            if direct_github_release_api_url(command_text):
                return True
            if graphql_release_mutation_text(command_text):
                return True
    return False


def language_payload_has_write_semantics(payload):
    return bool(
        re.search(r"\b(?:POST|PUT|PATCH|DELETE)\b", payload, re.I)
        or re.search(r"\b(?:requests|httpx)\.(?:post|put|patch|delete)\s*\(", payload, re.I)
        or re.search(r"\b(?:requests|httpx)\.request\s*\(", payload, re.I)
        or re.search(r"\burlopen\s*\(", payload, re.I)
        or re.search(r"\bRequest\s*\(", payload, re.I)
        or re.search(r"\burllib(?:\.request)?\.urlopen\s*\(", payload, re.I)
        or re.search(r"\burllib(?:\.request)?\.Request\s*\(", payload, re.I)
        or re.search(r"\bhttp\.client\.(?:HTTPConnection|HTTPSConnection)\s*\(", payload, re.I)
        or re.search(r"\b(?:aiohttp|urllib3)\b", payload, re.I)
        or re.search(r"\bfetch\s*\(", payload)
        or re.search(r"\b(?:curl|wget)\b", payload)
    )


def referenced_environment_names_in_payload(payload):
    names = set(referenced_env_names(payload))
    for pattern in (
        r"os\.environ\[\s*['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]\s*\]",
        r"os\.getenv\(\s*['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]",
        r"environ\.get\(\s*['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]",
        r"process\.env\.([A-Za-z_][A-Za-z0-9_]*)",
        r"process\.env\[\s*['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]\s*\]",
        r"ENV\[\s*['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]\s*\]",
    ):
        names.update(re.findall(pattern, payload))
    return names


def payload_env_endpoint_needs_gate(payload, command_has_write_semantics, env_map=None):
    if not command_has_write_semantics:
        return False
    env_map = env_map or {}
    for name in referenced_environment_names_in_payload(payload):
        value = env_map.get(name) or os.environ.get(name)
        if value:
            if direct_github_release_api_url(value):
                return True
            if is_graphql_endpoint(value) and graphql_release_mutation_text(payload):
                return True
            continue
        if DYNAMIC_RELEASE_ENDPOINT_HINT_RE.search(name):
            return True
    return False


def language_payload_mentions_release_command(payload, env_map=None):
    if decoded_payload_mentions_release_command(payload):
        return True
    if GH_RELEASE_MUTATING_RE.search(payload):
        return True
    if GIT_PUSH_RELEASE_TEXT_RE.search(payload):
        return True
    command_has_write_semantics = language_payload_has_write_semantics(payload)
    if payload_env_endpoint_needs_gate(payload, command_has_write_semantics, env_map):
        return True
    if direct_github_release_api_url(payload) and command_has_write_semantics:
        return True
    if GRAPHQL_RELEASE_ENDPOINT_RE.search(payload) and graphql_release_mutation_text(payload):
        return True
    if release_payload_matches_git_endpoint(payload) and (
        REQUESTS_SESSION_WRITE_RE.search(payload)
        or re.search(r"\burlopen\s*\(", payload, re.I)
        or re.search(r"\bRequest\s*\(", payload, re.I)
        or re.search(r"\b(?:requests|httpx)\.(?:post|put|patch|delete|request)\s*\(", payload, re.I)
        or any(
            re.search(rf"\b{re.escape(alias)}\s*\(", payload)
            for alias in release_payload_import_aliases(payload)
        )
    ):
        return True
    if re.search(r"\bgh\s+api\b", payload) and (
        direct_github_release_api_url(payload)
        or graphql_release_mutation_text(payload)
    ):
        return True
    if literal_argv_mentions_release_command(payload):
        return True
    compact = re.sub(r"[^A-Za-z0-9/_-]+", "", payload).lower()
    if "gh" in compact and "release" in compact and "create" in compact:
        return True
    if "ghapi" in compact and any(
        marker in compact
        for marker in {
            "releases",
            "createrelease",
            "updaterelease",
            "deleterelease",
        }
    ):
        return True
    if "ghapi" in compact and "refstags" in compact and any(
        marker in compact
        for marker in {
            "gitrefs",
            "createref",
            "updateref",
            "deleteref",
        }
    ):
        return True
    return False


def language_payload_with_args_mentions_release_command(payload, args, env_map=None):
    if language_payload_mentions_release_command(payload, env_map):
        return True
    if not args or not re.search(r"\b(?:argv|ARGV|process\.argv|sys\.argv)\b", payload):
        return False
    expanded = payload
    for index, arg in enumerate(args):
        literal = repr(arg)
        py_index = index + 1
        expanded = re.sub(rf"\bsys\.argv\[\s*{py_index}\s*\]", literal, expanded)
        expanded = re.sub(rf"\bargv\[\s*{py_index}\s*\]", literal, expanded)
        expanded = re.sub(rf"\bprocess\.argv\[\s*{py_index}\s*\]", literal, expanded)
        expanded = re.sub(rf"\bprocess\.argv\[\s*{py_index + 1}\s*\]", literal, expanded)
        expanded = re.sub(rf"\bARGV\[\s*{index}\s*\]", literal, expanded)
        expanded = re.sub(rf"\$ARGV\[\s*{index}\s*\]", literal, expanded)
    return language_payload_mentions_release_command(expanded, env_map)


def eval_payload(segment, start, variables=None):
    if start >= len(segment):
        return None
    command_name = Path(segment[start]).name
    payload_start = None
    if command_name == "eval":
        payload_start = start + 1
    elif command_name == "builtin" and start + 1 < len(segment) and segment[start + 1] == "eval":
        payload_start = start + 2
    if payload_start is None or payload_start >= len(segment):
        return None
    payload_tokens = segment[payload_start:]
    if variables:
        payload_tokens = resolve_variables(payload_tokens, variables)
    payload = " ".join(payload_tokens) or None
    if payload and re.search(r"[$`]", payload):
        return "gh release create"
    return payload


def raw_shell_segments(command):
    pieces = []
    current = []
    in_single = False
    in_double = False
    escaped = False
    paren_depth = 0
    index = 0
    while index < len(command):
        ch = command[index]
        if escaped:
            current.append(ch)
            escaped = False
            index += 1
            continue
        if ch == "\\" and not in_single:
            current.append(ch)
            escaped = True
            index += 1
            continue
        if ch == "'" and not in_double:
            in_single = not in_single
            current.append(ch)
            index += 1
            continue
        if ch == '"' and not in_single:
            in_double = not in_double
            current.append(ch)
            index += 1
            continue
        if not in_single and not in_double:
            if ch == "(":
                paren_depth += 1
            elif ch == ")" and paren_depth > 0:
                paren_depth -= 1
            if paren_depth == 0:
                if ch == ";":
                    text = "".join(current).strip()
                    if text:
                        pieces.append(text)
                    current = []
                    index += 1
                    continue
                if ch in {"&", "|"} and index + 1 < len(command) and command[index + 1] == ch:
                    text = "".join(current).strip()
                    if text:
                        pieces.append(text)
                    current = []
                    index += 2
                    continue
                if ch == "|":
                    text = "".join(current).strip()
                    if text:
                        pieces.append(text)
                    current = []
                    index += 1
                    continue
        current.append(ch)
        index += 1
    text = "".join(current).strip()
    if text:
        pieces.append(text)
    return pieces


def literal_state_assignment(text):
    try:
        tokens = tokenize(text)
    except Exception:
        return None
    assignments = standalone_literal_assignments(tokens)
    if assignments is not None:
        return ("vars", assignments)
    exported = exported_literal_assignments(tokens)
    if exported is not None:
        return ("vars", exported)
    indexed = indexed_array_assignment(tokens)
    if indexed is not None:
        return ("array-index", indexed)
    positionals = positional_assignment(tokens)
    if positionals is not None:
        return ("positionals", positionals)
    array = array_assignment(tokens)
    if array is not None:
        return ("array", array)
    return None


def expand_literal_shell_text(text, variables, arrays, positionals=None):
    positionals = positionals or []
    output = []
    changed = False
    index = 0
    in_single = False
    escaped = False
    while index < len(text):
        ch = text[index]
        if escaped:
            output.append(ch)
            escaped = False
            index += 1
            continue
        if ch == "\\" and not in_single:
            output.append(ch)
            escaped = True
            index += 1
            continue
        if ch == "'":
            in_single = not in_single
            output.append(ch)
            index += 1
            continue
        if in_single or ch != "$":
            output.append(ch)
            index += 1
            continue
        if text.startswith("$@", index) or text.startswith("$*", index):
            output.append(" ".join(positionals))
            changed = True
            index += 2
            continue
        if index + 1 < len(text) and text[index + 1] == "{":
            end = text.find("}", index + 2)
            if end != -1:
                expression = text[index + 2:end]
                if expression in {"@", "*"}:
                    output.append(" ".join(positionals))
                    changed = True
                    index = end + 1
                    continue
                indexed = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*)\[([0-9]+)\]", expression)
                array_all = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*)\[[*@]\]", expression)
                scalar = re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", expression)
                if indexed and indexed.group(1) in arrays:
                    values = arrays[indexed.group(1)]
                    position = int(indexed.group(2))
                    output.append(values[position] if position < len(values) else "")
                    changed = True
                    index = end + 1
                    continue
                if array_all and array_all.group(1) in arrays:
                    output.append(" ".join(arrays[array_all.group(1)]))
                    changed = True
                    index = end + 1
                    continue
                if scalar and expression in variables:
                    output.append(variables[expression])
                    changed = True
                    index = end + 1
                    continue
        plain = re.match(r"\$([A-Za-z_][A-Za-z0-9_]*)", text[index:])
        if plain and plain.group(1) in variables:
            output.append(variables[plain.group(1)])
            changed = True
            index += len(plain.group(0))
            continue
        output.append(ch)
        index += 1
    return "".join(output), changed


def literal_expanded_shell_payloads(command):
    variables = {}
    arrays = {}
    positionals = []
    payloads = []
    for text in raw_shell_segments(command):
        assignment = literal_state_assignment(text)
        if assignment:
            kind, value = assignment
            if kind == "vars":
                variables.update(value)
            elif kind == "array":
                arrays[value[0]] = value[1]
            elif kind == "array-index":
                name, position, item = value
                slots = arrays.setdefault(name, [])
                while len(slots) <= position:
                    slots.append("")
                slots[position] = item
            elif kind == "positionals":
                positionals = value
            continue
        expanded, changed = expand_literal_shell_text(text, variables, arrays, positionals)
        if changed and expanded.strip():
            payloads.append(expanded.strip())
    return payloads


def function_invocation_payloads(command):
    payloads = []
    pattern = re.compile(r"(?:^|[;&|]\s*)(?:function\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(\))?\s*\{")
    for match in pattern.finditer(command):
        name = match.group(1)
        body, end = read_balanced_payload(command, match.end(), "{", "}")
        if body is None:
            continue
        suffix = command[end + 1:]
        try:
            suffix_tokens = tokenize(suffix)
        except Exception:
            continue
        for segment in segments(suffix_tokens):
            start = command_index_from(segment)
            if start < len(segment) and Path(segment[start]).name == name:
                payloads.append((body, segment[start + 1:]))
    return payloads


def case_payloads(command):
    payloads = []
    for match in re.finditer(r"\bcase\b[\s\S]*?\bin\b([\s\S]*?)\besac\b", command):
        body = match.group(1)
        for branch in re.split(r";;&|;&|;;", body):
            if ")" not in branch:
                continue
            payload = branch.split(")", 1)[1].strip()
            if payload:
                payloads.append(payload)
    return payloads


def contains_release_create(command, depth=0):
    if depth > 12:
        return language_payload_mentions_release_command(command)
    if decoded_payload_mentions_release_command(command):
        return True
    normalized_command = normalize_command(command)
    if normalized_command != command:
        command = normalized_command
    if decoded_payload_mentions_release_command(command):
        return True
    for payload in literal_expanded_shell_payloads(command):
        if contains_release_create(payload, depth + 1):
            return True
    for receiver, payload in heredoc_payloads(command):
        if heredoc_receiver_runs_script(receiver):
            if language_payload_mentions_release_command(payload):
                return True
            if contains_release_create(payload, depth + 1):
                return True
    if heredoc_generated_file_used_for_release(command, depth):
        return True
    for payload, args in function_invocation_payloads(command):
        if payload_with_positionals_can_complete_release(payload, args, depth + 1):
            return True
    for payload in case_payloads(command):
        if contains_release_create(payload, depth + 1):
            return True
    for payload in newline_payloads(command):
        if contains_release_create(payload, depth + 1):
            return True
    for payload in backtick_payloads(command):
        if contains_release_create(payload, depth + 1):
            return True
    for payload in command_substitution_payloads(command):
        if contains_release_create(payload, depth + 1):
            return True
    for payload in brace_payloads(command):
        if contains_release_create(payload, depth + 1):
            return True
    for payload in process_substitution_payloads(command):
        if contains_release_create(payload, depth + 1):
            return True
    try:
        tokens = tokenize(command)
    except Exception as exc:
        print(f"validate-release-gate: failed to parse Bash command: {exc}", file=sys.stderr)
        raise SystemExit(2)

    previous_segment = None
    literal_vars = {}
    positionals = []
    arrays = {}
    aliases = {}
    gh_aliases = {}
    git_aliases = {}
    generated_files = {}
    expand_aliases = False
    cwd_changed = False
    for target, payload in heredoc_generated_file_writes(command):
        record_generated_file(generated_files, target, payload)
    for raw_segment, incoming_control in segments_with_controls(tokens):
        raw_segment = combine_braced_expansion_tokens(raw_segment)
        generated_segment = resolve_variables(raw_segment, literal_vars, positionals, arrays)
        generated = generated_file_write(generated_segment)
        if generated is not None:
            record_generated_file(generated_files, generated[0], generated[1])
        assignments = standalone_literal_assignments(raw_segment)
        if assignments is not None:
            literal_vars.update(assignments)
            previous_segment = raw_segment
            continue
        exported = exported_literal_assignments(raw_segment)
        if exported is not None:
            literal_vars.update(exported)
            previous_segment = raw_segment
            continue
        new_positionals = positional_assignment(raw_segment)
        if new_positionals is not None:
            positionals = new_positionals
            previous_segment = raw_segment
            continue
        indexed_array = indexed_array_assignment(raw_segment)
        if indexed_array is not None:
            name, position, item = indexed_array
            slots = arrays.setdefault(name, [])
            while len(slots) <= position:
                slots.append("")
            slots[position] = item
            previous_segment = raw_segment
            continue
        new_array = array_assignment(raw_segment)
        if new_array is not None:
            arrays[new_array[0]] = new_array[1]
            previous_segment = raw_segment
            continue
        if enables_alias_expansion(raw_segment):
            expand_aliases = True
            previous_segment = raw_segment
            continue
        new_aliases = alias_assignments(raw_segment)
        if new_aliases:
            aliases.update(new_aliases)
            previous_segment = raw_segment
            continue
        segment = resolve_variables(raw_segment, literal_vars, positionals, arrays)
        segment_start = command_index_from(raw_segment)
        command_env = command_scoped_assignments(raw_segment, segment_start)
        scoped_vars = dict(literal_vars)
        scoped_vars.update(command_env)
        raw_shell_parts = shell_payload_parts(raw_segment)
        if raw_shell_parts:
            raw_shell_text, raw_shell_args = raw_shell_parts
            resolved_shell_text = embedded_variable_substitution(raw_shell_text, scoped_vars)
            if resolved_shell_text != raw_shell_text and contains_release_create(resolved_shell_text, depth + 1):
                return True
            if resolved_shell_text != raw_shell_text and payload_with_positionals_can_complete_release(resolved_shell_text, raw_shell_args, depth + 1):
                return True
        for index, token in enumerate(segment):
            if Path(token).name == "env":
                for env_payload in env_split_payloads(segment, index):
                    if contains_release_create(env_payload, depth + 1):
                        return True
        for candidate in command_start_candidates(segment):
            start = command_index_from(segment, candidate)
            if start >= len(segment):
                continue
            command_name = Path(segment[start]).name
            command_env = command_scoped_assignments(segment, start)
            scoped_env = dict(literal_vars)
            scoped_env.update(command_env)
            segment_cwd_changed = segment_has_env_chdir(segment, start)
            if command_name in {"cd", "pushd", "popd"}:
                cwd_changed = True
                continue
            if (cwd_changed or segment_cwd_changed) and release_sensitive_relative_file_carrier(segment, start, generated_files):
                return True
            if local_script_operand_needs_gate(segment, start, depth, generated_files):
                return True
            if command_name == "gh":
                gh_config_dir = gh_config_dir_option(segment, start) or command_env.get("GH_CONFIG_DIR") or literal_vars.get("GH_CONFIG_DIR")
                effective_gh_aliases = dict(persistent_gh_aliases(gh_config_dir))
                effective_gh_aliases.update(gh_aliases)
                alias_assignment = gh_alias_assignment(segment, start)
                if alias_assignment is not None:
                    alias_name, alias_expansion = alias_assignment
                    alias_payload = gh_alias_payload(alias_expansion)
                    if contains_release_create(alias_payload, depth + 1):
                        return True
                    gh_aliases[alias_name] = alias_expansion
                    continue
                if gh_alias_import_command(segment, start):
                    return True
                if gh_release_mutating_command(segment, start) or gh_api_release_write_command(segment, start, generated_files):
                    return True
                alias_index = gh_subcommand_index(segment, start)
                if (
                    gh_context_switches_alias_source(segment, start, scoped_env)
                    and alias_index < len(segment)
                    and segment[alias_index] not in GH_KNOWN_SUBCOMMANDS
                    and segment[alias_index] not in effective_gh_aliases
                ):
                    return True
                if alias_index < len(segment) and segment[alias_index] in effective_gh_aliases:
                    alias_payload = gh_alias_payload(effective_gh_aliases[segment[alias_index]], segment[alias_index + 1:])
                    if contains_release_create(alias_payload, depth + 1):
                        return True
            if command_name == "git":
                effective_git_aliases = dict(persistent_git_aliases())
                effective_git_aliases.update(git_global_alias_assignments(segment, start))
                effective_git_aliases.update(git_aliases)
                git_config_alias = git_config_alias_assignment(segment, start)
                if git_config_alias is not None:
                    alias_name, alias_expansion = git_config_alias
                    alias_payload = git_alias_payload(alias_expansion)
                    if contains_release_create(alias_payload, depth + 1):
                        return True
                    git_aliases[alias_name] = alias_expansion
                    continue
                alias_index = git_subcommand_index(segment, start)
                if (
                    git_context_switches_alias_source(segment, start, scoped_env)
                    and alias_index < len(segment)
                    and segment[alias_index] not in GIT_KNOWN_SUBCOMMANDS
                    and segment[alias_index] not in effective_git_aliases
                ):
                    return True
                if alias_index < len(segment) and segment[alias_index] in effective_git_aliases:
                    alias_payload = git_alias_payload_with_aliases(
                        segment[alias_index],
                        segment[alias_index + 1:],
                        effective_git_aliases,
                    )
                    if contains_release_create(alias_payload, depth + 1):
                        return True
                if git_push_release_tag_command(segment, start):
                    return True
            if command_name == "curl" and curl_release_write_command(segment, start, generated_files):
                return True
            if command_name == "wget" and wget_release_write_command(segment, start, generated_files):
                return True
            if expand_aliases and segment[start] in aliases:
                alias_payload = " ".join(
                    [aliases[segment[start]]] + [shlex.quote(token) for token in segment[start + 1:]]
                )
                if contains_release_create(alias_payload, depth + 1):
                    return True
            for payload, interpreter_args in interpreter_payloads_with_args(segment, start):
                if language_payload_with_args_mentions_release_command(payload, interpreter_args, scoped_env):
                    return True
                if contains_release_create(payload, depth + 1):
                    return True
            if dynamic_expansion_can_complete_release(segment, start):
                return True
            payload = xargs_payload(segment, start)
            if payload and contains_release_create(payload, depth + 1):
                return True
            if xargs_stdin_can_complete_release(segment, start):
                return True
            if xargs_replacement_can_complete_release(segment, start):
                return True
            for stdin_candidate in stdin_payload(segment, start):
                if command_name in INTERPRETER_PAYLOAD_OPTIONS and language_payload_mentions_release_command(stdin_candidate, scoped_env):
                    return True
                if contains_release_create(stdin_candidate, depth + 1):
                    return True
                if command_name == "xargs":
                    xargs_tokens = xargs_static_tokens(segment, start)
                    if xargs_tokens:
                        xargs_probe = " ".join(shlex.quote(t) for t in xargs_tokens + [stdin_candidate])
                        if contains_release_create(xargs_probe, depth + 1):
                            return True
            for payload in find_exec_payloads(segment, start):
                if contains_release_create(payload, depth + 1):
                    return True
            payload = eval_payload(segment, start, literal_vars)
            if payload and contains_release_create(payload, depth + 1):
                return True
            for payload in process_substitution_script_payloads(segment, start):
                if command_name in INTERPRETER_PAYLOAD_OPTIONS and language_payload_mentions_release_command(payload, scoped_env):
                    return True
                if contains_release_create(payload, depth + 1):
                    return True
        payload = shell_payload(segment)
        if payload and contains_release_create(payload, depth + 1):
            return True
        shell_parts = shell_payload_parts(segment)
        if shell_parts:
            shell_text, shell_args = shell_parts
            argv0 = shell_args[0] if shell_args else None
            positionals = shell_args[1:] if len(shell_args) > 1 else []
            if payload_with_positionals_can_complete_release(shell_text, positionals, depth + 1, argv0):
                return True
        payload = static_shell_stdin_payload(previous_segment, incoming_control, segment)
        if payload and contains_release_create(payload, depth + 1):
            return True
        payload = static_interpreter_stdin_payload(previous_segment, incoming_control, segment)
        if payload and (
            language_payload_mentions_release_command(payload)
            or contains_release_create(payload, depth + 1)
        ):
            return True
        previous_segment = segment

    return False

raise SystemExit(0 if contains_release_create(sys.argv[1]) else 1)
PY
}

release_match=0
if is_gh_release_create "$COMMAND"; then
  release_match=1
else
  parser_rc=$?
  if [ "$parser_rc" -eq 1 ]; then
    exit 0
  fi
  exit "$parser_rc"
fi

[ "$release_match" -eq 1 ] || exit 0

release_command_has_same_command_file_write() {
  python3 - "$1" <<'PY'
from pathlib import Path
import re
import shlex
import sys

CONTROL = {";", "&&", "||", "|", "&"}
ASSIGNMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")

def tokenize(command):
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()<>{}")
    lexer.whitespace_split = True
    return list(lexer)

def segments(tokens):
    segment = []
    for token in tokens:
        if token in CONTROL:
            if segment:
                yield segment
                segment = []
            continue
        segment.append(token)
    if segment:
        yield segment

def command_index_from(segment):
    index = 0
    while index < len(segment) and ASSIGNMENT_RE.match(segment[index]):
        index += 1
    return index

def writes_file(segment):
    write_redirects = {">", ">>", ">|", "&>", "&>>", "<>", ">&"}
    fd_targets = {"/dev/null", "1", "2", "&1", "&2"}
    for index, token in enumerate(segment):
        if token in write_redirects:
            target = segment[index + 1] if index + 1 < len(segment) else ""
            return target not in fd_targets
    start = command_index_from(segment)
    if start < len(segment) and Path(segment[start]).name == "tee":
        index = start + 1
        while index < len(segment):
            token = segment[index]
            if token == "--":
                index += 1
                break
            if token in {"-a", "-i", "--append", "--ignore-interrupts"}:
                index += 1
                continue
            if token.startswith("-"):
                index += 1
                continue
            break
        return any(token != "/dev/null" for token in segment[index:])
    return False

try:
    tokens = tokenize(sys.argv[1].replace("\\\n", ""))
except Exception:
    print("1")
    raise SystemExit(0)

print("1" if any(writes_file(segment) for segment in segments(tokens)) else "0")
PY
}

if [ "$(release_command_has_same_command_file_write "$COMMAND" 2>/dev/null || printf 1)" = "1" ]; then
  reason="Pre-release quality gate cannot authorize release publication from a Bash command that also writes files. Run one explicit release publication command at a time from an already-prepared checkout."
  jq -cn --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
fi

release_command_segment_count() {
  local candidate count parser_rc
  count=0
  while IFS= read -r candidate; do
    [ -n "${candidate}" ] || continue
    if is_gh_release_create "${candidate}"; then
      count=$((count + 1))
    else
      parser_rc=$?
      if [ "${parser_rc}" -ne 1 ]; then
        return "${parser_rc}"
      fi
    fi
  done <<EOF
$(python3 - "$1" <<'PY'
from pathlib import Path
import re
import shlex
import sys

CONTROL = {";", "&&", "||", "|", "&"}
ASSIGNMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
ENV_VALUE_OPTIONS = {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"}
SHELLS = {"sh", "bash", "zsh"}

def tokenize(command):
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()<>{}")
    lexer.whitespace_split = True
    return list(lexer)

def segments(tokens):
    segment = []
    for token in tokens:
        if token in CONTROL:
            if segment:
                yield segment
                segment = []
            continue
        segment.append(token)
    if segment:
        yield segment

def skip_env(segment, index):
    index += 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            return index + 1
        if token in ENV_VALUE_OPTIONS:
            index += 2
            continue
        if any(token.startswith(option + "=") for option in ENV_VALUE_OPTIONS if option.startswith("--")):
            index += 1
            continue
        if token.startswith("-") or ASSIGNMENT_RE.match(token):
            index += 1
            continue
        break
    return index

def command_index_from(segment, index=0):
    while index < len(segment) and ASSIGNMENT_RE.match(segment[index]):
        index += 1
    while index < len(segment):
        wrapper = Path(segment[index]).name
        if wrapper == "env":
            index = skip_env(segment, index)
            continue
        if wrapper in {"command", "builtin", "noglob", "time", "gtime", "nice", "nohup", "setsid"}:
            index += 1
            continue
        if wrapper in {"sudo", "doas"}:
            index += 1
            while index < len(segment) and segment[index].startswith("-"):
                index += 2 if segment[index] in {"-u", "--user", "-g", "--group", "-h", "--host"} else 1
            while index < len(segment) and ASSIGNMENT_RE.match(segment[index]):
                index += 1
            continue
        if wrapper == "exec":
            index += 1
            while index < len(segment):
                if segment[index] == "-a":
                    index += 2
                    continue
                if segment[index] in {"-c", "-l"}:
                    index += 1
                    continue
                break
            continue
        break
    return index

def shell_payload_parts(segment, start):
    index = start + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            return None
        if token == "-c" or (token.startswith("-") and not token.startswith("--") and "c" in token[1:]):
            if index + 1 < len(segment):
                return segment[index + 1]
            return None
        if token.startswith("-"):
            index += 1
            continue
        break
    return None

def read_balanced_payload(command, start, opener, closer):
    depth = 1
    in_single = False
    in_double = False
    escaped = False
    payload = []
    index = start
    while index < len(command):
        char = command[index]
        if escaped:
            payload.append(char)
            escaped = False
            index += 1
            continue
        if char == "\\" and not in_single:
            payload.append(char)
            escaped = True
            index += 1
            continue
        if char == "'" and not in_double:
            in_single = not in_single
            payload.append(char)
            index += 1
            continue
        if char == '"' and not in_single:
            in_double = not in_double
            payload.append(char)
            index += 1
            continue
        if not in_single and not in_double:
            if char == opener:
                depth += 1
            elif char == closer:
                depth -= 1
                if depth == 0:
                    return "".join(payload), index
        payload.append(char)
        index += 1
    return None, len(command)

def backtick_payloads(command):
    payloads = []
    in_single = False
    in_double = False
    in_backtick = False
    escaped = False
    payload = []
    for char in command:
        if escaped:
            if in_backtick:
                payload.append(char)
            escaped = False
            continue
        if char == "\\" and not in_single:
            escaped = True
            if in_backtick:
                payload.append(char)
            continue
        if in_backtick:
            if char == "`":
                payloads.append("".join(payload))
                payload = []
                in_backtick = False
                continue
            payload.append(char)
            continue
        if char == "'" and not in_double:
            in_single = not in_single
            continue
        if char == '"' and not in_single:
            in_double = not in_double
            continue
        if char == "`" and not in_single:
            in_backtick = True
            payload = []
    return payloads

def command_substitution_payloads(command):
    payloads = []
    in_single = False
    in_double = False
    escaped = False
    index = 0
    while index < len(command):
        char = command[index]
        if escaped:
            escaped = False
            index += 1
            continue
        if char == "\\" and not in_single:
            escaped = True
            index += 1
            continue
        if char == "'" and not in_double:
            in_single = not in_single
            index += 1
            continue
        if char == '"' and not in_single:
            in_double = not in_double
            index += 1
            continue
        if not in_single and char == "$" and index + 1 < len(command) and command[index + 1] == "(":
            payload, end = read_balanced_payload(command, index + 2, "(", ")")
            if payload is not None:
                payloads.append(payload)
                index = end + 1
                continue
        index += 1
    return payloads

def process_substitution_payloads(command):
    payloads = []
    in_single = False
    in_double = False
    escaped = False
    index = 0
    while index < len(command):
        char = command[index]
        if escaped:
            escaped = False
            index += 1
            continue
        if char == "\\" and not in_single:
            escaped = True
            index += 1
            continue
        if char == "'" and not in_double:
            in_single = not in_single
            index += 1
            continue
        if char == '"' and not in_single:
            in_double = not in_double
            index += 1
            continue
        if not in_single and not in_double and char in "<>" and index + 1 < len(command) and command[index + 1] == "(":
            payload, end = read_balanced_payload(command, index + 2, "(", ")")
            if payload is not None:
                payloads.append(payload)
                index = end + 1
                continue
        index += 1
    return payloads

def emit_units(command, depth=0):
    if depth > 8:
        print(command)
        return
    for payload in backtick_payloads(command):
        emit_units(payload, depth + 1)
    for payload in command_substitution_payloads(command):
        emit_units(payload, depth + 1)
    for payload in process_substitution_payloads(command):
        emit_units(payload, depth + 1)
    try:
        tokens = tokenize(command.replace("\\\n", ""))
    except Exception:
        print(command)
        return
    for segment in segments(tokens):
        start = command_index_from(segment)
        if start >= len(segment):
            continue
        command_name = Path(segment[start]).name
        if command_name in SHELLS:
            payload = shell_payload_parts(segment, start)
            if payload:
                emit_units(payload, depth + 1)
                continue
        if command_name == "eval":
            emit_units(" ".join(segment[start + 1:]), depth + 1)
            continue
        print(" ".join(shlex.quote(token) for token in segment))

emit_units(sys.argv[1])
PY
)
EOF
  printf '%s\n' "${count}"
}

release_command_count="$(release_command_segment_count "$COMMAND" 2>/dev/null || true)"
case "${release_command_count}" in
  ''|*[!0-9]*)
    reason="Pre-release quality gate cannot validate this release command because release command segmentation failed. Run one explicit release publication command at a time."
    jq -cn --arg reason "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
    exit 0
    ;;
  *)
    if [ "${release_command_count}" -gt 1 ]; then
      reason="Pre-release quality gate cannot authorize multiple release publication operations in one Bash command. Run one explicit release publication command at a time so the gate can validate the exact target SHA."
      jq -cn --arg reason "$reason" '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: $reason
        }
      }'
      exit 0
    fi
    ;;
esac

release_target_metadata() {
  python3 - "$1" <<'PY'
from pathlib import Path
import codecs
import os
import re
import shlex
import subprocess
import sys
import urllib.parse

CONTROL = {";", "&&", "||", "|", "&"}
ASSIGNMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
ASSIGNMENT_FULL_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$")
ENV_VALUE_OPTIONS = {"-u", "--unset", "-C", "--chdir", "-S", "--split-string"}
SHELLS = {"sh", "bash", "zsh"}
GIT_VALUE_GLOBALS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--super-prefix"}
GIT_FLAG_GLOBALS = {"--bare", "--no-pager", "--paginate", "--literal-pathspecs", "--glob-pathspecs", "--noglob-pathspecs", "--icase-pathspecs"}
GIT_PUSH_VALUE_OPTIONS = {"-o", "--push-option", "--receive-pack", "--exec", "--recurse-submodules"}
GIT_PUSH_RELEASE_TAG_OPTIONS = {"--tags", "--follow-tags", "--mirror"}
GIT_PUSH_DESTRUCTIVE_TAG_OPTIONS = {"-d", "-f", "--delete", "--force"}
GH_RELEASE_CREATE_VALUE_OPTIONS = {"--target", "--title", "--notes", "--notes-file", "--discussion-category"}
GH_RELEASE_CREATE_FLAG_OPTIONS = {"--draft", "--generate-notes", "--latest", "--prerelease", "--verify-tag"}
GH_VALUE_GLOBALS = {"-R", "--repo", "--hostname", "--config-dir"}
GH_FLAG_GLOBALS = {"--paginate", "--no-pager"}
GH_API_WRITE_METHODS = {"POST", "PUT", "PATCH", "DELETE"}
GIT_PROVENANCE_ENV_NAMES = {
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_NAMESPACE",
    "GIT_CONFIG_COUNT",
    "GIT_CONFIG_PARAMETERS",
    "GIT_CONFIG_GLOBAL",
    "GIT_CONFIG_SYSTEM",
    "GIT_CONFIG_NOSYSTEM",
}
RELEASE_TAG_RE = re.compile(r"^v?[0-9]+[.][0-9]+[.][0-9]+(?:[-+][A-Za-z0-9._-]+)?$")
TAG_REF_TEXT_RE = re.compile(r"refs/tags/", re.IGNORECASE)
EXPANSION_RE = re.compile(r"(?:\$[A-Za-z_][A-Za-z0-9_]*|\$\{|\$\(|`)")
STATIC_STRING_CONCAT_RE = re.compile(
    r"('(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\")\s*\+\s*"
    r"('(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\")",
    re.DOTALL,
)
UNRESOLVABLE = "__UNRESOLVABLE__"
SIDEKICK_RELEASE_REPO = "alo-exp/sidekick"
SIDEKICK_RELEASE_HOSTS = {"github.com", "api.github.com"}
PERSISTENT_GH_ALIASES = {}

def decode_backslash_escapes(value):
    try:
        return codecs.decode(value, "unicode_escape")
    except Exception:
        return value

def decode_quoted_literal(value):
    if len(value) < 2 or value[0] not in {"'", '"'} or value[-1] != value[0]:
        return None
    return decode_backslash_escapes(value[1:-1])

def collapse_static_string_concats(value):
    text = str(value)
    for _ in range(16):
        def replace(match):
            left = decode_quoted_literal(match.group(1))
            right = decode_quoted_literal(match.group(2))
            if left is None or right is None:
                return match.group(0)
            return repr(left + right)

        updated = STATIC_STRING_CONCAT_RE.sub(replace, text)
        if updated == text:
            return text
        text = updated
    return text

def tokenize(command):
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()<>{}")
    lexer.whitespace_split = True
    return list(lexer)

def segments(tokens):
    segment = []
    for token in tokens:
        if token in CONTROL:
            if segment:
                yield segment
                segment = []
            continue
        segment.append(token)
    if segment:
        yield segment

def unsafe_ref(value):
    return not value or bool(EXPANSION_RE.search(value)) or value.startswith("<(") or value in {"-", "@-"}

def explicit_sha(value):
    return bool(value and re.fullmatch(r"[0-9a-fA-F]{7,40}", value))

def token_is_release_tag_ref(token):
    token = token.lstrip("+")
    return token.startswith("refs/tags/") or bool(RELEASE_TAG_RE.match(token))

def refspec_targets_release_tag(refspec):
    parts = [part for part in refspec.split(":") if part]
    if any(token_is_release_tag_ref(part) for part in parts):
        return True
    return bool(EXPANSION_RE.search(refspec))

def release_ref_from_refspec(refspec):
    if not refspec:
        return UNRESOLVABLE
    if refspec.startswith("+"):
        return UNRESOLVABLE
    source = refspec.split(":", 1)[0].lstrip("+")
    if not source:
        return UNRESOLVABLE
    return UNRESOLVABLE if unsafe_ref(source) else source

def skip_env(segment, index):
    index += 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            return index + 1
        if token in ENV_VALUE_OPTIONS:
            index += 2
            continue
        if any(token.startswith(option + "=") for option in ENV_VALUE_OPTIONS if option.startswith("--")):
            index += 1
            continue
        if token.startswith("-") or ASSIGNMENT_RE.match(token):
            index += 1
            continue
        break
    return index

def command_index_from(segment, index=0):
    while index < len(segment) and ASSIGNMENT_RE.match(segment[index]):
        index += 1
    while index < len(segment):
        wrapper = Path(segment[index]).name
        if wrapper == "env":
            index = skip_env(segment, index)
            continue
        if wrapper in {"command", "builtin", "noglob", "time", "gtime", "nice", "nohup", "setsid"}:
            index += 1
            continue
        if wrapper in {"sudo", "doas"}:
            index += 1
            while index < len(segment) and segment[index].startswith("-"):
                index += 2 if segment[index] in {"-u", "--user", "-g", "--group", "-h", "--host"} else 1
            while index < len(segment) and ASSIGNMENT_RE.match(segment[index]):
                index += 1
            continue
        if wrapper == "exec":
            index += 1
            while index < len(segment):
                if segment[index] == "-a":
                    index += 2
                    continue
                if segment[index] in {"-c", "-l"}:
                    index += 1
                    continue
                break
            continue
        break
    return index

def segment_has_env_chdir(segment, start):
    for token in segment[:start]:
        if token in {"-C", "--chdir"} or token.startswith("--chdir="):
            return True
    return False

def normalize_host(value):
    if not value or unsafe_ref(value):
        return None
    host = str(value).strip().strip("'\"").lower()
    if "://" in host:
        host = urllib.parse.urlparse(host).netloc.lower()
    if "@" in host and ":" in host:
        host = host.split("@", 1)[1].split(":", 1)[0]
    return host.strip("/") or None

def split_repo_identity(value):
    if not value or unsafe_ref(value):
        return None, None
    repo = str(value).strip().strip("'\"")
    host = None
    if repo.startswith("git@") and ":" in repo:
        user_host, repo_path = repo.split(":", 1)
        host = user_host.split("@", 1)[1].lower()
        repo = repo_path
    elif repo.startswith("git@github.com:"):
        repo = repo.split(":", 1)[1]
    elif "://" in repo:
        parsed = urllib.parse.urlparse(repo)
        host = parsed.netloc.lower()
        path = parsed.path.strip("/")
        if parsed.netloc.lower() == "api.github.com" and path.startswith("repos/"):
            path = path[len("repos/"):]
        repo = path
    elif repo.startswith("repos/"):
        repo = repo[len("repos/"):]
    repo = repo.removesuffix(".git").strip("/")
    parts = [part for part in repo.split("/") if part]
    if len(parts) >= 3 and ("." in parts[0] or ":" in parts[0]):
        host = parts[0].lower()
        parts = parts[1:]
    if len(parts) < 2:
        return None, host
    return "/".join(parts[:2]).lower(), host

def normalize_repo(value):
    repo, _ = split_repo_identity(value)
    return repo

def host_allowed(host):
    if host is None or host == "":
        return True
    normalized = normalize_host(host)
    return normalized in SIDEKICK_RELEASE_HOSTS

def repo_allowed(repo, host=None):
    if not host_allowed(host):
        return False
    if repo is None:
        return True
    normalized, repo_host = split_repo_identity(repo)
    effective_host = normalize_host(host) or repo_host
    return host_allowed(effective_host) and normalized == SIDEKICK_RELEASE_REPO

def git_provenance_env_untrusted(scoped_vars):
    keys = set(scoped_vars) | set(os.environ)
    for key in keys:
        if (
            key in GIT_PROVENANCE_ENV_NAMES
            or key.startswith("GIT_CONFIG_KEY_")
            or key.startswith("GIT_CONFIG_VALUE_")
        ):
            value = scoped_vars.get(key, os.environ.get(key, ""))
            if value != "":
                return True
    return False

def gh_repo_option(segment, gh_index):
    index = gh_index + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            index += 1
            continue
        if token in {"-R", "--repo"}:
            return segment[index + 1] if index + 1 < len(segment) else UNRESOLVABLE
        if token.startswith("-R") and token != "-R":
            return token[2:]
        if token.startswith("--repo="):
            return token.split("=", 1)[1]
        index += 1
    return None

def gh_release_create_explicit_repo(segment, gh_index):
    repo = None
    index = gh_index + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            index += 1
            continue
        if token == "--repo":
            value = segment[index + 1] if index + 1 < len(segment) else UNRESOLVABLE
            if repo is not None:
                return UNRESOLVABLE
            repo = value
            index += 2
            continue
        if token.startswith("--repo="):
            if repo is not None:
                return UNRESOLVABLE
            repo = token.split("=", 1)[1]
            index += 1
            continue
        if token == "-R" or (token.startswith("-R") and token != "-R"):
            return UNRESOLVABLE
        if token in {"--hostname", "--config-dir"}:
            index += 2
            continue
        if token.startswith("--hostname=") or token.startswith("--config-dir="):
            index += 1
            continue
        if token in GH_RELEASE_CREATE_VALUE_OPTIONS:
            index += 2
            continue
        if any(token.startswith(option + "=") for option in GH_RELEASE_CREATE_VALUE_OPTIONS):
            index += 1
            continue
        index += 1
    return repo if repo == SIDEKICK_RELEASE_REPO else UNRESOLVABLE

def gh_hostname_option(segment, gh_index):
    index = gh_index + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            index += 1
            continue
        if token == "--hostname":
            return segment[index + 1] if index + 1 < len(segment) else UNRESOLVABLE
        if token.startswith("--hostname="):
            return token.split("=", 1)[1]
        index += 1
    return None

def git_config_get(key, target_dir=None):
    try:
        cwd = target_dir or os.environ.get("PWD") or os.getcwd()
        result = subprocess.run(
            ["git", "-C", cwd, "config", "--get", key],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except (OSError, ValueError):
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None

def git_config_get_all(key, target_dir=None):
    try:
        cwd = target_dir or os.environ.get("PWD") or os.getcwd()
        result = subprocess.run(
            ["git", "-C", cwd, "config", "--get-all", key],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except (OSError, ValueError):
        return []
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]

def git_config_get_regexp(pattern, target_dir=None):
    try:
        cwd = target_dir or os.environ.get("PWD") or os.getcwd()
        result = subprocess.run(
            ["git", "-C", cwd, "config", "--get-regexp", pattern],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except (OSError, ValueError):
        return []
    if result.returncode != 0:
        return []
    pairs = []
    for line in result.stdout.splitlines():
        key, _, value = line.partition(" ")
        key = key.strip()
        value = value.strip()
        if key and value:
            pairs.append((key, value))
    return pairs

def implicit_cwd_repo():
    repo = git_config_get("remote.origin.url")
    if repo is None or not repo_allowed(repo):
        return UNRESOLVABLE
    fetch_urls = git_remote_fetch_urls("origin")
    push_urls = git_remote_push_urls("origin")
    if not fetch_urls or not push_urls:
        return UNRESOLVABLE
    if not all(repo_allowed(url) for url in fetch_urls + push_urls):
        return UNRESOLVABLE
    return repo

def gh_effective_repo(segment, gh_index, scoped_vars, require_implicit=False):
    host = (
        gh_hostname_option(segment, gh_index)
        or scoped_vars.get("GH_HOST")
        or os.environ.get("GH_HOST")
    )
    repo = (
        gh_repo_option(segment, gh_index)
        or scoped_vars.get("GH_REPO")
        or os.environ.get("GH_REPO")
    )
    if not host_allowed(host):
        return UNRESOLVABLE
    if repo:
        return repo if repo_allowed(repo, host) else UNRESOLVABLE
    if not require_implicit:
        return None
    if git_provenance_env_untrusted(scoped_vars):
        return UNRESOLVABLE
    repo = implicit_cwd_repo()
    if repo is None:
        return UNRESOLVABLE
    return repo if repo_allowed(repo, host) else UNRESOLVABLE

def endpoint_repo(endpoint):
    parts = github_api_path_parts(endpoint)
    if len(parts) >= 3 and parts[0] == "repos":
        return f"{parts[1]}/{parts[2]}"
    return None

def endpoint_host(endpoint):
    value = urllib.parse.unquote(str(endpoint)).strip().strip("'\"")
    if "://" not in value:
        return None
    return urllib.parse.urlparse(value).netloc.lower() or None

def skip_gh_globals(segment, index):
    while index < len(segment):
        token = segment[index]
        if token == "--":
            return index + 1
        if token in GH_VALUE_GLOBALS:
            index += 2
            continue
        if token.startswith("-R") and token != "-R":
            index += 1
            continue
        if token.startswith("--") and any(token.startswith(option + "=") for option in GH_VALUE_GLOBALS if option.startswith("--")):
            index += 1
            continue
        if token in GH_FLAG_GLOBALS:
            index += 1
            continue
        break
    return index

def gh_subcommand_index(segment, gh_index):
    return skip_gh_globals(segment, gh_index + 1)

def gh_config_dir_option(segment, gh_index):
    index = gh_index + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            break
        if token == "--config-dir":
            return segment[index + 1] if index + 1 < len(segment) else None
        if token.startswith("--config-dir="):
            return token.split("=", 1)[1]
        if token in GH_VALUE_GLOBALS:
            index += 2
            continue
        if token.startswith("-R") and token != "-R":
            index += 1
            continue
        if token.startswith("--") and any(token.startswith(option + "=") for option in GH_VALUE_GLOBALS if option.startswith("--")):
            index += 1
            continue
        if token in GH_FLAG_GLOBALS:
            index += 1
            continue
        break
    return None

def gh_alias_config_dir(segment, gh_index, command_env, variables):
    config_dir = gh_config_dir_option(segment, gh_index)
    if config_dir is not None:
        return config_dir, True
    if "GH_CONFIG_DIR" in command_env:
        return command_env.get("GH_CONFIG_DIR"), True
    if "GH_CONFIG_DIR" in variables:
        return variables.get("GH_CONFIG_DIR"), True
    return None, False

def gh_alias_payload(expansion, args=None):
    args = args or []
    expansion = expansion.strip()
    if expansion.startswith("!"):
        payload = expansion[1:].strip()
    elif expansion.startswith("gh "):
        payload = expansion
    else:
        payload = "gh " + expansion
    if args:
        payload = " ".join([payload] + [shlex.quote(arg) for arg in args])
    return payload

def unquote_gh_alias_expansion(expansion):
    expansion = expansion.strip()
    if len(expansion) < 2 or expansion[0] not in {"'", '"'} or expansion[-1] != expansion[0]:
        return expansion
    try:
        parts = shlex.split(expansion)
    except ValueError:
        return expansion
    return parts[0] if len(parts) == 1 else expansion

def parse_gh_alias_list(output):
    aliases = {}
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if "\t" in line:
            name, expansion = line.split("\t", 1)
        elif ":" in line:
            name, expansion = line.split(":", 1)
        else:
            parts = re.split(r"\s{2,}", line, maxsplit=1)
            if len(parts) == 1:
                parts = line.split(None, 1)
            if len(parts) != 2:
                continue
            name, expansion = parts
        name = name.strip()
        expansion = unquote_gh_alias_expansion(expansion)
        if re.match(r"^[A-Za-z][A-Za-z0-9_-]*$", name) and expansion:
            aliases[name] = expansion
    return aliases

def parse_gh_alias_config(output):
    aliases = parse_gh_alias_list(output)
    in_aliases_block = False
    for raw_line in output.splitlines():
        line = raw_line.rstrip()
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if re.match(r"^aliases\s*:\s*$", stripped):
            in_aliases_block = True
            continue
        if in_aliases_block and line == stripped and not stripped.startswith("-"):
            in_aliases_block = False
        if not in_aliases_block:
            continue
        match = re.match(r"^\s+([A-Za-z][A-Za-z0-9_-]*)\s*:\s*(.+?)\s*$", line)
        if not match:
            continue
        name = match.group(1).strip()
        expansion = unquote_gh_alias_expansion(match.group(2).strip())
        if expansion:
            aliases[name] = expansion
    return aliases

def gh_alias_config_paths(gh_config_dir=None):
    dirs = []
    if gh_config_dir:
        dirs.append(Path(gh_config_dir))
    else:
        env_config_dir = os.environ.get("GH_CONFIG_DIR")
        if env_config_dir:
            dirs.append(Path(env_config_dir))
        xdg_config_home = os.environ.get("XDG_CONFIG_HOME")
        if xdg_config_home:
            dirs.append(Path(xdg_config_home) / "gh")
        home = os.environ.get("HOME")
        if home:
            dirs.append(Path(home) / ".config" / "gh")
    seen = set()
    for directory in dirs:
        if not directory:
            continue
        for filename in ("aliases.yml", "aliases.yaml", "config.yml", "config.yaml"):
            path = directory / filename
            key = str(path)
            if key in seen:
                continue
            seen.add(key)
            yield path

def persistent_gh_aliases(gh_config_dir=None):
    cache_key = gh_config_dir or "__default__"
    if cache_key in PERSISTENT_GH_ALIASES:
        return PERSISTENT_GH_ALIASES[cache_key]
    alias_fixture = os.environ.get("SIDEKICK_GH_ALIAS_LIST")
    if alias_fixture is not None and gh_config_dir is None:
        PERSISTENT_GH_ALIASES[cache_key] = parse_gh_alias_list(alias_fixture)
        return PERSISTENT_GH_ALIASES[cache_key]
    aliases = {}
    for path in gh_alias_config_paths(gh_config_dir):
        try:
            if path.is_file():
                aliases.update(parse_gh_alias_config(path.read_text(encoding="utf-8")))
        except OSError:
            continue
    PERSISTENT_GH_ALIASES[cache_key] = aliases
    return aliases

def gh_alias_assignment(segment, gh_index):
    subcommand_index = gh_subcommand_index(segment, gh_index)
    if subcommand_index >= len(segment) or segment[subcommand_index] != "alias":
        return None
    action_index = skip_gh_globals(segment, subcommand_index + 1)
    if action_index >= len(segment) or segment[action_index] != "set":
        return None
    index = action_index + 1
    shell_alias = False
    while index < len(segment):
        token = segment[index]
        if token == "--":
            index += 1
            break
        if token in {"--shell", "-s"}:
            shell_alias = True
            index += 1
            continue
        if token.startswith("--shell="):
            shell_alias = token.split("=", 1)[1].lower() not in {"0", "false", "no"}
            index += 1
            continue
        if token == "--clobber" or token.startswith("--clobber="):
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        break
    if index + 1 >= len(segment):
        return None
    name = segment[index]
    if not re.match(r"^[A-Za-z][A-Za-z0-9_-]*$", name):
        return None
    expansion_tokens = []
    index += 1
    while index < len(segment):
        token = segment[index]
        if token in {"--shell", "-s"}:
            shell_alias = True
            index += 1
            continue
        if token.startswith("--shell="):
            shell_alias = token.split("=", 1)[1].lower() not in {"0", "false", "no"}
            index += 1
            continue
        if token == "--clobber" or token.startswith("--clobber="):
            index += 1
            continue
        expansion_tokens.append(token)
        index += 1
    expansion = " ".join(expansion_tokens).strip()
    if shell_alias and expansion and not expansion.startswith("!"):
        expansion = "!" + expansion
    return name, expansion

def git_subcommand_index(segment, git_index):
    index = git_index + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            return index + 1
        if token in GIT_VALUE_GLOBALS:
            index += 2
            continue
        if token.startswith("-c") and token != "-c":
            index += 1
            continue
        if token.startswith("--") and any(token.startswith(option + "=") for option in GIT_VALUE_GLOBALS if option.startswith("--")):
            index += 1
            continue
        if token in GIT_FLAG_GLOBALS:
            index += 1
            continue
        break
    return index

def git_global_alias_assignments(segment, git_index):
    aliases = {}
    index = git_index + 1
    while index < len(segment):
        token = segment[index]
        config_value = None
        if token == "--":
            break
        if token == "-c" and index + 1 < len(segment):
            config_value = segment[index + 1]
            index += 2
        elif token.startswith("-c") and token != "-c":
            config_value = token[2:]
            index += 1
        elif token in GIT_VALUE_GLOBALS:
            index += 2
            continue
        elif token.startswith("--") and any(token.startswith(option + "=") for option in GIT_VALUE_GLOBALS if option.startswith("--")):
            index += 1
            continue
        elif token in GIT_FLAG_GLOBALS:
            index += 1
            continue
        else:
            break
        if config_value:
            match = re.match(r"^alias\.([A-Za-z0-9_.-]+)=(.*)$", config_value)
            if match and match.group(2).strip():
                aliases[match.group(1)] = match.group(2).strip()
    return aliases

def git_alias_payload(alias_name, args, aliases):
    seen = set()
    current = alias_name
    current_args = list(args or [])
    for _ in range(8):
        if current in seen or current not in aliases:
            break
        seen.add(current)
        expansion = aliases[current].strip()
        if expansion.startswith("!"):
            return " ".join([expansion[1:]] + [shlex.quote(arg) for arg in current_args])
        try:
            tokens = shlex.split(expansion)
        except ValueError:
            return " ".join(["git", expansion] + [shlex.quote(arg) for arg in current_args])
        if tokens and tokens[0] in aliases:
            current = tokens[0]
            current_args = tokens[1:] + current_args
            continue
        return " ".join(["git"] + [shlex.quote(token) for token in tokens + current_args])
    return None

def git_payload_with_outer_c(payload, target_dir):
    if not payload or not target_dir:
        return payload
    try:
        payload_tokens = tokenize(payload)
    except Exception:
        return payload
    for payload_segment in segments(payload_tokens):
        start = command_index_from(payload_segment)
        if start >= len(payload_segment) or Path(payload_segment[start]).name != "git":
            return payload
        subcommand_index = git_subcommand_index(payload_segment, start)
        if "-C" in payload_segment[start + 1:subcommand_index]:
            return payload
        return " ".join(
            ["git", "-C", shlex.quote(target_dir)]
            + [shlex.quote(token) for token in payload_segment[start + 1:]]
        )
    return payload

def compose_git_c_target(current, value):
    if not value or unsafe_ref(value):
        return UNRESOLVABLE
    try:
        path = Path(value).expanduser()
        if current and current != UNRESOLVABLE and not path.is_absolute():
            path = Path(current) / path
        return str(path)
    except Exception:
        return UNRESOLVABLE

def git_config_key(config_value):
    if not config_value or "=" not in config_value:
        return None
    return config_value.split("=", 1)[0].strip().lower()

def git_config_changes_release_context(config_value):
    key = git_config_key(config_value)
    if not key:
        return False
    return (
        key.startswith("remote.")
        or key.startswith("url.")
        or key == "include.path"
        or key.startswith("includeif.")
    )

def git_config_assignment_operands(segment, subcommand_index):
    index = subcommand_index + 1
    mutating_action = False
    read_action = False
    operands = []
    value_options = {"-f", "--file", "--blob", "--type", "--default"}
    read_actions = {"--get", "--get-all", "--get-regexp", "--get-urlmatch", "--list", "-l"}
    mutating_actions = {
        "--add",
        "--replace-all",
        "--unset",
        "--unset-all",
        "--rename-section",
        "--remove-section",
    }
    flag_options = {
        "--global",
        "--system",
        "--local",
        "--worktree",
        "--null",
        "--bool",
        "--int",
        "--bool-or-int",
        "--path",
        "--expiry-date",
        "--fixed-value",
        "--includes",
        "--show-origin",
        "--show-scope",
        "--name-only",
    }
    while index < len(segment):
        token = segment[index]
        if token == "--":
            operands.extend(segment[index + 1:])
            break
        if token in read_actions:
            read_action = True
            index += 1
            continue
        if token in mutating_actions:
            mutating_action = True
            index += 1
            continue
        if token in value_options:
            index += 2
            continue
        if token.startswith("--") and any(token.startswith(option + "=") for option in value_options):
            index += 1
            continue
        if token in flag_options:
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        operands.append(token)
        index += 1
    return mutating_action, read_action, operands

def git_config_persistent_release_context_mutation(segment, subcommand_index):
    mutating_action, read_action, operands = git_config_assignment_operands(segment, subcommand_index)
    if not operands:
        return False
    key = operands[0].strip().lower()
    has_value = len(operands) > 1
    if read_action and not mutating_action and not has_value:
        return False
    if key.startswith("alias."):
        return has_value
    if (
        key.startswith("remote.")
        or key.startswith("url.")
        or key == "include.path"
        or key.startswith("includeif.")
    ):
        return mutating_action or has_value
    return False

def git_remote_persistent_context_mutation(segment, subcommand_index):
    index = subcommand_index + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            index += 1
            break
        if token.startswith("-"):
            index += 1
            continue
        action = token
        return action in {"add", "remove", "rm", "rename", "set-url"}
    return False

def git_release_context_untrusted(segment, git_index, scoped_vars):
    if any(
        key in scoped_vars or key in os.environ
        for key in {
            "GIT_DIR",
            "GIT_WORK_TREE",
            "GIT_NAMESPACE",
            "GIT_CONFIG_GLOBAL",
            "GIT_CONFIG_SYSTEM",
            "GIT_CONFIG_NOSYSTEM",
            "GIT_CONFIG_COUNT",
        }
    ):
        return True
    index = git_index + 1
    while index < len(segment):
        token = segment[index]
        config_value = None
        if token == "--":
            break
        if token in {"--git-dir", "--work-tree", "--namespace"}:
            return True
        if token.startswith(("--git-dir=", "--work-tree=", "--namespace=")):
            return True
        if token == "--bare":
            return True
        if token == "-c" and index + 1 < len(segment):
            config_value = segment[index + 1]
            index += 2
        elif token.startswith("-c") and token != "-c":
            config_value = token[2:]
            index += 1
        elif token in GIT_VALUE_GLOBALS:
            index += 2
            continue
        elif token.startswith("--") and any(token.startswith(option + "=") for option in GIT_VALUE_GLOBALS if option.startswith("--")):
            index += 1
            continue
        elif token in GIT_FLAG_GLOBALS:
            index += 1
            continue
        else:
            break
        if config_value and git_config_changes_release_context(config_value):
            return True
    return False

def git_remote_allowed(remote, target_dir=None):
    if not remote or unsafe_ref(remote):
        return False
    if (
        "://" in remote
        or remote.startswith("git@")
        or remote.startswith("ssh://")
        or remote.startswith("repos/")
        or "/" in remote
    ):
        return git_direct_push_url_allowed(remote, target_dir)
    push_urls = git_remote_push_urls(remote, target_dir)
    return bool(push_urls) and all(repo_allowed(push_url) for push_url in push_urls)

def git_remote_push_urls(remote, target_dir=None):
    try:
        cwd = target_dir or os.environ.get("PWD") or os.getcwd()
        result = subprocess.run(
            ["git", "-C", cwd, "remote", "get-url", "--push", "--all", remote],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except (OSError, ValueError):
        return []
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]

def git_remote_fetch_urls(remote, target_dir=None):
    try:
        cwd = target_dir or os.environ.get("PWD") or os.getcwd()
        result = subprocess.run(
            ["git", "-C", cwd, "remote", "get-url", "--all", remote],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except (OSError, ValueError):
        return []
    if result.returncode != 0:
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]

def git_direct_push_url_allowed(url, target_dir=None):
    urls = {url}
    rewritten = git_rewritten_push_url(url, target_dir)
    if rewritten:
        urls.add(rewritten)
    return all(repo_allowed(candidate) for candidate in urls)

def git_rewritten_push_url(url, target_dir=None):
    best_prefix = ""
    best_base = None
    for key, value in git_config_get_regexp(r"^url\.", target_dir):
        lowered = key.lower()
        for suffix in (".pushinsteadof", ".insteadof"):
            if not lowered.endswith(suffix):
                continue
            base = key[4:-len(suffix)]
            if url.startswith(value) and len(value) > len(best_prefix):
                best_prefix = value
                best_base = base
    if best_base is None:
        return None
    return best_base + url[len(best_prefix):]

def git_push_release_target(operands, release_push):
    if release_push:
        return ((operands[0] if operands else None), UNRESOLVABLE)
    if len(operands) < 2:
        return None
    remote = operands[0]
    refspecs = operands[1:]
    release_refs = []
    index = 0
    while index < len(refspecs):
        refspec = refspecs[index]
        if refspec == "tag":
            if index + 1 >= len(refspecs):
                return remote, UNRESOLVABLE
            release_refs.append(release_ref_from_refspec(refspecs[index + 1]))
            index += 2
            continue
        if refspec_targets_release_tag(refspec):
            release_refs.append(release_ref_from_refspec(refspec))
        index += 1
    if len(release_refs) > 1:
        return remote, UNRESOLVABLE
    if release_refs:
        return remote, release_refs[0]
    return None

def git_tag_mutates_release_ref(segment, subcommand_index):
    list_mode = False
    mutating_mode = False
    operands = []
    value_options = {
        "-m",
        "-F",
        "-u",
        "--message",
        "--file",
        "--local-user",
        "--cleanup",
        "--trailer",
    }
    list_value_options = {
        "--points-at",
        "--contains",
        "--no-contains",
        "--merged",
        "--no-merged",
        "--sort",
        "--format",
        "--column",
        "--color",
    }
    mutating_flags = {"-a", "-s", "-f", "--annotate", "--sign", "--force", "-d", "--delete", "-v", "--verify"}
    index = subcommand_index + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            operands.extend(segment[index + 1:])
            break
        if token in {"-l", "--list"} or re.match(r"^-n[0-9]*$", token):
            list_mode = True
            index += 1
            continue
        if token in list_value_options:
            list_mode = True
            index += 2
            continue
        if token.startswith("--") and any(token.startswith(option + "=") for option in list_value_options):
            list_mode = True
            index += 1
            continue
        if token in value_options:
            mutating_mode = True
            index += 2
            continue
        if token.startswith("--") and any(token.startswith(option + "=") for option in value_options):
            mutating_mode = True
            index += 1
            continue
        if token in mutating_flags:
            mutating_mode = True
            index += 1
            continue
        if token.startswith("-"):
            mutating_mode = True
            index += 1
            continue
        operands.append(token)
        index += 1
    if list_mode and not mutating_mode:
        return False
    if not operands:
        return mutating_mode
    return any(unsafe_ref(operand) or token_is_release_tag_ref(operand) for operand in operands)

def git_update_ref_mutates_release_ref(segment, subcommand_index):
    refs = []
    index = subcommand_index + 1
    while index < len(segment):
        token = segment[index]
        if token == "--stdin":
            return True
        if token == "--":
            if index + 1 < len(segment):
                refs.append(segment[index + 1])
            break
        if token in {"-m", "--message"}:
            index += 2
            continue
        if token.startswith("--message="):
            index += 1
            continue
        if token in {"-d", "--delete", "--no-deref", "--create-reflog", "-z"}:
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        refs.append(token)
        break
    return any(unsafe_ref(ref) or token_is_release_tag_ref(ref) for ref in refs)

def git_prior_release_ref_mutation(segment, git_index, scoped_vars):
    subcommand_index = git_subcommand_index(segment, git_index)
    if subcommand_index >= len(segment):
        return False
    subcommand = segment[subcommand_index]
    if subcommand not in {"tag", "update-ref"}:
        return False
    if git_release_context_untrusted(segment, git_index, scoped_vars):
        return True
    if subcommand == "tag":
        return git_tag_mutates_release_ref(segment, subcommand_index)
    return git_update_ref_mutates_release_ref(segment, subcommand_index)

def git_prior_release_context_mutation(segment, git_index, scoped_vars):
    subcommand_index = git_subcommand_index(segment, git_index)
    if subcommand_index >= len(segment):
        return False
    if git_release_context_untrusted(segment, git_index, scoped_vars):
        return True
    subcommand = segment[subcommand_index]
    if subcommand == "config":
        return git_config_persistent_release_context_mutation(segment, subcommand_index)
    if subcommand == "remote":
        return git_remote_persistent_context_mutation(segment, subcommand_index)
    return False

def shell_payload_parts(segment, start):
    index = start + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            return None
        if token == "-c" or (token.startswith("-") and not token.startswith("--") and "c" in token[1:]):
            if index + 1 < len(segment):
                return segment[index + 1], segment[index + 2:]
            return None
        if token.startswith("-"):
            index += 1
            continue
        break
    return None

def literal_assignment(token):
    match = ASSIGNMENT_FULL_RE.match(token)
    if not match or re.search(r"[$`]", match.group(2)):
        return None
    return match.group(1), match.group(2)

def substitute_vars(text, variables):
    def replace(match):
        return variables.get(match.group(1) or match.group(2), match.group(0))
    return re.sub(r"\$(?:([A-Za-z_][A-Za-z0-9_]*)|\{([A-Za-z_][A-Za-z0-9_]*)\})", replace, text)

def resolve_segment(segment, variables):
    resolved = []
    for token in segment:
        parsed = re.match(r"^\$(?:([A-Za-z_][A-Za-z0-9_]*)|\{([A-Za-z_][A-Za-z0-9_]*)\})$", token)
        if parsed and (parsed.group(1) or parsed.group(2)) in variables:
            resolved.extend(shlex.split(variables[parsed.group(1) or parsed.group(2)]))
        else:
            resolved.append(substitute_vars(token, variables))
    return resolved

def command_scoped_assignments(segment, start):
    assignments = {}
    for token in segment[:start]:
        parsed = ASSIGNMENT_FULL_RE.match(token)
        if parsed:
            value = parsed.group(2)
            assignments[parsed.group(1)] = UNRESOLVABLE if re.search(r"[$`]", value) else value
    return assignments

def github_api_path_parts(endpoint):
    value = urllib.parse.unquote(str(endpoint)).strip().strip("'\"")
    if value in {"graphql", "/graphql"}:
        return ["graphql"]
    parsed = urllib.parse.urlparse(value if "://" in value else "https://placeholder/" + value.lstrip("/"))
    parts = [part for part in parsed.path.split("/") if part]
    if parts[:2] == ["api", "v3"]:
        parts = parts[2:]
    return parts

def is_releases_endpoint(endpoint):
    parts = github_api_path_parts(endpoint)
    return len(parts) >= 4 and parts[0] == "repos" and parts[3] == "releases"

def is_release_create_endpoint(endpoint):
    parts = github_api_path_parts(endpoint)
    return len(parts) == 4 and parts[0] == "repos" and parts[3] == "releases"

def is_git_refs_endpoint(endpoint):
    parts = github_api_path_parts(endpoint)
    return len(parts) >= 5 and parts[0] == "repos" and parts[3:5] == ["git", "refs"]

def is_git_ref_create_endpoint(endpoint):
    parts = github_api_path_parts(endpoint)
    return len(parts) == 5 and parts[0] == "repos" and parts[3:5] == ["git", "refs"]

def endpoint_mentions_tag_ref(endpoint):
    return TAG_REF_TEXT_RE.search(urllib.parse.unquote(str(endpoint))) is not None

def is_graphql_endpoint(endpoint):
    parts = github_api_path_parts(endpoint)
    return parts == ["graphql"] or parts == ["api", "graphql"]

def field_pair(payload):
    if "=" not in payload:
        return None
    key, _, value = payload.partition("=")
    return key.rstrip(":"), value

def read_source(source):
    try:
        path = Path(source)
    except Exception:
        return None
    if not path.is_file():
        return None
    try:
        return path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return None

def normalized_payload_text(payload):
    if not payload:
        return ""
    text = str(payload)
    decoded = urllib.parse.unquote_plus(text)
    variants = {text, decoded}
    for value in list(variants):
        variants.add(collapse_static_string_concats(value))
    for value in list(variants):
        variants.add(value.replace("\\/", "/"))
    for value in list(variants):
        variants.add(
            re.sub(
                r"\\u([0-9a-fA-F]{4})",
                lambda match: chr(int(match.group(1), 16)),
                value,
            )
        )
    for value in list(variants):
        variants.add(value.replace("\\/", "/"))
    return "\n".join(variants)

def payload_values(payloads):
    values = []
    if isinstance(payloads, str):
        payloads = [payloads]
    for payload in payloads:
        pair = field_pair(payload)
        value = pair[1] if pair else payload
        if value in {"-", "@-"}:
            values.append(UNRESOLVABLE)
            continue
        if value.startswith("@"):
            source = value[1:]
            if unsafe_ref(source):
                values.append(UNRESOLVABLE)
                continue
            text = read_source(source)
            values.append(text if text is not None else UNRESOLVABLE)
            continue
        values.append(normalized_payload_text(value))
    return values

def payload_mentions_tag_ref(payloads):
    if isinstance(payloads, str):
        payloads = [payloads]
    text = "\n".join(value for value in payload_values(payloads) if value != UNRESOLVABLE)
    return bool(TAG_REF_TEXT_RE.search(text)) or any(
        (field_pair(payload) or ("", ""))[0] == "ref" and unsafe_ref((field_pair(payload) or ("", ""))[1])
        for payload in payloads
    )

def target_from_key(payloads, keys):
    for payload in payloads:
        pair = field_pair(payload)
        if pair and pair[0] in keys:
            value = pair[1]
            if value.startswith("@"):
                text = read_source(value[1:])
                value = text.strip() if text is not None else UNRESOLVABLE
            return UNRESOLVABLE if unsafe_ref(value) else value
    text = "\n".join(value for value in payload_values(payloads) if value != UNRESOLVABLE)
    for key in keys:
        pattern = re.compile(rf"[\"']?{re.escape(key)}[\"']?\s*[:=]\s*[\"']?([A-Za-z0-9._:/+-]+)", re.IGNORECASE)
        match = pattern.search(text)
        if match:
            value = match.group(1)
            return UNRESOLVABLE if unsafe_ref(value) else value
    return None

def truthy_payload_key(payloads, keys):
    for payload in payloads:
        pair = field_pair(payload)
        if not pair or pair[0] not in keys:
            continue
        value = pair[1].strip().strip("'\"").lower()
        return value not in {"", "0", "false", "no", "off"}
    text = "\n".join(value for value in payload_values(payloads) if value != UNRESOLVABLE)
    for key in keys:
        pattern = re.compile(
            rf"[\"']?{re.escape(key)}[\"']?\s*[:=]\s*([\"'][^\"']*[\"']|[A-Za-z0-9_.+-]+)",
            re.IGNORECASE,
        )
        found = False
        for match in pattern.finditer(text):
            found = True
            value = match.group(1).strip().strip("'\"").lower()
            if value not in {"", "0", "false", "no", "off"}:
                return True
        if not found and re.search(rf"[\"']?{re.escape(key)}[\"']?\s*[:=]", text, re.IGNORECASE):
            return True
    return False

def graphql_target(payloads):
    text = "\n".join(value for value in payload_values(payloads) if value != UNRESOLVABLE)
    if "createRef" in text and TAG_REF_TEXT_RE.search(text):
        return target_from_key([text], {"oid"}) or UNRESOLVABLE
    if "createRelease" in text or "updateRelease" in text:
        return target_from_key([text], {"targetCommitish", "target_commitish"})
    return None

def gh_api_metadata(segment, gh_index, scoped_vars):
    subcommand_index = gh_subcommand_index(segment, gh_index)
    if subcommand_index >= len(segment) or segment[subcommand_index] != "api":
        return None
    method = None
    has_write_fields = False
    endpoint = None
    payloads = []
    index = subcommand_index + 1
    while index < len(segment):
        token = segment[index]
        if token == "--":
            index += 1
            continue
        if token in {"-X", "--method"}:
            if index + 1 < len(segment):
                method = segment[index + 1].upper()
            index += 2
            continue
        if token.startswith("-X") and token != "-X":
            method = token[2:].upper()
            index += 1
            continue
        if token.startswith("--method="):
            method = token.split("=", 1)[1].upper()
            index += 1
            continue
        if token in {"-f", "--field", "-F", "--raw-field"}:
            has_write_fields = True
            if index + 1 < len(segment):
                payloads.append(segment[index + 1])
            index += 2
            continue
        if token == "--input":
            has_write_fields = True
            if index + 1 < len(segment):
                payloads.append("@" + segment[index + 1])
            index += 2
            continue
        if token.startswith("--field=") or token.startswith("--raw-field="):
            has_write_fields = True
            payloads.append(token.split("=", 1)[1])
            index += 1
            continue
        if token.startswith("--input="):
            has_write_fields = True
            payloads.append("@" + token.split("=", 1)[1])
            index += 1
            continue
        if (token.startswith("-f") or token.startswith("-F")) and token not in {"-f", "-F"}:
            has_write_fields = True
            payloads.append(token[2:])
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        if endpoint is None:
            endpoint = token
        index += 1
    if not endpoint:
        return None
    effective_method = method or ("POST" if has_write_fields else "GET")
    command_has_write_semantics = effective_method in GH_API_WRITE_METHODS or has_write_fields
    if not command_has_write_semantics:
        return None
    target = None
    endpoint_repo_name = endpoint_repo(endpoint)
    endpoint_host_name = endpoint_host(endpoint)
    gh_repo_name = gh_effective_repo(segment, gh_index, scoped_vars, require_implicit=endpoint_repo_name is None)
    if gh_repo_name == UNRESOLVABLE:
        return UNRESOLVABLE
    repo = endpoint_repo_name or gh_repo_name
    if not repo_allowed(repo, endpoint_host_name or gh_hostname_option(segment, gh_index) or scoped_vars.get("GH_HOST") or os.environ.get("GH_HOST")):
        return UNRESOLVABLE
    if is_releases_endpoint(endpoint):
        if not is_release_create_endpoint(endpoint) or effective_method != "POST":
            return UNRESOLVABLE
        tag = target_from_key(payloads, {"tag_name", "tagName"})
        if tag is None or not token_is_release_tag_ref(tag):
            return UNRESOLVABLE
        target = target_from_key(payloads, {"target_commitish", "targetCommitish"})
        if target is None:
            return UNRESOLVABLE
        if target:
            return ("gh-target", f"{tag}\t{target if explicit_sha(target) else UNRESOLVABLE}")
    elif is_git_refs_endpoint(endpoint):
        if (
            not is_git_ref_create_endpoint(endpoint)
            or effective_method != "POST"
            or truthy_payload_key(payloads, {"force"})
        ):
            return UNRESOLVABLE if endpoint_mentions_tag_ref(endpoint) or payload_mentions_tag_ref(payloads) else None
        if not payload_mentions_tag_ref(payloads):
            return None
        target = target_from_key(payloads, {"sha"}) or UNRESOLVABLE
    elif is_graphql_endpoint(endpoint):
        target = graphql_target(payloads)
        if target:
            return UNRESOLVABLE
    if target:
        return target if explicit_sha(target) else UNRESOLVABLE
    return None

def gh_release_metadata(segment, gh_index, scoped_vars):
    subcommand_index = gh_subcommand_index(segment, gh_index)
    if subcommand_index >= len(segment) or segment[subcommand_index] != "release":
        return None
    action_index = skip_gh_globals(segment, subcommand_index + 1)
    if action_index >= len(segment) or segment[action_index] != "create":
        return None
    repo = gh_release_create_explicit_repo(segment, gh_index)
    if repo == UNRESOLVABLE or not repo_allowed(repo, gh_hostname_option(segment, gh_index) or scoped_vars.get("GH_HOST") or os.environ.get("GH_HOST")):
        return ("unresolvable", UNRESOLVABLE)
    index = action_index + 1
    tag = None
    target = None
    verify_tag = False
    verify_tag_false = False
    while index < len(segment):
        current = segment[index]
        if current == "--":
            if index + 1 < len(segment) and tag is None:
                tag = segment[index + 1]
            break
        if current == "--target":
            target = segment[index + 1] if index + 1 < len(segment) else UNRESOLVABLE
            index += 2
            continue
        if current.startswith("--target="):
            target = current.split("=", 1)[1]
            index += 1
            continue
        if current == "--verify-tag":
            verify_tag = True
            index += 1
            continue
        if current.startswith("--verify-tag="):
            verify_value = current.split("=", 1)[1].strip().lower()
            if verify_value in {"", "0", "false", "no", "off"}:
                verify_tag = False
                verify_tag_false = True
            else:
                verify_tag = True
            index += 1
            continue
        if current in GH_VALUE_GLOBALS:
            index += 2
            continue
        if current.startswith("-R") and current != "-R":
            index += 1
            continue
        if current.startswith("--") and any(current.startswith(option + "=") for option in GH_VALUE_GLOBALS if option.startswith("--")):
            index += 1
            continue
        if current in GH_RELEASE_CREATE_VALUE_OPTIONS:
            index += 2
            continue
        if any(current.startswith(option + "=") for option in GH_RELEASE_CREATE_VALUE_OPTIONS):
            index += 1
            continue
        if current in GH_RELEASE_CREATE_FLAG_OPTIONS or current.startswith("-"):
            index += 1
            continue
        if tag is None:
            tag = current
        index += 1
    if verify_tag_false:
        return ("unresolvable", UNRESOLVABLE)
    if target is not None:
        if verify_tag:
            return ("unresolvable", UNRESOLVABLE)
        if not tag or not token_is_release_tag_ref(tag):
            return ("unresolvable", UNRESOLVABLE)
        return ("gh-target", f"{tag}\t{target if explicit_sha(target) else UNRESOLVABLE}")
    if tag:
        return ("unresolvable", UNRESOLVABLE)
    return ("unresolvable", UNRESOLVABLE)

def git_metadata(segment, git_index, scoped_vars):
    if git_release_context_untrusted(segment, git_index, scoped_vars):
        return ("unresolvable", UNRESOLVABLE)
    target_dir = None
    index = git_index + 1
    while index < len(segment):
        current = segment[index]
        if current == "-C":
            target_dir = compose_git_c_target(
                target_dir,
                segment[index + 1] if index + 1 < len(segment) else UNRESOLVABLE,
            )
            index += 2
            continue
        if current.startswith("-C") and current != "-C":
            target_dir = compose_git_c_target(target_dir, current[2:])
            index += 1
            continue
        if current == "--":
            index += 1
            break
        if current in GIT_VALUE_GLOBALS:
            index += 2
            continue
        if current.startswith("--") and any(current.startswith(option + "=") for option in GIT_VALUE_GLOBALS if option.startswith("--")):
            index += 1
            continue
        if current in GIT_FLAG_GLOBALS:
            index += 1
            continue
        break
    alias_index = git_subcommand_index(segment, git_index)
    aliases = git_global_alias_assignments(segment, git_index)
    if alias_index < len(segment) and segment[alias_index] in aliases:
        payload = git_alias_payload(segment[alias_index], segment[alias_index + 1:], aliases)
        return ("payload", git_payload_with_outer_c(payload, target_dir))
    if index >= len(segment) or segment[index] != "push":
        return None
    operands = []
    cursor = index + 1
    release_push = False
    destructive_push = False
    while cursor < len(segment):
        current = segment[cursor]
        if current == "--":
            operands.extend(segment[cursor + 1:])
            break
        if current in GIT_PUSH_DESTRUCTIVE_TAG_OPTIONS or current.startswith("--force-with-lease"):
            destructive_push = True
            cursor += 1
            continue
        if current in GIT_PUSH_RELEASE_TAG_OPTIONS:
            release_push = True
            break
        if current in GIT_PUSH_VALUE_OPTIONS:
            cursor += 2
            continue
        if current.startswith("--") and any(current.startswith(option + "=") for option in GIT_PUSH_VALUE_OPTIONS if option.startswith("--")):
            cursor += 1
            continue
        if current.startswith("-o") and current != "-o":
            cursor += 1
            continue
        if current.startswith("-"):
            cursor += 1
            continue
        operands.append(current)
        cursor += 1
    release_target = git_push_release_target(operands, release_push)
    if release_target:
        remote, release_ref = release_target
        if destructive_push:
            return ("unresolvable", UNRESOLVABLE)
        if target_dir == UNRESOLVABLE or (target_dir is not None and unsafe_ref(target_dir)):
            return ("unresolvable", UNRESOLVABLE)
        if not git_remote_allowed(remote, target_dir):
            return ("unresolvable", UNRESOLVABLE)
        if release_ref == UNRESOLVABLE:
            return ("unresolvable", UNRESOLVABLE)
        if target_dir is None:
            return ("ref", release_ref)
        return ("git-c-ref", f"{target_dir}\t{release_ref}")
    return None

def extract(command, depth=0):
    if depth > 8:
        return None
    try:
        tokens = tokenize(command.replace("\\\n", ""))
    except Exception:
        return ("unresolvable", UNRESOLVABLE)
    variables = {}
    gh_aliases = {}
    cwd_changed = False
    prior_release_ref_mutation = False
    release_result = None
    def guard_prior_ref_mutation(result):
        if result and prior_release_ref_mutation and result[0] != "unresolvable":
            return ("unresolvable", UNRESOLVABLE)
        return result
    def record_release_result(result):
        nonlocal release_result
        if not result:
            return None
        result = guard_prior_ref_mutation(result)
        if release_result is not None:
            return ("unresolvable", UNRESOLVABLE)
        release_result = result
        return None
    for raw_segment in segments(tokens):
        if len(raw_segment) == 1:
            parsed = literal_assignment(raw_segment[0])
            if parsed:
                variables[parsed[0]] = parsed[1]
                continue
        if raw_segment and Path(raw_segment[0]).name in {"export", "declare", "typeset"}:
            exported = {}
            for token in raw_segment[1:]:
                parsed = literal_assignment(token)
                if parsed:
                    exported[parsed[0]] = parsed[1]
            if exported:
                variables.update(exported)
                continue
        segment = resolve_segment(raw_segment, variables)
        start = command_index_from(segment)
        if start >= len(segment):
            continue
        command_name = Path(segment[start]).name
        command_env = command_scoped_assignments(segment, start)
        scoped_vars = dict(variables)
        scoped_vars.update(command_env)
        if command_name in {"cd", "pushd", "popd"}:
            cwd_changed = True
            continue
        if cwd_changed or segment_has_env_chdir(segment, start):
            return ("unresolvable", UNRESOLVABLE)
        if command_name in SHELLS:
            shell_parts = shell_payload_parts(segment, start)
            if shell_parts:
                nested = substitute_vars(shell_parts[0], scoped_vars)
                result = extract(nested, depth + 1)
                if result:
                    blocked = record_release_result(result)
                    if blocked:
                        return blocked
                    continue
        if command_name == "eval":
            result = extract(" ".join(segment[start + 1:]), depth + 1)
            if result:
                blocked = record_release_result(result)
                if blocked:
                    return blocked
                continue
        if command_name == "gh":
            gh_config_dir, command_scoped_gh_config = gh_alias_config_dir(segment, start, command_env, variables)
            effective_gh_aliases = dict(persistent_gh_aliases(gh_config_dir))
            effective_gh_aliases.update(gh_aliases)
            alias_assignment = gh_alias_assignment(segment, start)
            if alias_assignment is not None:
                alias_name, alias_expansion = alias_assignment
                gh_aliases[alias_name] = alias_expansion
                result = extract(gh_alias_payload(alias_expansion), depth + 1)
                if result:
                    return ("unresolvable", UNRESOLVABLE)
                continue
            target = gh_release_metadata(segment, start, scoped_vars)
            if target:
                result = ("unresolvable", UNRESOLVABLE) if target[1] == UNRESOLVABLE or unsafe_ref(target[1]) else target
                blocked = record_release_result(result)
                if blocked:
                    return blocked
                continue
            target = gh_api_metadata(segment, start, scoped_vars)
            if target:
                if isinstance(target, tuple):
                    value_parts = str(target[1]).split("\t")
                    result = (
                        ("unresolvable", UNRESOLVABLE)
                        if target[1] == UNRESOLVABLE or UNRESOLVABLE in value_parts or any(unsafe_ref(part) for part in value_parts)
                        else target
                    )
                else:
                    result = ("unresolvable", UNRESOLVABLE) if target == UNRESOLVABLE or unsafe_ref(target) else ("ref", target)
                blocked = record_release_result(result)
                if blocked:
                    return blocked
                continue
            alias_index = gh_subcommand_index(segment, start)
            if alias_index < len(segment) and segment[alias_index] in effective_gh_aliases:
                if command_scoped_gh_config or segment[alias_index] in gh_aliases:
                    return ("unresolvable", UNRESOLVABLE)
                alias_payload = gh_alias_payload(effective_gh_aliases[segment[alias_index]], segment[alias_index + 1:])
                result = extract(alias_payload, depth + 1)
                if result:
                    blocked = record_release_result(result)
                    if blocked:
                        return blocked
                    continue
        if command_name == "git":
            if git_prior_release_context_mutation(segment, start, scoped_vars):
                prior_release_ref_mutation = True
                continue
            if git_prior_release_ref_mutation(segment, start, scoped_vars):
                prior_release_ref_mutation = True
                continue
            result = git_metadata(segment, start, scoped_vars)
            if result and result[0] == "payload" and result[1]:
                nested = extract(result[1], depth + 1)
                if nested:
                    blocked = record_release_result(nested)
                    if blocked:
                        return blocked
                    continue
            if result and result[0] in {"git-c", "git-c-ref", "ref", "unresolvable"}:
                blocked = record_release_result(result)
                if blocked:
                    return blocked
                continue
    return release_result

result = extract(sys.argv[1])
if not result:
    raise SystemExit(1)
print(f"{result[0]}\t{result[1]}")
PY
}

if [ -z "$QUALITY_GATE_SESSION_ID" ]; then
  reason="Pre-release quality gate cannot validate this release command because no host session id is available. Set SIDEKICK_SESSION_ID, CODEX_THREAD_ID, CLAUDE_SESSION_ID, or SESSION_ID and rerun the gate in the current session."
  jq -cn --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
fi

sidekick_checkout_remote_allowed() {
  case "$1" in
    https://github.com/alo-exp/sidekick|\
    https://github.com/alo-exp/sidekick.git|\
    git@github.com:alo-exp/sidekick.git|\
    ssh://git@github.com/alo-exp/sidekick.git)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

trusted_sidekick_checkout() {
  local candidate origin
  candidate="$1"
  [ -n "${candidate}" ] || return 1
  git -C "${candidate}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  origin="$(git -C "${candidate}" config --get remote.origin.url 2>/dev/null || true)"
  sidekick_checkout_remote_allowed "${origin}" || return 1
  sidekick_checkout_effective_remotes_allowed "${candidate}"
}

sidekick_checkout_effective_remotes_allowed() {
  local candidate fetch_urls found push_urls url
  candidate="$1"
  fetch_urls="$(git -C "${candidate}" remote get-url --all origin 2>/dev/null || true)"
  found=0
  while IFS= read -r url; do
    [ -n "${url}" ] || continue
    found=1
    sidekick_checkout_remote_allowed "${url}" || return 1
  done <<EOF
${fetch_urls}
EOF
  [ "${found}" -eq 1 ] || return 1

  push_urls="$(git -C "${candidate}" remote get-url --push --all origin 2>/dev/null || true)"
  found=0
  while IFS= read -r url; do
    [ -n "${url}" ] || continue
    found=1
    sidekick_checkout_remote_allowed "${url}" || return 1
  done <<EOF
${push_urls}
EOF
  [ "${found}" -eq 1 ] || return 1
}

inside_git_worktree() {
  local candidate
  candidate="$1"
  [ -n "${candidate}" ] || return 1
  git -C "${candidate}" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

trusted_sidekick_head_sha() {
  local candidate
  candidate="$1"
  trusted_sidekick_checkout "${candidate}" || return 1
  git -C "${candidate}" rev-parse --short=12 HEAD 2>/dev/null
}

release_ref_current_head_sha() {
  local candidate ref target_sha head_sha
  candidate="$1"
  ref="$2"
  target_sha="$(git -C "${candidate}" rev-parse --short=12 "${ref}^{commit}" 2>/dev/null)" || return 1
  head_sha="$(trusted_sidekick_head_sha "${candidate}")" || return 1
  [ "${target_sha}" = "${head_sha}" ] || return 1
  printf '%s\n' "${head_sha}"
}

remote_release_tag_allows_current_head() {
  local candidate tag head_sha output peeled direct selected
  candidate="$1"
  tag="$2"
  head_sha="$3"
  [ -n "${tag}" ] || return 1
  case "${tag}" in
    *[!A-Za-z0-9._+-]*|'')
      return 1
      ;;
  esac
  output="$(git -C "${candidate}" ls-remote --tags origin "refs/tags/${tag}" 2>/dev/null)" || return 1
  [ -n "${output}" ] || return 0
  peeled="$(awk -v ref="refs/tags/${tag}^{}" '$2 == ref { print substr($1, 1, 12); exit }' <<EOF
${output}
EOF
)"
  direct="$(awk -v ref="refs/tags/${tag}" '$2 == ref { print substr($1, 1, 12); exit }' <<EOF
${output}
EOF
)"
  selected="${peeled:-${direct}}"
  [ -n "${selected}" ] || return 1
  [ "${selected}" = "${head_sha}" ]
}

gh_release_target_current_head_sha() {
  local candidate tag target target_sha head_sha
  candidate="$1"
  tag="$2"
  target="$3"
  trusted_sidekick_checkout "${candidate}" || return 1
  target_sha="$(git -C "${candidate}" rev-parse --short=12 "${target}^{commit}" 2>/dev/null)" || return 1
  head_sha="$(trusted_sidekick_head_sha "${candidate}")" || return 1
  [ "${target_sha}" = "${head_sha}" ] || return 1
  remote_release_tag_allows_current_head "${candidate}" "${tag}" "${head_sha}" || return 1
  printf '%s\n' "${head_sha}"
}

current_release_sha() {
  local candidate git_c_ref git_c_target gh_tag gh_target metadata metadata_kind metadata_value
  metadata="$(release_target_metadata "$COMMAND" 2>/dev/null || true)"
  if [ -n "${metadata}" ]; then
    metadata_kind="${metadata%%$'\t'*}"
    metadata_value="${metadata#*$'\t'}"
    if [ "${metadata_kind}" = "unresolvable" ]; then
      return 1
    fi
    if [ "${metadata_kind}" = "git-c" ]; then
      trusted_sidekick_head_sha "${metadata_value}" && return 0
      return 1
    fi
    if [ "${metadata_kind}" = "git-c-ref" ]; then
      git_c_target="${metadata_value%%$'\t'*}"
      git_c_ref="${metadata_value#*$'\t'}"
      release_ref_current_head_sha "${git_c_target}" "${git_c_ref}" && return 0
      return 1
    fi
    if [ "${metadata_kind}" = "gh-target" ]; then
      gh_tag="${metadata_value%%$'\t'*}"
      gh_target="${metadata_value#*$'\t'}"
      if inside_git_worktree "${PWD:-.}"; then
        gh_release_target_current_head_sha "${PWD:-.}" "${gh_tag}" "${gh_target}" && return 0
        return 1
      fi
      for candidate in "${CLAUDE_PROJECT_DIR:-}" "${CODEX_PROJECT_DIR:-}" "${SIDEKICK_PROJECT_DIR:-}" "${REPO_ROOT}"; do
        if [ -n "${candidate}" ] && gh_release_target_current_head_sha "${candidate}" "${gh_tag}" "${gh_target}"; then
          return 0
        fi
      done
      return 1
    fi
    if [ "${metadata_kind}" = "ref" ]; then
      if inside_git_worktree "${PWD:-.}"; then
        release_ref_current_head_sha "${PWD:-.}" "${metadata_value}" && return 0
        return 1
      fi
      for candidate in "${CLAUDE_PROJECT_DIR:-}" "${CODEX_PROJECT_DIR:-}" "${SIDEKICK_PROJECT_DIR:-}" "${REPO_ROOT}"; do
        if [ -n "${candidate}" ] && release_ref_current_head_sha "${candidate}" "${metadata_value}"; then
          return 0
        fi
      done
      return 1
    fi
  fi
  return 1
}

missing=()
current_head_sha="$(current_release_sha || true)"
if [ -z "$current_head_sha" ]; then
  reason="Pre-release quality gate cannot validate this release command because no current git SHA or release target SHA is available. Use one explicit release operation that targets the current trusted Sidekick checkout HEAD, such as gh release create --repo alo-exp/sidekick --target <current-sha>."
  jq -cn --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
fi

for stage in $(seq 1 "$STAGE_COUNT"); do
  # Token-aware match so quality-gate-stage-10 does not satisfy stage 1, stale
  # markers from another host session do not satisfy the current session, and
  # stale markers from an older commit do not satisfy source-checkout releases.
  if ! awk -v marker="quality-gate-stage-${stage}" -v sid="$QUALITY_GATE_SESSION_ID" -v sha="$current_head_sha" '
    $1 == marker {
      has_session = 0
      has_sha = 0
      for (i = 2; i <= NF; i++) {
        if ($i == "session=" sid) {
          has_session = 1
        }
        if ($i == "sha=" sha) {
          has_sha = 1
        }
      }
      if (has_session && has_sha) {
        found = 1
      }
    }
    END { exit found ? 0 : 1 }
  ' "$STATE_FILE" 2>/dev/null; then
    missing+=("${stage}")
  fi
done

if [ ${#missing[@]} -eq 0 ]; then
  live_pyramid_runs=$(
    awk -v marker="$LIVE_PYRAMID_MARKER" -v sid="$QUALITY_GATE_SESSION_ID" -v sha="$current_head_sha" '
      $1 == marker {
        has_session = 0
        has_sha = 0
        for (i = 2; i <= NF; i++) {
          if ($i == "session=" sid) {
            has_session = 1
          }
          if ($i == "sha=" sha) {
            has_sha = 1
          }
        }
        if (has_session && has_sha) {
          print $0
        }
      }
    ' "$STATE_FILE" 2>/dev/null | sort -u | wc -l | tr -d ' '
  )

  if [ "${live_pyramid_runs:-0}" -ge "$LIVE_PYRAMID_REQUIRED_RUNS" ]; then
    exit 0
  fi

  reason="Pre-release live pyramid incomplete. Found ${live_pyramid_runs:-0}/${LIVE_PYRAMID_REQUIRED_RUNS} current-session, current-commit ${LIVE_PYRAMID_MARKER} marker(s). Run SIDEKICK_LIVE_CODEX=1 bash tests/run_release.bash twice in this host session before cutting a release."
  jq -cn --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
fi

missing_list=$(IFS=, ; echo "${missing[*]}")
reason="Pre-release quality gate not complete for the current session and commit. Missing stage(s): ${missing_list}. Run all ${STAGE_COUNT} stages in site/pre-release-quality-gate.md before cutting a release."

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

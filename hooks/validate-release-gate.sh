#!/usr/bin/env bash
# Pre-release quality gate enforcer
# Intercepts Bash tool calls containing "gh release create" and denies them
# (via the Claude Code PreToolUse permissionDecision envelope) unless all
# current-session quality-gate stage markers are present in Sidekick's state file.
#
# Stage count and marker names are defined in docs/pre-release-quality-gate.md.
# Each stage in that document resolves host-specific state, invokes
# /superpowers:verification-before-completion, then writes:
#   mkdir -p "$(dirname "$SIDEKICK_QG_STATE")"
#   printf 'quality-gate-stage-N session=%s\n' "$SIDEKICK_QG_SESSION" >> "$SIDEKICK_QG_STATE"
# If stages are added or removed from that document, update STAGE_COUNT below
# and commit both files together.
#
# NOTE: we deliberately do NOT use ~/.claude/.silver-bullet/state here —
# Silver Bullet's dev-cycle-check.sh hook blocks direct writes to that path
# and the markers would never land.

set -euo pipefail

STAGE_COUNT=4
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
import codecs
import os
import re
import shlex
import subprocess
import sys

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
GRAPHQL_RELEASE_MUTATION_RE = re.compile(
    r"\b(?:create|update|delete)Release\b|"
    r"\b(?:create|update|delete)Ref\b|"
    r"refs/tags/",
    re.IGNORECASE,
)
PERSISTENT_GH_ALIASES = {}


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


def render_static_command(command):
    try:
        tokens = tokenize(command)
    except Exception:
        return None
    for segment in segments(tokens):
        return static_producer_payload(segment)
    return None


def normalize_command(command):
    normalized = command.replace("\\\r\n", "").replace("\\\n", "")
    normalized = re.sub(r"\)(?=;)", ") ", normalized)
    normalized = expand_ansi_c_quotes(normalized)
    normalized = expand_parameter_expansions(normalized)
    normalized = expand_static_substitutions(normalized)
    return normalized


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


def gh_release_create_command(segment, gh_index):
    subcommand_index = gh_subcommand_index(segment, gh_index)
    if subcommand_index >= len(segment) or segment[subcommand_index] != "release":
        return False
    create_index = skip_gh_globals(segment, subcommand_index + 1)
    return create_index < len(segment) and segment[create_index] == "create"


def is_release_api_endpoint(endpoint):
    path = endpoint.split("?", 1)[0].strip("/")
    parts = [part for part in path.split("/") if part]
    if len(parts) < 4 or parts[0] != "repos":
        return False
    return parts[3] == "releases" or parts[3:5] == ["git", "refs"]


def is_graphql_endpoint(endpoint):
    return endpoint.split("?", 1)[0].strip("/") == "graphql"


def graphql_release_mutation_text(value):
    if GRAPHQL_RELEASE_MUTATION_RE.search(value):
        return True
    if "=" in value:
        _, _, tail = value.partition("=")
        return GRAPHQL_RELEASE_MUTATION_RE.search(tail) is not None
    return False


def graphql_file_backed_query(value):
    return (
        value.startswith("query=@")
        or value.startswith("query:=@")
        or value.startswith("query=@-")
        or value.startswith("query:=@-")
    )


def graphql_dynamic_query(value):
    if not (value.startswith("query=") or value.startswith("query:=")):
        return False
    _, _, query_value = value.partition("=")
    return bool(EXPANSION_RE.search(query_value))


def gh_api_release_write_command(segment, gh_index):
    subcommand_index = gh_subcommand_index(segment, gh_index)
    if subcommand_index >= len(segment) or segment[subcommand_index] != "api":
        return False
    method = None
    has_write_fields = False
    graphql_payloads = []
    graphql_input_file = False
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
                if graphql_file_backed_query(segment[index + 1]):
                    graphql_input_file = True
            index += 2
            continue
        if token == "--input":
            has_write_fields = True
            graphql_input_file = True
            if index + 1 < len(segment):
                graphql_payloads.append(segment[index + 1])
            index += 2
            continue
        if token.startswith("--field=") or token.startswith("--raw-field="):
            has_write_fields = True
            payload = token.split("=", 1)[1]
            graphql_payloads.append(payload)
            if graphql_file_backed_query(payload):
                graphql_input_file = True
            index += 1
            continue
        if token.startswith("--input="):
            has_write_fields = True
            graphql_input_file = True
            graphql_payloads.append(token.split("=", 1)[1])
            index += 1
            continue
        if (token.startswith("-f") or token.startswith("-F")) and token not in {"-f", "-F"}:
            has_write_fields = True
            payload = token[2:]
            graphql_payloads.append(payload)
            if graphql_file_backed_query(payload):
                graphql_input_file = True
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
        return graphql_input_file or any(
            graphql_dynamic_query(payload)
            or
            graphql_release_mutation_text(payload)
            for payload in graphql_payloads
        )
    if not is_release_api_endpoint(endpoint):
        return False
    return effective_method in GH_API_WRITE_METHODS or has_write_fields


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
        parsed = literal_assignment(token)
        if parsed is not None:
            assignments[parsed[0]] = parsed[1]
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


def persistent_gh_aliases(gh_config_dir=None):
    cache_key = gh_config_dir or "__default__"
    if cache_key in PERSISTENT_GH_ALIASES:
        return PERSISTENT_GH_ALIASES[cache_key]
    alias_fixture = os.environ.get("SIDEKICK_GH_ALIAS_LIST")
    if alias_fixture is not None and gh_config_dir is None:
        PERSISTENT_GH_ALIASES[cache_key] = parse_gh_alias_list(alias_fixture)
        return PERSISTENT_GH_ALIASES[cache_key]
    env = {}
    for key in ("HOME", "PATH", "XDG_CONFIG_HOME", "SIDEKICK_TEST_GH_CONFIG_DIR"):
        value = os.environ.get(key)
        if value is not None:
            env[key] = value
    env.setdefault("PATH", "/usr/bin:/bin:/usr/sbin:/sbin")
    if gh_config_dir:
        env["GH_CONFIG_DIR"] = gh_config_dir
    try:
        result = subprocess.run(
            ["gh", "alias", "list"],
            capture_output=True,
            check=False,
            env=env,
            text=True,
            timeout=1,
        )
    except (FileNotFoundError, OSError, subprocess.SubprocessError):
        PERSISTENT_GH_ALIASES[cache_key] = {}
        return PERSISTENT_GH_ALIASES[cache_key]
    if result.returncode != 0:
        PERSISTENT_GH_ALIASES[cache_key] = {}
        return PERSISTENT_GH_ALIASES[cache_key]
    PERSISTENT_GH_ALIASES[cache_key] = parse_gh_alias_list(result.stdout)
    return PERSISTENT_GH_ALIASES[cache_key]


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
        if re.search(r"\bgh\s+release\s+create\b", literal):
            return True
        if literal != "gh":
            continue
        args = literals[index + 1:]
        if len(args) >= 2 and args[0] == "release" and args[1] == "create":
            return True
        if args and args[0] == "api":
            command_text = " ".join(["gh"] + args)
            if re.search(r"repos/[^/]+/[^/]+/(?:releases|git/refs)\b", command_text):
                return True
            if GRAPHQL_RELEASE_MUTATION_RE.search(command_text):
                return True
    return False


def language_payload_mentions_release_command(payload):
    if re.search(r"\bgh\s+release\s+create\b", payload):
        return True
    if re.search(r"\bgh\s+api\b", payload) and (
        re.search(r"repos/[^/]+/[^/]+/(?:releases|git/refs)\b", payload)
        or GRAPHQL_RELEASE_MUTATION_RE.search(payload)
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
            "gitrefs",
            "refstags",
            "createrelease",
            "updaterelease",
            "deleterelease",
            "createref",
            "updateref",
            "deleteref",
        }
    ):
        return True
    return False


def language_payload_with_args_mentions_release_command(payload, args):
    if language_payload_mentions_release_command(payload):
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
    return language_payload_mentions_release_command(expanded)


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
    normalized_command = normalize_command(command)
    if normalized_command != command:
        command = normalized_command
    for payload in literal_expanded_shell_payloads(command):
        if contains_release_create(payload, depth + 1):
            return True
    for receiver, payload in heredoc_payloads(command):
        if heredoc_receiver_runs_script(receiver):
            if language_payload_mentions_release_command(payload):
                return True
            if contains_release_create(payload, depth + 1):
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
    expand_aliases = False
    for raw_segment, incoming_control in segments_with_controls(tokens):
        raw_segment = combine_braced_expansion_tokens(raw_segment)
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
        raw_shell_parts = shell_payload_parts(raw_segment)
        if raw_shell_parts:
            raw_shell_text, raw_shell_args = raw_shell_parts
            resolved_shell_text = embedded_variable_substitution(raw_shell_text, literal_vars)
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
            if command_name == "gh":
                command_env = command_scoped_assignments(segment, start)
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
                if gh_release_create_command(segment, start) or gh_api_release_write_command(segment, start):
                    return True
                alias_index = gh_subcommand_index(segment, start)
                if alias_index < len(segment) and segment[alias_index] in effective_gh_aliases:
                    alias_payload = gh_alias_payload(effective_gh_aliases[segment[alias_index]], segment[alias_index + 1:])
                    if contains_release_create(alias_payload, depth + 1):
                        return True
            if expand_aliases and segment[start] in aliases:
                alias_payload = " ".join(
                    [aliases[segment[start]]] + [shlex.quote(token) for token in segment[start + 1:]]
                )
                if contains_release_create(alias_payload, depth + 1):
                    return True
            for payload, interpreter_args in interpreter_payloads_with_args(segment, start):
                if language_payload_with_args_mentions_release_command(payload, interpreter_args):
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
                if command_name in INTERPRETER_PAYLOAD_OPTIONS and language_payload_mentions_release_command(stdin_candidate):
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
                if command_name in INTERPRETER_PAYLOAD_OPTIONS and language_payload_mentions_release_command(payload):
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

if [ -z "$QUALITY_GATE_SESSION_ID" ]; then
  reason="Pre-release quality gate cannot validate this release command because no host session id is available. Set SIDEKICK_SESSION_ID, CODEX_THREAD_ID, or SESSION_ID and rerun the gate in the current session."
  jq -cn --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
fi

missing=()
for stage in $(seq 1 "$STAGE_COUNT"); do
  # Anchored whole-line fixed-string match so quality-gate-stage-10 does
  # not satisfy stage 1, and stale markers from another host session do not
  # satisfy the current session.
  if ! grep -qxF "quality-gate-stage-${stage} session=${QUALITY_GATE_SESSION_ID}" "$STATE_FILE" 2>/dev/null; then
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

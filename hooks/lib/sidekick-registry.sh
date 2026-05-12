#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — shared sidekick registry helpers
# =============================================================================
# Provides small, reusable helpers for reading the sidekick registry and for
# writing per-sidekick audit ledgers.
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

[[ -n "${_SIDEKICK_REGISTRY_LOADED:-}" ]] && return 0
_SIDEKICK_REGISTRY_LOADED=1

sidekick_plugin_root() {
  if [[ -n "${SIDEKICK_PLUGIN_ROOT:-}" ]]; then
    printf '%s' "${SIDEKICK_PLUGIN_ROOT}"
    return 0
  fi

  if [[ -n "${CODEX_PLUGIN_ROOT:-}" ]]; then
    printf '%s' "${CODEX_PLUGIN_ROOT}"
    return 0
  fi

  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    printf '%s' "${CLAUDE_PLUGIN_ROOT}"
    return 0
  fi

  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

sidekick_registry_file() {
  printf '%s/sidekicks/registry.json' "$(sidekick_plugin_root)"
}

sidekick_registry_get() {
  local sidekick="$1"
  local jq_filter="$2"
  local registry_file
  registry_file="$(sidekick_registry_file)"

  if command -v jq >/dev/null 2>&1; then
    jq -r --arg sidekick "$sidekick" "${jq_filter}" "${registry_file}"
    return 0
  fi

  python3 - "$sidekick" "$jq_filter" "$registry_file" <<'PY'
import json
import re
import sys

sidekick, jq_filter, registry_file = sys.argv[1:4]
match = re.fullmatch(r"\.\[\$sidekick\]\.(.+)", jq_filter)
if not match:
    raise SystemExit(1)

path = match.group(1).split(".")
with open(registry_file, "r", encoding="utf-8") as fh:
    data = json.load(fh)

value = data.get(sidekick, {})
for key in path:
    if isinstance(value, dict):
        value = value.get(key)
    else:
        value = None
        break

if value is None:
    print("")
elif isinstance(value, (dict, list)):
    print(json.dumps(value))
else:
    print(value)
PY
}

sidekick_session_id() {
  if [[ -n "${SIDEKICK_TEST_SESSION_ID:-}" ]]; then
    printf '%s' "${SIDEKICK_TEST_SESSION_ID}"
    return 0
  fi

  if [[ -n "${SIDEKICK_SESSION_ID:-}" ]]; then
    printf '%s' "${SIDEKICK_SESSION_ID}"
    return 0
  fi

  if [[ -n "${CODEX_THREAD_ID:-}" ]]; then
    printf '%s' "${CODEX_THREAD_ID}"
    return 0
  fi

  if [[ -n "${CLAUDE_SESSION_ID:-}" ]]; then
    printf '%s' "${CLAUDE_SESSION_ID}"
    return 0
  fi

  if [[ -n "${SESSION_ID:-}" ]]; then
    printf '%s' "${SESSION_ID}"
    return 0
  fi

  return 1
}

sidekick_session_marker_file() {
  local sidekick="$1"
  local marker_template session_id

  marker_template="$(sidekick_registry_get "$sidekick" '.[$sidekick].marker_file')"
  session_id="$(sidekick_session_id)" || return 1

  marker_template="${marker_template//\$\{CODEX_THREAD_ID\}/$session_id}"
  marker_template="${marker_template//\$CODEX_THREAD_ID/$session_id}"
  marker_template="${marker_template//\$\{CLAUDE_SESSION_ID\}/$session_id}"
  marker_template="${marker_template//\$CLAUDE_SESSION_ID/$session_id}"

  if [[ -z "${marker_template}" ]]; then
    return 1
  fi

  case "${marker_template}" in
    /*) printf '%s' "${marker_template}" ;;
    *) printf '%s/%s' "${HOME}" "${marker_template}" ;;
  esac
}

sidekick_project_root() {
  local root="${SIDEKICK_PROJECT_DIR:-${CODEX_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}}"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$root" 2>/dev/null && return 0
  fi
  printf '%s' "$root"
}

sidekick_project_sidekick_dir() {
  local sidekick="$1"
  printf '%s/.%s' "$(sidekick_project_root)" "$sidekick"
}

sidekick_idx_path() {
  local sidekick="$1"
  printf '%s/conversations.idx' "$(sidekick_project_sidekick_dir "$sidekick")"
}

sidekick_ensure_idx() {
  local sidekick="$1"
  mkdir -p "$(sidekick_project_sidekick_dir "$sidekick")" 2>/dev/null || return 1
  touch -a "$(sidekick_idx_path "$sidekick")" 2>/dev/null || return 1
}

sidekick_gen_uuid() {
  if [[ -n "${SIDEKICK_TEST_UUID_OVERRIDE:-}" ]]; then
    printf '%s' "${SIDEKICK_TEST_UUID_OVERRIDE}"
    return 0
  fi
  uuidgen | tr 'A-Z' 'a-z'
}

sidekick_validate_uuid() {
  [[ "$1" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

sidekick_extract_exec_prompt() {
  local cmd="$1"
  local hint=""
  if command -v python3 >/dev/null 2>&1; then
    hint="$(python3 -c '
import shlex, sys
cmd = sys.argv[1]
try:
    toks = shlex.split(cmd)
except Exception:
    toks = cmd.split()
for idx, tok in enumerate(toks):
    if tok == "exec":
        rest = toks[idx + 1:]
        if rest:
            sys.stdout.write(rest[-1])
        break
' "$cmd" 2>/dev/null || true)"
  fi
  hint="${hint//$'\t'/ }"
  hint="${hint//$'\n'/ }"
  printf '%s' "${hint:0:200}"
}

sidekick_append_idx_row() {
  local sidekick="$1"
  local uuid="$2"
  local hint="$3"
  local idx
  idx="$(sidekick_idx_path "$sidekick")"
  if [[ -f "$idx" ]] && grep -qF "$uuid" "$idx" 2>/dev/null; then
    return 0
  fi
  local tag_suffix sidekick_tag
  tag_suffix="${uuid##*-}"
  tag_suffix="${tag_suffix:0:8}"
  sidekick_tag="${sidekick}-$(date +%s)-${tag_suffix}"
  {
    printf '%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$uuid" "$sidekick_tag" "$hint" >> "$idx"
  } 2>/dev/null || true
  return 0
}

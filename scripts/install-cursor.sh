#!/usr/bin/env bash
# Sync Sidekick into the Cursor plugin cache and merge Cursor hooks.
#
# Usage:
#   bash scripts/install-cursor.sh [--merge-hooks-only] [--register-claude-import]
#
# Cursor discovers marketplace plugins only after they are enabled in Settings → Plugins.
# Until the central alo-labs-cursor marketplace lists Sidekick on GitHub, also add:
#   https://github.com/alo-exp/sidekick
# as a standalone marketplace source, then enable sidekick there.
#
# As a fallback, --register-claude-import adds sidekick@alo-labs to Claude's
# installed_plugins.json so Cursor's Claude-plugin import path loads the skills.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION="$(python3 -c "import json; print(json.load(open('${REPO_ROOT}/.cursor-plugin/plugin.json'))['version'])")"
CURSOR_HOME="${CURSOR_HOME:-${HOME}/.cursor}"
CURSOR_MARKETPLACE_NAME="${CURSOR_MARKETPLACE_NAME:-alo-labs-sidekick}"
CURSOR_MARKETPLACE_ROOT="${CURSOR_HOME}/plugins/marketplaces/${CURSOR_MARKETPLACE_NAME}"
DEST_ROOT="${CURSOR_HOME}/plugins/cache/alo-labs/sidekick/${VERSION}"
MERGE_HOOKS="${REPO_ROOT}/scripts/merge-cursor-hooks.py"
RENDERER="${REPO_ROOT}/scripts/render-agent-bundle.py"
MERGE_ONLY=0
MERGE_HOOKS_FLAG=0
REGISTER_CLAUDE_IMPORT=1

usage() {
  cat <<'USAGE'
Usage: scripts/install-cursor.sh [--merge-hooks-only] [--merge-hooks] [--no-register-claude-import]

  --merge-hooks-only           Only merge hooks from the current install path
  --merge-hooks                Merge Sidekick hooks into ~/.cursor/hooks.json
  --no-register-claude-import  Skip adding sidekick@alo-labs to Claude installed_plugins.json
USAGE
}

sync_plugin_tree_from_checkout() {
  local source_root="$1"
  local version="$2"
  local dest="${CURSOR_HOME}/plugins/cache/alo-labs/sidekick/${version}"

  mkdir -p "${dest}"
  rsync -a --delete \
    --exclude '.git' \
    --exclude '.planning' \
    --exclude 'tests' \
    --exclude 'site' \
    --exclude '.kay' \
    "${source_root}/" "${dest}/"
  printf '%s\n' "$dest"
}

register_local_marketplace() {
  mkdir -p "$(dirname "${CURSOR_MARKETPLACE_ROOT}")"
  if [[ -e "${CURSOR_MARKETPLACE_ROOT}" && ! -L "${CURSOR_MARKETPLACE_ROOT}" ]]; then
    printf 'WARN: marketplace path exists and is not a symlink: %s\n' "${CURSOR_MARKETPLACE_ROOT}" >&2
    return 0
  fi
  ln -sfn "${REPO_ROOT}" "${CURSOR_MARKETPLACE_ROOT}"
}

register_claude_import() {
  local plugins_file="${HOME}/.claude/plugins/installed_plugins.json"
  local marketplace_file="${HOME}/.claude/plugins/known_marketplaces.json"
  mkdir -p "$(dirname "${plugins_file}")"
  [[ -f "${plugins_file}" ]] || printf '{"version":2,"plugins":{}}\n' >"${plugins_file}"

  python3 - "${plugins_file}" "${marketplace_file}" "${DEST_ROOT}" "${VERSION}" "${REPO_ROOT}" <<'PY'
import json
import sys
from datetime import datetime, timezone

plugins_path, marketplaces_path, install_path, version, repo_root = sys.argv[1:6]
now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

with open(plugins_path, encoding="utf-8") as handle:
    data = json.load(handle)

plugins = data.setdefault("plugins", {})
plugins["sidekick@alo-labs"] = [{
    "scope": "user",
    "installPath": install_path,
    "version": version,
    "installedAt": now,
    "lastUpdated": now,
}]

with open(plugins_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")

if marketplaces_path:
    try:
        with open(marketplaces_path, encoding="utf-8") as handle:
            marketplaces = json.load(handle)
    except FileNotFoundError:
        marketplaces = {}
    marketplaces.setdefault("sidekick-local", {
        "source": {"source": "directory", "path": repo_root},
        "installLocation": repo_root,
        "lastUpdated": now,
    })
    with open(marketplaces_path, "w", encoding="utf-8") as handle:
        json.dump(marketplaces, handle, indent=2)
        handle.write("\n")
PY
}

for arg in "$@"; do
  case "$arg" in
    --merge-hooks-only) MERGE_ONLY=1; MERGE_HOOKS_FLAG=1 ;;
    --merge-hooks) MERGE_HOOKS_FLAG=1 ;;
    --register-claude-import) REGISTER_CLAUDE_IMPORT=1 ;;
    --no-register-claude-import) REGISTER_CLAUDE_IMPORT=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage; exit 2 ;;
  esac
done

if [[ "$MERGE_ONLY" -eq 0 ]]; then
  bash "${REPO_ROOT}/scripts/sync-host-surfaces.sh"
  mkdir -p "${REPO_ROOT}/agents"
  DEST_ROOT="$(sync_plugin_tree_from_checkout "${REPO_ROOT}" "${VERSION}")"
  register_local_marketplace
  if [[ "${REGISTER_CLAUDE_IMPORT}" -eq 1 ]]; then
    register_claude_import
  fi
else
  DEST_ROOT="${CURSOR_HOME}/plugins/cache/alo-labs/sidekick/current"
  if [[ ! -d "$DEST_ROOT" ]]; then
    printf 'ERROR: no installed Cursor plugin at %s; run without --merge-hooks-only first\n' "$DEST_ROOT" >&2
    exit 1
  fi
fi

if [[ "${MERGE_HOOKS_FLAG}" -eq 1 ]]; then
  python3 "${MERGE_HOOKS}" "${DEST_ROOT}"
  printf '  hooks merged into: %s/hooks.json\n' "${CURSOR_HOME}"
  if python3 - "${CURSOR_HOME}/hooks.json" "${DEST_ROOT}" <<'PY'
import json
import os
import sys

hooks_path, install_path = sys.argv[1:3]
data = json.load(open(hooks_path))
entries = data.get("hooks", {}).get("preToolUse", [])
sidekick = [entry for entry in entries if "codex-delegation-enforcer.sh" in entry.get("command", "")]
if len(sidekick) != 1:
    raise SystemExit(f"expected 1 Sidekick preToolUse hook, found {len(sidekick)}")
command = sidekick[0].get("command", "")
if install_path not in command:
    raise SystemExit(f"Sidekick hook command does not reference install path: {command}")
if sidekick[0].get("failClosed") is not False:
    raise SystemExit("Sidekick preToolUse hook must set failClosed to false")
script = command.rsplit("bash ", 1)[-1].strip().strip('"')
if not os.path.isfile(script):
    raise SystemExit(f"Sidekick hook script missing: {script}")
if not os.access(script, os.R_OK):
    raise SystemExit(f"Sidekick hook script not readable: {script}")
PY
  then
    printf '  hook registration verified (path exists, failClosed=false)\n'
  else
    printf 'ERROR: Sidekick hook registration verification failed; re-run --merge-hooks-only after enabling the plugin\n' >&2
    exit 1
  fi
else
  printf '  hooks not merged (pass --merge-hooks after enabling the plugin in Cursor)\n'
fi
if [[ "${MERGE_ONLY}" -eq 0 ]]; then
  ln -sfn "${DEST_ROOT}" "${CURSOR_HOME}/plugins/cache/alo-labs/sidekick/current"
fi

printf '\nSidekick Cursor install complete.\n'
printf '  plugin cache: %s\n' "${DEST_ROOT}"
printf '  current symlink: %s/plugins/cache/alo-labs/sidekick/current\n' "${CURSOR_HOME}"
printf '  local marketplace symlink: %s -> %s\n' "${CURSOR_MARKETPLACE_ROOT}" "${REPO_ROOT}"
printf '\nRecovery: if hooks still lock down all tools, re-run with --merge-hooks-only after reload.\n'
printf '  Stale ~/.cursor/hooks.json entries from older installs are replaced idempotently by merge-cursor-hooks.py.\n'
printf '  Set preToolUse failClosed to false (Sidekick default) so inactive hooks always allow host tools.\n'
printf '\nNext steps:\n'
printf '  1. Reload Cursor (Cmd+Shift+P → Developer: Reload Window)\n'
printf '  2. In Settings → Plugins, add marketplace https://github.com/alo-exp/sidekick if sidekick is not listed\n'
printf '  3. Enable sidekick, then reload again\n'
printf '  4. Run: bash scripts/install-cursor.sh --merge-hooks-only\n'
printf '  5. Try slash commands: kay, kay-stop, codex, codex-stop\n'

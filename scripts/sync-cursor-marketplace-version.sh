#!/usr/bin/env bash
# Bump the Sidekick entry in alo-labs-cursor-marketplace.
#
# Usage:
#   bash scripts/sync-cursor-marketplace-version.sh <version> [marketplace-repo]
#
# Default marketplace repo:
#   ~/.cursor/plugins/marketplaces/alo-labs-cursor
#   or ~/projects/alo-labs-cursor-marketplace when present

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"
if [ -z "${VERSION}" ]; then
  VERSION="$(python3 -c "import json; print(json.load(open('${ROOT}/.cursor-plugin/plugin.json'))['version'])")"
fi

MARKETPLACE_REPO="${2:-}"
if [ -z "${MARKETPLACE_REPO}" ]; then
  for candidate in \
    "${HOME}/projects/alo-labs-cursor-marketplace" \
    "${HOME}/.cursor/plugins/marketplaces/alo-labs-cursor"
  do
    if [ -f "${candidate}/.cursor-plugin/marketplace.json" ]; then
      MARKETPLACE_REPO="${candidate}"
      break
    fi
  done
fi

if [ -z "${MARKETPLACE_REPO}" ] || [ ! -f "${MARKETPLACE_REPO}/.cursor-plugin/marketplace.json" ]; then
  echo "ERROR: Cursor marketplace repo not found. Pass the checkout path as the second argument." >&2
  exit 1
fi

MARKETPLACE_FILE="${MARKETPLACE_REPO}/.cursor-plugin/marketplace.json"
SIDEKICK_ENTRY="${ROOT}/.cursor-plugin/marketplace.json"
COMMIT_SHA="$(git -C "${ROOT}" rev-parse "v${VERSION}^{commit}" 2>/dev/null || git -C "${ROOT}" rev-parse HEAD)"

python3 - "${MARKETPLACE_FILE}" "${SIDEKICK_ENTRY}" "${VERSION}" "${COMMIT_SHA}" <<'PY'
import json
import sys

marketplace_path, sidekick_entry_path, version, commit_sha = sys.argv[1:5]
marketplace = json.load(open(marketplace_path))
sidekick_template = json.load(open(sidekick_entry_path))
sidekick = next(plugin for plugin in sidekick_template["plugins"] if plugin["name"] == "sidekick")
sidekick["version"] = version
sidekick["source"]["ref"] = commit_sha

plugins = [plugin for plugin in marketplace.get("plugins", []) if plugin.get("name") != "sidekick"]
plugins.insert(0, sidekick)
marketplace["plugins"] = plugins
description = marketplace.get("metadata", {}).get("description", "")
if "Sidekick" not in description:
    marketplace.setdefault("metadata", {})["description"] = (
        "Ālo Labs plugins for Cursor — Sidekick delegation workflows and Silver Bullet orchestration"
    )

with open(marketplace_path, "w", encoding="utf-8") as handle:
    json.dump(marketplace, handle, indent=2)
    handle.write("\n")
PY

echo "Updated ${MARKETPLACE_FILE} for sidekick ${VERSION} at ${COMMIT_SHA}"

#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — post-release cleanup
# =============================================================================
# Removes non-essential transient artifacts from the local repo after a
# release is published. The cleanup list is intentionally narrow and limited
# to directories that are safe to delete between release cycles. Planning,
# spec, and design artifacts are intentionally preserved.
#
# Override SIDEKICK_REPO_ROOT in tests or ad-hoc dry runs.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAW_REPO_ROOT="${SIDEKICK_REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

if ! REPO_ROOT="$(cd "${RAW_REPO_ROOT}" && pwd -P 2>/dev/null)"; then
  echo "post-release cleanup: refusing unknown repo root: ${RAW_REPO_ROOT}" >&2
  exit 1
fi

if [ -z "${REPO_ROOT}" ] || [ "${REPO_ROOT}" = "/" ]; then
  echo "post-release cleanup: refusing unsafe repo root: ${REPO_ROOT}" >&2
  exit 1
fi

HOME_ROOT="$(cd "${HOME}" && pwd -P 2>/dev/null || true)"
if [ -n "${HOME_ROOT}" ] && [ "${REPO_ROOT}" = "${HOME_ROOT}" ]; then
  echo "post-release cleanup: refusing to run against HOME: ${REPO_ROOT}" >&2
  exit 1
fi

if ! GIT_TOP="$(git -C "${REPO_ROOT}" rev-parse --show-toplevel 2>/dev/null)"; then
  echo "post-release cleanup: refusing non-git repo root: ${REPO_ROOT}" >&2
  exit 1
fi

if ! GIT_TOP="$(cd "${GIT_TOP}" && pwd -P 2>/dev/null)"; then
  echo "post-release cleanup: refusing unresolved git root: ${REPO_ROOT}" >&2
  exit 1
fi

if [ "${GIT_TOP}" != "${REPO_ROOT}" ]; then
  echo "post-release cleanup: refusing nested or mismatched repo root: ${REPO_ROOT}" >&2
  exit 1
fi

if [ ! -f "${REPO_ROOT}/.claude-plugin/plugin.json" ] \
  || [ ! -f "${REPO_ROOT}/tests/post_release_cleanup.bash" ] \
  || [ ! -f "${REPO_ROOT}/skills/kay-delegate/SKILL.md" ] \
  || [ ! -f "${REPO_ROOT}/hooks/hooks.json" ]; then
  echo "post-release cleanup: refusing root without Sidekick repo markers: ${REPO_ROOT}" >&2
  exit 1
fi

if ! PLUGIN_NAME="$(python3 - "${REPO_ROOT}/.claude-plugin/plugin.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle).get("name", ""))
PY
)"; then
  echo "post-release cleanup: refusing unreadable plugin manifest: ${REPO_ROOT}" >&2
  exit 1
fi

if [ "${PLUGIN_NAME}" != "sidekick" ]; then
  echo "post-release cleanup: refusing non-Sidekick plugin root: ${REPO_ROOT}" >&2
  exit 1
fi

cleanup_paths=(
  ".tmp"
  ".cache"
  "target"
  "build"
  "dist"
  "coverage"
  ".pytest_cache"
  "node_modules"
  "~"
)

resolve_path() {
  python3 - "$1" <<'PY'
from pathlib import Path
import sys

print(Path(sys.argv[1]).resolve())
PY
}

removed=()
for rel in "${cleanup_paths[@]}"; do
  path="${REPO_ROOT}/${rel}"
  if [ -e "${path}" ]; then
    target_real="$(resolve_path "${path}")"
    case "${target_real}" in
      "${REPO_ROOT}"/*) ;;
      *)
        echo "post-release cleanup: refusing path outside repo root: ${rel} -> ${target_real}" >&2
        exit 1
        ;;
    esac
    rm -rf -- "${path}"
    removed+=("${rel}")
  fi
done

if [ "${#removed[@]}" -eq 0 ]; then
  echo "post-release cleanup: no transient artifacts found"
else
  echo "post-release cleanup removed: ${removed[*]}"
fi

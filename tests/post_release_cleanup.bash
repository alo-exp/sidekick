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

if [ ! -f "${REPO_ROOT}/.claude-plugin/plugin.json" ] || [ ! -f "${REPO_ROOT}/tests/post_release_cleanup.bash" ]; then
  echo "post-release cleanup: refusing root without Sidekick repo markers: ${REPO_ROOT}" >&2
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

removed=()
for rel in "${cleanup_paths[@]}"; do
  path="${REPO_ROOT}/${rel}"
  if [ -e "${path}" ]; then
    rm -rf -- "${path}"
    removed+=("${rel}")
  fi
done

if [ "${#removed[@]}" -eq 0 ]; then
  echo "post-release cleanup: no transient artifacts found"
else
  echo "post-release cleanup removed: ${removed[*]}"
fi

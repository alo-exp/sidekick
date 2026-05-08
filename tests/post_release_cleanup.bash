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
REPO_ROOT="${SIDEKICK_REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

cleanup_paths=(
  ".tmp"
  ".cache"
  "target"
  "build"
  "dist"
  "coverage"
  ".pytest_cache"
  "node_modules"
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

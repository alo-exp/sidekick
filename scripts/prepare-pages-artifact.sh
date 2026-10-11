#!/usr/bin/env bash
# Build a GitHub Pages artifact from site/ without shipping markdown sources.
# Markdown remains in the repo for authoring; HTML help pages are the public surface.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGING="${1:-${ROOT}/.pages-staging}"

rm -rf "${STAGING}"
mkdir -p "${STAGING}"

rsync -a \
  --prune-empty-dirs \
  --exclude='*.md' \
  "${ROOT}/site/" \
  "${STAGING}/"

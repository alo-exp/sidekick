#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

UI_FILE="src/public/notes-ui.js"
HTML_FILE="src/public/index.html"

fail() { echo "FAIL: $1" >&2; exit 1; }

# Check that index.html has bulkArchiveButton
if grep -q 'bulkArchiveButton' "${HTML_FILE}"; then
  echo "  OK: bulkArchiveButton found in ${HTML_FILE}"
else
  fail "No bulkArchiveButton found in ${HTML_FILE}"
fi

# Check that notes-ui.js references bulk-archive endpoint
if grep -q 'bulk-archive' "${UI_FILE}"; then
  echo "  OK: bulk-archive endpoint reference found in ${UI_FILE}"
else
  fail "No bulk-archive endpoint reference found in ${UI_FILE}"
fi

# Check that notes-ui.js wires bulkArchiveButton
if grep -q 'bulkArchiveButton' "${UI_FILE}"; then
  echo "  OK: bulkArchiveButton wired in ${UI_FILE}"
else
  fail "bulkArchiveButton not wired in ${UI_FILE}"
fi

# Check that notes-ui.js renders checkboxes for multi-select
if grep -q 'note-checkbox' "${UI_FILE}"; then
  echo "  OK: note-checkbox rendered in ${UI_FILE}"
else
  fail "note-checkbox not rendered in ${UI_FILE}"
fi

# Check that notes-ui.js has selectedIds state for tracking selections
if grep -q 'selectedIds' "${UI_FILE}"; then
  echo "  OK: selectedIds state found in ${UI_FILE}"
else
  fail "selectedIds state not found in ${UI_FILE}"
fi

echo "verify-bulk-archive-ui passed"

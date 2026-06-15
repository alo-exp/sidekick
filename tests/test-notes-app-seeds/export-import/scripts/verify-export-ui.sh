#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

UI_FILE="src/public/notes-ui.js"
HTML_FILE="src/public/index.html"

fail() { echo "FAIL: $1" >&2; exit 1; }

# Check that notes-ui.js references export endpoint
# Accept either literal path /api/notes/export or template literal ${API}/export
if grep -qE '(/api/notes/export|\$\{API\}/export)' "${UI_FILE}"; then
  echo "  OK: export endpoint reference found in ${UI_FILE}"
else
  fail "No export endpoint reference found in ${UI_FILE}"
fi

# Check that notes-ui.js references import endpoint
if grep -qE '(/api/notes/import|\$\{API\}/import)' "${UI_FILE}"; then
  echo "  OK: import endpoint reference found in ${UI_FILE}"
else
  fail "No import endpoint reference found in ${UI_FILE}"
fi

# Check that index.html has export button
if grep -q 'exportButton' "${HTML_FILE}"; then
  echo "  OK: exportButton found in ${HTML_FILE}"
else
  fail "No exportButton found in ${HTML_FILE}"
fi

# Check that index.html has import input
if grep -q 'importInput' "${HTML_FILE}"; then
  echo "  OK: importInput found in ${HTML_FILE}"
else
  fail "No importInput found in ${HTML_FILE}"
fi

# Check that notes-ui.js wires export button
if grep -q 'exportButton' "${UI_FILE}"; then
  echo "  OK: exportButton wired in ${UI_FILE}"
else
  fail "exportButton not wired in ${UI_FILE}"
fi

# Check that notes-ui.js wires import input
if grep -q 'importInput' "${UI_FILE}"; then
  echo "  OK: importInput wired in ${UI_FILE}"
else
  fail "importInput not wired in ${UI_FILE}"
fi

echo "verify-export-ui passed"

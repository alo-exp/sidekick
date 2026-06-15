#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

UI_FILE="src/public/notes-ui.js"
HTML_FILE="src/public/index.html"

fail() { echo "FAIL: $1" >&2; exit 1; }

# Check that index.html has sort select
if grep -q 'sortSelect' "${HTML_FILE}"; then
  echo "  OK: sortSelect found in ${HTML_FILE}"
else
  fail "No sortSelect found in ${HTML_FILE}"
fi

# Check that notes-ui.js references sort query param
if grep -q "params.set('sort'" "${UI_FILE}"; then
  echo "  OK: sort param in currentQueryParams found in ${UI_FILE}"
else
  fail "No sort param reference found in ${UI_FILE}"
fi

# Check that notes-ui.js wires sortSelect
if grep -q 'sortSelect' "${UI_FILE}"; then
  echo "  OK: sortSelect wired in ${UI_FILE}"
else
  fail "sortSelect not wired in ${UI_FILE}"
fi

# Check that sortSelect has both updated_desc and title_asc options in HTML
if grep -q 'updated_desc' "${HTML_FILE}" && grep -q 'title_asc' "${HTML_FILE}"; then
  echo "  OK: sort options (updated_desc, title_asc) present in ${HTML_FILE}"
else
  fail "Sort options not fully present in ${HTML_FILE}"
fi

# Check that API route handles sort parameter
ROUTE_FILE="src/routes/notes.js"
if grep -q 'SORT_MAP' "${ROUTE_FILE}" && grep -q 'req.query.sort' "${ROUTE_FILE}"; then
  echo "  OK: sort parameter handling found in ${ROUTE_FILE}"
else
  fail "Sort parameter not handled in ${ROUTE_FILE}"
fi

echo "verify-sort-ui passed"

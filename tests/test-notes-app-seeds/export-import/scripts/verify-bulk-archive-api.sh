#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-3458}"
export PORT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [ ! -d node_modules ]; then
  echo "node_modules missing; run npm install first" >&2
  exit 1
fi

export NOTES_APP_DB_PATH="${ROOT}/data/verify-bulk-archive-api.db"
rm -rf "$(dirname "${NOTES_APP_DB_PATH}")"
mkdir -p "$(dirname "${NOTES_APP_DB_PATH}")"

node src/server.js &
server_pid=$!
trap 'kill "${server_pid}" 2>/dev/null || true; wait "${server_pid}" 2>/dev/null || true' EXIT

ready=0
for _ in $(seq 1 40); do
  if curl -sf "http://127.0.0.1:${PORT}/api/health" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.25
done

if [ "${ready}" -ne 1 ]; then
  echo "server did not become ready on port ${PORT}" >&2
  exit 1
fi

# Create three notes
curl -sf -X POST "http://127.0.0.1:${PORT}/api/notes" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Bulk Test A","body":"alpha"}' > /dev/null

curl -sf -X POST "http://127.0.0.1:${PORT}/api/notes" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Bulk Test B","body":"beta"}' > /dev/null

curl -sf -X POST "http://127.0.0.1:${PORT}/api/notes" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Bulk Test C","body":"gamma"}' > /dev/null

# Test 1: bulk-archive with valid ids
archive_json="$(curl -sf -X POST "http://127.0.0.1:${PORT}/api/notes/bulk-archive" \
  -H 'Content-Type: application/json' \
  -d '{"ids":[1,3]}')"

case "${archive_json}" in
  *'"archived":2'*) ;;
  *)
    echo "POST /api/notes/bulk-archive failed: ${archive_json}" >&2
    exit 1
    ;;
esac

# Test 2: verify archived notes (order-independent)
all_notes="$(curl -sf "http://127.0.0.1:${PORT}/api/notes?archived=true")"
case "${all_notes}" in
  *'Bulk Test A'*) ;;
  *)
    echo "Bulk Test A not found in archived: ${all_notes}" >&2
    exit 1
    ;;
esac
case "${all_notes}" in
  *'Bulk Test C'*) ;;
  *)
    echo "Bulk Test C not found in archived: ${all_notes}" >&2
    exit 1
    ;;
esac

# Test 3: note 2 should NOT be archived
active_notes="$(curl -sf "http://127.0.0.1:${PORT}/api/notes?archived=false")"
case "${active_notes}" in
  *'Bulk Test B'*) ;;
  *)
    echo "Bulk Test B should still be active: ${active_notes}" >&2
    exit 1
    ;;
esac

# Test 4: missing ids returns 400
http_code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:${PORT}/api/notes/bulk-archive" \
  -H 'Content-Type: application/json' \
  -d '{}')"
if [ "${http_code}" != "400" ]; then
  echo "Expected 400 for missing ids, got ${http_code}" >&2
  exit 1
fi

# Test 5: invalid ids returns 400
http_code2="$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:${PORT}/api/notes/bulk-archive" \
  -H 'Content-Type: application/json' \
  -d '{"ids":[1,"abc",3]}')"
if [ "${http_code2}" != "400" ]; then
  echo "Expected 400 for invalid ids, got ${http_code2}" >&2
  exit 1
fi

echo "verify-bulk-archive-api passed"

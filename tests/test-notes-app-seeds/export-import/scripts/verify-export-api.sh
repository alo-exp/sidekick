#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-3457}"
export PORT
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [ ! -d node_modules ]; then
  echo "node_modules missing; run npm install first" >&2
  exit 1
fi

export NOTES_APP_DB_PATH="${ROOT}/data/verify-export-api.db"
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

# Create two notes
curl -sf -X POST "http://127.0.0.1:${PORT}/api/notes" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Export Test A","body":"alpha"}' > /dev/null

curl -sf -X POST "http://127.0.0.1:${PORT}/api/notes" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Export Test B","body":"beta"}' > /dev/null

# GET /api/notes/export
export_json="$(curl -sf "http://127.0.0.1:${PORT}/api/notes/export")"

case "${export_json}" in
  *'Export Test A'*'Export Test B'*) ;;
  *)
    echo "GET /api/notes/export failed: ${export_json}" >&2
    exit 1
    ;;
esac

# POST /api/notes/import
import_json="$(curl -sf -X POST "http://127.0.0.1:${PORT}/api/notes/import" \
  -H 'Content-Type: application/json' \
  -d '[{"title":"Imported C","body":"gamma"}]')"

case "${import_json}" in
  *'"imported":1'*'Imported C'*) ;;
  *)
    echo "POST /api/notes/import failed: ${import_json}" >&2
    exit 1
    ;;
esac

# Verify imported note appears in export
export_after="$(curl -sf "http://127.0.0.1:${PORT}/api/notes/export")"
case "${export_after}" in
  *'Imported C'*) ;;
  *)
    echo "Imported note not found in export: ${export_after}" >&2
    exit 1
    ;;
esac

echo "verify-export-api passed"

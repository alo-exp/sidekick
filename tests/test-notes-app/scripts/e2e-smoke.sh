#!/usr/bin/env bash
# Live E2E smoke checks for the Test Notes App sandbox copy.
set -euo pipefail

PORT="${PORT:?PORT is required}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

if [ ! -d node_modules ]; then
  echo "node_modules missing; run npm install first" >&2
  exit 1
fi

export PORT
export NOTES_APP_DB_PATH="${NOTES_APP_DB_PATH:-${ROOT}/data/notes.db}"
rm -rf "$(dirname "${NOTES_APP_DB_PATH}")"
mkdir -p "$(dirname "${NOTES_APP_DB_PATH}")"

node src/server.js &
server_pid=$!
trap 'kill "${server_pid}" 2>/dev/null || true; wait "${server_pid}" 2>/dev/null || true' EXIT

ready=0
for _ in $(seq 1 40); do
  if curl -sf "http://127.0.0.1:${PORT}/api/health" >/tmp/sidekick-notes-e2e-health.json 2>/dev/null; then
    ready=1
    break
  fi
  sleep 0.25
done

if [ "${ready}" -ne 1 ]; then
  echo "server did not become ready on port ${PORT}" >&2
  exit 1
fi

health_json="$(cat /tmp/sidekick-notes-e2e-health.json)"
case "${health_json}" in
  *'"status":"ok"'*) ;;
  *)
    echo "health check failed: ${health_json}" >&2
    exit 1
    ;;
esac

post_json="$(curl -sf -X POST "http://127.0.0.1:${PORT}/api/notes" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Sidekick live E2E","body":"notes API smoke"}')"
case "${post_json}" in
  *'"title":"Sidekick live E2E"'*) ;;
  *)
    echo "POST /api/notes failed: ${post_json}" >&2
    exit 1
    ;;
esac

list_json="$(curl -sf "http://127.0.0.1:${PORT}/api/notes")"
case "${list_json}" in
  *'"title":"Sidekick live E2E"'*) ;;
  *)
    echo "GET /api/notes failed: ${list_json}" >&2
    exit 1
    ;;
esac

echo "e2e-smoke passed"

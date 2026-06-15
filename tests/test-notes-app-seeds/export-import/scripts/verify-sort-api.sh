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

export NOTES_APP_DB_PATH="${ROOT}/data/verify-sort-api.db"
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

# Create notes with staggered timestamps to exercise ordering
curl -sf -X POST "http://127.0.0.1:${PORT}/api/notes" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Zebra","body":"last alphabetically"}' > /dev/null

sleep 1.1

curl -sf -X POST "http://127.0.0.1:${PORT}/api/notes" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Apple","body":"first alphabetically"}' > /dev/null

sleep 1.1

curl -sf -X POST "http://127.0.0.1:${PORT}/api/notes" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Mango","body":"middle alphabetically"}' > /dev/null

# Test updated_desc (default): newest updated first
desc_json="$(curl -sf "http://127.0.0.1:${PORT}/api/notes?sort=updated_desc")"
first_title="$(echo "${desc_json}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['title'])")"
if [ "${first_title}" != "Mango" ]; then
  echo "FAIL updated_desc: expected Mango first, got ${first_title}" >&2
  echo "Response: ${desc_json}" >&2
  exit 1
fi
echo "  OK: updated_desc returns newest first"

# Test title_asc: alphabetical by title
asc_json="$(curl -sf "http://127.0.0.1:${PORT}/api/notes?sort=title_asc")"
titles="$(echo "${asc_json}" | python3 -c "import sys,json; print(' '.join(n['title'] for n in json.load(sys.stdin)))")"
if [ "${titles}" != "Apple Mango Zebra" ]; then
  echo "FAIL title_asc: expected 'Apple Mango Zebra', got '${titles}'" >&2
  exit 1
fi
echo "  OK: title_asc returns alphabetical order"

# Test title_desc: reverse alphabetical
desc_title_json="$(curl -sf "http://127.0.0.1:${PORT}/api/notes?sort=title_desc")"
titles_rev="$(echo "${desc_title_json}" | python3 -c "import sys,json; print(' '.join(n['title'] for n in json.load(sys.stdin)))")"
if [ "${titles_rev}" != "Zebra Mango Apple" ]; then
  echo "FAIL title_desc: expected 'Zebra Mango Apple', got '${titles_rev}'" >&2
  exit 1
fi
echo "  OK: title_desc returns reverse alphabetical"

# Test updated_asc: oldest first
asc_updated_json="$(curl -sf "http://127.0.0.1:${PORT}/api/notes?sort=updated_asc")"
first_title_asc="$(echo "${asc_updated_json}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['title'])")"
if [ "${first_title_asc}" != "Zebra" ]; then
  echo "FAIL updated_asc: expected Zebra first, got ${first_title_asc}" >&2
  exit 1
fi
echo "  OK: updated_asc returns oldest first"

echo "verify-sort-api passed"

#!/usr/bin/env bash
# Rebuild tests/test-notes-app-seeds/export-import with export + bulk-archive + sort via Kay.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${ROOT}/tests/run_kay_live_task.bash"
SEED="${ROOT}/tests/test-notes-app-seeds/export-import"
PROMPTS="${ROOT}/tests/kay-live-prompts"

copy_sandbox_to_seed() {
  local task_id="$1"
  local log meta sb
  log="$(ls -t "${ROOT}/tests/.kay-live-logs/${task_id}-"*.log 2>/dev/null | head -1)"
  meta="${log%.log}.meta"
  if [ -f "${meta}" ]; then
    sb="$(grep '^sandbox=' "${meta}" | tail -1 | cut -d= -f2-)"
  else
    sb="$(grep '^sandbox=' "${log}" 2>/dev/null | tail -1 | cut -d= -f2-)"
  fi
  if [ -z "${sb}" ] || [ ! -d "${sb}" ]; then
    echo "FAIL: could not find sandbox for ${task_id} (meta=${meta} log=${log})" >&2
    exit 1
  fi
  echo "Copying ${sb} -> ${SEED}"
  rsync -a --delete \
    --exclude='node_modules' \
    --exclude='data' \
    --exclude='.git' \
    --exclude='.kay' \
    "${sb}/" "${SEED}/"
}

run_kay() {
  local id="$1" prompt="$2" max="${3:-900}"
  export SIDEKICK_KAY_SEED_DIR="${SEED}"
  export SIDEKICK_KAY_REQUIRE_STATUS=1
  export SIDEKICK_KAY_HOST_VERIFY=1
  bash "${RUNNER}" "${id}" "${prompt}" "${max}"
}

chmod +x "${RUNNER}"

# Ensure base export seed exists
if [ ! -f "${SEED}/scripts/verify-export-api.sh" ]; then
  echo "Base seed missing; run task7-seed-build first" >&2
  exit 1
fi

echo "=== Kay: bulk archive on seed ==="
run_kay task8-seed-refresh "${PROMPTS}/task8-bulk-archive.txt" 900
copy_sandbox_to_seed task8-seed-refresh

echo "=== Kay: sort API/UI on seed ==="
run_kay task9-seed-refresh "${PROMPTS}/task9-sort-ui-retry2.txt" 600
copy_sandbox_to_seed task9-seed-refresh

echo "=== Host verify all scripts in seed ==="
( cd "${SEED}" && npm install --silent )
shopt -s nullglob
for vs in "${SEED}"/scripts/verify-*.sh; do
  echo "Running $(basename "${vs}")"
  ( cd "${SEED}" && bash "${vs}" )
done
shopt -u nullglob

echo "SEED_REFRESH_OK ${SEED}"
ls -1 "${SEED}"/scripts/verify-*.sh

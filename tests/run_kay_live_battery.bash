#!/usr/bin/env bash
# Run Kay live prompts sequentially with STATUS + host-verify gates.
# Usage: bash tests/run_kay_live_battery.bash [task_spec ...]
#   task_spec = id:prompt_file:max_seconds[:seed_dir]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="${SCRIPT_DIR}/run_kay_live_task.bash"
KNOWN_ISSUES="39|42|43|44|45|46|47|48|49|50|51"
FAILURES=0
NEW_ISSUE_HINTS=""

run_task() {
  local spec="$1"
  IFS=: read -r id prompt max seed <<<"${spec}:::"
  max="${max:-600}"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "BATTERY ${id} (max=${max}s)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if [ -n "${seed}" ] && [ -d "${seed}" ]; then
    export SIDEKICK_KAY_SEED_DIR="${seed}"
  else
    unset SIDEKICK_KAY_SEED_DIR
  fi
  export SIDEKICK_KAY_REQUIRE_STATUS=1
  export SIDEKICK_KAY_HOST_VERIFY=1
  set +e
  bash "${RUNNER}" "${id}" "${prompt}" "${max}"
  local rc=$?
  set -e
  if [[ "${rc}" -ne 0 ]]; then
    FAILURES=$((FAILURES + 1))
  fi
  local log
  log="$(ls -t "${SCRIPT_DIR}/.kay-live-logs/${id}-"*.log 2>/dev/null | head -1)"
  if [ -n "${log}" ]; then
    while IFS= read -r line; do
      case "${line}" in
        *Invalid\ patch*|*Failed\ to\ find\ context*|*EPERM*|*executable\ not\ found*|*command\ not\ found*|*Command\ guard*)
          NEW_ISSUE_HINTS="${NEW_ISSUE_HINTS}${id}: ${line}"$'\n'
          ;;
      esac
    done < <(grep -iE 'Invalid patch|Failed to find context|listen EPERM|executable not found|command not found|Command guard' "${log}" 2>/dev/null | head -5)
  fi
  return "${rc}"
}

if [ "$#" -gt 0 ]; then
  SPECS=("$@")
else
  SEED="${SCRIPT_DIR}/test-notes-app-seeds/export-import"
  SPECS=(
    "task7-retry2:${SCRIPT_DIR}/kay-live-prompts/task7-retry2-closeout.txt:90:${SEED}"
    "task8-bulk-archive:${SCRIPT_DIR}/kay-live-prompts/task8-bulk-archive.txt:900"
    "task9-sort-ui:${SCRIPT_DIR}/kay-live-prompts/task9-sort-ui.txt:900"
  )
fi

chmod +x "${RUNNER}"
for spec in "${SPECS[@]}"; do
  run_task "${spec}" || true
done

echo ""
echo "═══════════════════════════════════════════"
if [[ "${FAILURES}" -eq 0 ]]; then
  echo "BATTERY PASSED (all tasks)"
  exit 0
fi
echo "BATTERY FAILED (${FAILURES} task(s))"
if [ -n "${NEW_ISSUE_HINTS}" ]; then
  echo "--- log hints for Kay issues ---"
  printf '%s' "${NEW_ISSUE_HINTS}"
fi
exit 1

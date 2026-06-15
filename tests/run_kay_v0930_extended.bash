#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
LOG_DIR="$ROOT/tests/.kay-live-logs"
SUMMARY="$LOG_DIR/v0930-campaign-summary.tsv"
SEED="$ROOT/tests/test-notes-app-seeds/export-import"
PROMPTS="$ROOT/tests/kay-live-prompts"

run_one() {
  local profile="$1" task="$2" prompt="$3" max="$4" seed="${5:-}"
  local tid="${profile}-v0930-ext-${task}"
  local mp model
  if [ "$profile" = ocg ]; then mp=opencode-go; model=mimo-v2.5-pro; else mp=minimax; model=minimax/MiniMax-M3; fi
  # pin-ui may use browser/CDP (image turns); kay-delegate routes vision to mimo-v2.5 not pro
  if [ "$profile" = ocg ] && [ "$task" = task4-pin-ui ]; then
    model=mimo-v2.5
  fi
  export KAY_LIVE_MODEL_PROVIDER="$mp" KAY_LIVE_MODEL="$model"
  set +e
  env SIDEKICK_KAY_REQUIRE_STATUS=1 SIDEKICK_KAY_HOST_VERIFY=1 \
    bash tests/run_kay_live_task.bash "$tid" "$prompt" "$max"
  local rc=$?
  set +e
  local log lm kay_rc st hostv
  log="$(ls -t "$LOG_DIR/${tid}-"*.log 2>/dev/null | head -1)"
  lm="$LOG_DIR/${tid}-last-message.txt"
  kay_rc="$(grep -aE '^kay_rc=' "$log" 2>/dev/null | tail -1 | sed 's/kay_rc=//')"
  hostv="$(grep -c '^PASS host_verify' "$log" 2>/dev/null)"; hostv="${hostv:-0}"
  if [ "$rc" -eq 0 ]; then st=PASS; else st=FAIL; fi
  prof_label=$([ "$profile" = ocg ] && echo OCG || echo MiniMax)
  printf '%s\text-%s\t%s\t%s\t%s\t%s\n' "$prof_label" "$task" "${kay_rc:-?}" "$st" "$hostv" "$rc" >>"$SUMMARY"
}

for profile in ocg minimax; do
  run_one "$profile" task1-stats "$PROMPTS/task1-stats.txt" 600
  run_one "$profile" task2-pagination "$PROMPTS/task2-pagination.txt" 600
  run_one "$profile" task3-middleware "$PROMPTS/task3-middleware.txt" 600
  run_one "$profile" task4-pin-ui "$PROMPTS/task4-pin-ui.txt" 600
  run_one "$profile" task5-rate-limit-docs "$PROMPTS/task5-rate-limit-docs.txt" 600
  run_one "$profile" task6-hardening "$PROMPTS/task6-hardening.txt" 900
done
echo "extended pass complete"

#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
LOG_DIR="$ROOT/tests/.kay-live-logs"
mkdir -p "$LOG_DIR"
SUMMARY="$LOG_DIR/v0927-campaign-summary.tsv"
printf 'profile\ttest\tkay_rc\tstatus\thost_verify\trc\n' >"$SUMMARY"

run_e2e() {
  local profile="$1" model_provider="$2" model="$3" tag="$4"
  local log="$LOG_DIR/${profile}-v0927-e2e-${tag}-$(date +%Y%m%dT%H%M%S).log"
  set +e
  KAY_LIVE_MODEL_PROVIDER="$model_provider" KAY_LIVE_MODEL="$model" \
    SIDEKICK_LIVE_CODEX=1 bash tests/run_live_codex_e2e.bash >"$log" 2>&1
  local rc=$?
  set -e
  local kay_rc status hostv
  kay_rc="$(grep -E '^kay rc=' "$log" | tail -1 | sed 's/kay rc=//')"
  if grep -q 'LIVE E2E PASSED' "$log"; then status=PASS; else status=FAIL; fi
  hostv="$(grep -c 'PASS e2e_smoke_passes_after_fix' "$log" || true)"
  printf '%s\te2e-%s\t%s\t%s\t%s\t%s\n' "$profile" "$tag" "${kay_rc:-?}" "$status" "$hostv" "$rc" >>"$SUMMARY"
}

run_battery() {
  local profile="$1" model_provider="$2" model="$3"
  export KAY_LIVE_MODEL_PROVIDER="$model_provider" KAY_LIVE_MODEL="$model"
  local SEED="$ROOT/tests/test-notes-app-seeds/export-import"
  local log="$LOG_DIR/${profile}-v0927-battery-$(date +%Y%m%dT%H%M%S).log"
  set +e
  bash tests/run_kay_live_battery.bash \
    "${profile}-v0927-task7-retry2:$ROOT/tests/kay-live-prompts/task7-retry2-closeout.txt:90:$SEED" \
    "${profile}-v0927-task8-bulk-archive:$ROOT/tests/kay-live-prompts/task8-bulk-archive.txt:900" \
    "${profile}-v0927-task9-sort-ui:$ROOT/tests/kay-live-prompts/task9-sort-ui.txt:900" \
    >"$log" 2>&1
  local rc=$?
  set -e
  for id in task7-retry2 task8-bulk-archive task9-sort-ui; do
    local tid="${profile}-v0927-${id}"
    local tlog
    tlog="$(ls -t "$LOG_DIR/${tid}-"*.log 2>/dev/null | head -1 || true)"
    local kay_rc st hv
    kay_rc="$(grep -E '^kay_rc=' "$tlog" 2>/dev/null | tail -1 | sed 's/kay_rc=//')"
  if [ -f "$LOG_DIR/${tid}-last-message.txt" ] && grep -q 'STATUS: SUCCESS' "$LOG_DIR/${tid}-last-message.txt" 2>/dev/null; then st=PASS; else st=FAIL; fi
    hv="$(grep -c '^PASS host_verify' "$tlog" 2>/dev/null || echo 0)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$profile" "$id" "${kay_rc:-?}" "$st" "$hv" "${rc}" >>"$SUMMARY"
  done
}

run_task10() {
  local profile="$1" model_provider="$2" model="$3"
  export KAY_LIVE_MODEL_PROVIDER="$model_provider" KAY_LIVE_MODEL="$model"
  local tid="${profile}-v0927-task10-full-regression"
  local log="$LOG_DIR/${tid}-$(date +%Y%m%dT%H%M%S).log"
  set +e
  SIDEKICK_KAY_SEED_DIR="$ROOT/tests/test-notes-app-seeds/export-import" \
    bash tests/run_kay_live_task.bash "$tid" \
    "$ROOT/tests/kay-live-prompts/task10-full-regression.txt" 600 >"$log" 2>&1
  local rc=$?
  set -e
  local kay_rc st hv
  kay_rc="$(grep -E '^kay_rc=' "$log" | tail -1 | sed 's/kay_rc=//')"
  if grep -q 'STATUS: SUCCESS' "$LOG_DIR/${tid}-last-message.txt" 2>/dev/null; then st=PASS; else st=FAIL; fi
  hv="$(grep -c '^PASS host_verify' "$log" || echo 0)"
  printf '%s\ttask10\t%s\t%s\t%s\t%s\n' "$profile" "${kay_rc:-?}" "$st" "$hv" "$rc" >>"$SUMMARY"
}

for profile in ocg minimax; do
  if [ "$profile" = ocg ]; then
    mp=opencode-go; m=mimo-v2.5-pro
    run_e2e ocg opencode-go opencode-go/deepseek-v4-flash deepseek
    run_e2e ocg opencode-go mimo-v2.5-pro mimo
  else
    mp=minimax; m=minimax/MiniMax-M3
    run_e2e minimax minimax minimax/MiniMax-M3 primary
  fi
  run_battery "$profile" "$mp" "$m"
  run_task10 "$profile" "$mp" "$m"
done
echo "Campaign done. Summary: $SUMMARY"

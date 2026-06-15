#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
LOG_DIR="$ROOT/tests/.kay-live-logs"
REPORT="$LOG_DIR/v0930-issue-report.tsv"
SUMMARY="$LOG_DIR/v0930-campaign-summary.tsv"
KAY_VER="0.9.30"
REPO="alo-labs/kay"
SEED="$ROOT/tests/test-notes-app-seeds/export-import"
PICK_PY="$LOG_DIR/_pick_log.py"
LOCK="$LOG_DIR/v0930-report.lock"
mkdir -p "$LOG_DIR"

cat >"$PICK_PY" <<'PY'
import glob, os, re, sys
tid, log_dir = sys.argv[1], sys.argv[2]
logs = glob.glob(os.path.join(log_dir, f"{tid}-*.log"))
best, best_sc = None, -1
for p in logs:
    t = open(p, errors="replace").read()
    sc = 0
    m = re.search(r"^task=%s\b.*\blog=(\S+)" % re.escape(tid), t, re.M)
    if m and os.path.basename(m.group(1)) == os.path.basename(p):
        sc += 500
    sc += len(re.findall(r"^PASS host_verify", t, re.M)) * 25
    if "LIVE E2E" in t: sc += 200
    if "gate_failures=" in t: sc += 100
    if re.search(r"^kay_rc=|^kay rc=", t, re.M): sc += 50
    sc += os.path.getmtime(p) / 1e12
    if sc > best_sc:
        best_sc, best = sc, p
print(best or "")
PY

if [ ! -f "$REPORT" ] || [ ! -s "$REPORT" ]; then
  printf 'task_id\tprofile\tkay_rc\tstatus\taction\tissue_url\n' >"$REPORT"
fi
if [ ! -f "$SUMMARY" ] || [ ! -s "$SUMMARY" ]; then
  printf 'profile\ttest\tkay_rc\tstatus\thost_verify\trc\n' >"$SUMMARY"
fi

classify() {
  local log="$1" lm="$2"
  local text issues=()
  text="$(cat "$log" 2>/dev/null; [ -f "$lm" ] && cat "$lm")"
  grep -qE "PORT=[0-9]+: command not found|bash: PORT=" <<<"$text" && issues+=(52)
  grep -qE "status_contract|STATUS: SUCCESS missing|kay rc=0 but STATUS" <<<"$text" && issues+=(42)
  grep -qE "bash -lc.*apply_patch|apply_patch &&" <<<"$text" && issues+=(55)
  grep -q "cat -A" <<<"$text" && issues+=(39)
  grep -qE "listen EPERM|EPERM.*listen" <<<"$text" && issues+=(47)
  grep -qE "Begin Patch|apply_patch.*fail|missing Begin Patch|apply_patch '.*Begin Patch" <<<"$text" && issues+=(46)
  grep -qE "invalid.*hunk|corrupt patch" <<<"$text" && issues+=(50)
  grep -qE "Invalid kill arguments|trailing characters" <<<"$text" && issues+=(54)
  grep -qE "exit 124|timed out" <<<"$text" && issues+=(49)
  grep -qE "registry\.npmjs|ENOTFOUND.*npm" <<<"$text" && issues+=(44)
  if [ ${#issues[@]} -eq 0 ]; then echo ""; return; fi
  printf "%s\n" "${issues[@]}" | sort -nu | tr "\n" " "
}

report_task() {
  local tid="$1" profile="$2"
  local log lm kay_rc status hostv rc test_name
  test_name="${tid#*-r1-}"
  log="$(python3 "$PICK_PY" "$tid" "$LOG_DIR")"
  if [ -z "$log" ]; then
    log="$(ls -t "$LOG_DIR/${tid}-"*.log 2>/dev/null | head -1 || true)"
  fi
  lm="$LOG_DIR/${tid}-last-message.txt"
  if [ -z "$log" ] || [ ! -f "$log" ]; then
    (
      flock -x 9
      printf '%s\t%s\t?\tUNKNOWN\tnone\tnone\n' "$tid" "$profile" >>"$REPORT"
      printf '%s\t%s\t?\tUNKNOWN\t0\t2\n' "$profile" "$test_name" >>"$SUMMARY"
    ) 9>"$LOCK"
    return
  fi
  kay_rc="$(grep -E "^kay_rc=|^kay rc=" "$log" | tail -1 | sed -E 's/^kay[_ ]rc=//')"
  hostv="$(grep -c "^PASS host_verify" "$log" || true)"
  if grep -q "LIVE E2E PASSED" "$log"; then status=PASS; rc=0
  elif grep -q "LIVE E2E FAILED" "$log"; then status=FAIL; rc=1
  elif grep -q "^PASS status_contract" "$log" && ! grep -q "^FAIL " "$log"; then status=PASS; rc=0
  elif grep -q "^FAIL " "$log"; then status=FAIL; rc=1
  elif grep -q "gate_failures=0" "$log"; then status=PASS; rc=0
  elif grep -q "gate_failures=" "$log"; then status=FAIL; rc=1
  else status=UNKNOWN; rc=2
  fi
  local issue_nums action url logbase evidence body n excerpt
  logbase="$(basename "$log")"
  issue_nums="$(classify "$log" "$lm")"
  action=none
  url=n/a
  issue_nums="${issue_nums%% }"
  if [ -n "$issue_nums" ]; then
    for n in $issue_nums; do
      if gh issue list -R "$REPO" --search "issue:$n" --limit 1 2>/dev/null | grep -q "^$n"; then
        evidence="$(grep -E "PORT=|status_contract|STATUS:|apply_patch|EPERM|124|kill arguments" "$log" 2>/dev/null | tail -1 | head -c 200 || echo "see ${logbase}")"
        body="**Sidekick live v0.9.30 r1** — kay ${KAY_VER}

- **task_id:** \`${tid}\`
- **profile:** ${profile}
- **kay_rc:** ${kay_rc:-?}
- **STATUS:** ${status}
- **evidence:** ${evidence}
- **log:** \`${logbase}\`

triage: sidekick-repo docs/knowledge/2026-06.md"
        gh issue comment "$n" -R "$REPO" --body "$body" >/dev/null 2>&1 || true
        url="https://github.com/${REPO}/issues/${n}"
        action="comment#${n}"
      fi
    done
  elif [ "$status" = FAIL ]; then
    excerpt="$(tail -40 "$log" | sed -E 's/sk-[A-Za-z0-9_-]+/[REDACTED]/g' | head -c 3500)"
    if url="$(gh issue create -R "$REPO" --title "Sidekick r1 ${tid} (${profile}, kay ${KAY_VER})" --label "third-party-model-compat" --body "## Repro
task: \`${tid}\` profile: ${profile}

\`\`\`
${excerpt}
\`\`\`" 2>/dev/null)"; then
      action=file-new
    else
      action=file-new-failed
      url=none
    fi
  fi
  (
    flock -x 9
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$tid" "$profile" "${kay_rc:-?}" "$status" "$action" "$url" >>"$REPORT"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$profile" "$test_name" "${kay_rc:-?}" "$status" "$hostv" "$rc" >>"$SUMMARY"
  ) 9>"$LOCK"
}

run_worker() {
  local profile="$1" tid="$2" kind="$3"
  local mp model log
  if [ "$profile" = ocg ]; then mp=opencode-go; model=mimo-v2.5-pro
  else mp=minimax; model=minimax/MiniMax-M3
  fi
  export KAY_LIVE_MODEL_PROVIDER="$mp" KAY_LIVE_MODEL="$model"
  log="$LOG_DIR/${tid}-$(date +%Y%m%dT%H%M%S).log"
  set +e
  case "$kind" in
    e2e)
      SIDEKICK_LIVE_CODEX=1 bash tests/run_live_codex_e2e.bash >"$log" 2>&1
      ;;
    task7)
      SIDEKICK_KAY_SEED_DIR="$SEED" SIDEKICK_KAY_REQUIRE_STATUS=1 SIDEKICK_KAY_HOST_VERIFY=1 \
        bash tests/run_kay_live_task.bash "$tid" "$ROOT/tests/kay-live-prompts/task7-retry2-closeout.txt" 90 >>"$log" 2>&1
      ;;
    task8)
      SIDEKICK_KAY_REQUIRE_STATUS=1 SIDEKICK_KAY_HOST_VERIFY=1 \
        bash tests/run_kay_live_task.bash "$tid" "$ROOT/tests/kay-live-prompts/task8-bulk-archive.txt" 900 >>"$log" 2>&1
      ;;
    task9)
      SIDEKICK_KAY_REQUIRE_STATUS=1 SIDEKICK_KAY_HOST_VERIFY=1 \
        bash tests/run_kay_live_task.bash "$tid" "$ROOT/tests/kay-live-prompts/task9-sort-ui.txt" 900 >>"$log" 2>&1
      ;;
    task10)
      SIDEKICK_KAY_SEED_DIR="$SEED" SIDEKICK_KAY_REQUIRE_STATUS=1 SIDEKICK_KAY_HOST_VERIFY=1 \
        bash tests/run_kay_live_task.bash "$tid" "$ROOT/tests/kay-live-prompts/task10-full-regression.txt" 600 >>"$log" 2>&1
      ;;
  esac
  set +e
  local prof_label
  if [ "$profile" = ocg ]; then prof_label=OCG; else prof_label=MiniMax; fi
  report_task "$tid" "$prof_label" || true
}

for profile in ocg minimax; do
  run_worker "$profile" "${profile}-v0930-r1-e2e" e2e &
  run_worker "$profile" "${profile}-v0930-r1-task7" task7 &
  run_worker "$profile" "${profile}-v0930-r1-task8" task8 &
  run_worker "$profile" "${profile}-v0930-r1-task9" task9 &
  run_worker "$profile" "${profile}-v0930-r1-task10" task10 &
done
wait
echo "v0930 r1 campaign complete: $SUMMARY"

#!/usr/bin/env bash
# Reusable Kay release live-test matrix (profiles × tasks).
# Usage:
#   KAY_RELEASE=v0.9.31 KAY_MATRIX_PREFIX=v0931 KAY_MATRIX_PARALLEL=1 \
#     bash tests/run_kay_release_matrix.bash
#
# Env:
#   KAY_RELEASE          — target Kay version (optional install via official install.sh)
#   KAY_MATRIX_PREFIX    — log/report prefix (default: derived from KAY_RELEASE, e.g. v0931)
#   KAY_MATRIX_PROFILES  — override profile list (see tests/kay-live-matrix.md)
#   KAY_MATRIX_TASKS     — space-separated tasks (default: e2e task7 task8 task9 task10)
#   KAY_MATRIX_PARALLEL  — 1 = run jobs in parallel subshells (default: 0)
#   KAY_MATRIX_SKIP_INSTALL — 1 = skip curl install even when KAY_RELEASE is set
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.local/bin:${PATH}"
LOG_DIR="$ROOT/tests/.kay-live-logs"
REPO="alo-labs/kay"
SEED="$ROOT/tests/test-notes-app-seeds/export-import"
PROMPTS="$ROOT/tests/kay-live-prompts"

KAY_RELEASE="${KAY_RELEASE:-}"
KAY_MATRIX_PREFIX="${KAY_MATRIX_PREFIX:-}"
if [ -z "$KAY_MATRIX_PREFIX" ] && [ -n "$KAY_RELEASE" ]; then
  KAY_MATRIX_PREFIX="${KAY_RELEASE#v}"
  KAY_MATRIX_PREFIX="v${KAY_MATRIX_PREFIX//./}"
fi
KAY_MATRIX_PREFIX="${KAY_MATRIX_PREFIX:-matrix}"
KAY_MATRIX_TASKS="${KAY_MATRIX_TASKS:-e2e task7 task8 task9 task10}"
KAY_MATRIX_PARALLEL="${KAY_MATRIX_PARALLEL:-0}"
KAY_MATRIX_SKIP_INSTALL="${KAY_MATRIX_SKIP_INSTALL:-0}"

KAY_VER="${KAY_RELEASE#v}"
[ -n "$KAY_VER" ] || KAY_VER="$(kay --version 2>/dev/null | awk '{print $2}' || echo unknown)"

REPORT="$LOG_DIR/${KAY_MATRIX_PREFIX}-issue-report.tsv"
SUMMARY="$LOG_DIR/${KAY_MATRIX_PREFIX}-matrix-summary.tsv"
LOCK="$LOG_DIR/${KAY_MATRIX_PREFIX}-report.lock"
LOCKDIR="${LOCK}.d"

with_report_lock() {
  while ! mkdir "${LOCKDIR}" 2>/dev/null; do sleep 0.05; done
  trap 'rmdir "${LOCKDIR}" 2>/dev/null || true' RETURN
  "$@"
}
PICK_PY="$LOG_DIR/_pick_log.py"
mkdir -p "$LOG_DIR"

DEFAULT_PROFILES=$'ocg-minimax-m3:opencode-go:minimax-m3\nocg-mimo-pro:opencode-go:mimo-v2.5-pro\nocg-mimo:opencode-go:mimo-v2.5\nminimax-m3:minimax:minimax/MiniMax-M3'
KAY_MATRIX_PROFILES="${KAY_MATRIX_PROFILES:-$DEFAULT_PROFILES}"

install_kay_if_needed() {
  [ -n "$KAY_RELEASE" ] || return 0
  [ "$KAY_MATRIX_SKIP_INSTALL" = 1 ] && return 0
  local want="${KAY_RELEASE#v}"
  local cur
  cur="$(kay --version 2>/dev/null | awk '{print $2}' || true)"
  if [ "$cur" = "$want" ]; then
    echo "kay already at ${want}"
    return 0
  fi
  echo "Installing kay ${KAY_RELEASE} (current: ${cur:-none})"
  curl -fsSL "https://raw.githubusercontent.com/${REPO}/${KAY_RELEASE}/scripts/install/install.sh" | bash -s -- --release "$KAY_RELEASE"
  export PATH="${HOME}/.local/bin:${PATH}"
  kay --version
}

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

init_tsv() {
  if [ ! -f "$REPORT" ] || [ ! -s "$REPORT" ]; then
    printf 'task_id\tprofile_id\tprovider\tmodel\tkay_rc\tstatus\taction\tissue_url\n' >"$REPORT"
  fi
  if [ ! -f "$SUMMARY" ] || [ ! -s "$SUMMARY" ]; then
    printf 'profile_id\tprovider\tmodel\ttest\tkay_rc\tstatus\thost_verify\trc\n' >"$SUMMARY"
  fi
}

kay_issue_exists() {
  local n="$1"
  gh issue view "$n" -R "$REPO" --json number -q .number 2>/dev/null | grep -qE '^[0-9]+$'
}

# Map log + last-message text to one parent Kay issue (priority order).
classify_primary() {
  local log="$1" lm="$2"
  local text
  text="$(cat "$log" 2>/dev/null; [ -f "$lm" ] && cat "$lm")"
  grep -qE "PORT=[0-9]+: command not found|bash: PORT=" <<<"$text" && { echo 52; return; }
  grep -qE "Begin Patch|apply_patch.*fail|missing Begin Patch|apply_patch '.*Begin Patch" <<<"$text" && { echo 46; return; }
  grep -qE "FAIL host_verify.*verify-bulk|verify-bulk-archive.*(fail|exited non-zero)|verify-bulk.*exited non-zero" <<<"$text" && { echo 46; return; }
  grep -qE "^kay_rc=124|^kay rc=124|^kay_rc=143|^kay rc=143|exit 124|timed out|Time budget exceeded" <<<"$text" && { echo 49; return; }
  grep -qE "status_contract|STATUS: SUCCESS missing|kay rc=0 but STATUS|Final status contract|did not start with .STATUS" <<<"$text" && { echo 42; return; }
  grep -qE "bash -lc.*apply_patch|apply_patch &&" <<<"$text" && { echo 55; return; }
  grep -q "cat -A" <<<"$text" && { echo 39; return; }
  grep -qE "Invalid kill arguments|trailing characters" <<<"$text" && { echo 54; return; }
  grep -qE "listen EPERM|EPERM.*listen" <<<"$text" && { echo 47; return; }
  grep -qE "invalid.*hunk|corrupt patch" <<<"$text" && { echo 50; return; }
  grep -qE "registry\.npmjs|ENOTFOUND.*npm" <<<"$text" && { echo 44; return; }
  grep -qE "unsupported model|Unsupported model" <<<"$text" && { echo 45; return; }
  echo ""
}

report_task() {
  local tid="$1" profile_id="$2" provider="$3" model="$4"
  local log lm kay_rc status hostv rc test_name
  test_name="${tid#${profile_id}-${KAY_MATRIX_PREFIX}-}"
  log="$(python3 "$PICK_PY" "$tid" "$LOG_DIR")"
  if [ -z "$log" ]; then
    log="$(ls -t "$LOG_DIR/${tid}-"*.log 2>/dev/null | head -1 || true)"
  fi
  lm="$LOG_DIR/${tid}-last-message.txt"
  if [ -z "$log" ] || [ ! -f "$log" ]; then
    with_report_lock bash -c "printf '%s\t%s\t%s\t%s\t?\tUNKNOWN\tnone\tnone\n' \"$tid\" \"$profile_id\" \"$provider\" \"$model\" >>\"$REPORT\"; printf '%s\t%s\t%s\t%s\t?\tUNKNOWN\t0\t2\n' \"$profile_id\" \"$provider\" \"$model\" \"$test_name\" >>\"$SUMMARY\""
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
  elif [ "${kay_rc:-?}" != "0" ] && [ "${kay_rc:-?}" != "?" ]; then status=FAIL; rc=1
  else status=UNKNOWN; rc=2
  fi
  local parent action url logbase evidence body n excerpt
  logbase="$(basename "$log")"
  parent="$(classify_primary "$log" "$lm")"
  action=none
  url=n/a
  if [ -n "$parent" ] && kay_issue_exists "$parent"; then
    n="$parent"
    evidence="$(grep -E "PORT=|status_contract|STATUS:|apply_patch|verify-bulk|EPERM|124|kill arguments|unsupported model|Final status" "$log" 2>/dev/null | tail -1 | head -c 200 || echo "see ${logbase}")"
    body="**Sidekick Kay live matrix** — kay ${KAY_VER}

- **task_id:** \`${tid}\`
- **profile:** ${profile_id} (\`${provider}\` / \`${model}\`)
- **kay_rc:** ${kay_rc:-?}
- **STATUS:** ${status}
- **prefix:** ${KAY_MATRIX_PREFIX}
- **parent bucket:** #${n}
- **evidence:** ${evidence}
- **log:** \`tests/.kay-live-logs/${logbase}\`

triage: sidekick-repo docs/knowledge/2026-06.md"
    if gh issue comment "$n" -R "$REPO" --body "$body" >/dev/null 2>&1; then
      url="https://github.com/${REPO}/issues/${n}"
      action="comment#${n}"
    else
      action="comment-failed#${n}"
      url="https://github.com/${REPO}/issues/${n}"
    fi
  elif [ "$status" = FAIL ] || [ "$status" = UNKNOWN ]; then
    excerpt="$(tail -40 "$log" | sed -E 's/sk-[A-Za-z0-9_-]+/[REDACTED]/g' | head -c 3500)"
    if url="$(gh issue create -R "$REPO" --title "Sidekick matrix ${tid} (${profile_id}, kay ${KAY_VER})" --body "## Repro
task: \`${tid}\` profile: ${profile_id} provider: ${provider} model: ${model}
matrix prefix: ${KAY_MATRIX_PREFIX}

\`\`\`
${excerpt}
\`\`\`" 2>/dev/null)"; then
      action=file-new
    else
      action=file-new-failed
      url=none
    fi
  fi
  with_report_lock bash -c "printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \"$tid\" \"$profile_id\" \"$provider\" \"$model\" \"${kay_rc:-?}\" \"$status\" \"$action\" \"$url\" >>\"$REPORT\"; printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \"$profile_id\" \"$provider\" \"$model\" \"$test_name\" \"${kay_rc:-?}\" \"$status\" \"$hostv\" \"$rc\" >>\"$SUMMARY\""
}

run_job() {
  local profile_id="$1" provider="$2" model="$3" task="$4"
  local tid kind log
  tid="${profile_id}-${KAY_MATRIX_PREFIX}-${task}"
  export KAY_LIVE_MODEL_PROVIDER="$provider"
  export KAY_LIVE_MODEL="$model"
  log="$LOG_DIR/${tid}-$(date +%Y%m%dT%H%M%S).log"
  echo "=== job ${tid} provider=${provider} model=${model} ===" | tee -a "$log"
  set +e
  case "$task" in
    e2e)
      SIDEKICK_LIVE_CODEX=1 bash tests/run_live_codex_e2e.bash >>"$log" 2>&1
      ;;
    task7)
      SIDEKICK_KAY_SEED_DIR="$SEED" SIDEKICK_KAY_REQUIRE_STATUS=1 SIDEKICK_KAY_HOST_VERIFY=1 \
        bash tests/run_kay_live_task.bash "$tid" "$PROMPTS/task7-retry2-closeout.txt" 90 >>"$log" 2>&1
      ;;
    task8)
      SIDEKICK_KAY_REQUIRE_STATUS=1 SIDEKICK_KAY_HOST_VERIFY=1 \
        bash tests/run_kay_live_task.bash "$tid" "$PROMPTS/task8-bulk-archive.txt" 1800 >>"$log" 2>&1
      ;;
    task9)
      SIDEKICK_KAY_REQUIRE_STATUS=1 SIDEKICK_KAY_HOST_VERIFY=1 \
        bash tests/run_kay_live_task.bash "$tid" "$PROMPTS/task9-sort-ui.txt" 1800 >>"$log" 2>&1
      ;;
    task10)
      SIDEKICK_KAY_SEED_DIR="$SEED" SIDEKICK_KAY_REQUIRE_STATUS=1 SIDEKICK_KAY_HOST_VERIFY=1 \
        bash tests/run_kay_live_task.bash "$tid" "$PROMPTS/task10-full-regression.txt" 900 >>"$log" 2>&1
      ;;
    *)
      echo "unknown task: $task" >>"$log"
      set -e
      report_task "$tid" "$profile_id" "$provider" "$model" || true
      return 2
      ;;
  esac
  set +e
  report_task "$tid" "$profile_id" "$provider" "$model" || true
}

main() {
  install_kay_if_needed
  init_tsv
  local jobs=() line profile_id provider model task
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(echo "$line" | tr -d '[:space:]')"
    [ -z "$line" ] && continue
    profile_id="${line%%:*}"
    rest="${line#*:}"
    provider="${rest%%:*}"
    model="${rest#*:}"
    for task in $KAY_MATRIX_TASKS; do
      jobs+=("${profile_id}|${provider}|${model}|${task}")
    done
  done <<< "$(printf '%s\n' "$KAY_MATRIX_PROFILES")"

  echo "Kay matrix prefix=${KAY_MATRIX_PREFIX} kay=${KAY_VER} jobs=${#jobs[@]} parallel=${KAY_MATRIX_PARALLEL}"
  echo "Report: $REPORT"
  echo "Summary: $SUMMARY"

  if [ "$KAY_MATRIX_PARALLEL" = 1 ]; then
    for spec in "${jobs[@]}"; do
      IFS='|' read -r profile_id provider model task <<<"$spec"
      run_job "$profile_id" "$provider" "$model" "$task" &
    done
    wait
  else
    for spec in "${jobs[@]}"; do
      IFS='|' read -r profile_id provider model task <<<"$spec"
      run_job "$profile_id" "$provider" "$model" "$task"
    done
  fi
  echo "Matrix complete: $SUMMARY"
}


rereport_only() {
  printf 'task_id	profile_id	provider	model	kay_rc	status	action	issue_url
' >"$REPORT"
  printf 'profile_id	provider	model	test	kay_rc	status	host_verify	rc
' >"$SUMMARY"
  local jobs=() line profile_id provider model task
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(echo "$line" | tr -d '[:space:]')"
    [ -z "$line" ] && continue
    profile_id="${line%%:*}"
    rest="${line#*:}"
    provider="${rest%%:*}"
    model="${rest#*:}"
    for task in $KAY_MATRIX_TASKS; do
      tid="${profile_id}-${KAY_MATRIX_PREFIX}-${task}"
      report_task "$tid" "$profile_id" "$provider" "$model" || true
    done
  done <<< "$(printf '%s\n' "$KAY_MATRIX_PROFILES")"
  echo "Rereport complete: $SUMMARY"
}

if [ "${KAY_MATRIX_REREPORT:-}" = 1 ]; then
  rereport_only
  exit 0
fi

main "$@"

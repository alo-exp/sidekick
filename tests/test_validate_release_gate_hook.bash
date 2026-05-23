#!/usr/bin/env bash
# Unit tests for hooks/validate-release-gate.sh
#
# The hook blocks GitHub release and release-tag publication commands via
# Claude Code's PreToolUse permissionDecision=deny mechanism unless all
# current-session quality-gate stage current-commit markers and two
# current-session, current-commit live-pyramid run markers are present in the active host
# quality-gate state file.
#
# We override HOME to a temp directory for each scenario so we can
# write marker files deterministically without touching the real state.

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${REPO_ROOT}/hooks/validate-release-gate.sh"

PASS=0; FAIL=0
assert_pass() { echo "  [PASS] $1"; PASS=$((PASS+1)); }
assert_fail() { echo "  [FAIL] $1 — $2"; FAIL=$((FAIL+1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not in PATH — skipping validate-release-gate tests"
  exit 0
fi

if [ ! -x "${HOOK}" ] && [ ! -r "${HOOK}" ]; then
  echo "Hook script not found at ${HOOK}"
  exit 1
fi

REAL_GIT="$(command -v git)"
GIT_WRAPPER_DIR="$(mktemp -d)"
trap 'rm -rf "${GIT_WRAPPER_DIR}"' EXIT
cat > "${GIT_WRAPPER_DIR}/git" <<'SH'
#!/usr/bin/env bash
real_git="${SIDEKICK_TEST_REAL_GIT:?}"
args=("$@")
index=0
while [ "${index}" -lt "${#args[@]}" ]; do
  case "${args[$index]}" in
    -C|--git-dir|--work-tree|--namespace|--exec-path|--super-prefix)
      index=$((index + 2))
      ;;
    --git-dir=*|--work-tree=*|--namespace=*|--exec-path=*|--super-prefix=*|--bare|--no-pager|--paginate)
      index=$((index + 1))
      ;;
    -c)
      index=$((index + 2))
      ;;
    *)
      break
      ;;
  esac
done
if [ "${index}" -lt "${#args[@]}" ] && [ "${args[$index]}" = "ls-remote" ]; then
  printf '%b' "${SIDEKICK_TEST_LS_REMOTE_OUTPUT:-}"
  exit "${SIDEKICK_TEST_LS_REMOTE_STATUS:-0}"
fi
exec "${real_git}" "$@"
SH
chmod +x "${GIT_WRAPPER_DIR}/git"

sanitize_release_env() {
  if [ "${SIDEKICK_TEST_INHERIT_RELEASE_ENV:-0}" = "1" ]; then
    return 0
  fi
  unset GH_HOST GH_REPO
  unset GIT_DIR GIT_WORK_TREE GIT_NAMESPACE GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
  unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM
  local name
  for name in $(compgen -e); do
    case "${name}" in
      GIT_CONFIG_KEY_*|GIT_CONFIG_VALUE_*) unset "${name}" ;;
    esac
  done
}

run_hook() {
  # $1 = temp HOME, $2 = JSON payload
  (sanitize_release_env; HOME="$1" PATH="${GIT_WRAPPER_DIR}:${PATH}" SIDEKICK_TEST_REAL_GIT="${REAL_GIT}" SIDEKICK_TEST_LS_REMOTE_OUTPUT="${SIDEKICK_TEST_LS_REMOTE_OUTPUT:-}" SIDEKICK_TEST_LS_REMOTE_STATUS="${SIDEKICK_TEST_LS_REMOTE_STATUS:-0}" CODEX_PLUGIN_ROOT= CODEX_HOME= CODEX_THREAD_ID= SIDEKICK_SESSION_ID="${SIDEKICK_TEST_SESSION:-test-session}" SESSION_ID="${SIDEKICK_TEST_SESSION:-test-session}" bash "${HOOK}" <<<"$2")
}

run_hook_codex() {
  # $1 = temp HOME, $2 = JSON payload
  (sanitize_release_env; HOME="$1" PATH="${GIT_WRAPPER_DIR}:${PATH}" SIDEKICK_TEST_REAL_GIT="${REAL_GIT}" SIDEKICK_TEST_LS_REMOTE_OUTPUT="${SIDEKICK_TEST_LS_REMOTE_OUTPUT:-}" SIDEKICK_TEST_LS_REMOTE_STATUS="${SIDEKICK_TEST_LS_REMOTE_STATUS:-0}" SIDEKICK_SESSION_ID= SESSION_ID= CLAUDE_SESSION_ID= CODEX_THREAD_ID="${SIDEKICK_TEST_SESSION:-test-session}" bash "${HOOK}" <<<"$2")
}

run_hook_no_git() {
  # $1 = temp HOME, $2 = JSON payload, $3 = package root with hooks/ but no .git
  (sanitize_release_env; HOME="$1" PATH="${GIT_WRAPPER_DIR}:${PATH}" SIDEKICK_TEST_REAL_GIT="${REAL_GIT}" SIDEKICK_TEST_LS_REMOTE_OUTPUT="${SIDEKICK_TEST_LS_REMOTE_OUTPUT:-}" SIDEKICK_TEST_LS_REMOTE_STATUS="${SIDEKICK_TEST_LS_REMOTE_STATUS:-0}" CODEX_PLUGIN_ROOT= CODEX_HOME= CODEX_THREAD_ID= SIDEKICK_SESSION_ID="${SIDEKICK_TEST_SESSION:-test-session}" SESSION_ID="${SIDEKICK_TEST_SESSION:-test-session}" bash "$3/hooks/validate-release-gate.sh" <<<"$2")
}

run_hook_no_git_from_cwd() {
  # $1 = temp HOME, $2 = JSON payload, $3 = package root with hooks/ but no .git, $4 = caller cwd
  (cd "$4" && sanitize_release_env; HOME="$1" PATH="${GIT_WRAPPER_DIR}:${PATH}" SIDEKICK_TEST_REAL_GIT="${REAL_GIT}" SIDEKICK_TEST_LS_REMOTE_OUTPUT="${SIDEKICK_TEST_LS_REMOTE_OUTPUT:-}" SIDEKICK_TEST_LS_REMOTE_STATUS="${SIDEKICK_TEST_LS_REMOTE_STATUS:-0}" CODEX_PLUGIN_ROOT= CODEX_HOME= CODEX_THREAD_ID= SIDEKICK_SESSION_ID="${SIDEKICK_TEST_SESSION:-test-session}" SESSION_ID="${SIDEKICK_TEST_SESSION:-test-session}" bash "$3/hooks/validate-release-gate.sh" <<<"$2")
}

run_hook_from_cwd() {
  # $1 = temp HOME, $2 = JSON payload, $3 = caller cwd
  (cd "$3" && sanitize_release_env; HOME="$1" PATH="${GIT_WRAPPER_DIR}:${PATH}" SIDEKICK_TEST_REAL_GIT="${REAL_GIT}" SIDEKICK_TEST_LS_REMOTE_OUTPUT="${SIDEKICK_TEST_LS_REMOTE_OUTPUT:-}" SIDEKICK_TEST_LS_REMOTE_STATUS="${SIDEKICK_TEST_LS_REMOTE_STATUS:-0}" CODEX_PLUGIN_ROOT= CODEX_HOME= CODEX_THREAD_ID= SIDEKICK_SESSION_ID="${SIDEKICK_TEST_SESSION:-test-session}" SESSION_ID="${SIDEKICK_TEST_SESSION:-test-session}" bash "${HOOK}" <<<"$2")
}

run_hook_without_python() {
  # $1 = temp HOME, $2 = JSON payload. PATH deliberately contains jq/cat but
  # not python3, proving the release gate fails closed when its parser runtime is
  # unavailable.
  local h="$1" payload="$2" bin jq_bin cat_bin rc
  bin="$(mktemp -d)"
  jq_bin="$(command -v jq)"
  cat_bin="$(command -v cat)"
  ln -sf "${jq_bin}" "${bin}/jq"
  ln -sf "${cat_bin}" "${bin}/cat"
  HOME="${h}" PATH="${bin}" CODEX_PLUGIN_ROOT= CODEX_HOME= CODEX_THREAD_ID= SIDEKICK_SESSION_ID="${SIDEKICK_TEST_SESSION:-test-session}" SESSION_ID="${SIDEKICK_TEST_SESSION:-test-session}" /bin/bash "${HOOK}" <<<"${payload}"
  rc=$?
  rm -rf "${bin}"
  return "${rc}"
}

setup_home() {
  local h
  h="$(mktemp -d)"
  mkdir -p "${h}/.claude/.sidekick"
  mkdir -p "${h}/.codex/.sidekick"
  echo "${h}"
}

write_markers() {
  local h="$1" sha; shift
  sha="$(current_head_sha)"
  : > "${h}/.claude/.sidekick/quality-gate-state"
  for s in "$@"; do
    echo "quality-gate-stage-${s} session=${SIDEKICK_TEST_SESSION:-test-session} sha=${sha}" >> "${h}/.claude/.sidekick/quality-gate-state"
  done
}

current_head_sha() {
  git -C "${REPO_ROOT}" rev-parse --short=12 HEAD 2>/dev/null || printf 'unknown'
}

current_head_release_command() {
  printf 'gh release create v1.2.1 --repo alo-exp/sidekick --target %s --generate-notes' "$(current_head_sha)"
}

substitution_target_release_command() {
  printf 'gh release create v1.2.1 --repo alo-exp/sidekick --target "$(git rev-parse HEAD)" --generate-notes'
}

write_markers_for_sha() {
  local h="$1" sha="$2"; shift 2
  : > "${h}/.claude/.sidekick/quality-gate-state"
  for s in "$@"; do
    echo "quality-gate-stage-${s} session=${SIDEKICK_TEST_SESSION:-test-session} sha=${sha}" >> "${h}/.claude/.sidekick/quality-gate-state"
  done
}

write_legacy_session_only_markers() {
  local h="$1"; shift
  : > "${h}/.claude/.sidekick/quality-gate-state"
  for s in "$@"; do
    echo "quality-gate-stage-${s} session=${SIDEKICK_TEST_SESSION:-test-session}" >> "${h}/.claude/.sidekick/quality-gate-state"
  done
}

write_live_pyramid_markers() {
  local h="$1" count="${2:-2}" i sha
  sha="$(current_head_sha)"
  for i in $(seq 1 "${count}"); do
    echo "quality-gate-live-pyramid session=${SIDEKICK_TEST_SESSION:-test-session} sha=${sha} at=20260515T00000${i}Z" >> "${h}/.claude/.sidekick/quality-gate-state"
  done
}

write_live_pyramid_markers_for_sha() {
  local h="$1" sha="$2" count="${3:-2}" i
  for i in $(seq 1 "${count}"); do
    echo "quality-gate-live-pyramid session=${SIDEKICK_TEST_SESSION:-test-session} sha=${sha} at=20260515T00000${i}Z" >> "${h}/.claude/.sidekick/quality-gate-state"
  done
}

write_codex_markers() {
  local h="$1" sha; shift
  sha="$(current_head_sha)"
  : > "${h}/.codex/.sidekick/quality-gate-state"
  for s in "$@"; do
    echo "quality-gate-stage-${s} session=${SIDEKICK_TEST_SESSION:-test-session} sha=${sha}" >> "${h}/.codex/.sidekick/quality-gate-state"
  done
}

write_codex_live_pyramid_markers() {
  local h="$1" count="${2:-2}" i sha
  sha="$(current_head_sha)"
  for i in $(seq 1 "${count}"); do
    echo "quality-gate-live-pyramid session=${SIDEKICK_TEST_SESSION:-test-session} sha=${sha} at=20260515T00000${i}Z" >> "${h}/.codex/.sidekick/quality-gate-state"
  done
}

write_gh_alias_config() {
  local gh_config="$1"
  mkdir -p "${gh_config}"
  cat > "${gh_config}/aliases.yml" <<'YAML'
rel: release create
rc: '!gh release create'
YAML
}

assert_denied_command() {
  local label="$1" command="$2" h payload out rc decision
  echo "${label}"
  h="$(setup_home)"
  payload="$(jq -cn --arg cmd "${command}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
  out="$(run_hook "${h}" "${payload}")"; rc=$?
  decision=$(printf '%s' "${out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "${rc}" -eq 0 ] && [ "${decision}" = "deny" ]; then
    assert_pass "${label}: permissionDecision=deny"
  else
    assert_fail "${label}" "rc=${rc} decision=${decision} out=${out}"
  fi
  rm -rf "${h}"
}

assert_passthrough_command() {
  local label="$1" command="$2" h payload out rc
  echo "${label}"
  h="$(setup_home)"
  payload="$(jq -cn --arg cmd "${command}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
  out="$(run_hook "${h}" "${payload}")"; rc=$?
  if [ "${rc}" -eq 0 ] && [ -z "${out}" ]; then
    assert_pass "${label}: exit 0, no JSON decision"
  else
    assert_fail "${label}" "rc=${rc} out=${out}"
  fi
  rm -rf "${h}"
}

assert_denied_command_with_current_markers() {
  local label="$1" command="$2" h payload out rc decision
  echo "${label}"
  h="$(setup_home)"
  write_markers "${h}" 1 2 3 4
  write_live_pyramid_markers "${h}" 2
  payload="$(jq -cn --arg cmd "${command}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
  out="$(run_hook "${h}" "${payload}")"; rc=$?
  decision=$(printf '%s' "${out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "${rc}" -eq 0 ] && [ "${decision}" = "deny" ]; then
    assert_pass "${label}: permissionDecision=deny"
  else
    assert_fail "${label}" "rc=${rc} decision=${decision} out=${out}"
  fi
  rm -rf "${h}"
}

assert_denied_release_command_with_current_markers() {
  local label="$1" command="$2" h payload out rc decision
  echo "${label}"
  h="$(setup_home)"
  write_markers "${h}" 1 2 3 4
  write_live_pyramid_markers "${h}" 2
  payload="$(jq -cn --arg cmd "${command}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
  out="$(run_hook "${h}" "${payload}")"; rc=$?
  decision=$(printf '%s' "${out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "${rc}" -eq 0 ] && [ "${decision}" = "deny" ]; then
    assert_pass "${label}: permissionDecision=deny"
  else
    assert_fail "${label}" "rc=${rc} decision=${decision} out=${out}"
  fi
  rm -rf "${h}"
}

assert_passthrough_release_command_with_sha_markers() {
  local label="$1" command="$2" sha="$3" h payload out rc decision
  echo "${label}"
  h="$(setup_home)"
  write_markers_for_sha "${h}" "${sha}" 1 2 3 4
  write_live_pyramid_markers_for_sha "${h}" "${sha}" 2
  payload="$(jq -cn --arg cmd "${command}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
  out="$(run_hook "${h}" "${payload}")"; rc=$?
  decision=$(printf '%s' "${out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "${rc}" -eq 0 ] && [ -z "${decision}" ] && [ -z "${out}" ]; then
    assert_pass "${label}: exit 0, no JSON decision"
  else
    assert_fail "${label}" "rc=${rc} decision=${decision} out=${out}"
  fi
  rm -rf "${h}"
}

assert_denied_release_command_with_sha_markers() {
  local label="$1" command="$2" sha="$3" h payload out rc decision
  echo "${label}"
  h="$(setup_home)"
  write_markers_for_sha "${h}" "${sha}" 1 2 3 4
  write_live_pyramid_markers_for_sha "${h}" "${sha}" 2
  payload="$(jq -cn --arg cmd "${command}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
  out="$(run_hook "${h}" "${payload}")"; rc=$?
  decision=$(printf '%s' "${out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "${rc}" -eq 0 ] && [ "${decision}" = "deny" ]; then
    assert_pass "${label}: permissionDecision=deny"
  else
    assert_fail "${label}" "rc=${rc} decision=${decision} out=${out}"
  fi
  rm -rf "${h}"
}

assert_denied_release_command_with_sha_markers_from_cwd() {
  local label="$1" command="$2" sha="$3" cwd="$4" h payload out rc decision
  echo "${label}"
  h="$(setup_home)"
  write_markers_for_sha "${h}" "${sha}" 1 2 3 4
  write_live_pyramid_markers_for_sha "${h}" "${sha}" 2
  payload="$(jq -cn --arg cmd "${command}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
  out="$(run_hook_from_cwd "${h}" "${payload}" "${cwd}")"; rc=$?
  decision=$(printf '%s' "${out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "${rc}" -eq 0 ] && [ "${decision}" = "deny" ]; then
    assert_pass "${label}: permissionDecision=deny"
  else
    assert_fail "${label}" "rc=${rc} decision=${decision} out=${out}"
  fi
  rm -rf "${h}"
}

assert_denied_command_with_env_var() {
  local label="$1" command="$2" env_name="$3" env_value="$4" h payload out rc decision
  echo "${label}"
  h="$(setup_home)"
  payload="$(jq -cn --arg cmd "${command}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
  out="$(env HOME="${h}" CODEX_PLUGIN_ROOT= CODEX_HOME= CODEX_THREAD_ID= SIDEKICK_SESSION_ID="${SIDEKICK_TEST_SESSION:-test-session}" SESSION_ID="${SIDEKICK_TEST_SESSION:-test-session}" "${env_name}=${env_value}" bash "${HOOK}" <<<"${payload}")"; rc=$?
  decision=$(printf '%s' "${out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "${rc}" -eq 0 ] && [ "${decision}" = "deny" ]; then
    assert_pass "${label}: permissionDecision=deny"
  else
    assert_fail "${label}" "rc=${rc} decision=${decision} out=${out}"
  fi
  rm -rf "${h}"
}

assert_denied_command_with_gh_aliases() {
  local label="$1" command="$2" alias_list="$3" h payload out rc decision
  echo "${label}"
  h="$(setup_home)"
  payload="$(jq -cn --arg cmd "${command}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
  out="$(SIDEKICK_GH_ALIAS_LIST="${alias_list}" run_hook "${h}" "${payload}")"; rc=$?
  decision=$(printf '%s' "${out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "${rc}" -eq 0 ] && [ "${decision}" = "deny" ]; then
    assert_pass "${label}: permissionDecision=deny"
  else
    assert_fail "${label}" "rc=${rc} decision=${decision} out=${out}"
  fi
  rm -rf "${h}"
}

assert_denied_command_with_git_alias_config() {
  local label="$1" command="$2" alias_config="$3" h payload out rc decision
  echo "${label}"
  h="$(setup_home)"
  payload="$(jq -cn --arg cmd "${command}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
  out="$(SIDEKICK_GIT_ALIAS_CONFIG="${alias_config}" run_hook "${h}" "${payload}")"; rc=$?
  decision=$(printf '%s' "${out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "${rc}" -eq 0 ] && [ "${decision}" = "deny" ]; then
    assert_pass "${label}: permissionDecision=deny"
  else
    assert_fail "${label}" "rc=${rc} decision=${decision} out=${out}"
  fi
  rm -rf "${h}"
}

assert_denied_command_with_command_scoped_gh_alias() {
  local label="$1" h bin gh_config capture payload out rc decision
  echo "${label}"
  h="$(setup_home)"
  bin="$(mktemp -d)"
  gh_config="$(mktemp -d)"
  capture="$(mktemp)"
  write_gh_alias_config "${gh_config}"
  cat > "${bin}/gh" <<SH
#!/usr/bin/env bash
printf 'gh-executed\n' >> "${capture}"
exit 0
SH
  chmod +x "${bin}/gh"
  payload="$(jq -cn --arg cmd "GH_CONFIG_DIR=${gh_config} gh rel v1.2.1" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
  out="$(PATH="${bin}:${PATH}" run_hook "${h}" "${payload}")"; rc=$?
  decision=$(printf '%s' "${out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "${rc}" -eq 0 ] && [ "${decision}" = "deny" ] && [ ! -s "${capture}" ]; then
    assert_pass "${label}: permissionDecision=deny without executing gh"
  else
    assert_fail "${label}" "rc=${rc} decision=${decision} out=${out} gh_capture=$(cat "${capture}" 2>/dev/null)"
  fi
  rm -rf "${h}" "${bin}" "${gh_config}" "${capture}"
}

assert_denied_command_with_gh_global_config_alias() {
  local label="$1" command_template="$2" h bin gh_config capture command payload out rc decision
  echo "${label}"
  h="$(setup_home)"
  bin="$(mktemp -d)"
  gh_config="$(mktemp -d)"
  capture="$(mktemp)"
  write_gh_alias_config "${gh_config}"
  cat > "${bin}/gh" <<SH
#!/usr/bin/env bash
printf 'gh-executed\n' >> "${capture}"
exit 0
SH
  chmod +x "${bin}/gh"
  command="${command_template//__GH_CONFIG_DIR__/${gh_config}}"
  payload="$(jq -cn --arg cmd "${command}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
  out="$(PATH="${bin}:${PATH}" run_hook "${h}" "${payload}")"; rc=$?
  decision=$(printf '%s' "${out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "${rc}" -eq 0 ] && [ "${decision}" = "deny" ] && [ ! -s "${capture}" ]; then
    assert_pass "${label}: permissionDecision=deny without executing gh"
  else
    assert_fail "${label}" "rc=${rc} decision=${decision} out=${out} gh_capture=$(cat "${capture}" 2>/dev/null)"
  fi
  rm -rf "${h}" "${bin}" "${gh_config}" "${capture}"
}

assert_gh_alias_lookup_sanitizes_env() {
  local label="$1" h bin gh_config capture payload out rc decision
  echo "${label}"
  h="$(setup_home)"
  bin="$(mktemp -d)"
  gh_config="$(mktemp -d)"
  capture="$(mktemp)"
  write_gh_alias_config "${gh_config}"
  cat > "${bin}/gh" <<SH
#!/usr/bin/env bash
env > "${capture}"
exit 0
SH
  chmod +x "${bin}/gh"
  payload="$(jq -cn --arg cmd "gh --config-dir ${gh_config} rel v1.2.1" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
  out="$(PATH="${bin}:${PATH}" CLAUDE_API_KEY=claude-secret CODEX_TOKEN=codex-secret OPENAI_API_KEY=openai-secret GH_TOKEN=gh-secret run_hook "${h}" "${payload}")"; rc=$?
  decision=$(printf '%s' "${out}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  if [ "${rc}" -eq 0 ] \
    && [ "${decision}" = "deny" ] \
    && [ ! -s "${capture}" ]; then
    assert_pass "${label}: gh alias config parsed without executing gh"
  else
    assert_fail "${label}" "rc=${rc} decision=${decision} out=${out} gh_capture=$(cat "${capture}" 2>/dev/null)"
  fi
  rm -rf "${h}" "${bin}" "${gh_config}" "${capture}"
}

# ---------------------------------------------------------------------------
# Scenario 1: non-Bash tool → exit 0, no output
# ---------------------------------------------------------------------------
echo "Scenario 1: non-Bash tool passes through"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Read","tool_input":{"file_path":"/etc/hosts"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
if [ "${RC}" -eq 0 ] && [ -z "${OUT}" ]; then
  assert_pass "non-Bash tool: exit 0, no JSON decision"
else
  assert_fail "non-Bash tool" "rc=${RC} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 2: Bash with non-target command → exit 0, no output
# ---------------------------------------------------------------------------
echo "Scenario 2: Bash with non-release command passes through"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
if [ "${RC}" -eq 0 ] && [ -z "${OUT}" ]; then
  assert_pass "Bash non-target: exit 0, no JSON decision"
else
  assert_fail "Bash non-target" "rc=${RC} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 3: gh release create with NO markers → deny
# ---------------------------------------------------------------------------
echo "Scenario 3: release command with no markers is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "no markers: permissionDecision=deny"
else
  assert_fail "no markers deny" "rc=${RC} decision=${DECISION}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 4: gh release create with all markers and two live runs → pass-through
# ---------------------------------------------------------------------------
echo "Scenario 4: release command with all markers and live pyramid passes"
H="$(setup_home)"
write_markers "${H}" 1 2 3 4
write_live_pyramid_markers "${H}" 2
PAYLOAD="$(jq -cn --arg cmd "$(current_head_release_command)" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
if [ "${RC}" -eq 0 ] && [ -z "${OUT}" ]; then
  assert_pass "all 4 markers plus live pyramid: exit 0, no deny"
else
  assert_fail "all markers plus live pyramid pass" "rc=${RC} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 4a: packaged hook without .git falls back to release command cwd SHA
# ---------------------------------------------------------------------------
echo "Scenario 4a: release command passes from package tree using caller git cwd"
H="$(setup_home)"
NO_GIT_ROOT="$(mktemp -d)"
mkdir -p "${NO_GIT_ROOT}/hooks"
cp "${HOOK}" "${NO_GIT_ROOT}/hooks/validate-release-gate.sh"
write_markers "${H}" 1 2 3 4
write_live_pyramid_markers "${H}" 2
PAYLOAD="$(jq -cn --arg cmd "$(current_head_release_command)" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook_no_git "${H}" "${PAYLOAD}" "${NO_GIT_ROOT}")"; RC=$?
if [ "${RC}" -eq 0 ] && [ -z "${OUT}" ]; then
  assert_pass "package tree without .git: caller git cwd SHA authorizes current-session live pyramid"
else
  assert_fail "package tree without .git caller cwd pass" "rc=${RC} out=${OUT}"
fi
rm -rf "${H}" "${NO_GIT_ROOT}"

# ---------------------------------------------------------------------------
# Scenario 4b: packaged hook with no git metadata anywhere → deny
# ---------------------------------------------------------------------------
echo "Scenario 4a2: package hook git root does not override caller release cwd SHA"
H="$(setup_home)"
HOOK_GIT_ROOT="$(mktemp -d)"
RELEASE_CWD="$(mktemp -d)"
mkdir -p "${HOOK_GIT_ROOT}/hooks"
cp "${HOOK}" "${HOOK_GIT_ROOT}/hooks/validate-release-gate.sh"
git -C "${HOOK_GIT_ROOT}" init -q
git -C "${HOOK_GIT_ROOT}" add hooks/validate-release-gate.sh
git -C "${HOOK_GIT_ROOT}" -c user.email=sidekick@example.invalid -c user.name=Sidekick commit -q -m hook-root
git -C "${RELEASE_CWD}" init -q
git -C "${RELEASE_CWD}" remote add origin https://github.com/alo-exp/sidekick.git
printf 'release cwd\n' > "${RELEASE_CWD}/README.md"
git -C "${RELEASE_CWD}" add README.md
git -C "${RELEASE_CWD}" -c user.email=sidekick@example.invalid -c user.name=Sidekick commit -q -m release-cwd
release_cwd_sha="$(git -C "${RELEASE_CWD}" rev-parse --short=12 HEAD)"
write_markers_for_sha "${H}" "${release_cwd_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${release_cwd_sha}" 2
PAYLOAD="$(jq -cn --arg cmd "gh release create v1.2.1 --repo alo-exp/sidekick --target ${release_cwd_sha} --generate-notes" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook_no_git_from_cwd "${H}" "${PAYLOAD}" "${HOOK_GIT_ROOT}" "${RELEASE_CWD}")"; RC=$?
if [ "${RC}" -eq 0 ] && [ -z "${OUT}" ]; then
  assert_pass "hook root git SHA does not preempt caller release cwd SHA"
else
  assert_fail "hook root git SHA preemption" "rc=${RC} out=${OUT}"
fi
rm -rf "${H}" "${HOOK_GIT_ROOT}" "${RELEASE_CWD}"

# ---------------------------------------------------------------------------
# Scenario 4b: packaged hook with no git metadata anywhere → deny
# ---------------------------------------------------------------------------
echo "Scenario 4b: release command is denied when no current git SHA is available"
H="$(setup_home)"
NO_GIT_ROOT="$(mktemp -d)"
NO_GIT_CWD="$(mktemp -d)"
mkdir -p "${NO_GIT_ROOT}/hooks"
cp "${HOOK}" "${NO_GIT_ROOT}/hooks/validate-release-gate.sh"
write_markers "${H}" 1 2 3 4
write_live_pyramid_markers "${H}" 2
PAYLOAD="$(jq -cn --arg cmd "$(current_head_release_command)" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook_no_git_from_cwd "${H}" "${PAYLOAD}" "${NO_GIT_ROOT}" "${NO_GIT_CWD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
REASON=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ] && [[ "${REASON}" == *"no current git SHA"* ]]; then
  assert_pass "package tree and caller cwd without git metadata: permissionDecision=deny"
else
  assert_fail "no git metadata deny" "rc=${RC} decision=${DECISION} reason=${REASON} out=${OUT}"
fi
rm -rf "${H}" "${NO_GIT_ROOT}" "${NO_GIT_CWD}"

# ---------------------------------------------------------------------------
# Scenario 4b2: missing session id guidance names all accepted variables
# ---------------------------------------------------------------------------
echo "Scenario 4b2: missing host session guidance names Claude session variable"
H="$(setup_home)"
PAYLOAD="$(jq -cn --arg cmd "$(current_head_release_command)" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(HOME="${H}" CODEX_PLUGIN_ROOT= CODEX_HOME= CODEX_THREAD_ID= SIDEKICK_SESSION_ID= CLAUDE_SESSION_ID= SESSION_ID= bash "${HOOK}" <<<"${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
REASON=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ] && [[ "${REASON}" == *"CLAUDE_SESSION_ID"* ]]; then
  assert_pass "missing host session guidance includes CLAUDE_SESSION_ID"
else
  assert_fail "missing host session guidance" "rc=${RC} decision=${DECISION} reason=${REASON} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 4c: all 4 stage markers without live pyramid markers → deny
# ---------------------------------------------------------------------------
echo "Scenario 4c: stage markers without live pyramid are denied"
H="$(setup_home)"
write_markers "${H}" 1 2 3 4
PAYLOAD="$(jq -cn --arg cmd "$(current_head_release_command)" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
REASON=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ] && [[ "${REASON}" == *"live pyramid incomplete"* ]] && [[ "${REASON}" == *"0/2"* ]]; then
  assert_pass "stage markers without live pyramid: permissionDecision=deny"
else
  assert_fail "stage markers without live pyramid deny" "rc=${RC} decision=${DECISION} reason=${REASON}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 4d: only one live-pyramid run marker → deny
# ---------------------------------------------------------------------------
echo "Scenario 4d: one live-pyramid marker is denied"
H="$(setup_home)"
write_markers "${H}" 1 2 3 4
write_live_pyramid_markers "${H}" 1
PAYLOAD="$(jq -cn --arg cmd "$(current_head_release_command)" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
REASON=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] \
  && [ "${DECISION}" = "deny" ] \
  && [[ "${REASON}" == *"1/2"* ]] \
  && [[ "${REASON}" == *"current-session, current-commit"* ]]; then
  assert_pass "one live-pyramid marker: permissionDecision=deny with current-commit guidance"
else
  assert_fail "one live-pyramid marker deny" "rc=${RC} decision=${DECISION} reason=${REASON}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 4e: stale stage marker SHA does not satisfy current checkout
# ---------------------------------------------------------------------------
echo "Scenario 4e: stale stage marker SHA is denied"
H="$(setup_home)"
write_markers_for_sha "${H}" "stale-stage-sha" 1 2 3 4
write_live_pyramid_markers "${H}" 2
PAYLOAD="$(jq -cn --arg cmd "$(current_head_release_command)" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
REASON=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ] && [[ "${REASON}" == *"current session and commit"* ]] && [[ "${REASON}" == *"1,2,3,4"* ]]; then
  assert_pass "stale stage marker SHA: permissionDecision=deny"
else
  assert_fail "stale stage marker SHA deny" "rc=${RC} decision=${DECISION} reason=${REASON}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 4f: legacy session-only stage markers are denied in source checkout
# ---------------------------------------------------------------------------
echo "Scenario 4f: legacy session-only stage markers are denied"
H="$(setup_home)"
write_legacy_session_only_markers "${H}" 1 2 3 4
write_live_pyramid_markers "${H}" 2
PAYLOAD="$(jq -cn --arg cmd "$(current_head_release_command)" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
REASON=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ] && [[ "${REASON}" == *"current session and commit"* ]]; then
  assert_pass "legacy session-only stage markers: permissionDecision=deny"
else
  assert_fail "legacy session-only stage markers deny" "rc=${RC} decision=${DECISION} reason=${REASON}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 5: stage-10 marker must NOT satisfy stage-1 (anchored match)
# ---------------------------------------------------------------------------
echo "Scenario 5: stage-10 does not satisfy stage-1 (anchored grep)"
H="$(setup_home)"
: > "${H}/.claude/.sidekick/quality-gate-state"
# Only a spurious stage-10 marker — stages 1-4 should all still be missing.
echo "quality-gate-stage-10 session=${SIDEKICK_TEST_SESSION:-test-session} sha=$(current_head_sha)" >> "${H}/.claude/.sidekick/quality-gate-state"
PAYLOAD="$(jq -cn --arg cmd "$(current_head_release_command)" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
REASON=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ] && [[ "${REASON}" == *"1"* ]] && [[ "${REASON}" == *"2"* ]]; then
  assert_pass "stage-10 does not satisfy stage-1: denied with missing 1,2,3,4"
else
  assert_fail "stage-10 anchored" "rc=${RC} decision=${DECISION} reason=${REASON}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 6: partial markers (1,2 only) → deny listing missing 3,4
# ---------------------------------------------------------------------------
echo "Scenario 6: partial markers deny with correct missing list"
H="$(setup_home)"
write_markers "${H}" 1 2
PAYLOAD="$(jq -cn --arg cmd "$(current_head_release_command)" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
REASON=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ] && [[ "${REASON}" == *"3"* ]] && [[ "${REASON}" == *"4"* ]]; then
  assert_pass "partial markers: denied with 3,4 missing"
else
  assert_fail "partial markers" "rc=${RC} decision=${DECISION} reason=${REASON}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 7: hookEventName is 'PreToolUse' in the output JSON
# ---------------------------------------------------------------------------
echo "Scenario 7: deny JSON has hookEventName=PreToolUse"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
EVENT=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)
if [ "${EVENT}" = "PreToolUse" ]; then
  assert_pass "hookEventName=PreToolUse"
else
  assert_fail "hookEventName" "got=${EVENT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 8: stale markers from another session do not authorize release
# ---------------------------------------------------------------------------
echo "Scenario 8: stale markers from another session are denied"
H="$(setup_home)"
: > "${H}/.claude/.sidekick/quality-gate-state"
for s in 1 2 3 4; do
  echo "quality-gate-stage-${s} session=old-session sha=$(current_head_sha)" >> "${H}/.claude/.sidekick/quality-gate-state"
done
PAYLOAD="$(jq -cn --arg cmd "$(current_head_release_command)" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
REASON=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ] && [[ "${REASON}" == *"1"* ]] && [[ "${REASON}" == *"4"* ]]; then
  assert_pass "stale session markers do not satisfy current session"
else
  assert_fail "stale session markers" "rc=${RC} decision=${DECISION} reason=${REASON}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 9: tokenized gh release create with extra spaces is denied
# ---------------------------------------------------------------------------
echo "Scenario 9: release command with extra whitespace is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh  release   create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "extra whitespace release command: permissionDecision=deny"
else
  assert_fail "extra whitespace release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 10: quoted text mentioning gh release create does not trigger
# ---------------------------------------------------------------------------
echo "Scenario 10: quoted mention is not treated as a release command"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"echo \"gh release create v1.2.1\""}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
if [ "${RC}" -eq 0 ] && [ -z "${OUT}" ]; then
  assert_pass "quoted mention: exit 0, no JSON decision"
else
  assert_fail "quoted mention" "rc=${RC} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 11: shell wrapper with gh release create payload is denied
# ---------------------------------------------------------------------------
echo "Scenario 11: shell-wrapped release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"bash -lc '\''gh release create v1.2.1'\''"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "shell-wrapped release command: permissionDecision=deny"
else
  assert_fail "shell-wrapped release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 12: absolute gh path is still treated as release creation
# ---------------------------------------------------------------------------
echo "Scenario 12: absolute gh path release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"/opt/homebrew/bin/gh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "absolute gh release command: permissionDecision=deny"
else
  assert_fail "absolute gh release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 13: unquoted non-command mention is not treated as release creation
# ---------------------------------------------------------------------------
echo "Scenario 13: unquoted non-command mention is not treated as release command"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"echo gh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
if [ "${RC}" -eq 0 ] && [ -z "${OUT}" ]; then
  assert_pass "unquoted mention: exit 0, no JSON decision"
else
  assert_fail "unquoted mention" "rc=${RC} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 14: assignment-prefixed release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 14: assignment-prefixed release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"GH_TOKEN=x gh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "assignment-prefixed release command: permissionDecision=deny"
else
  assert_fail "assignment-prefixed release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 15: command wrapper release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 15: command-wrapped release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"command gh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "command-wrapped release command: permissionDecision=deny"
else
  assert_fail "command-wrapped release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 16: gh global repo option before release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 16: gh --repo release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh --repo alo-exp/sidekick release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "gh --repo release command: permissionDecision=deny"
else
  assert_fail "gh --repo release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 17: gh short repo option before release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 17: gh -R release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh -R alo-exp/sidekick release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "gh -R release command: permissionDecision=deny"
else
  assert_fail "gh -R release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 18: env option with operand before release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 18: env -u release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"env -u GH_TOKEN gh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "env -u release command: permissionDecision=deny"
else
  assert_fail "env -u release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 19: shell-wrapped gh global option release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 19: shell-wrapped gh --repo release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"bash -lc '\''gh --repo alo-exp/sidekick release create v1.2.1'\''"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "shell-wrapped gh --repo release command: permissionDecision=deny"
else
  assert_fail "shell-wrapped gh --repo release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 20: gh hostname global option before release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 20: gh --hostname release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh --hostname github.com release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "gh --hostname release command: permissionDecision=deny"
else
  assert_fail "gh --hostname release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 21: shell control keyword before release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 21: if-wrapped release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"if gh release create v1.2.1; then echo ok; fi"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "if-wrapped release command: permissionDecision=deny"
else
  assert_fail "if-wrapped release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 21b: newline-separated release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 21b: newline-separated release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"echo ok\ngh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "newline-separated release command: permissionDecision=deny"
else
  assert_fail "newline-separated release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 21c: compact function-body release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 21c: compact function-body release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"f(){ gh release create v1.2.1; }; f"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "compact function-body release command: permissionDecision=deny"
else
  assert_fail "compact function-body release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 21d: function keyword release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 21d: function-keyword release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"function f { gh release create v1.2.1; }; f"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "function-keyword release command: permissionDecision=deny"
else
  assert_fail "function-keyword release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 22: command substitution around release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 22: command-substitution release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"echo $(gh release create v1.2.1)"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "command-substitution release command: permissionDecision=deny"
else
  assert_fail "command-substitution release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 22b: double-quoted command substitution release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 22b: double-quoted command-substitution release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"echo \"$(gh release create v1.2.1)\""}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "double-quoted command-substitution release command: permissionDecision=deny"
else
  assert_fail "double-quoted command-substitution release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 22c: single-quoted command substitution text is not treated as a release command
# ---------------------------------------------------------------------------
echo "Scenario 22c: single-quoted command-substitution mention is not treated as release command"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"echo '\''$(gh release create v1.2.1)'\''"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
if [ "${RC}" -eq 0 ] && [ -z "${OUT}" ]; then
  assert_pass "single-quoted command-substitution mention: exit 0, no JSON decision"
else
  assert_fail "single-quoted command-substitution mention" "rc=${RC} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 22d: dynamic command expansion can complete release command
# ---------------------------------------------------------------------------
echo "Scenario 22d: dynamic command expansion completes release command"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"$(printf gh) release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "dynamic command expansion completes release command: permissionDecision=deny"
else
  assert_fail "dynamic command expansion completes release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 22e: dynamic gh subcommand expansion can complete release command
# ---------------------------------------------------------------------------
echo "Scenario 22e: dynamic gh subcommand expansion completes release command"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh $(printf release) create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "dynamic gh subcommand expansion completes release command: permissionDecision=deny"
else
  assert_fail "dynamic gh subcommand expansion completes release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 22f: variable command expansion can complete release command
# ---------------------------------------------------------------------------
echo "Scenario 22f: variable command expansion completes release command"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"cmd=gh; $cmd release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "variable command expansion completes release command: permissionDecision=deny"
else
  assert_fail "variable command expansion completes release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 23: time wrapper before release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 23: time-wrapped release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"time gh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "time-wrapped release command: permissionDecision=deny"
else
  assert_fail "time-wrapped release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 24: sudo wrapper before release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 24: sudo-wrapped release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"sudo gh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "sudo-wrapped release command: permissionDecision=deny"
else
  assert_fail "sudo-wrapped release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 25: noglob wrapper before release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 25: noglob-wrapped release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"noglob gh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "noglob-wrapped release command: permissionDecision=deny"
else
  assert_fail "noglob-wrapped release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 26: command substitution with a non-release command still passes
# ---------------------------------------------------------------------------
echo "Scenario 26: command-substitution mention is not treated as release command"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"echo $(echo gh release create v1.2.1)"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
if [ "${RC}" -eq 0 ] && [ -z "${OUT}" ]; then
  assert_pass "command-substitution mention: exit 0, no JSON decision"
else
  assert_fail "command-substitution mention" "rc=${RC} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 27: missing python3 fails closed for Bash release classification
# ---------------------------------------------------------------------------
echo "Scenario 27: missing python3 fails closed"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh release create v1.2.1"}}'
OUT="$(run_hook_without_python "${H}" "${PAYLOAD}" 2>/dev/null)"; RC=$?
if [ "${RC}" -eq 2 ] && [ -z "${OUT}" ]; then
  assert_pass "missing python3: exits non-zero before release can pass"
else
  assert_fail "missing python3 fail-closed" "rc=${RC} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 28: command env wrapper before release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 28: command env release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"command env gh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "command env release command: permissionDecision=deny"
else
  assert_fail "command env release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 29: sudo env wrapper before release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 29: sudo env release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"sudo env gh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "sudo env release command: permissionDecision=deny"
else
  assert_fail "sudo env release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 30: GNU time wrapper option with operand before release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 30: gtime -f release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gtime -f %E gh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "gtime -f release command: permissionDecision=deny"
else
  assert_fail "gtime -f release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 31: brace-group release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 31: brace-group release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"{ gh release create v1.2.1; }"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "brace-group release command: permissionDecision=deny"
else
  assert_fail "brace-group release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 32: env -S release payload is denied
# ---------------------------------------------------------------------------
echo "Scenario 32: env -S release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"env -S '\''gh release create v1.2.1'\''"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "env -S release command: permissionDecision=deny"
else
  assert_fail "env -S release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 33: env --split-string= release payload is denied
# ---------------------------------------------------------------------------
echo "Scenario 33: env --split-string release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"env --split-string='\''gh release create v1.2.1'\''"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "env --split-string release command: permissionDecision=deny"
else
  assert_fail "env --split-string release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 34: xargs command carrier before release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 34: xargs release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"xargs gh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "xargs release command: permissionDecision=deny"
else
  assert_fail "xargs release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 35: find -exec command carrier before release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 35: find -exec release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"find . -exec gh release create v1.2.1 {} \\;"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "find -exec release command: permissionDecision=deny"
else
  assert_fail "find -exec release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 36: find -okdir command carrier before release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 36: find -okdir release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"find . -okdir gh release create v1.2.1 {} \\;"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "find -okdir release command: permissionDecision=deny"
else
  assert_fail "find -okdir release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 37: backtick command substitution around release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 37: backtick release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"echo `gh release create v1.2.1`"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "backtick release command: permissionDecision=deny"
else
  assert_fail "backtick release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 38: eval command carrier before release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 38: eval release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"eval \"gh release create v1.2.1\""}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "eval release command: permissionDecision=deny"
else
  assert_fail "eval release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 39: builtin eval command carrier before release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 39: builtin eval release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"builtin eval \"gh release create v1.2.1\""}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "builtin eval release command: permissionDecision=deny"
else
  assert_fail "builtin eval release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 39b: static release command piped into shell stdin is denied
# ---------------------------------------------------------------------------
echo "Scenario 39b: static release command piped into shell stdin is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"printf \"gh release create v1.2.1\" | bash"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "static release command piped into shell stdin: permissionDecision=deny"
else
  assert_fail "static release command piped into shell stdin" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 39c: echo release command piped into shell stdin is denied
# ---------------------------------------------------------------------------
echo "Scenario 39c: echo release command piped into shell stdin is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"echo gh release create v1.2.1 | sh"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "echo release command piped into shell stdin: permissionDecision=deny"
else
  assert_fail "echo release command piped into shell stdin" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 39d: formatted printf release command piped into shell stdin is denied
# ---------------------------------------------------------------------------
echo "Scenario 39d: formatted printf release command piped into shell stdin is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"printf \"%s\\n\" \"gh release create v1.2.1\" | bash"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "formatted printf release command piped into shell stdin: permissionDecision=deny"
else
  assert_fail "formatted printf release command piped into shell stdin" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 39e: printf -- release command piped into shell stdin is denied
# ---------------------------------------------------------------------------
echo "Scenario 39e: printf -- release command piped into shell stdin is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"printf -- \"gh release create v1.2.1\" | sh"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "printf -- release command piped into shell stdin: permissionDecision=deny"
else
  assert_fail "printf -- release command piped into shell stdin" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 39f: echo -e release command piped into shell stdin is denied
# ---------------------------------------------------------------------------
echo "Scenario 39f: echo -e release command piped into shell stdin is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"echo -e \"gh release create v1.2.1\" | sh"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "echo -e release command piped into shell stdin: permissionDecision=deny"
else
  assert_fail "echo -e release command piped into shell stdin" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 39g: shell stdin from process substitution is denied
# ---------------------------------------------------------------------------
echo "Scenario 39g: shell stdin from process substitution is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"sh < <(printf \"gh release create v1.2.1\")"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "shell stdin from process substitution: permissionDecision=deny"
else
  assert_fail "shell stdin from process substitution" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 39h: shell here-string release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 39h: shell here-string release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"bash <<< \"gh release create v1.2.1\""}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "shell here-string release command: permissionDecision=deny"
else
  assert_fail "shell here-string release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 39i: xargs stdin from process substitution completes release command
# ---------------------------------------------------------------------------
echo "Scenario 39i: xargs stdin from process substitution completes release command"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"xargs gh release < <(printf create)"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "xargs stdin from process substitution completes release command: permissionDecision=deny"
else
  assert_fail "xargs stdin from process substitution completes release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 40: input process substitution release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 40: input process-substitution release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"cat <(gh release create v1.2.1)"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "input process-substitution release command: permissionDecision=deny"
else
  assert_fail "input process-substitution release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 40b: nested command substitution inside process substitution is denied
# ---------------------------------------------------------------------------
echo "Scenario 40b: nested command-substitution release command in process substitution is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"cat <(echo \"$(gh release create v1.2.1)\")"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "nested command-substitution in process substitution: permissionDecision=deny"
else
  assert_fail "nested command-substitution in process substitution" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 41: output process substitution release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 41: output process-substitution release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"tee >(gh release create v1.2.1)"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "output process-substitution release command: permissionDecision=deny"
else
  assert_fail "output process-substitution release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 42: quoted process-substitution text is not treated as a release command
# ---------------------------------------------------------------------------
echo "Scenario 42: quoted process-substitution mention is not treated as release command"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"echo \"<(gh release create v1.2.1)\""}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
if [ "${RC}" -eq 0 ] && [ -z "${OUT}" ]; then
  assert_pass "quoted process-substitution mention: exit 0, no JSON decision"
else
  assert_fail "quoted process-substitution mention" "rc=${RC} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 43: xargs -a operand option before release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 43: xargs -a release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"xargs -a /tmp/items gh release create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "xargs -a release command: permissionDecision=deny"
else
  assert_fail "xargs -a release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 44: stdin-assembled xargs gh release command is denied
# ---------------------------------------------------------------------------
echo "Scenario 44: stdin-assembled xargs gh release command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"printf \"release create v1.2.1\" | xargs gh"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "stdin-assembled xargs gh release command: permissionDecision=deny"
else
  assert_fail "stdin-assembled xargs gh release command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 45: stdin-assembled xargs gh release subcommand is denied
# ---------------------------------------------------------------------------
echo "Scenario 45: stdin-assembled xargs gh release subcommand is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"printf \"create v1.2.1\" | xargs gh release"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "stdin-assembled xargs gh release subcommand: permissionDecision=deny"
else
  assert_fail "stdin-assembled xargs gh release subcommand" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 46: xargs shell carrier without static -c payload is denied
# ---------------------------------------------------------------------------
echo "Scenario 46: xargs shell carrier without static payload is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"printf \"gh release create v1.2.1\" | xargs sh -c"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "xargs shell carrier without static payload: permissionDecision=deny"
else
  assert_fail "xargs shell carrier without static payload" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 46b: xargs replacement shell payload is denied
# ---------------------------------------------------------------------------
echo "Scenario 46b: xargs replacement shell payload is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"printf \"gh release create v1.2.1\" | xargs -I{} sh -c \"{}\""}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "xargs replacement shell payload: permissionDecision=deny"
else
  assert_fail "xargs replacement shell payload" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 46c: xargs replacement can supply gh release subcommand
# ---------------------------------------------------------------------------
echo "Scenario 46c: xargs replacement can supply gh release subcommand"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"printf \"release create v1.2.1\" | xargs -I{} gh {}"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "xargs replacement supplies gh release subcommand: permissionDecision=deny"
else
  assert_fail "xargs replacement supplies gh release subcommand" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 46d: xargs replacement can supply gh release create subcommand
# ---------------------------------------------------------------------------
echo "Scenario 46d: xargs replacement can supply gh release create subcommand"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"printf \"create v1.2.1\" | xargs -I{} gh release {}"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "xargs replacement supplies gh release create: permissionDecision=deny"
else
  assert_fail "xargs replacement supplies gh release create" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 46e: xargs shell positional args can complete gh release create
# ---------------------------------------------------------------------------
echo "Scenario 46e: xargs shell positional args complete gh release create"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"printf \"create v1.2.1\" | xargs sh -c '\''gh release \"$@\"'\'' sh"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "xargs shell positional args complete gh release create: permissionDecision=deny"
else
  assert_fail "xargs shell positional args complete gh release create" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 46f: xargs shell positional args can complete gh release subcommand
# ---------------------------------------------------------------------------
echo "Scenario 46f: xargs shell positional args complete gh release subcommand"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"printf \"release create v1.2.1\" | xargs sh -c '\''gh \"$@\"'\'' sh"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "xargs shell positional args complete gh release subcommand: permissionDecision=deny"
else
  assert_fail "xargs shell positional args complete gh release subcommand" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 46g: xargs shell numeric positional arg can complete gh release create
# ---------------------------------------------------------------------------
echo "Scenario 46g: xargs shell numeric positional arg completes gh release create"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"printf \"create v1.2.1\" | xargs sh -c '\''gh release $1'\'' sh"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "xargs shell numeric positional arg completes gh release create: permissionDecision=deny"
else
  assert_fail "xargs shell numeric positional arg completes gh release create" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 47: gh release option before create is denied
# ---------------------------------------------------------------------------
echo "Scenario 47: gh release --repo create command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh release --repo alo-exp/sidekick create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "gh release --repo create command: permissionDecision=deny"
else
  assert_fail "gh release --repo create command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 48: gh release short repo option before create is denied
# ---------------------------------------------------------------------------
echo "Scenario 48: gh release -R create command is denied"
H="$(setup_home)"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh release -R alo-exp/sidekick create v1.2.1"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "gh release -R create command: permissionDecision=deny"
else
  assert_fail "gh release -R create command" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

assert_denied_command "Scenario 48a: gh release upload command is denied" \
  "gh release upload v1.2.1 dist/sidekick.zip"
assert_denied_command "Scenario 48b: gh release edit publish command is denied" \
  "gh release edit v1.2.1 --draft=false"
assert_denied_command "Scenario 48c: gh release delete command is denied" \
  "gh release delete v1.2.1 --yes"
assert_denied_command "Scenario 48d: gh release delete-asset command is denied" \
  "gh release delete-asset v1.2.1 asset.zip --yes"
assert_denied_command "Scenario 48e: unknown gh release subcommand fails closed" \
  "gh release publish v1.2.1"
assert_passthrough_command "Scenario 48f: gh release view passes through" \
  "gh release view v1.2.1"
assert_passthrough_command "Scenario 48g: gh release list passes through" \
  "gh release list"
assert_passthrough_command "Scenario 48h: gh release download passes through" \
  "gh release download v1.2.1"

# ---------------------------------------------------------------------------
# Scenario 49: accepted review bypass regressions are denied
# ---------------------------------------------------------------------------
assert_denied_command "Scenario 49a: builtin command wrapper release command is denied" \
  "builtin command gh release create v1.2.1"
assert_denied_command "Scenario 49b: builtin exec wrapper release command is denied" \
  "builtin exec gh release create v1.2.1"
assert_denied_command "Scenario 49c: static shell stdin after prior semicolon command is denied" \
  "echo ok; printf \"gh release create v1.2.1\" | bash"
assert_denied_command "Scenario 49d: static shell stdin after prior && command is denied" \
  "true && printf \"gh release create v1.2.1\" | bash"
_generated_release_script="$(mktemp)"
assert_denied_command "Scenario 49d2: same-command generated release script is denied" \
  "printf 'gh release create v1.2.1' > ${_generated_release_script}; bash ${_generated_release_script}"
assert_denied_command "Scenario 49d3: dynamic generated script file fails closed" \
  "printf \"\$UNKNOWN_PAYLOAD\" > ${_generated_release_script}; bash ${_generated_release_script}"
rm -f "${_generated_release_script}"
assert_denied_command "Scenario 49d4: dynamic generated bash script path is denied" \
  "p=\$(mktemp); printf 'gh release create v1.2.1' > \"\$p\"; bash \"\$p\""
assert_denied_command "Scenario 49d5: dynamic generated sourced script path is denied" \
  "p=\$(mktemp); printf 'gh release create v1.2.1' > \"\$p\"; source \"\$p\""
assert_denied_command "Scenario 49d6: dynamic generated python script path is denied" \
  "p=\$(mktemp); printf 'import os; os.system(\"gh release create v1.2.1\")' > \"\$p\"; python3 \"\$p\""
assert_denied_command "Scenario 49d7: dynamic generated executable script path is denied" \
  "p=\$(mktemp); printf '#!/usr/bin/env bash\ngh release create v1.2.1\n' > \"\$p\"; chmod +x \"\$p\"; \"\$p\""
assert_denied_command "Scenario 49d8: generated script path normalization is denied" \
  "printf 'gh release create v1.2.1' > ./sidekick-generated-release-test; bash sidekick-generated-release-test"
assert_denied_command "Scenario 49e: shell positional args complete gh release create" \
  "bash -c 'gh \"\$@\"' sh release create v1.2.1"
assert_denied_command "Scenario 49f: function positional args complete gh release create" \
  "f(){ gh \"\$@\"; }; f release create v1.2.1"
assert_denied_command "Scenario 49g: eval resolves static release variable" \
  "x=\"gh release create v1.2.1\"; eval \"\$x\""
assert_denied_command "Scenario 49h: printf format assembles release create through operand" \
  "printf 'gh release %s\\n' create | bash"
assert_denied_command "Scenario 49i: printf format assembles release subcommand through operand" \
  "printf 'gh %s create\\n' release | bash"
assert_denied_command "Scenario 49j: echo -e octal escape assembles release create" \
  "echo -e 'gh release\\040create v1.2.1' | bash"
assert_denied_command "Scenario 49k: literal variables assemble dynamic command and subcommand" \
  "cmd=gh; sub=release; \$cmd \$sub create v1.2.1"
assert_denied_command "Scenario 49l: literal variables assemble all release tokens" \
  "cmd=gh; rel=release; create=create; \$cmd \$rel \$create v1.2.1"
assert_denied_command "Scenario 49m: exec -a wrapper release command is denied" \
  "exec -a notgh gh release create v1.2.1"
assert_denied_command "Scenario 49n: shell long option before -c release command is denied" \
  "bash --norc -c 'gh release create v1.2.1'"
assert_denied_command "Scenario 49o: static shell stdin with -s option is denied" \
  "printf 'gh release create v1.2.1' | bash -s"
assert_denied_command "Scenario 49p: shell script path from process substitution is denied" \
  "bash <(printf 'gh release create v1.2.1')"
assert_denied_command "Scenario 49q: source process substitution release script is denied" \
  "source <(printf 'gh release create v1.2.1')"
assert_denied_command "Scenario 49r: dot-source process substitution release script is denied" \
  ". <(printf 'gh release create v1.2.1')"
assert_denied_command "Scenario 49s: ANSI-C quoted command word assembly is denied" \
  "g\$'h' release create v1.2.1"
assert_denied_command "Scenario 49t: ANSI-C quoted subcommand assembly is denied" \
  "gh rel\$'ease' create v1.2.1"
assert_denied_command "Scenario 49u: IFS parameter expansion assembly is denied" \
  "gh\${IFS}release\${IFS}create v1.2.1"
assert_denied_command "Scenario 49v: default parameter expansion command assembly is denied" \
  "g\${EMPTY:-h} release create v1.2.1"
assert_denied_command "Scenario 49w: backslash-newline release command is denied" \
  $'gh \\\nrelease \\\ncreate v1.2.1'
assert_denied_command "Scenario 49x: embedded command substitution assembles command word" \
  "g\$(printf h) release create v1.2.1"
assert_denied_command "Scenario 49y: embedded command substitution assembles release word" \
  "gh rel\$(printf ease) create v1.2.1"
assert_denied_command "Scenario 49z: embedded command substitution assembles create word" \
  "gh release cre\$(printf ate) v1.2.1"
assert_denied_command "Scenario 49aa: backtick substitution assembles command word" \
  "\`printf gh\` release create v1.2.1"
assert_denied_command "Scenario 49ab: multi-word command substitution assembles release create" \
  "gh \$(printf 'release create') v1.2.1"
assert_denied_command "Scenario 49ac: shell argv0 completes create position" \
  "sh -c 'gh release \"\$0\"' create"
assert_denied_command "Scenario 49ad: shell argv0 completes command position" \
  "sh -c '\$0 release create v1.2.1' gh"
assert_denied_command "Scenario 49ae: shell argv0 completes subcommand position" \
  "sh -c 'gh \"\$0\" create v1.2.1' release"
assert_denied_command "Scenario 49ae2: shell adjacent positional fragments complete create position" \
  "bash -c 'gh release \"\$1\$2\" v1.2.1' sh cre ate"
assert_denied_command "Scenario 49af: echo -en release script to shell stdin is denied" \
  "echo -en 'gh release create v1.2.1' | bash"
assert_denied_command "Scenario 49ag: echo -ne release script to shell stdin is denied" \
  "echo -ne 'gh release create v1.2.1' | bash"
assert_denied_command "Scenario 49ah: unquoted multiword variable completes release command" \
  "rel=\"release create\"; gh \$rel v1.2.1"
assert_denied_command "Scenario 49ai: positional expansion completes release command" \
  "set -- release create; gh \$@ v1.2.1"
assert_denied_command "Scenario 49ai2: set without -- positional expansion completes release command" \
  "set release create; gh \$@ v1.2.1"
assert_denied_command "Scenario 49aj: array expansion completes release command" \
  "arr=(release create); gh \${arr[@]} v1.2.1"
assert_denied_command "Scenario 49aj2: star array expansion completes release command" \
  "arr=(release create); gh \${arr[*]} v1.2.1"
assert_denied_command "Scenario 49aj3: indexed array assignments complete release command" \
  "arr[0]=release; arr[1]=create; gh \${arr[*]} v1.2.1"
assert_denied_command "Scenario 49aj4: declared array expansion completes release command" \
  "declare -a arr=(release create); gh \${arr[@]} v1.2.1"
assert_denied_command "Scenario 49ak: multiword command variable completes release command" \
  "cmd=\"gh release create\"; \$cmd v1.2.1"
assert_denied_command "Scenario 49ak2: multiline command variable completes release command" \
  $'cmd="gh release create"\n$cmd v1.2.1'
assert_denied_command "Scenario 49al: embedded literal variable assembles command word" \
  "h=h; g\$h release create v1.2.1"
assert_denied_command "Scenario 49am: default parameter expansion without colon assembles command word" \
  "g\${EMPTY-h} release create v1.2.1"
assert_denied_command "Scenario 49an: gh api POST release endpoint is denied" \
  "gh api --method POST repos/alo-exp/sidekick/releases -f tag_name=v1.2.1 -f name=v1.2.1"
assert_denied_command "Scenario 49ao: gh api implicit POST release endpoint is denied" \
  "gh api repos/alo-exp/sidekick/releases -f tag_name=v1.2.1 -f name=v1.2.1"
assert_denied_command "Scenario 49ap: gh api POST tag ref endpoint is denied" \
  "gh api -X POST repos/alo-exp/sidekick/git/refs -f ref=refs/tags/v1.2.1 -f sha=abc123"
assert_denied_command "Scenario 49ap0b: gh api escaped tag ref field is denied" \
  "gh api -X POST repos/alo-exp/sidekick/git/refs -f 'ref=refs\\/tags\\/v1.2.1' -f sha=abc123"
assert_denied_command "Scenario 49ap0c: gh api dynamic ref field fails closed" \
  'gh api -X POST repos/alo-exp/sidekick/git/refs -f ref="$x" -f sha=abc123'
assert_passthrough_command "Scenario 49ap1: gh api POST branch ref endpoint passes through" \
  "gh api -X POST repos/alo-exp/sidekick/git/refs -f ref=refs/heads/release-hardening -f sha=abc123"
assert_denied_command "Scenario 49ap2: curl POST release endpoint is denied" \
  "curl -sS -X POST https://api.github.com/repos/alo-exp/sidekick/releases -d '{\"tag_name\":\"v1.2.1\"}'"
assert_denied_command "Scenario 49ap2b: curl attached short data flag release endpoint is denied" \
  "curl -sS -d'{\"tag_name\":\"v1.2.1\"}' https://api.github.com/repos/alo-exp/sidekick/releases"
assert_denied_command "Scenario 49ap2c: curl attached short form flag release endpoint is denied" \
  "curl -sS -Ftag_name=v1.2.1 https://api.github.com/repos/alo-exp/sidekick/releases"
assert_denied_command "Scenario 49ap3: curl data-implied POST tag ref endpoint is denied" \
  "curl --url https://api.github.com/repos/alo-exp/sidekick/git/refs --data '{\"ref\":\"refs/tags/v1.2.1\",\"sha\":\"abc123\"}'"
assert_denied_command "Scenario 49ap3a0: curl dynamic tag ref payload fails closed" \
  'x=$(cat VERSION); curl --url https://api.github.com/repos/alo-exp/sidekick/git/refs --data "{\"ref\":\"$x\",\"sha\":\"abc123\"}"'
assert_denied_command "Scenario 49ap3a: curl escaped tag ref endpoint is denied" \
  "curl --url https://api.github.com/repos/alo-exp/sidekick/git/refs --data '{\"ref\":\"refs\\/tags\\/v1.2.1\",\"sha\":\"abc123\"}'"
assert_denied_command "Scenario 49ap3a2: curl unicode-escaped tag ref endpoint is denied" \
  "curl --url https://api.github.com/repos/alo-exp/sidekick/git/refs --data '{\"ref\":\"refs\\u002ftags\\u002fv1.2.1\",\"sha\":\"abc123\"}'"
assert_passthrough_command "Scenario 49ap3b: curl data-implied POST branch ref endpoint passes through" \
  "curl --url https://api.github.com/repos/alo-exp/sidekick/git/refs --data '{\"ref\":\"refs/heads/release-hardening\",\"sha\":\"abc123\"}'"
_tag_ref_body="$(mktemp)"
_branch_ref_body="$(mktemp)"
_unicode_tag_ref_body="$(mktemp)"
_tag_ref_value="$(mktemp)"
_branch_ref_value="$(mktemp)"
printf '%s\n' '{"ref":"refs/tags/v1.2.1","sha":"abc123"}' > "${_tag_ref_body}"
printf '%s\n' '{"ref":"refs/heads/release-hardening","sha":"abc123"}' > "${_branch_ref_body}"
printf '%s\n' '{"ref":"refs\u002ftags\u002fv1.2.1","sha":"abc123"}' > "${_unicode_tag_ref_body}"
printf '%s\n' 'refs/tags/v1.2.1' > "${_tag_ref_value}"
printf '%s\n' 'refs/heads/release-hardening' > "${_branch_ref_value}"
assert_denied_command "Scenario 49ap3c: gh api input file tag ref is denied" \
  "gh api -X POST repos/alo-exp/sidekick/git/refs --input ${_tag_ref_body}"
assert_passthrough_command "Scenario 49ap3d: gh api input file branch ref passes through" \
  "gh api -X POST repos/alo-exp/sidekick/git/refs --input ${_branch_ref_body}"
assert_denied_command "Scenario 49ap3e: curl data file tag ref is denied" \
  "curl --url https://api.github.com/repos/alo-exp/sidekick/git/refs --data @${_tag_ref_body}"
assert_passthrough_command "Scenario 49ap3f: curl data file branch ref passes through" \
  "curl --url https://api.github.com/repos/alo-exp/sidekick/git/refs --data @${_branch_ref_body}"
assert_denied_command "Scenario 49ap3g: curl JSON file tag ref is denied" \
  "curl --url https://api.github.com/repos/alo-exp/sidekick/git/refs --json @${_tag_ref_body}"
assert_denied_command "Scenario 49ap3h: wget body file tag ref is denied" \
  "wget --method=POST --body-file=${_tag_ref_body} https://api.github.com/repos/alo-exp/sidekick/git/refs"
assert_passthrough_command "Scenario 49ap3i: wget body file branch ref passes through" \
  "wget --method=POST --body-file=${_branch_ref_body} https://api.github.com/repos/alo-exp/sidekick/git/refs"
assert_denied_command "Scenario 49ap3j: curl stdin body for git refs fails closed" \
  "curl --url https://api.github.com/repos/alo-exp/sidekick/git/refs --data @-"
assert_denied_command "Scenario 49ap3k: gh api unicode-escaped tag ref is denied" \
  "gh api -X POST repos/alo-exp/sidekick/git/refs --input ${_unicode_tag_ref_body}"
assert_denied_command "Scenario 49ap3l: gh api field file tag ref is denied" \
  "gh api -X POST repos/alo-exp/sidekick/git/refs -F ref=@${_tag_ref_value} -F sha=abc123"
assert_passthrough_command "Scenario 49ap3m: gh api field file branch ref passes through" \
  "gh api -X POST repos/alo-exp/sidekick/git/refs -F ref=@${_branch_ref_value} -F sha=abc123"
assert_denied_command "Scenario 49ap3n: gh api field stdin tag ref fails closed" \
  "gh api -X POST repos/alo-exp/sidekick/git/refs -F ref=@- -F sha=abc123"
rm -f "${_tag_ref_body}" "${_branch_ref_body}" "${_unicode_tag_ref_body}" "${_tag_ref_value}" "${_branch_ref_value}"
assert_denied_command "Scenario 49ap4: wget POST release endpoint is denied" \
  "wget --method=POST --body-data '{\"tag_name\":\"v1.2.1\"}' https://api.github.com/repos/alo-exp/sidekick/releases"
assert_denied_command "Scenario 49ap5: python direct GitHub release API write is denied" \
  "python3 -c 'import requests; requests.post(\"https://api.github.com/repos/alo-exp/sidekick/releases\", json={\"tag_name\":\"v1.2.1\"})'"
assert_denied_command "Scenario 49ap5b: python concatenated release API write is denied" \
  "python3 -c 'import requests; requests.post(\"https://api.github.com/repos/\"+\"alo-exp/sidekick/releases\", json={\"tag_name\":\"v1.2.1\"})'"
assert_denied_command "Scenario 49ap6: python urllib direct GitHub release API write is denied" \
  "python3 -c 'import urllib.request as u; u.urlopen(u.Request(\"https://api.github.com/repos/alo-exp/sidekick/releases\", data=b\"{}\"))'"
assert_denied_command "Scenario 49ap6b: python requests import alias write is denied" \
  "python3 -c 'from requests import post as p; p(\"https://api.github.com/repos/alo-exp/sidekick/releases\", json={\"tag_name\":\"v1.2.1\"})'"
assert_denied_command "Scenario 49ap6c: python requests session write is denied" \
  "python3 -c 'import requests; s=requests.Session(); s.post(\"https://api.github.com/repos/alo-exp/sidekick/releases\", json={\"tag_name\":\"v1.2.1\"})'"
assert_denied_command "Scenario 49ap6d: python split-host http.client write is denied" \
  "python3 -c 'import http.client as h; c=h.HTTPSConnection(\"api.github.com\"); c.request(\"POST\", \"/repos/alo-exp/sidekick/releases\", body=\"{}\")'"
assert_denied_command "Scenario 49ap6e: python GraphQL release mutation is denied" \
  "python3 -c 'import requests; requests.post(\"https://api.github.com/graphql\", json={\"query\":\"mutation { createRelease(input:{repositoryId:\\\"R\\\", tagName:\\\"v1\\\"}) { release { id } } }\"})'"
assert_denied_command "Scenario 49ap6f: curl GraphQL createRelease mutation is denied" \
  "curl -sS -X POST https://api.github.com/graphql -d '{\"query\":\"mutation { createRelease(input:{repositoryId:\\\"R\\\", tagName:\\\"v1\\\"}) { release { id } } }\"}'"
assert_denied_command "Scenario 49ap6g: curl GraphQL createRef JSON body is denied" \
  "curl -sS --json '{\"query\":\"mutation { createRef(input:{ref:\\\"refs/tags/v1\\\", oid:\\\"abc\\\"}) { ref { id } } }\"}' https://api.github.com/graphql"
assert_denied_command "Scenario 49ap6g2: curl GraphQL unicode-escaped createRelease mutation name is denied" \
  "curl -sS -X POST https://api.github.com/graphql -d '{\"query\":\"mutation { \\u0063reateRelease(input:{repositoryId:\\\"R\\\", tagName:\\\"v1\\\"}) { release { id } } }\"}'"
assert_denied_command "Scenario 49ap6g3: curl GraphQL unicode-escaped createRef mutation name is denied" \
  "curl -sS --json '{\"query\":\"mutation { \\u0063reateRef(input:{ref:\\\"refs/tags/v1\\\", oid:\\\"abc\\\"}) { ref { id } } }\"}' https://api.github.com/graphql"
assert_denied_command "Scenario 49ap6h: curl GraphQL file-backed query field is denied" \
  "curl -sS -F query=@release-mutation.graphql https://api.github.com/graphql"
_graphql_query="$(mktemp)"
_graphql_read_query="$(mktemp)"
printf '%s\n' 'mutation { createRelease(input:{repositoryId:"R", tagName:"v1"}) { release { id } } }' > "${_graphql_query}"
printf '%s\n' 'query { viewer { login } }' > "${_graphql_read_query}"
assert_denied_command "Scenario 49ap6h2: curl GraphQL data-urlencode query file is denied" \
  "curl -sS --data-urlencode query@${_graphql_query} https://api.github.com/graphql"
assert_passthrough_command "Scenario 49ap6h3: curl GraphQL read-only query file passes through" \
  "curl -sS --data-urlencode query@${_graphql_read_query} https://api.github.com/graphql"
assert_passthrough_command "Scenario 49ap6h4: gh api GraphQL read-only query file passes through" \
  "gh api graphql -F query=@${_graphql_read_query}"
rm -f "${_graphql_query}" "${_graphql_read_query}"
assert_denied_command "Scenario 49ap6i: wget GraphQL createRelease mutation is denied" \
  "wget --method=POST --body-data '{\"query\":\"mutation { createRelease(input:{repositoryId:\\\"R\\\", tagName:\\\"v1\\\"}) { release { id } } }\"}' https://api.github.com/graphql"
assert_denied_command "Scenario 49ap6j: GHES /api/graphql createRelease mutation is denied" \
  "curl -sS -X POST https://ghe.example.test/api/graphql -d '{\"query\":\"mutation { createRelease(input:{repositoryId:\\\"R\\\", tagName:\\\"v1\\\"}) { release { id } } }\"}'"
_curl_config="$(mktemp)"
_curl_implicit_post_config="$(mktemp)"
cat > "${_curl_config}" <<'EOF'
url = "https://api.github.com/repos/alo-exp/sidekick/releases"
request = POST
data = "{\"tag_name\":\"v1.2.1\"}"
EOF
cat > "${_curl_implicit_post_config}" <<'EOF'
url = "https://api.github.com/repos/alo-exp/sidekick/releases"
data = "{\"tag_name\":\"v1.2.1\"}"
EOF
assert_denied_command "Scenario 49ap7: curl config file release endpoint is denied" \
  "curl -K ${_curl_config}"
assert_denied_command "Scenario 49ap7a: curl config implicit POST release endpoint is denied" \
  "curl -K ${_curl_implicit_post_config}"
assert_denied_command "Scenario 49ap7b: curl stdin config source is denied" \
  "curl -K -"
assert_denied_command "Scenario 49ap7c: curl attached stdin config source is denied" \
  "curl -K-"
_generated_curl_config="$(mktemp)"
_generated_curl_var_config="$(mktemp)"
assert_denied_command "Scenario 49ap7d: curl same-command generated config file is denied" \
  "printf 'url = \"https://api.github.com/repos/alo-exp/sidekick/releases\"\\nrequest = POST\\n' > ${_generated_curl_config}; curl -K ${_generated_curl_config}"
assert_denied_command "Scenario 49ap7e: curl generated config through variable path is denied" \
  "cfg=${_generated_curl_var_config}; printf 'url = \"https://api.github.com/repos/alo-exp/sidekick/releases\"\\nrequest = POST\\n' > \"\$cfg\"; curl -K \"\$cfg\""
rm -f "${_generated_curl_config}" "${_generated_curl_var_config}"
assert_denied_command "Scenario 49ap7e2: curl generated config path normalization is denied" \
  "printf 'url = \"https://api.github.com/repos/alo-exp/sidekick/releases\"\\nrequest = POST\\n' > ./sidekick-release-curl.cfg; curl -K sidekick-release-curl.cfg"
assert_denied_command "Scenario 49ap7e3: heredoc-generated curl config is denied" \
  $'cat > sidekick-release-curl.cfg <<\'EOF\'\nurl = "https://api.github.com/repos/alo-exp/sidekick/releases"\nrequest = POST\nEOF\ncurl -K sidekick-release-curl.cfg'
assert_denied_command "Scenario 49ap7e4: tee heredoc-generated curl config is denied" \
  $'tee ./sidekick-release-curl.cfg <<\'EOF\'\nurl = "https://api.github.com/repos/alo-exp/sidekick/releases"\nrequest = POST\nEOF\ncurl -K sidekick-release-curl.cfg'
assert_denied_command "Scenario 49ap7f: curl process-substitution config is denied" \
  "curl -K <(printf 'url = \"https://api.github.com/repos/alo-exp/sidekick/releases\"\\nrequest = POST\\n')"
assert_denied_command "Scenario 49ap7g: curl config write semantics combine with CLI release URL" \
  "curl -K <(printf 'request = POST\\ndata = \"{}\"\\n') https://api.github.com/repos/alo-exp/sidekick/releases"
_wget_urls="$(mktemp)"
printf '%s\n' "https://api.github.com/repos/alo-exp/sidekick/releases" > "${_wget_urls}"
assert_denied_command "Scenario 49ap8: wget input file release endpoint is denied" \
  "wget --method=POST --body-data '{\"tag_name\":\"v1.2.1\"}' -i ${_wget_urls}"
assert_denied_command "Scenario 49ap8b: wget stdin input source is denied" \
  "wget -i -"
assert_denied_command "Scenario 49ap8c: wget attached stdin input source is denied" \
  "wget -i-"
rm -f "${_curl_config}" "${_curl_implicit_post_config}" "${_wget_urls}"
assert_denied_command "Scenario 49ap9: node direct GitHub release API write is denied" \
  "node -e 'fetch(\"https://api.github.com/repos/alo-exp/sidekick/git/refs\", {method:\"POST\", body:\"{\\\"ref\\\":\\\"refs/tags/v1.2.1\\\"}\"})'"
assert_denied_command "Scenario 49ap9b0: node concatenated tag-ref API write is denied" \
  "node -e 'fetch(\"https://api.github.com/repos/\"+\"alo-exp/sidekick/git/refs\", {method:\"POST\", body:\"{\\\"ref\\\":\\\"refs/tags/v1.2.1\\\"}\"})'"
assert_passthrough_command "Scenario 49ap9a: node direct branch ref API write passes through" \
  "node -e 'fetch(\"https://api.github.com/repos/alo-exp/sidekick/git/refs\", {method:\"POST\", body:\"{\\\"ref\\\":\\\"refs/heads/release-hardening\\\"}\"})'"
assert_denied_command_with_env_var "Scenario 49ap9d: gh api inherited env release endpoint is denied" \
  'gh api -X POST "$RELEASE_ENDPOINT" -f tag_name=v1.2.1' \
  "RELEASE_ENDPOINT" "repos/alo-exp/sidekick/releases"
assert_denied_command_with_env_var "Scenario 49ap9e: curl inherited env release URL is denied" \
  'curl -X POST "$RELEASE_URL" -d "{\"tag_name\":\"v1.2.1\"}"' \
  "RELEASE_URL" "https://api.github.com/repos/alo-exp/sidekick/releases"
assert_denied_command_with_env_var "Scenario 49ap9f: wget inherited env release URL is denied" \
  'wget --method=POST --body-data "{\"tag_name\":\"v1.2.1\"}" "$RELEASE_URL"' \
  "RELEASE_URL" "https://api.github.com/repos/alo-exp/sidekick/releases"
assert_denied_command_with_env_var "Scenario 49ap9g: python inherited env release URL is denied" \
  'python3 -c "import os,requests; requests.post(os.environ[\"RELEASE_URL\"], json={\"tag_name\":\"v1.2.1\"})"' \
  "RELEASE_URL" "https://api.github.com/repos/alo-exp/sidekick/releases"
assert_denied_command "Scenario 49ap9h: curl command-scoped generic env release URL is denied" \
  'env URL=https://api.github.com/repos/alo-exp/sidekick/releases sh -c '\''curl -X POST "$URL" -d "{\"tag_name\":\"v1.2.1\"}"'\'''
assert_denied_command "Scenario 49ap9i: python command-scoped generic env release URL is denied" \
  'env URL=https://api.github.com/repos/alo-exp/sidekick/releases python3 -c "import os,requests; requests.post(os.environ[\"URL\"], json={\"tag_name\":\"v1.2.1\"})"'
echo "Scenario 49ap9b: curl missing config on example.com passes through"
H="$(setup_home)"
OUT="$(run_hook "${H}" '{"tool_name":"Bash","tool_input":{"command":"curl -K /tmp/sidekick-missing.cfg https://example.com"}}')"; RC=$?
if [ "${RC}" -eq 0 ] && [ -z "${OUT}" ]; then
  assert_pass "curl missing config on example.com: exit 0, no JSON decision"
else
  assert_fail "curl missing config on example.com" "rc=${RC} out=${OUT}"
fi
rm -rf "${H}"
echo "Scenario 49ap9c: wget missing input on example.com passes through"
H="$(setup_home)"
OUT="$(run_hook "${H}" '{"tool_name":"Bash","tool_input":{"command":"wget -i /tmp/sidekick-missing.txt https://example.com"}}')"; RC=$?
if [ "${RC}" -eq 0 ] && [ -z "${OUT}" ]; then
  assert_pass "wget missing input on example.com: exit 0, no JSON decision"
else
  assert_fail "wget missing input on example.com" "rc=${RC} out=${OUT}"
fi
rm -rf "${H}"
assert_denied_command "Scenario 49aq: alias expansion release command is denied" \
  "shopt -s expand_aliases; alias r='gh release create'; r v1.2.1"
assert_denied_command "Scenario 49aq2: multiline alias expansion release command is denied" \
  $'shopt -s expand_aliases\nalias r="gh release create"\nr v1.2.1'
assert_denied_command "Scenario 49ar: case branch release command is denied" \
  "case x in x) gh release create v1.2.1;; esac"
assert_denied_command "Scenario 49as: python static interpreter payload release command is denied" \
  "python3 -c 'import os; os.system(\"gh release create v1.2.1\")'"
assert_denied_command "Scenario 49at: perl static interpreter payload release command is denied" \
  "perl -e 'system(\"gh release create v1.2.1\")'"
assert_denied_command "Scenario 49au: ruby static interpreter payload release command is denied" \
  "ruby -e 'system(\"gh release create v1.2.1\")'"
assert_denied_command "Scenario 49av: node static interpreter payload release command is denied" \
  "node -e 'require(\"child_process\").execSync(\"gh release create v1.2.1\")'"
assert_denied_command "Scenario 49av0a: python base64-decoded release payload is denied" \
  "python3 -c 'import base64, os; os.system(base64.b64decode(\"Z2ggcmVsZWFzZSBjcmVhdGUgdjEuMi4xIC0tdGFyZ2V0IEhFQUQ=\").decode())'"
assert_denied_command "Scenario 49av0b: shell base64-decoded release payload is denied" \
  'bash -c "$(printf %s Z2ggcmVsZWFzZSBjcmVhdGUgdjEuMi4xIC0tdGFyZ2V0IEhFQUQ= | base64 -d)"'
assert_denied_command "Scenario 49av0c: node base64-decoded release payload is denied" \
  "node -e 'require(\"child_process\").execSync(Buffer.from(\"Z2l0IHB1c2ggb3JpZ2luIHYxLjIuMQ==\", \"base64\").toString())'"
_local_script_dir="$(mktemp -d)"
cat > "${_local_script_dir}/release.sh" <<'EOF'
#!/usr/bin/env bash
gh release create v1.2.1
EOF
chmod +x "${_local_script_dir}/release.sh"
cat > "${_local_script_dir}/publish.py" <<'EOF'
import subprocess
subprocess.run(["gh", "release", "create", "v1.2.1"])
EOF
cat > "${_local_script_dir}/publish.js" <<'EOF'
require("child_process").execSync("gh release create v1.2.1")
EOF
cat > "${_local_script_dir}/tag.sh" <<'EOF'
git push origin v1.2.1
EOF
cat > "${_local_script_dir}/deploy" <<'EOF'
#!/usr/bin/env bash
gh release create v1.2.1
EOF
chmod +x "${_local_script_dir}/deploy"
assert_denied_command "Scenario 49av1: bash local release script is denied" \
  "bash ${_local_script_dir}/release.sh"
assert_denied_command "Scenario 49av2: sh local tag script is denied" \
  "sh ${_local_script_dir}/tag.sh"
assert_denied_command "Scenario 49av3: python local release script is denied" \
  "python3 ${_local_script_dir}/publish.py"
assert_denied_command "Scenario 49av4: node local release script is denied" \
  "node ${_local_script_dir}/publish.js"
assert_denied_command "Scenario 49av5: direct local release script is denied" \
  "${_local_script_dir}/release.sh"
assert_denied_command "Scenario 49av6: source local release script is denied" \
  "source ${_local_script_dir}/release.sh"
assert_denied_command "Scenario 49av7: direct executable script without release hint is denied" \
  "${_local_script_dir}/deploy"
rm -rf "${_local_script_dir}"
assert_denied_command "Scenario 49aw: gh api GraphQL createRelease mutation is denied" \
  "gh api graphql -f query='mutation { createRelease(input:{repositoryId:\"R\", tagName:\"v1\"}) { release { id } } }'"
assert_denied_command "Scenario 49aw2: gh api full GraphQL URL createRelease mutation is denied" \
  "gh api https://api.github.com/graphql -f query='mutation { createRelease(input:{repositoryId:\"R\", tagName:\"v1\"}) { release { id } } }'"
assert_denied_command "Scenario 49aw3: gh api GHE full release URL is denied" \
  "gh api https://github.example.com/api/v3/repos/acme/sidekick/releases -X POST -f tag_name=v1.2.1"
assert_denied_command "Scenario 49aw4: gh api GraphQL unicode-escaped createRelease mutation name is denied" \
  "gh api graphql -f query='mutation { \\u0063reateRelease(input:{repositoryId:\"R\", tagName:\"v1\"}) { release { id } } }'"
assert_denied_command "Scenario 49ax: gh api GraphQL createRef tag mutation is denied" \
  "gh api -X POST graphql -f query='mutation { createRef(input:{ref:\"refs/tags/v1\"}) { ref { id } } }'"
assert_denied_command "Scenario 49ax2: gh api GraphQL unicode-escaped createRef tag mutation is denied" \
  "gh api -X POST graphql -f query='mutation { createRef(input:{ref:\"refs\\u002ftags\\u002fv1\"}) { ref { id } } }'"
assert_denied_command "Scenario 49ax3: gh api GraphQL unicode-escaped createRef mutation name is denied" \
  "gh api -X POST graphql -f query='mutation { \\u0063reateRef(input:{ref:\"refs/tags/v1\", oid:\"abc\"}) { ref { id } } }'"
assert_denied_command "Scenario 49ay: gh api GraphQL input file write is denied" \
  "gh api graphql --input release-mutation.json"
assert_denied_command "Scenario 49az: gh CLI release alias definition is denied" \
  "gh alias set r 'release create'"
assert_denied_command "Scenario 49ba: gh CLI release alias execution is denied" \
  "gh alias set rr 'repo view' && gh alias set r 'release create' && gh r v1.2.1"
assert_denied_command "Scenario 49ba1: gh CLI trailing --shell alias execution is denied" \
  "gh alias set rc --shell 'gh release create' && gh rc v1.2.1"
assert_denied_command "Scenario 49ba1b: gh CLI trailing -s alias execution is denied" \
  "gh alias set rc -s 'gh release create' && gh rc v1.2.1"
assert_denied_command "Scenario 49ba2: gh CLI alias file import is denied before same-command execution" \
  "printf 'r: release create\n' > /tmp/sidekick-gh-alias.yml; gh alias import /tmp/sidekick-gh-alias.yml; gh r v1.2.1"
assert_denied_command "Scenario 49ba3: gh CLI alias stdin import is denied before same-command execution" \
  "printf 'r: release create\n' | gh alias import -; gh r v1.2.1"
assert_denied_command "Scenario 49bb: gh api attached DELETE tag ref endpoint is denied" \
  "gh api -XDELETE repos/alo-exp/sidekick/git/refs/tags/v1.2.1"
assert_denied_command "Scenario 49bc: gh api attached POST release endpoint is denied" \
  "gh api -XPOST repos/alo-exp/sidekick/releases -f tag_name=v1.2.1"
assert_denied_command "Scenario 49bd: gh api GraphQL query file field is denied" \
  "gh api graphql -F query=@release-mutation.graphql"
assert_denied_command "Scenario 49be: gh api GraphQL stdin query field is denied" \
  "printf 'mutation { createRelease(input:{repositoryId:\"R\", tagName:\"v1\"}) { release { id } } }' | gh api graphql -F query=@-"
assert_denied_command "Scenario 49bf: gh api GraphQL attached query file field is denied" \
  "gh api graphql -Fquery=@release-mutation.graphql"
assert_denied_command "Scenario 49bg: gh api GraphQL long option query file field is denied" \
  "gh api graphql --field=query=@release-mutation.graphql"
assert_denied_command "Scenario 49bh: python argv-vector release command is denied" \
  "python3 -c 'import subprocess; subprocess.run([\"gh\",\"release\",\"create\",\"v1.2.1\"])'"
assert_denied_command "Scenario 49bh1a: python argv-vector git release tag push is denied" \
  "python3 -c 'import subprocess; subprocess.run([\"git\",\"push\",\"origin\",\"v1.2.1\"])'"
assert_denied_command "Scenario 49bh2: python concatenated argv-vector release command is denied" \
  "python3 -c 'import subprocess; subprocess.run([\"gh\",\"release\",\"cre\"+\"ate\",\"v1.2.1\"])'"
assert_denied_command "Scenario 49bh3: python variable-concatenated shell release command is denied" \
  "python3 -c 'import os; cmd=\"gh release\"; os.system(cmd+\" create v1.2.1\")'"
assert_denied_command "Scenario 49bh4: python argv fragment release command is denied" \
  "python3 -c 'import subprocess,sys; subprocess.run([\"g\"+sys.argv[1],\"release\",\"create\",\"v1.2.1\"])' h"
assert_denied_command "Scenario 49bi: node argv-vector release command is denied" \
  "node -e 'require(\"child_process\").execFileSync(\"gh\",[\"release\",\"create\",\"v1.2.1\"])'"
assert_denied_command "Scenario 49bi1: node shell git release tag push is denied" \
  "node -e 'require(\"child_process\").execSync(\"git push origin v1.2.1\")'"
assert_denied_command "Scenario 49bj: ruby argv-vector release command is denied" \
  "ruby -e 'system(\"gh\",\"release\",\"create\",\"v1.2.1\")'"
assert_denied_command "Scenario 49bk: perl argv-vector release command is denied" \
  "perl -e 'system(\"gh\",\"release\",\"create\",\"v1.2.1\")'"
assert_denied_command "Scenario 49bl: python heredoc release script is denied" \
  $'python3 - <<\'PY\'\nimport os\nos.system("gh release create v1.2.1")\nPY'
assert_denied_command "Scenario 49bm: node heredoc release script is denied" \
  $'node <<\'JS\'\nrequire("child_process").execSync("gh release create v1.2.1")\nJS'
assert_denied_command "Scenario 49bn: ruby heredoc release script is denied" \
  $'ruby <<\'RB\'\nsystem("gh","release","create","v1.2.1")\nRB'
assert_denied_command "Scenario 49bo: perl heredoc release script is denied" \
  $'perl <<\'PL\'\nsystem("gh","release","create","v1.2.1")\nPL'
assert_denied_command "Scenario 49bp: python stdin release script is denied" \
  "printf 'import os; os.system(\"gh release create v1.2.1\")' | python3 -"
assert_denied_command "Scenario 49bp2: python here-string release script is denied" \
  "python3 <<< 'import os; os.system(\"gh release create v1.2.1\")'"
assert_denied_command "Scenario 49bp3: node here-string release script is denied" \
  "node <<< 'require(\"child_process\").execSync(\"gh release create v1.2.1\")'"
assert_denied_command "Scenario 49bp4: python process-substitution release script is denied" \
  "python3 <(printf 'import os; os.system(\"gh release create v1.2.1\")')"
assert_denied_command_with_gh_aliases "Scenario 49bq: persistent gh release alias execution is denied" \
  "gh r v1.2.1" $'r\trelease create'
assert_denied_command_with_gh_aliases "Scenario 49bq2: persistent gh shell alias execution is denied" \
  "gh rc v1.2.1" "rc: '!gh release create'"
assert_denied_command_with_command_scoped_gh_alias \
  "Scenario 49br: command-scoped GH_CONFIG_DIR release alias execution is denied"
assert_denied_command "Scenario 49bs: literal variable shell payload release command is denied" \
  'cmd="gh release create v1.2.1"; bash -c "$cmd"'
assert_denied_command "Scenario 49bt: braced literal variable shell payload release command is denied" \
  'cmd="gh release create"; bash -c "${cmd} v1.2.1"'
assert_denied_command "Scenario 49bu: gh api GraphQL dynamic query field is denied" \
  'gh api graphql -F query="$(cat release-mutation.graphql)"'
assert_denied_command "Scenario 49bv: gh api GraphQL attached dynamic query field is denied" \
  'gh api graphql -Fquery="$(cat release-mutation.graphql)"'
assert_denied_command "Scenario 49bw: braced embedded literal variable assembles command word" \
  'h=h; g${h} release create v1.2.1'
assert_denied_command "Scenario 49bx: adjacent braced literal variables assemble command word" \
  'a=g; b=h; ${a}${b} release create v1.2.1'
assert_denied_command "Scenario 49by: adjacent indexed array expansions assemble command word" \
  'a=(g h); ${a[0]}${a[1]} release create v1.2.1'
assert_denied_command "Scenario 49bz: sudo command-scoped env release command is denied" \
  "sudo GH_TOKEN=x gh release create v1.2.1"
assert_denied_command "Scenario 49ca: doas release command is denied" \
  "doas gh release create v1.2.1"
assert_denied_command_with_gh_global_config_alias \
  "Scenario 49cb: gh --config-dir alias execution is denied" \
  "gh --config-dir __GH_CONFIG_DIR__ rel v1.2.1"
assert_denied_command_with_gh_global_config_alias \
  "Scenario 49cc: gh --config-dir= alias execution is denied" \
  "gh --config-dir=__GH_CONFIG_DIR__ rel v1.2.1"
assert_denied_command_with_gh_global_config_alias \
  "Scenario 49cd: exported GH_CONFIG_DIR alias execution is denied" \
  "export GH_CONFIG_DIR=__GH_CONFIG_DIR__; gh rel v1.2.1"
assert_denied_command_with_gh_global_config_alias \
  "Scenario 49ce: declare-exported GH_CONFIG_DIR alias execution is denied" \
  "declare -x GH_CONFIG_DIR=__GH_CONFIG_DIR__; gh rel v1.2.1"
assert_gh_alias_lookup_sanitizes_env \
  "Scenario 49cf: persistent gh alias lookup sanitizes secret env"
assert_denied_command "Scenario 49cg: nice wrapper release command is denied" \
  "nice gh release create v1.2.1"
assert_denied_command "Scenario 49ch: nohup wrapper release command is denied" \
  "nohup gh release create v1.2.1"
assert_denied_command "Scenario 49ci: setsid wrapper release command is denied" \
  "setsid gh release create v1.2.1"
assert_denied_command "Scenario 49cj: env split-string nice wrapper release command is denied" \
  "env -S \"nice gh release create v1.2.1\""
NESTED_RELEASE_COMMAND="gh release create v1.2.1"
for _ in 1 2 3 4 5 6; do
  NESTED_RELEASE_COMMAND="bash -c $(printf '%q' "${NESTED_RELEASE_COMMAND}")"
done
assert_denied_command "Scenario 49ck: deeply nested shell wrappers are denied" \
  "${NESTED_RELEASE_COMMAND}"
assert_denied_command "Scenario 49cl: git push release tag shorthand is denied" \
  "git push origin v1.2.1"
assert_denied_command "Scenario 49cm: git push release tag ref is denied" \
  "git push origin refs/tags/v1.2.1"
assert_denied_command "Scenario 49cn: git push release tag destination is denied" \
  "git push origin HEAD:refs/tags/v1.2.1"
assert_denied_command "Scenario 49co: git push all tags is denied" \
  "git push --tags origin"
assert_denied_command "Scenario 49cp: git push follow-tags is denied" \
  "git push --follow-tags origin main"
assert_denied_command "Scenario 49cq: git push dynamic release tag variable is denied" \
  'git push origin "$TAG"'
assert_denied_command "Scenario 49cq2: git push generic dynamic refspec fails closed" \
  'git push origin "$x"'
assert_denied_command "Scenario 49cr: git push dynamic release tag ref is denied" \
  'git push origin refs/tags/$TAG'
assert_denied_command "Scenario 49cs: git push command-substitution refspec is denied" \
  'git push origin "$(cat VERSION)"'
assert_denied_command "Scenario 49cs2: git push explicit non-v tag ref is denied" \
  "git push origin refs/tags/release-candidate"
assert_denied_command "Scenario 49cs3: git push explicit numeric tag ref is denied" \
  "git push origin refs/tags/0.6.0"
assert_denied_command "Scenario 49cs4: git push explicit tag deletion refspec is denied" \
  "git push origin :refs/tags/release-candidate"
assert_denied_command "Scenario 49cs5: git push tag operand with dynamic tag is denied" \
  'git push origin tag "$TAG"'
assert_denied_command "Scenario 49cs5b: git push bare numeric semver tag is denied" \
  "git push origin 0.6.0"
assert_denied_command "Scenario 49cs6: git command-scoped release tag alias is denied" \
  'git -c alias.sidekickreleasepush="push origin v1.2.1" sidekickreleasepush'
assert_denied_command "Scenario 49cs6b: chained git command-scoped release tag aliases are denied" \
  'git -c alias.releasepush="push origin v1.2.1" -c alias.r=releasepush r'
assert_denied_command "Scenario 49cs7: git command-scoped shell release tag alias is denied" \
  'git -c alias.sidekickshellreleasepush="!git push origin v1.2.1" sidekickshellreleasepush'
assert_denied_command_with_git_alias_config "Scenario 49cs8: persistent git release tag alias is denied" \
  "git sidekickreleasepush" \
  "[alias]
  sidekickreleasepush = push origin v1.2.1"
assert_denied_command "Scenario 49cs8a: same-command git config release alias is denied without markers" \
  "git config alias.ship 'push origin HEAD:refs/tags/v1.2.1' && git ship"
assert_denied_release_command_with_current_markers \
  "Scenario 49cs8b: same-command git config release alias is denied with markers" \
  "git config alias.ship 'push origin HEAD:refs/tags/v1.2.1' && git ship"
assert_passthrough_command "Scenario 49cs9: dynamic branch refspec passes through" \
  'git push origin "$BRANCH"'
assert_denied_command_with_env_var "Scenario 49cs9b: inherited BRANCH semver tag is denied" \
  'git push origin "$BRANCH"' "BRANCH" "v1.2.1"
assert_passthrough_command "Scenario 49cs9c: gh release create help passes through" \
  "gh release create --help"
assert_denied_command_with_current_markers "Scenario 49cs9d: gh release delete remains denied with current HEAD markers" \
  "gh release delete v0.5.0 --yes"

echo "Scenario 49cs10: release tag pushes require local tag target markers"
STALE_TAG_REPO="$(mktemp -d)"
git -C "${STALE_TAG_REPO}" init -q
git -C "${STALE_TAG_REPO}" remote add origin https://github.com/alo-exp/sidekick.git
printf '%s\n' "old target" > "${STALE_TAG_REPO}/README.md"
git -C "${STALE_TAG_REPO}" add README.md
git -C "${STALE_TAG_REPO}" -c user.email=sidekick@example.invalid -c user.name=Sidekick commit -q -m old-target
stale_tag_sha="$(git -C "${STALE_TAG_REPO}" rev-parse --short=12 HEAD)"
git -C "${STALE_TAG_REPO}" update-ref refs/tags/v7.7.7 HEAD
printf '%s\n' "new head" > "${STALE_TAG_REPO}/README.md"
git -C "${STALE_TAG_REPO}" add README.md
git -C "${STALE_TAG_REPO}" -c user.email=sidekick@example.invalid -c user.name=Sidekick commit -q -m new-head
stale_repo_head_sha="$(git -C "${STALE_TAG_REPO}" rev-parse --short=12 HEAD)"
stale_git_push_command="git -C ${STALE_TAG_REPO} push origin v7.7.7"
H="$(setup_home)"
write_markers_for_sha "${H}" "${stale_repo_head_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${stale_repo_head_sha}" 2
PAYLOAD="$(jq -cn --arg cmd "${stale_git_push_command}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "git push stale tag with HEAD markers is denied"
else
  assert_fail "git push stale tag with HEAD markers" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
H="$(setup_home)"
write_markers_for_sha "${H}" "${stale_tag_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${stale_tag_sha}" 2
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "git push stale tag with tag target markers is denied"
else
  assert_fail "git push stale tag with tag target markers deny" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
stale_git_alias_command="git -C ${STALE_TAG_REPO} -c alias.releasepush=\"push origin v7.7.7\" -c alias.r=releasepush r"
H="$(setup_home)"
write_markers_for_sha "${H}" "${stale_repo_head_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${stale_repo_head_sha}" 2
PAYLOAD="$(jq -cn --arg cmd "${stale_git_alias_command}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "git alias stale tag with HEAD markers is denied"
else
  assert_fail "git alias stale tag with HEAD markers" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
H="$(setup_home)"
write_markers_for_sha "${H}" "${stale_tag_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${stale_tag_sha}" 2
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "git alias stale tag with tag target markers is denied"
else
  assert_fail "git alias stale tag with tag target markers deny" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
stale_gh_release_command="gh release create v7.7.7"
H="$(setup_home)"
write_markers_for_sha "${H}" "${stale_repo_head_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${stale_repo_head_sha}" 2
PAYLOAD="$(jq -cn --arg cmd "${stale_gh_release_command}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook_from_cwd "${H}" "${PAYLOAD}" "${STALE_TAG_REPO}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "unverified gh release stale tag with HEAD markers is denied"
else
  assert_fail "unverified gh release stale tag with HEAD markers" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
H="$(setup_home)"
write_markers_for_sha "${H}" "${stale_tag_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${stale_tag_sha}" 2
OUT="$(run_hook_from_cwd "${H}" "${PAYLOAD}" "${STALE_TAG_REPO}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "unverified gh release stale tag with tag target markers is denied"
else
  assert_fail "unverified gh release stale tag with tag target markers" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
stale_gh_verified_release_command="gh release create v7.7.7 --verify-tag"
H="$(setup_home)"
write_markers_for_sha "${H}" "${stale_tag_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${stale_tag_sha}" 2
PAYLOAD="$(jq -cn --arg cmd "${stale_gh_verified_release_command}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook_from_cwd "${H}" "${PAYLOAD}" "${STALE_TAG_REPO}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "verified gh release stale tag is denied with local tag target markers"
else
  assert_fail "verified gh release stale tag with local tag target markers" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
stale_gh_target_release_command="gh release create v7.7.7 --repo alo-exp/sidekick --target ${stale_repo_head_sha}"
stale_remote_tag_output="${stale_tag_sha}"$'\t'"refs/tags/v7.7.7"$'\n'
H="$(setup_home)"
write_markers_for_sha "${H}" "${stale_repo_head_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${stale_repo_head_sha}" 2
PAYLOAD="$(jq -cn --arg cmd "${stale_gh_target_release_command}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
SIDEKICK_TEST_LS_REMOTE_OUTPUT="${stale_remote_tag_output}"
OUT="$(run_hook_from_cwd "${H}" "${PAYLOAD}" "${STALE_TAG_REPO}")"; RC=$?
unset SIDEKICK_TEST_LS_REMOTE_OUTPUT
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "gh release --target current SHA is denied when remote tag is stale"
else
  assert_fail "gh release --target current SHA with stale remote tag" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
same_command_retag_push="git -C ${STALE_TAG_REPO} tag -f v7.7.7 HEAD && git -C ${STALE_TAG_REPO} push origin v7.7.7"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cs10a: same-command retag before git push is denied with stale tag markers" \
  "${same_command_retag_push}" "${stale_tag_sha}"
same_command_update_ref_push="git -C ${STALE_TAG_REPO} update-ref refs/tags/v7.7.7 HEAD && git -C ${STALE_TAG_REPO} push origin v7.7.7"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cs10b: same-command update-ref before git push is denied with stale tag markers" \
  "${same_command_update_ref_push}" "${stale_tag_sha}"
same_command_retag_gh_release="git tag -f v7.7.7 HEAD && gh release create v7.7.7 --verify-tag"
assert_denied_release_command_with_sha_markers_from_cwd \
  "Scenario 49cs10c: same-command retag before verified gh release is denied with stale tag markers" \
  "${same_command_retag_gh_release}" "${stale_tag_sha}" "${STALE_TAG_REPO}"
same_command_update_ref_gh_release="git update-ref refs/tags/v7.7.7 HEAD && gh release create v7.7.7 --verify-tag"
assert_denied_release_command_with_sha_markers_from_cwd \
  "Scenario 49cs10d: same-command update-ref before verified gh release is denied with stale tag markers" \
  "${same_command_update_ref_gh_release}" "${stale_tag_sha}" "${STALE_TAG_REPO}"
stale_gh_false_verified_release_command="gh release create v7.7.7 --verify-tag=false"
H="$(setup_home)"
write_markers_for_sha "${H}" "${stale_tag_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${stale_tag_sha}" 2
PAYLOAD="$(jq -cn --arg cmd "${stale_gh_false_verified_release_command}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook_from_cwd "${H}" "${PAYLOAD}" "${STALE_TAG_REPO}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "gh release --verify-tag=false is denied with tag target markers"
else
  assert_fail "gh release --verify-tag=false with tag target markers" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}" "${STALE_TAG_REPO}"

echo "Scenario 49ct: git push release tag passes after gate markers"
H="$(setup_home)"
write_markers "${H}" 1 2 3 4
write_live_pyramid_markers "${H}" 2
release_gate_test_tag="v987.654.321"
git -C "${REPO_ROOT}" update-ref "refs/tags/${release_gate_test_tag}" HEAD
PAYLOAD="$(jq -cn --arg cmd "git push origin ${release_gate_test_tag}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ -z "${DECISION}" ] && [ -z "${OUT}" ]; then
  assert_pass "git push release tag passes after gate markers"
else
  assert_fail "git push release tag passes after gate markers" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
H="$(setup_home)"
write_markers "${H}" 1 2 3 4
write_live_pyramid_markers "${H}" 2
PAYLOAD="$(jq -cn --arg cmd "git push https://github.com/attacker/other.git ${release_gate_test_tag}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "git push release tag to different URL is denied"
else
  assert_fail "git push release tag to different URL" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
H="$(setup_home)"
write_markers "${H}" 1 2 3 4
write_live_pyramid_markers "${H}" 2
PAYLOAD="$(jq -cn --arg cmd "git push https://github.com/alo-exp/sidekick.git ${release_gate_test_tag}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ -z "${DECISION}" ] && [ -z "${OUT}" ]; then
  assert_pass "git push release tag to Sidekick URL passes after gate markers"
else
  assert_fail "git push release tag to Sidekick URL" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
compound_release_gate_test_tag="v987.654.322"
git -C "${REPO_ROOT}" update-ref "refs/tags/${compound_release_gate_test_tag}" HEAD
assert_denied_release_command_with_current_markers \
  "Scenario 49ct0a: git push with two release tags is denied" \
  "git push origin ${release_gate_test_tag} ${compound_release_gate_test_tag}"
assert_denied_release_command_with_current_markers \
  "Scenario 49ct0b: git push mixed tag forms is denied" \
  "git push origin tag ${release_gate_test_tag} HEAD:refs/tags/${compound_release_gate_test_tag}"
assert_denied_release_command_with_current_markers \
  "Scenario 49ct0c: git push forced release tag is denied" \
  "git push --force origin ${release_gate_test_tag}"
assert_denied_release_command_with_current_markers \
  "Scenario 49ct0d: git push plus-prefixed release tag is denied" \
  "git push origin +${release_gate_test_tag}"
assert_denied_release_command_with_current_markers \
  "Scenario 49ct0e: git push delete release tag is denied" \
  "git push --delete origin ${release_gate_test_tag}"
assert_denied_release_command_with_current_markers \
  "Scenario 49ct0f: git push empty-source release tag deletion is denied" \
  "git push origin :refs/tags/${release_gate_test_tag}"
PUSHURL_RELEASE_CWD="$(mktemp -d)"
git -C "${PUSHURL_RELEASE_CWD}" init -q
git -C "${PUSHURL_RELEASE_CWD}" remote add origin https://github.com/alo-exp/sidekick.git
git -C "${PUSHURL_RELEASE_CWD}" remote set-url --push origin https://github.com/attacker/other.git
printf '%s\n' "release target" > "${PUSHURL_RELEASE_CWD}/README.md"
git -C "${PUSHURL_RELEASE_CWD}" add README.md
git -C "${PUSHURL_RELEASE_CWD}" -c user.email=sidekick@example.invalid -c user.name=Sidekick commit -q -m release-target
pushurl_release_sha="$(git -C "${PUSHURL_RELEASE_CWD}" rev-parse --short=12 HEAD)"
H="$(setup_home)"
write_markers_for_sha "${H}" "${pushurl_release_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${pushurl_release_sha}" 2
PAYLOAD="$(jq -cn --arg cmd "git -C ${PUSHURL_RELEASE_CWD} push origin HEAD:refs/tags/v1.2.1" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "git push release tag honors attacker pushurl and is denied"
else
  assert_fail "git push release tag honors attacker pushurl" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}" "${PUSHURL_RELEASE_CWD}"
PERSISTENT_REWRITE_CWD="$(mktemp -d)"
git -C "${PERSISTENT_REWRITE_CWD}" init -q
git -C "${PERSISTENT_REWRITE_CWD}" remote add origin https://github.com/alo-exp/sidekick.git
printf '%s\n' "release target" > "${PERSISTENT_REWRITE_CWD}/README.md"
git -C "${PERSISTENT_REWRITE_CWD}" add README.md
git -C "${PERSISTENT_REWRITE_CWD}" -c user.email=sidekick@example.invalid -c user.name=Sidekick commit -q -m release-target
persistent_rewrite_sha="$(git -C "${PERSISTENT_REWRITE_CWD}" rev-parse --short=12 HEAD)"
git -C "${PERSISTENT_REWRITE_CWD}" config url.https://attacker.example/alo-exp/sidekick/.pushInsteadOf https://github.com/alo-exp/sidekick
H="$(setup_home)"
write_markers_for_sha "${H}" "${persistent_rewrite_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${persistent_rewrite_sha}" 2
PAYLOAD="$(jq -cn --arg cmd "git -C ${PERSISTENT_REWRITE_CWD} push origin HEAD:refs/tags/v1.2.1" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "git push release tag honors persistent pushInsteadOf rewrite and is denied"
else
  assert_fail "git push release tag honors persistent pushInsteadOf rewrite" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
H="$(setup_home)"
write_markers_for_sha "${H}" "${persistent_rewrite_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${persistent_rewrite_sha}" 2
PAYLOAD="$(jq -cn --arg cmd "git -C ${PERSISTENT_REWRITE_CWD} push https://github.com/alo-exp/sidekick.git HEAD:refs/tags/v1.2.1" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "direct git push release tag honors persistent pushInsteadOf rewrite and is denied"
else
  assert_fail "direct git push release tag honors persistent pushInsteadOf rewrite" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
git -C "${PERSISTENT_REWRITE_CWD}" config --unset-all url.https://attacker.example/alo-exp/sidekick/.pushInsteadOf
git -C "${PERSISTENT_REWRITE_CWD}" config url.https://attacker.example/alo-exp/sidekick/.insteadOf https://github.com/alo-exp/sidekick
H="$(setup_home)"
write_markers_for_sha "${H}" "${persistent_rewrite_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${persistent_rewrite_sha}" 2
PAYLOAD="$(jq -cn --arg cmd "git -C ${PERSISTENT_REWRITE_CWD} push origin HEAD:refs/tags/v1.2.1" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "git push release tag honors persistent insteadOf rewrite and is denied"
else
  assert_fail "git push release tag honors persistent insteadOf rewrite" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}" "${PERSISTENT_REWRITE_CWD}"
assert_denied_release_command_with_current_markers \
  "Scenario 49ct2: git --git-dir/--work-tree release tag push is denied" \
  "git --git-dir=${REPO_ROOT}/.git --work-tree=${REPO_ROOT} push origin HEAD:refs/tags/${release_gate_test_tag}"
assert_denied_release_command_with_current_markers \
  "Scenario 49ct3: git command-scoped remote URL rewrite is denied" \
  "git -c remote.origin.url=https://github.com/attacker/other.git push origin HEAD:refs/tags/${release_gate_test_tag}"
assert_denied_release_command_with_current_markers \
  "Scenario 49ct4: git command-scoped URL insteadOf rewrite is denied" \
  "git -c url.https://github.com/attacker/other.git.insteadOf=https://github.com/alo-exp/sidekick.git push https://github.com/alo-exp/sidekick.git ${release_gate_test_tag}"
assert_denied_release_command_with_current_markers \
  "Scenario 49ct5: same-command git config pushInsteadOf rewrite is denied" \
  "git config url.https://attacker.example/alo-exp/sidekick/.pushInsteadOf https://github.com/alo-exp/sidekick && git push https://github.com/alo-exp/sidekick.git ${release_gate_test_tag}"
assert_denied_release_command_with_current_markers \
  "Scenario 49ct6: same-command git remote push URL rewrite is denied" \
  "git remote set-url --push origin https://github.com/attacker/other.git && git push origin ${release_gate_test_tag}"
git -C "${REPO_ROOT}" update-ref -d "refs/tags/${release_gate_test_tag}" >/dev/null 2>&1 || true
git -C "${REPO_ROOT}" update-ref -d "refs/tags/${compound_release_gate_test_tag}" >/dev/null 2>&1 || true

echo "Scenario 49cu: git -C release tag push requires target repository markers"
GIT_C_RELEASE_CWD="$(mktemp -d)"
git -C "${GIT_C_RELEASE_CWD}" init -q
git -C "${GIT_C_RELEASE_CWD}" remote add origin https://github.com/attacker/other.git
printf '%s\n' "release target" > "${GIT_C_RELEASE_CWD}/README.md"
git -C "${GIT_C_RELEASE_CWD}" add README.md
git -C "${GIT_C_RELEASE_CWD}" -c user.email=sidekick@example.invalid -c user.name=Sidekick commit -q -m release-target
git -C "${GIT_C_RELEASE_CWD}" update-ref refs/tags/v1.2.1 HEAD
git_c_release_sha="$(git -C "${GIT_C_RELEASE_CWD}" rev-parse --short=12 HEAD)"
H="$(setup_home)"
write_markers "${H}" 1 2 3 4
write_live_pyramid_markers "${H}" 2
PAYLOAD="$(jq -cn --arg cmd "git -C ${GIT_C_RELEASE_CWD} push origin v1.2.1" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "git -C release tag push with wrong repo markers is denied"
else
  assert_fail "git -C release tag push with wrong repo markers" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
H="$(setup_home)"
write_markers_for_sha "${H}" "${git_c_release_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${git_c_release_sha}" 2
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "git -C release tag push to different origin is denied with target markers"
else
  assert_fail "git -C release tag push to different origin with target markers" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
git -C "${GIT_C_RELEASE_CWD}" remote set-url origin https://github.com/alo-exp/sidekick.git
H="$(setup_home)"
write_markers_for_sha "${H}" "${git_c_release_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${git_c_release_sha}" 2
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ -z "${DECISION}" ] && [ -z "${OUT}" ]; then
  assert_pass "git -C release tag push passes with target repo markers"
else
  assert_fail "git -C release tag push with target repo markers" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
wrapped_git_c_release_command="bash -lc 'git -C ${GIT_C_RELEASE_CWD} push origin v1.2.1'"
assert_denied_release_command_with_current_markers \
  "Scenario 49cu2: shell-wrapped git -C release tag push with wrong repo markers is denied" \
  "${wrapped_git_c_release_command}"
assert_passthrough_release_command_with_sha_markers \
  "Scenario 49cu3: shell-wrapped git -C release tag push passes with target repo markers" \
  "${wrapped_git_c_release_command}" "${git_c_release_sha}"
git_c_shell_alias_release_command="git -c alias.r=\"!git -C ${GIT_C_RELEASE_CWD} push origin v1.2.1\" r"
assert_denied_release_command_with_current_markers \
  "Scenario 49cu4: git -C shell alias release tag push with wrong repo markers is denied" \
  "${git_c_shell_alias_release_command}"
assert_passthrough_release_command_with_sha_markers \
  "Scenario 49cu5: git -C shell alias release tag push passes with target repo markers" \
  "${git_c_shell_alias_release_command}" "${git_c_release_sha}"
git_c_chained_alias_release_command="git -C ${GIT_C_RELEASE_CWD} -c alias.releasepush=\"push origin v1.2.1\" -c alias.r=releasepush r"
assert_denied_release_command_with_current_markers \
  "Scenario 49cu6: git -C chained alias release tag push with wrong repo markers is denied" \
  "${git_c_chained_alias_release_command}"
assert_passthrough_release_command_with_sha_markers \
  "Scenario 49cu7: git -C chained alias release tag push passes with target repo markers" \
  "${git_c_chained_alias_release_command}" "${git_c_release_sha}"
shell_alias_git_c_release_command="shopt -s expand_aliases; alias r='git -C ${GIT_C_RELEASE_CWD} push origin v1.2.1'; r"
assert_denied_release_command_with_current_markers \
  "Scenario 49cu7b: shell alias git -C release tag push with wrong repo markers is denied" \
  "${shell_alias_git_c_release_command}"
generated_script_git_c_release_command="printf 'git -C ${GIT_C_RELEASE_CWD} push origin v1.2.1' > ./sidekick-generated-release-target.sh; bash ./sidekick-generated-release-target.sh"
assert_denied_release_command_with_current_markers \
  "Scenario 49cu7c: generated script git -C release tag push with wrong repo markers is denied" \
  "${generated_script_git_c_release_command}"
echo "Scenario 49cu7d: persistent git alias with git -C release tag push requires resolvable target metadata"
H="$(setup_home)"
write_markers "${H}" 1 2 3 4
write_live_pyramid_markers "${H}" 2
PAYLOAD="$(jq -cn --arg cmd "git releasepush" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(SIDEKICK_GIT_ALIAS_CONFIG="[alias]
  releasepush = -C ${GIT_C_RELEASE_CWD} push origin v1.2.1" run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "persistent git alias git -C release tag push with wrong repo markers is denied"
else
  assert_fail "persistent git alias git -C release tag push with wrong repo markers" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
git -C "${GIT_C_RELEASE_CWD}" config alias.ship "push origin v1.2.1"
assert_denied_release_command_with_current_markers \
  "Scenario 49cu7e: git -C local persistent alias release tag push is denied without target metadata" \
  "git -C ${GIT_C_RELEASE_CWD} ship"
git_alias_cfg="$(mktemp)"
cat > "${git_alias_cfg}" <<CFG
[alias]
  ship = push origin v1.2.1
CFG
assert_denied_release_command_with_current_markers \
  "Scenario 49cu7f: command-scoped GIT_CONFIG_GLOBAL release alias is denied without target metadata" \
  "GIT_CONFIG_GLOBAL=${git_alias_cfg} git ship"
rm -f "${git_alias_cfg}"
GIT_C_OUTER="$(mktemp -d)"
GIT_C_INNER="${GIT_C_OUTER}/inner"
mkdir -p "${GIT_C_INNER}"
git -C "${GIT_C_INNER}" init -q
git -C "${GIT_C_INNER}" remote add origin https://github.com/alo-exp/sidekick.git
printf '%s\n' "nested release target" > "${GIT_C_INNER}/README.md"
git -C "${GIT_C_INNER}" add README.md
git -C "${GIT_C_INNER}" -c user.email=sidekick@example.invalid -c user.name=Sidekick commit -q -m nested-release-target
git -C "${GIT_C_INNER}" update-ref refs/tags/v1.2.1 HEAD
git_c_nested_sha="$(git -C "${GIT_C_INNER}" rev-parse --short=12 HEAD)"
git_c_nested_command="git -C ${GIT_C_OUTER} -C inner push origin v1.2.1"
assert_denied_release_command_with_current_markers \
  "Scenario 49cu8: composed git -C release tag push with wrong repo markers is denied" \
  "${git_c_nested_command}"
assert_passthrough_release_command_with_sha_markers \
  "Scenario 49cu9: composed git -C release tag push passes with target repo markers" \
  "${git_c_nested_command}" "${git_c_nested_sha}"
rm -rf "${GIT_C_OUTER}"
rm -rf "${GIT_C_RELEASE_CWD}"

echo "Scenario 49cv: gh release --target requires target ref markers"
target_ref_sha="$(git -C "${REPO_ROOT}" rev-parse --short=12 HEAD~1)"
H="$(setup_home)"
write_markers "${H}" 1 2 3 4
write_live_pyramid_markers "${H}" 2
PAYLOAD="$(jq -cn --arg cmd "gh release create v1.2.1 --target ${target_ref_sha}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "gh release --target with current HEAD markers is denied"
else
  assert_fail "gh release --target with current HEAD markers" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
H="$(setup_home)"
write_markers_for_sha "${H}" "${target_ref_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${target_ref_sha}" 2
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "gh release --target stale SHA is denied with target ref markers"
else
  assert_fail "gh release --target stale SHA with target ref markers deny" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
gh_target_repo_before_tag_command="gh release create --repo alo-exp/sidekick v1.2.1 --target $(current_head_sha)"
assert_passthrough_release_command_with_sha_markers \
  "Scenario 49cv-1: gh release --repo before tag passes with current target" \
  "${gh_target_repo_before_tag_command}" "$(current_head_sha)"
gh_target_repo_equals_before_tag_command="gh release create --repo=alo-exp/sidekick v1.2.1 --target $(current_head_sha)"
assert_passthrough_release_command_with_sha_markers \
  "Scenario 49cv-2: gh release --repo= before tag passes with current target" \
  "${gh_target_repo_equals_before_tag_command}" "$(current_head_sha)"
gh_target_short_repo_command="gh release create -R alo-exp/sidekick v1.2.1 --target $(current_head_sha)"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv-3: gh release -R repo shorthand is denied" \
  "${gh_target_short_repo_command}" "$(current_head_sha)"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv0: gh release --target symbolic branch is denied" \
  "gh release create v1.2.1 --target main"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv0a0: gh release --target command substitution is denied" \
  "$(substitution_target_release_command)"
multi_gh_mixed_target_command="gh release create v1.2.1 --target $(current_head_sha) && gh release create v2.2.2 --target ${target_ref_sha}"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv0a: multi-gh release with unauthorized second target is denied" \
  "${multi_gh_mixed_target_command}"
multi_gh_second_unresolved_command="gh release create v1.2.1 --target $(current_head_sha) && gh release create v2.2.2 --verify-tag"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv0b: multi-gh release with unresolvable second target is denied" \
  "${multi_gh_second_unresolved_command}"
nested_multi_gh_mixed_target_command="bash -lc 'gh release create v1.2.1 --target $(current_head_sha) && gh release create v2.2.2 --target ${target_ref_sha}'"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv0c: nested multi-gh release with unauthorized second target is denied" \
  "${nested_multi_gh_mixed_target_command}"
generated_script_multi_release_command="printf 'gh release create v2.2.2 --target ${target_ref_sha}' > ./deploy.sh; bash ./deploy.sh && gh release create v1.2.1 --target $(current_head_sha)"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv0c2: generated release script plus visible release is denied" \
  "${generated_script_multi_release_command}"
hidden_substitution_release_command="gh release create v1.2.1 --target $(current_head_sha) --notes \"\$(gh release create v2.2.2 --target $(current_head_sha))\""
assert_denied_release_command_with_current_markers \
  "Scenario 49cv0c3: release command hidden in substitution is denied" \
  "${hidden_substitution_release_command}"
same_command_force_redirect_release="printf x >| ./sidekick-review-temp.txt; gh release create v1.2.1 --target $(current_head_sha)"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv0c4: same-command force redirection plus release is denied" \
  "${same_command_force_redirect_release}"
same_command_read_write_redirect_release=": <> ./sidekick-review-temp.txt; gh release create v1.2.1 --target $(current_head_sha)"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv0c5: same-command read-write redirection plus release is denied" \
  "${same_command_read_write_redirect_release}"
multi_release_test_tag="v555.555.555"
git -C "${REPO_ROOT}" update-ref "refs/tags/${multi_release_test_tag}" HEAD
multi_git_push_then_gh_command="git push origin ${multi_release_test_tag} && gh release create v2.2.2 --target ${target_ref_sha}"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv0d: git tag push plus gh release in one command is denied" \
  "${multi_git_push_then_gh_command}"
multi_gh_api_then_git_push_command="gh api -X POST repos/alo-exp/sidekick/releases -f tag_name=v1.2.1 -f target_commitish=$(current_head_sha) && git push origin ${multi_release_test_tag}"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv0e: gh api release plus git tag push in one command is denied" \
  "${multi_gh_api_then_git_push_command}"
git -C "${REPO_ROOT}" update-ref -d "refs/tags/${multi_release_test_tag}" >/dev/null 2>&1 || true
gh_false_verify_target_after_command="gh release create v1.2.1 --target ${target_ref_sha} --verify-tag=false"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv1a: gh release --target with later --verify-tag=false is denied" \
  "${gh_false_verify_target_after_command}" "${target_ref_sha}"
gh_false_verify_target_before_command="gh release create v1.2.1 --verify-tag=false --target ${target_ref_sha}"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv1b: gh release --verify-tag=false before --target is denied" \
  "${gh_false_verify_target_before_command}" "${target_ref_sha}"
gh_false_verify_target_equals_command="gh release create v1.2.1 --target=${target_ref_sha} --verify-tag=false"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv1c: gh release --target= with --verify-tag=false is denied" \
  "${gh_false_verify_target_equals_command}" "${target_ref_sha}"
gh_verify_target_after_command="gh release create v1.2.1 --repo alo-exp/sidekick --target $(current_head_sha) --verify-tag"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv1d: gh release --target with --verify-tag is denied" \
  "${gh_verify_target_after_command}" "$(current_head_sha)"
gh_verify_target_before_command="gh release create v1.2.1 --repo alo-exp/sidekick --verify-tag --target $(current_head_sha)"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv1e: gh release --verify-tag before --target is denied" \
  "${gh_verify_target_before_command}" "$(current_head_sha)"
gh_verify_true_target_command="gh release create v1.2.1 --repo alo-exp/sidekick --target=$(current_head_sha) --verify-tag=true"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv1f: gh release --verify-tag=true with --target is denied" \
  "${gh_verify_true_target_command}" "$(current_head_sha)"
implicit_git_config_release_command="GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.url GIT_CONFIG_VALUE_0=https://github.com/attacker/not-sidekick.git gh release create v1.2.1 --target $(current_head_sha)"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv1g: implicit gh release with command-scoped git config is denied" \
  "${implicit_git_config_release_command}" "$(current_head_sha)"
wrapped_gh_target_command="bash -lc 'gh release create v1.2.1 --target ${target_ref_sha}'"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv2: shell-wrapped gh release --target with current HEAD markers is denied" \
  "${wrapped_gh_target_command}"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv3: shell-wrapped gh release --target stale SHA is denied with target ref markers" \
  "${wrapped_gh_target_command}" "${target_ref_sha}"
gh_target_alias_config="$(mktemp -d)"
cat > "${gh_target_alias_config}/aliases.yml" <<YAML
r: release create --target ${target_ref_sha}
YAML
gh_target_alias_command="gh --config-dir ${gh_target_alias_config} r v1.2.1"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv4: gh --config-dir release target alias with current HEAD markers is denied" \
  "${gh_target_alias_command}"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv5: gh --config-dir release target alias is denied even with target ref markers" \
  "${gh_target_alias_command}" "${target_ref_sha}"
gh_env_target_alias_command="GH_CONFIG_DIR=${gh_target_alias_config} gh r v1.2.1"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv5a: command-scoped GH_CONFIG_DIR release target alias with current HEAD markers is denied" \
  "${gh_env_target_alias_command}"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv5aa: command-scoped GH_CONFIG_DIR release target alias is denied even with target ref markers" \
  "${gh_env_target_alias_command}" "${target_ref_sha}"
rm -rf "${gh_target_alias_config}"
gh_same_command_target_alias="gh alias set rc 'release create --target ${target_ref_sha}' && gh rc v1.2.1"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv5b: same-command gh target alias with current HEAD markers is denied" \
  "${gh_same_command_target_alias}"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv5c: same-command gh target alias is denied even with target ref markers" \
  "${gh_same_command_target_alias}" "${target_ref_sha}"
gh_api_release_target_command="gh api -X POST repos/alo-exp/sidekick/releases -f tag_name=v1.2.1 -f target_commitish=${target_ref_sha}"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv6: gh api release target_commitish with current HEAD markers is denied" \
  "${gh_api_release_target_command}"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv7: gh api release target_commitish stale SHA is denied with target ref markers" \
  "${gh_api_release_target_command}" "${target_ref_sha}"
gh_api_current_release_target_command="gh api -X POST repos/alo-exp/sidekick/releases -f tag_name=v1.2.1 -f target_commitish=$(current_head_sha)"
assert_passthrough_release_command_with_sha_markers \
  "Scenario 49cv7b: gh api release target_commitish current SHA passes with current markers" \
  "${gh_api_current_release_target_command}" "$(current_head_sha)"
gh_api_delete_release_target_command="gh api -X DELETE repos/alo-exp/sidekick/releases/123 -f target_commitish=$(current_head_sha)"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv7c: gh api release DELETE with current target is denied" \
  "${gh_api_delete_release_target_command}" "$(current_head_sha)"
gh_api_patch_release_target_command="gh api -X PATCH repos/alo-exp/sidekick/releases/123 -f target_commitish=$(current_head_sha)"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv7d: gh api release PATCH with current target is denied" \
  "${gh_api_patch_release_target_command}" "$(current_head_sha)"
gh_api_symbolic_release_target_command="gh api -X POST repos/alo-exp/sidekick/releases -f tag_name=v1.2.1 -f target_commitish=main"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv7a: gh api symbolic target_commitish is denied" \
  "${gh_api_symbolic_release_target_command}"
gh_api_tag_ref_target_command="gh api -X POST repos/alo-exp/sidekick/git/refs -f ref=refs/tags/v1.2.1 -f sha=${target_ref_sha}"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv8: gh api tag ref sha with current HEAD markers is denied" \
  "${gh_api_tag_ref_target_command}"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv9: gh api tag ref stale SHA is denied with target ref markers" \
  "${gh_api_tag_ref_target_command}" "${target_ref_sha}"
gh_api_current_tag_ref_target_command="gh api -X POST repos/alo-exp/sidekick/git/refs -f ref=refs/tags/v1.2.1 -f sha=$(current_head_sha)"
assert_passthrough_release_command_with_sha_markers \
  "Scenario 49cv9b: gh api tag ref current SHA passes with current markers" \
  "${gh_api_current_tag_ref_target_command}" "$(current_head_sha)"
gh_api_force_true_body="$(mktemp)"
printf '{"ref":"refs/tags/v1.2.1","sha":"%s","force":true}\n' "$(current_head_sha)" > "${gh_api_force_true_body}"
gh_api_force_true_input_command="gh api -X POST repos/alo-exp/sidekick/git/refs --input ${gh_api_force_true_body}"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv9b1: gh api tag ref input force true is denied" \
  "${gh_api_force_true_input_command}" "$(current_head_sha)"
rm -f "${gh_api_force_true_body}"
gh_api_force_false_body="$(mktemp)"
printf '{"ref":"refs/tags/v1.2.1","sha":"%s","force":false}\n' "$(current_head_sha)" > "${gh_api_force_false_body}"
gh_api_force_false_input_command="gh api -X POST repos/alo-exp/sidekick/git/refs --input ${gh_api_force_false_body}"
assert_passthrough_release_command_with_sha_markers \
  "Scenario 49cv9b2: gh api tag ref input force false passes with current markers" \
  "${gh_api_force_false_input_command}" "$(current_head_sha)"
rm -f "${gh_api_force_false_body}"
gh_api_patch_tag_ref_force_command="gh api -X PATCH repos/alo-exp/sidekick/git/refs/tags/v1.2.1 -f sha=$(current_head_sha) -f force=true"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv9c: gh api tag ref PATCH force with current SHA is denied" \
  "${gh_api_patch_tag_ref_force_command}" "$(current_head_sha)"
gh_api_delete_tag_ref_command="gh api -X DELETE repos/alo-exp/sidekick/git/refs/tags/v1.2.1 -f sha=$(current_head_sha)"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv9d: gh api tag ref DELETE with current SHA is denied" \
  "${gh_api_delete_tag_ref_command}" "$(current_head_sha)"
gh_api_graphql_target_command="gh api graphql -f query='mutation { createRef(input:{ref:\"refs/tags/v1.2.1\", oid:\"${target_ref_sha}\"}) { ref { id } } }'"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv10: gh api GraphQL createRef oid with current HEAD markers is denied" \
  "${gh_api_graphql_target_command}"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv11: gh api GraphQL createRef oid is denied even with target ref markers because repo is unresolved" \
  "${gh_api_graphql_target_command}" "${target_ref_sha}"
curl_api_release_target_command="curl -X POST https://api.github.com/repos/alo-exp/sidekick/releases -d '{\"tag_name\":\"v1.2.1\",\"target_commitish\":\"${target_ref_sha}\"}'"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv12: curl release target_commitish with current HEAD markers is denied" \
  "${curl_api_release_target_command}"
wget_api_tag_ref_target_command="wget --method=POST --body-data '{\"ref\":\"refs/tags/v1.2.1\",\"sha\":\"${target_ref_sha}\"}' https://api.github.com/repos/alo-exp/sidekick/git/refs"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv13: wget tag ref sha with current HEAD markers is denied" \
  "${wget_api_tag_ref_target_command}"
curl_generated_config_target_command="printf 'url = \"https://api.github.com/repos/alo-exp/sidekick/releases\"\nrequest = POST\ndata = \"{\\\"tag_name\\\":\\\"v1.2.1\\\",\\\"target_commitish\\\":\\\"${target_ref_sha}\\\"}\"\n' > ./sidekick-curl-release-target.cfg; curl -K ./sidekick-curl-release-target.cfg"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv14: generated curl config release target with current HEAD markers is denied" \
  "${curl_generated_config_target_command}"
python_api_tag_ref_target_command="python3 -c 'import requests; requests.post(\"https://api.github.com/repos/alo-exp/sidekick/git/refs\", json={\"ref\":\"refs/tags/v1.2.1\",\"sha\":\"${target_ref_sha}\"})'"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv15: python API tag ref target with current HEAD markers is denied" \
  "${python_api_tag_ref_target_command}"
cross_repo_gh_target_command="gh -R attacker/other release create v1.2.1 --target $(current_head_sha)"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv16: gh -R different repo release target is denied" \
  "${cross_repo_gh_target_command}"
cross_repo_gh_api_command="gh api -X POST repos/attacker/other/releases -f tag_name=v1.2.1 -f target_commitish=$(current_head_sha)"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv17: gh api different repo release target is denied" \
  "${cross_repo_gh_api_command}"
cross_repo_gh_repo_env_command="GH_REPO=attacker/other gh release create v1.2.1 --target $(current_head_sha)"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv17a: command-scoped GH_REPO different repo release target is denied" \
  "${cross_repo_gh_repo_env_command}"
same_repo_gh_repo_env_command="GH_REPO=alo-exp/sidekick gh release create v1.2.1 --target $(current_head_sha)"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv17a2: command-scoped GH_REPO same repo release target is denied" \
  "${same_repo_gh_repo_env_command}"
echo "Scenario 49cv17b: inherited GH_REPO different repo release target is denied"
H="$(setup_home)"
write_markers "${H}" 1 2 3 4
write_live_pyramid_markers "${H}" 2
PAYLOAD="$(jq -cn --arg cmd "gh release create v1.2.1 --target $(current_head_sha)" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(SIDEKICK_TEST_INHERIT_RELEASE_ENV=1 GH_REPO=attacker/other run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "inherited GH_REPO different repo release target is denied"
else
  assert_fail "inherited GH_REPO different repo release target" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
echo "Scenario 49cv17b2: inherited GH_REPO same repo release target is denied"
H="$(setup_home)"
write_markers "${H}" 1 2 3 4
write_live_pyramid_markers "${H}" 2
PAYLOAD="$(jq -cn --arg cmd "gh release create v1.2.1 --target $(current_head_sha)" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(SIDEKICK_TEST_INHERIT_RELEASE_ENV=1 GH_REPO=alo-exp/sidekick run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "inherited GH_REPO same repo release target is denied"
else
  assert_fail "inherited GH_REPO same repo release target" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
cross_host_gh_target_command="gh --hostname ghe.example.invalid --repo alo-exp/sidekick release create v1.2.1 --target $(current_head_sha)"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv17c: gh release target on non-GitHub host is denied" \
  "${cross_host_gh_target_command}"
dynamic_host_gh_target_command='gh --hostname $HOST --repo alo-exp/sidekick release create v1.2.1 --target '"$(current_head_sha)"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv17c2: gh release target with dynamic hostname is denied" \
  "${dynamic_host_gh_target_command}"
dynamic_env_host_gh_target_command='GH_HOST=$HOST gh --repo alo-exp/sidekick release create v1.2.1 --target '"$(current_head_sha)"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv17c3: gh release target with dynamic GH_HOST is denied" \
  "${dynamic_env_host_gh_target_command}"
dynamic_endpoint_gh_api_command='gh api -X POST https://api.$HOST/repos/alo-exp/sidekick/releases -f tag_name=v1.2.1 -f target_commitish='"$(current_head_sha)"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv17c4: gh api release target with dynamic endpoint host is denied" \
  "${dynamic_endpoint_gh_api_command}"
implicit_other_repo="$(mktemp -d)"
git -C "${implicit_other_repo}" init -q
git -C "${implicit_other_repo}" remote add origin https://github.com/attacker/other.git
echo "Scenario 49cv17d: implicit cwd different repo gh release target is denied"
H="$(setup_home)"
write_markers "${H}" 1 2 3 4
write_live_pyramid_markers "${H}" 2
OUT="$(run_hook_from_cwd "${H}" "${PAYLOAD}" "${implicit_other_repo}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "implicit cwd different repo gh release target is denied"
else
  assert_fail "implicit cwd different repo gh release target" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}" "${implicit_other_repo}"
rewritten_sidekick_repo="$(mktemp -d)"
git -C "${rewritten_sidekick_repo}" init -q
git -C "${rewritten_sidekick_repo}" remote add origin https://github.com/alo-exp/sidekick.git
printf '%s\n' "rewritten release" > "${rewritten_sidekick_repo}/README.md"
git -C "${rewritten_sidekick_repo}" add README.md
git -C "${rewritten_sidekick_repo}" -c user.email=sidekick@example.invalid -c user.name=Sidekick commit -q -m rewritten-release
git -C "${rewritten_sidekick_repo}" update-ref refs/tags/v1.2.1 HEAD
rewritten_sidekick_sha="$(git -C "${rewritten_sidekick_repo}" rev-parse --short=12 HEAD)"
git -C "${rewritten_sidekick_repo}" config url.https://attacker.example/alo-exp/sidekick/.insteadOf https://github.com/alo-exp/sidekick
echo "Scenario 49cv17d2: implicit gh release from persistent insteadOf checkout is denied"
H="$(setup_home)"
write_markers_for_sha "${H}" "${rewritten_sidekick_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${rewritten_sidekick_sha}" 2
PAYLOAD="$(jq -cn --arg cmd "gh release create v1.2.1 --verify-tag" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook_from_cwd "${H}" "${PAYLOAD}" "${rewritten_sidekick_repo}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "implicit gh release from persistent insteadOf checkout is denied"
else
  assert_fail "implicit gh release from persistent insteadOf checkout" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
git -C "${rewritten_sidekick_repo}" config --unset-all url.https://attacker.example/alo-exp/sidekick/.insteadOf
git -C "${rewritten_sidekick_repo}" config url.https://attacker.example/alo-exp/sidekick/.pushInsteadOf https://github.com/alo-exp/sidekick
echo "Scenario 49cv17d3: implicit gh release target from persistent pushInsteadOf checkout is denied"
H="$(setup_home)"
write_markers_for_sha "${H}" "${rewritten_sidekick_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${rewritten_sidekick_sha}" 2
PAYLOAD="$(jq -cn --arg cmd "gh release create v1.2.1 --target ${rewritten_sidekick_sha}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook_from_cwd "${H}" "${PAYLOAD}" "${rewritten_sidekick_repo}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "implicit gh release target from persistent pushInsteadOf checkout is denied"
else
  assert_fail "implicit gh release target from persistent pushInsteadOf checkout" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
echo "Scenario 49cv17d4: explicit gh release target from persistent pushInsteadOf checkout is denied"
H="$(setup_home)"
write_markers_for_sha "${H}" "${rewritten_sidekick_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${rewritten_sidekick_sha}" 2
PAYLOAD="$(jq -cn --arg cmd "gh -R alo-exp/sidekick release create v1.2.1 --target ${rewritten_sidekick_sha}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook_from_cwd "${H}" "${PAYLOAD}" "${rewritten_sidekick_repo}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "explicit gh release target from persistent pushInsteadOf checkout is denied"
else
  assert_fail "explicit gh release target from persistent pushInsteadOf checkout" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}" "${rewritten_sidekick_repo}"
foreign_release_repo="$(mktemp -d)"
git -C "${foreign_release_repo}" init -q
git -C "${foreign_release_repo}" remote add origin https://github.com/attacker/other.git
printf '%s\n' "foreign release" > "${foreign_release_repo}/README.md"
git -C "${foreign_release_repo}" add README.md
git -C "${foreign_release_repo}" -c user.email=sidekick@example.invalid -c user.name=Sidekick commit -q -m foreign-release
git -C "${foreign_release_repo}" update-ref refs/tags/v1.2.1 HEAD
foreign_release_sha="$(git -C "${foreign_release_repo}" rev-parse --short=12 HEAD)"
echo "Scenario 49cv17e: explicit Sidekick gh release target from foreign checkout is denied"
H="$(setup_home)"
write_markers_for_sha "${H}" "${foreign_release_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${foreign_release_sha}" 2
PAYLOAD="$(jq -cn --arg cmd "gh -R alo-exp/sidekick release create v1.2.1 --target ${foreign_release_sha}" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook_from_cwd "${H}" "${PAYLOAD}" "${foreign_release_repo}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "explicit Sidekick gh release target from foreign checkout is denied"
else
  assert_fail "explicit Sidekick gh release target from foreign checkout" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
echo "Scenario 49cv17e2: foreign checkout cannot authorize gh release with valid Sidekick target"
H="$(setup_home)"
write_markers "${H}" 1 2 3 4
write_live_pyramid_markers "${H}" 2
PAYLOAD="$(jq -cn --arg cmd "gh -R alo-exp/sidekick release create v1.2.1 --target $(current_head_sha)" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook_from_cwd "${H}" "${PAYLOAD}" "${foreign_release_repo}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "foreign checkout cannot authorize gh release with valid Sidekick target"
else
  assert_fail "foreign checkout gh release with valid Sidekick target" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
echo "Scenario 49cv17e3: foreign checkout cannot authorize gh api release with valid Sidekick target"
H="$(setup_home)"
write_markers "${H}" 1 2 3 4
write_live_pyramid_markers "${H}" 2
PAYLOAD="$(jq -cn --arg cmd "gh api -X POST repos/alo-exp/sidekick/releases -f tag_name=v1.2.1 -f target_commitish=$(current_head_sha)" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook_from_cwd "${H}" "${PAYLOAD}" "${foreign_release_repo}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "foreign checkout cannot authorize gh api release with valid Sidekick target"
else
  assert_fail "foreign checkout gh api release with valid Sidekick target" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
echo "Scenario 49cv17f: explicit Sidekick git push from foreign checkout is denied"
H="$(setup_home)"
write_markers_for_sha "${H}" "${foreign_release_sha}" 1 2 3 4
write_live_pyramid_markers_for_sha "${H}" "${foreign_release_sha}" 2
PAYLOAD="$(jq -cn --arg cmd "git push https://github.com/alo-exp/sidekick.git v1.2.1" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook_from_cwd "${H}" "${PAYLOAD}" "${foreign_release_repo}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "explicit Sidekick git push from foreign checkout is denied"
else
  assert_fail "explicit Sidekick git push from foreign checkout" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"
echo "Scenario 49cv17f2: foreign checkout cannot authorize git tag push with valid Sidekick markers"
H="$(setup_home)"
write_markers "${H}" 1 2 3 4
write_live_pyramid_markers "${H}" 2
PAYLOAD="$(jq -cn --arg cmd "git push https://github.com/alo-exp/sidekick.git HEAD:refs/tags/v1.2.1" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook_from_cwd "${H}" "${PAYLOAD}" "${foreign_release_repo}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ]; then
  assert_pass "foreign checkout cannot authorize git tag push with valid Sidekick markers"
else
  assert_fail "foreign checkout git tag push with valid Sidekick markers" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}" "${foreign_release_repo}"
gh_api_release_without_target_command="gh api -X POST repos/alo-exp/sidekick/releases -f tag_name=v1.2.1"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv17g: gh api release without explicit target_commitish is denied" \
  "${gh_api_release_without_target_command}"
assert_denied_release_command_with_sha_markers \
  "Scenario 49cv17h: gh api release without explicit target_commitish is denied even with current markers" \
  "${gh_api_release_without_target_command}" "$(current_head_sha)"
gh_xdg_alias_config="$(mktemp -d)"
mkdir -p "${gh_xdg_alias_config}/gh"
cat > "${gh_xdg_alias_config}/gh/aliases.yml" <<YAML
ship: release create --target $(current_head_sha)
YAML
assert_denied_command_with_current_markers \
  "Scenario 49cv18: command-scoped XDG_CONFIG_HOME gh alias is denied without target metadata" \
  "XDG_CONFIG_HOME=${gh_xdg_alias_config} gh ship v1.2.1"
rm -rf "${gh_xdg_alias_config}"
cwd_release_repo="$(mktemp -d)"
cat > "${cwd_release_repo}/cfg" <<CFG
url = "https://api.github.com/repos/alo-exp/sidekick/releases"
request = POST
data = "{\"tag_name\":\"v1.2.1\",\"target_commitish\":\"$(current_head_sha)\"}"
CFG
cat > "${cwd_release_repo}/deploy.sh" <<SH
#!/usr/bin/env bash
gh release create v1.2.1 --target $(current_head_sha)
SH
chmod +x "${cwd_release_repo}/deploy.sh"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv19: cd before curl config release write is denied without target metadata" \
  "cd ${cwd_release_repo} && curl -K cfg"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv20: cd before local release script is denied without target metadata" \
  "cd ${cwd_release_repo} && ./deploy.sh"
assert_denied_release_command_with_current_markers \
  "Scenario 49cv21: env -C before curl config release write is denied without target metadata" \
  "env -C ${cwd_release_repo} curl -K cfg"
rm -rf "${cwd_release_repo}"

# ---------------------------------------------------------------------------
# Scenario 50: Codex host state path satisfies release gate
# ---------------------------------------------------------------------------
echo "Scenario 50: Codex host markers satisfy release command"
H="$(setup_home)"
write_codex_markers "${H}" 1 2 3 4
write_codex_live_pyramid_markers "${H}" 2
PAYLOAD="$(jq -cn --arg cmd "$(current_head_release_command)" '{tool_name:"Bash",tool_input:{command:$cmd}}')"
OUT="$(run_hook_codex "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ -z "${DECISION}" ] && [ -z "${OUT}" ]; then
  assert_pass "Codex host markers: release command passes"
else
  assert_fail "Codex host markers" "rc=${RC} decision=${DECISION} out=${OUT}"
fi
rm -rf "${H}"

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
exit "${FAIL}"

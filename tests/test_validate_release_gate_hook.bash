#!/usr/bin/env bash
# Unit tests for hooks/validate-release-gate.sh
#
# The hook blocks `gh release create` commands via Claude Code's PreToolUse
# permissionDecision=deny mechanism unless all current-session quality-gate stage
# markers and two current-session live-pyramid run markers are present in the
# active host quality-gate state file.
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

run_hook() {
  # $1 = temp HOME, $2 = JSON payload
  HOME="$1" CODEX_PLUGIN_ROOT= CODEX_HOME= CODEX_THREAD_ID= SIDEKICK_SESSION_ID="${SIDEKICK_TEST_SESSION:-test-session}" SESSION_ID="${SIDEKICK_TEST_SESSION:-test-session}" bash "${HOOK}" <<<"$2"
}

run_hook_codex() {
  # $1 = temp HOME, $2 = JSON payload
  HOME="$1" SIDEKICK_SESSION_ID= SESSION_ID= CLAUDE_SESSION_ID= CODEX_THREAD_ID="${SIDEKICK_TEST_SESSION:-test-session}" bash "${HOOK}" <<<"$2"
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
  local h="$1"; shift
  : > "${h}/.claude/.sidekick/quality-gate-state"
  for s in "$@"; do
    echo "quality-gate-stage-${s} session=${SIDEKICK_TEST_SESSION:-test-session}" >> "${h}/.claude/.sidekick/quality-gate-state"
  done
}

current_head_sha() {
  git -C "${REPO_ROOT}" rev-parse --short=12 HEAD 2>/dev/null || printf 'unknown'
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
  local h="$1"; shift
  : > "${h}/.codex/.sidekick/quality-gate-state"
  for s in "$@"; do
    echo "quality-gate-stage-${s} session=${SIDEKICK_TEST_SESSION:-test-session}" >> "${h}/.codex/.sidekick/quality-gate-state"
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
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh release create v1.2.1 --generate-notes"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
if [ "${RC}" -eq 0 ] && [ -z "${OUT}" ]; then
  assert_pass "all 4 markers plus live pyramid: exit 0, no deny"
else
  assert_fail "all markers plus live pyramid pass" "rc=${RC} out=${OUT}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 4b: all 4 stage markers without live pyramid markers → deny
# ---------------------------------------------------------------------------
echo "Scenario 4b: stage markers without live pyramid are denied"
H="$(setup_home)"
write_markers "${H}" 1 2 3 4
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh release create v1.2.1 --generate-notes"}}'
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
# Scenario 4c: only one live-pyramid run marker → deny
# ---------------------------------------------------------------------------
echo "Scenario 4c: one live-pyramid marker is denied"
H="$(setup_home)"
write_markers "${H}" 1 2 3 4
write_live_pyramid_markers "${H}" 1
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh release create v1.2.1 --generate-notes"}}'
OUT="$(run_hook "${H}" "${PAYLOAD}")"; RC=$?
DECISION=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
REASON=$(printf '%s' "${OUT}" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
if [ "${RC}" -eq 0 ] && [ "${DECISION}" = "deny" ] && [[ "${REASON}" == *"1/2"* ]]; then
  assert_pass "one live-pyramid marker: permissionDecision=deny"
else
  assert_fail "one live-pyramid marker deny" "rc=${RC} decision=${DECISION} reason=${REASON}"
fi
rm -rf "${H}"

# ---------------------------------------------------------------------------
# Scenario 5: stage-10 marker must NOT satisfy stage-1 (anchored match)
# ---------------------------------------------------------------------------
echo "Scenario 5: stage-10 does not satisfy stage-1 (anchored grep)"
H="$(setup_home)"
: > "${H}/.claude/.sidekick/quality-gate-state"
# Only a spurious stage-10 marker — stages 1-4 should all still be missing.
echo "quality-gate-stage-10 session=${SIDEKICK_TEST_SESSION:-test-session}" >> "${H}/.claude/.sidekick/quality-gate-state"
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh release create v1.2.1"}}'
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
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh release create v1.2.1"}}'
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
  echo "quality-gate-stage-${s} session=old-session" >> "${H}/.claude/.sidekick/quality-gate-state"
done
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh release create v1.2.1"}}'
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
assert_denied_command "Scenario 49ap2: curl POST release endpoint is denied" \
  "curl -sS -X POST https://api.github.com/repos/alo-exp/sidekick/releases -d '{\"tag_name\":\"v1.2.1\"}'"
assert_denied_command "Scenario 49ap2b: curl attached short data flag release endpoint is denied" \
  "curl -sS -d'{\"tag_name\":\"v1.2.1\"}' https://api.github.com/repos/alo-exp/sidekick/releases"
assert_denied_command "Scenario 49ap2c: curl attached short form flag release endpoint is denied" \
  "curl -sS -Ftag_name=v1.2.1 https://api.github.com/repos/alo-exp/sidekick/releases"
assert_denied_command "Scenario 49ap3: curl data-implied POST tag ref endpoint is denied" \
  "curl --url https://api.github.com/repos/alo-exp/sidekick/git/refs --data '{\"ref\":\"refs/tags/v1.2.1\",\"sha\":\"abc123\"}'"
assert_denied_command "Scenario 49ap4: wget POST release endpoint is denied" \
  "wget --method=POST --body-data '{\"tag_name\":\"v1.2.1\"}' https://api.github.com/repos/alo-exp/sidekick/releases"
assert_denied_command "Scenario 49ap5: python direct GitHub release API write is denied" \
  "python3 -c 'import requests; requests.post(\"https://api.github.com/repos/alo-exp/sidekick/releases\", json={\"tag_name\":\"v1.2.1\"})'"
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
_curl_config="$(mktemp)"
cat > "${_curl_config}" <<'EOF'
url = "https://api.github.com/repos/alo-exp/sidekick/releases"
request = POST
data = "{\"tag_name\":\"v1.2.1\"}"
EOF
assert_denied_command "Scenario 49ap7: curl config file release endpoint is denied" \
  "curl -K ${_curl_config}"
assert_denied_command "Scenario 49ap7b: curl stdin config source is denied" \
  "curl -K -"
assert_denied_command "Scenario 49ap7c: curl attached stdin config source is denied" \
  "curl -K-"
_wget_urls="$(mktemp)"
printf '%s\n' "https://api.github.com/repos/alo-exp/sidekick/releases" > "${_wget_urls}"
assert_denied_command "Scenario 49ap8: wget input file release endpoint is denied" \
  "wget --method=POST --body-data '{\"tag_name\":\"v1.2.1\"}' -i ${_wget_urls}"
assert_denied_command "Scenario 49ap8b: wget stdin input source is denied" \
  "wget -i -"
assert_denied_command "Scenario 49ap8c: wget attached stdin input source is denied" \
  "wget -i-"
rm -f "${_curl_config}" "${_wget_urls}"
assert_denied_command "Scenario 49ap9: node direct GitHub release API write is denied" \
  "node -e 'fetch(\"https://api.github.com/repos/alo-exp/sidekick/git/refs\", {method:\"POST\", body:\"{}\"})'"
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
assert_denied_command "Scenario 49aw: gh api GraphQL createRelease mutation is denied" \
  "gh api graphql -f query='mutation { createRelease(input:{repositoryId:\"R\", tagName:\"v1\"}) { release { id } } }'"
assert_denied_command "Scenario 49ax: gh api GraphQL createRef tag mutation is denied" \
  "gh api -X POST graphql -f query='mutation { createRef(input:{ref:\"refs/tags/v1\"}) { ref { id } } }'"
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
assert_denied_command "Scenario 49bh2: python concatenated argv-vector release command is denied" \
  "python3 -c 'import subprocess; subprocess.run([\"gh\",\"release\",\"cre\"+\"ate\",\"v1.2.1\"])'"
assert_denied_command "Scenario 49bh3: python variable-concatenated shell release command is denied" \
  "python3 -c 'import os; cmd=\"gh release\"; os.system(cmd+\" create v1.2.1\")'"
assert_denied_command "Scenario 49bh4: python argv fragment release command is denied" \
  "python3 -c 'import subprocess,sys; subprocess.run([\"g\"+sys.argv[1],\"release\",\"create\",\"v1.2.1\"])' h"
assert_denied_command "Scenario 49bi: node argv-vector release command is denied" \
  "node -e 'require(\"child_process\").execFileSync(\"gh\",[\"release\",\"create\",\"v1.2.1\"])'"
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

# ---------------------------------------------------------------------------
# Scenario 50: Codex host state path satisfies release gate
# ---------------------------------------------------------------------------
echo "Scenario 50: Codex host markers satisfy release command"
H="$(setup_home)"
write_codex_markers "${H}" 1 2 3 4
write_codex_live_pyramid_markers "${H}" 2
PAYLOAD='{"tool_name":"Bash","tool_input":{"command":"gh release create v1.2.1 --generate-notes"}}'
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

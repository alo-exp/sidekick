#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin - legacy user-hook scrubber tests
# =============================================================================

set -euo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "${SCRIPT_DIR}")"
SCRUBBER="${PLUGIN_DIR}/hooks/scrub-legacy-user-hooks.py"
REPO_ROOT="$(cd "${PLUGIN_DIR}" && pwd)"

green='\033[0;32m'
red='\033[0;31m'
reset='\033[0m'

assert_pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
assert_fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

seed_fixture() {
  local file_path="$1"
  local home_dir="$2"
  local session_keep="$3"
  local pre_keep="$4"

  mkdir -p "$(dirname "${file_path}")"
  cat > "${file_path}" <<EOF
{
  "SessionStart": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "test -f \"${home_dir}/.claude/.sidekick/.installed\" || (bash \"${REPO_ROOT}/install.sh\" && touch \"${home_dir}/.claude/.sidekick/.installed\")"
        }
      ]
    },
    {
      "hooks": [
        {
          "type": "command",
          "command": "ROOT=\"${REPO_ROOT}\"; if [ -f \"\${ROOT}/.installed\" ]; then bash \"\${ROOT}/hooks/runtime-sync.sh\"; fi"
        }
      ]
    },
    {
      "hooks": [
        {
          "type": "command",
          "command": "${session_keep}"
        }
      ]
    }
  ],
  "PreToolUse": [
    {
      "matcher": "Write|Edit|NotebookEdit|Bash|mcp__filesystem__write_file|mcp__filesystem__edit_file|mcp__filesystem__move_file|mcp__filesystem__create_directory",
      "hooks": [
        {
          "type": "command",
          "command": "bash \"${REPO_ROOT}/hooks/forge-delegation-enforcer.sh\""
        },
        {
          "type": "command",
          "command": "bash \"${REPO_ROOT}/hooks/codex-delegation-enforcer.sh\""
        }
      ]
    },
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash \"${REPO_ROOT}/hooks/validate-release-gate.sh\""
        }
      ]
    },
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "${pre_keep}"
        }
      ]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash \"${REPO_ROOT}/hooks/forge-progress-surface.sh\""
        },
        {
          "type": "command",
          "command": "bash \"${REPO_ROOT}/hooks/codex-progress-surface.sh\""
        }
      ]
    }
  ]
}
EOF
}

assert_json() {
  local home_dir="$1"
  local target_path="$2"
  local snapshot_path="$3"
  local expect_session="$4"
  local expect_pre="$5"
  local expect_other_status="$6"
  python3 - "$home_dir" "$target_path" "$snapshot_path" "$expect_session" "$expect_pre" "$expect_other_status" <<'PY'
import json
import sys
from pathlib import Path

home = Path(sys.argv[1])
target = Path(sys.argv[2])
snapshot = Path(sys.argv[3])
expect_session = sys.argv[4]
expect_pre = sys.argv[5]
expect_other_status = sys.argv[6]

state = json.load(open(home / ".sidekick/legacy-hooks-scrub-state.json"))
assert state["status"] in {"applied", "rolled_back", "clean"}

target_data = json.load(open(target))
if state["status"] == "clean":
    assert target_data == {}
elif state["status"] == "applied":
    assert len(target_data["SessionStart"]) == 1
    assert target_data["SessionStart"][0]["hooks"][0]["command"] == expect_session
    assert len(target_data["PreToolUse"]) == 1
    assert target_data["PreToolUse"][0]["matcher"] == "Bash"
    assert target_data["PreToolUse"][0]["hooks"][0]["command"] == expect_pre
    assert target_data["PostToolUse"] == []

    entries = {entry["path"]: entry for entry in state["targets"]}
    assert entries[str(target)]["status"] == "scrubbed"
    assert Path(entries[str(target)]["backup_path"]).read_text() == snapshot.read_text()
    assert any(
        entry["status"] in {expect_other_status, "absent"}
        for entry in state["targets"]
        if entry["path"] != str(target)
    )
else:
    assert state["status"] == "rolled_back"
    assert target.read_text() == snapshot.read_text()
PY
}

TMP_HOME="$(mktemp -d)"
CLEAN_HOME="$(mktemp -d)"
V1_HOME="$(mktemp -d)"
COLLISION_HOME="$(mktemp -d)"
trap 'rm -rf "${TMP_HOME}" "${CLEAN_HOME}" "${V1_HOME}" "${COLLISION_HOME}"' EXIT

echo "=== lower_case_scrub ==="
mkdir -p "${TMP_HOME}/.codex"
seed_fixture "${TMP_HOME}/.codex/hooks.json" "${TMP_HOME}" "echo keep-me" "echo unrelated"
cp "${TMP_HOME}/.codex/hooks.json" "${TMP_HOME}/.codex/hooks.json.original"

if HOME="${TMP_HOME}" python3 "${SCRUBBER}" >/tmp/sidekick-scrub-lower.out 2>/tmp/sidekick-scrub-lower.err; then
  assert_pass "lower-case scrubber exits successfully on apply"
else
  assert_fail "lower-case scrubber apply" "non-zero exit"
fi

assert_json "${TMP_HOME}" "${TMP_HOME}/.codex/hooks.json" "${TMP_HOME}/.codex/hooks.json.original" "echo keep-me" "echo unrelated" "clean"

if HOME="${TMP_HOME}" python3 "${SCRUBBER}" >/tmp/sidekick-scrub-lower-2.out 2>/tmp/sidekick-scrub-lower-2.err; then
  assert_pass "lower-case second apply exits successfully"
else
  assert_fail "lower-case second apply" "non-zero exit"
fi

assert_json "${TMP_HOME}" "${TMP_HOME}/.codex/hooks.json" "${TMP_HOME}/.codex/hooks.json.original" "echo keep-me" "echo unrelated" "clean"

echo "=== preexisting_v1_state_reruns ==="
mkdir -p "${V1_HOME}/.codex" "${V1_HOME}/.sidekick"
seed_fixture "${V1_HOME}/.codex/hooks.json" "${V1_HOME}" "echo keep-v1" "echo unrelated-v1"
cat > "${V1_HOME}/.sidekick/legacy-hooks-scrub-state.json" <<'EOF'
{
  "migration": "legacy-hooks-scrub-v1",
  "status": "clean",
  "checked_at": "2026-05-13T00:00:00Z",
  "targets": []
}
EOF

if HOME="${V1_HOME}" python3 "${SCRUBBER}" >/tmp/sidekick-scrub-v1.out 2>/tmp/sidekick-scrub-v1.err; then
  assert_pass "v1 state does not suppress v2 runtime-sync scrub"
else
  assert_fail "v1 state rerun" "non-zero exit"
fi

if python3 - "${V1_HOME}" <<'PY'
import json
import sys
from pathlib import Path

home = Path(sys.argv[1])
state = json.load(open(home / ".sidekick/legacy-hooks-scrub-state.json"))
target = json.load(open(home / ".codex/hooks.json"))
assert state["migration"] == "legacy-hooks-scrub-v2"
assert state["status"] == "applied"
serialized = json.dumps(target)
assert "runtime-sync.sh" not in serialized
assert "install.sh" not in serialized
assert "keep-v1" in serialized
assert "unrelated-v1" in serialized
PY
then
  assert_pass "v2 scrub removes runtime-sync despite preexisting v1 clean state"
else
  assert_fail "v2 scrub result" "runtime-sync remained or unrelated hooks changed"
fi

echo "=== same_basename_unowned_hooks_preserved ==="
mkdir -p "${COLLISION_HOME}/.codex"
cat > "${COLLISION_HOME}/.codex/hooks.json" <<'EOF'
{
  "SessionStart": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "test -f \"/tmp/.installed\" || (bash \"/tmp/install.sh\" && touch \"/tmp/.installed\")"
        }
      ]
    },
    {
      "hooks": [
        {
          "type": "command",
          "command": "ROOT=\"/tmp\"; if [ -f \"${ROOT}/.installed\" ]; then bash \"${ROOT}/hooks/runtime-sync.sh\"; fi"
        }
      ]
    }
  ],
  "PreToolUse": [
    {
      "matcher": "Write|Edit|NotebookEdit|Bash|mcp__filesystem__write_file|mcp__filesystem__edit_file|mcp__filesystem__move_file|mcp__filesystem__create_directory",
      "hooks": [
        {
          "type": "command",
          "command": "bash \"/tmp/hooks/forge-delegation-enforcer.sh\""
        },
        {
          "type": "command",
          "command": "bash \"/tmp/hooks/codex-delegation-enforcer.sh\""
        }
      ]
    },
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash \"/tmp/hooks/validate-release-gate.sh\""
        }
      ]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash \"/tmp/hooks/forge-progress-surface.sh\""
        },
        {
          "type": "command",
          "command": "bash \"/tmp/hooks/codex-progress-surface.sh\""
        }
      ]
    }
  ]
}
EOF
cp "${COLLISION_HOME}/.codex/hooks.json" "${COLLISION_HOME}/.codex/hooks.json.original"

if HOME="${COLLISION_HOME}" python3 "${SCRUBBER}" >/tmp/sidekick-scrub-collision.out 2>/tmp/sidekick-scrub-collision.err; then
  assert_pass "same-basename unowned hook scrub exits successfully"
else
  assert_fail "same-basename unowned hook scrub" "non-zero exit"
fi

if python3 - "${COLLISION_HOME}" <<'PY'
import json
import sys
from pathlib import Path

home = Path(sys.argv[1])
state = json.load(open(home / ".sidekick/legacy-hooks-scrub-state.json"))
assert state["status"] == "clean"
assert (home / ".codex/hooks.json").read_text() == (home / ".codex/hooks.json.original").read_text()
PY
then
  assert_pass "same-basename unowned hooks are preserved"
else
  assert_fail "same-basename unowned hooks" "unowned hook block was modified or scrubbed"
fi

if HOME="${TMP_HOME}" python3 "${SCRUBBER}" --rollback >/tmp/sidekick-scrub-lower-rollback.out 2>/tmp/sidekick-scrub-lower-rollback.err; then
  assert_pass "lower-case rollback exits successfully"
else
  assert_fail "lower-case rollback" "non-zero exit"
fi

assert_json "${TMP_HOME}" "${TMP_HOME}/.codex/hooks.json" "${TMP_HOME}/.codex/hooks.json.original" "echo keep-me" "echo unrelated" "clean"

echo "=== clean_home_noop ==="
mkdir -p "${CLEAN_HOME}/.claude"
if HOME="${CLEAN_HOME}" python3 "${SCRUBBER}" >/tmp/sidekick-scrub-clean.out 2>/tmp/sidekick-scrub-clean.err; then
  assert_pass "clean home apply exits successfully"
else
  assert_fail "clean home apply" "non-zero exit"
fi

if python3 - "${CLEAN_HOME}" <<'PY'
import json
import sys
from pathlib import Path

home = Path(sys.argv[1])
state = json.load(open(home / ".sidekick/legacy-hooks-scrub-state.json"))
assert state["status"] == "clean"
assert state["targets"][0]["status"] == "absent"
assert state["targets"][1]["status"] == "absent"
PY
then
  assert_pass "clean home records a clean state and does nothing"
else
  assert_fail "clean home state" "clean state not recorded"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ]

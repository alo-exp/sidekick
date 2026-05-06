#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Live Codex plugin/read skill exposure test
# =============================================================================

set -euo pipefail

PASS=0; FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIDEKICK_DIR="$(dirname "${SCRIPT_DIR}")"
CODEX_REPO="/Users/shafqat/projects/codex-cli/kay"
CODEX_BIN="${CODEX_REPO}/codex-rs/target/debug/codex"

green='\033[0;32m'; red='\033[0;31m'; yellow='\033[0;33m'; bold='\033[1m'; reset='\033[0m'
pass() { echo -e "${green}PASS${reset} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${red}FAIL${reset} $1: $2"; FAIL=$((FAIL+1)); }

if [[ "${SIDEKICK_LIVE_CODEX:-}" != "1" ]]; then
  echo -e "${yellow}Codex plugin/read test skipped${reset} (set SIDEKICK_LIVE_CODEX=1 to exercise the real Codex plugin reader)."
  exit 0
fi

if [ ! -x "${CODEX_BIN}" ]; then
  fail "codex binary" "expected ${CODEX_BIN} to exist and be executable"
  exit 1
fi

if python3 - "${CODEX_BIN}" "${SIDEKICK_DIR}" <<'PY'
import json
import os
import pathlib
import queue
import subprocess
import sys
import tempfile
import threading
import time

codex_bin = pathlib.Path(sys.argv[1])
sidekick_dir = pathlib.Path(sys.argv[2])
root = pathlib.Path(tempfile.mkdtemp(prefix="sidekick-plugin-read."))
repo_root = root / "repo"
marketplace_root = repo_root / ".agents" / "plugins"
plugin_root = repo_root / "plugins" / "sidekick"
code_home = root / "code-home"

marketplace_root.mkdir(parents=True)
plugin_root.parent.mkdir(parents=True)
if plugin_root.exists() or plugin_root.is_symlink():
    plugin_root.unlink()
plugin_root.symlink_to(sidekick_dir)

(marketplace_root / "marketplace.json").write_text(
    json.dumps(
        {
            "name": "test-marketplace",
            "interface": {"displayName": "Test Marketplace"},
            "plugins": [
                {
                    "name": "sidekick",
                    "source": {"source": "local", "path": "./plugins/sidekick"},
                    "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"},
                    "category": "Development",
                }
            ],
        },
        indent=2,
    )
)

(code_home / "plugins" / "cache" / "test-marketplace" / "sidekick" / "local" / ".codex-plugin").mkdir(
    parents=True
)
(code_home / "plugins" / "cache" / "test-marketplace" / "sidekick" / "local" / ".codex-plugin" / "plugin.json").write_text(
    '{"name":"sidekick"}\n'
)
(code_home / "config.toml").write_text(
    "[features]\nplugins = true\n\n[plugins.\"sidekick@test-marketplace\"]\nenabled = true\n"
)

env = os.environ.copy()
env["CODEX_HOME"] = str(code_home)
env["PATH"] = f"{pathlib.Path('/Users/shafqat/.cargo/bin')}:{env.get('PATH', '')}"

proc = subprocess.Popen(
    [str(codex_bin), "app-server", "--listen", "stdio://"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    env=env,
)

q = queue.Queue()

def pump(pipe, label):
    for line in iter(pipe.readline, ""):
        q.put((label, line))
    q.put((label, None))

threading.Thread(target=pump, args=(proc.stdout, "stdout"), daemon=True).start()
threading.Thread(target=pump, args=(proc.stderr, "stderr"), daemon=True).start()

def send(obj):
    proc.stdin.write(json.dumps(obj) + "\n")
    proc.stdin.flush()

def recv_id(target_id, timeout=20):
    end = time.time() + timeout
    while time.time() < end:
        try:
            _label, line = q.get(timeout=0.2)
        except queue.Empty:
            continue
        if line is None:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if obj.get("id") == target_id:
            return obj
    raise TimeoutError(f"timed out waiting for JSON-RPC response {target_id}")

try:
    send(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "clientInfo": {
                    "name": "sidekick-probe",
                    "title": "Sidekick Probe",
                    "version": "0.1.0",
                },
                "capabilities": {"experimentalApi": True},
            },
        }
    )
    recv_id(1)
    send({"jsonrpc": "2.0", "method": "initialized", "params": {}})
    send(
        {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "plugin/read",
            "params": {
                "marketplacePath": str((marketplace_root / "marketplace.json").resolve()),
                "pluginName": "sidekick",
            },
        }
    )
    resp = recv_id(2)
    skills = resp["result"]["plugin"]["skills"]
    names = [skill["name"] for skill in skills]
    required = {
        "sidekick:codex-stop",
        "sidekick:codex-history",
        "sidekick:forge-stop",
        "sidekick:forge-history",
    }
    missing = sorted(required.difference(names))
    print("skill_names:", ", ".join(names))
    if missing:
        raise SystemExit(f"missing required skills: {', '.join(missing)}")
finally:
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
PY
then
  pass "Codex plugin/read surfaces the Forge and Codex command bridges"
else
  fail "plugin_read" "Codex plugin/read did not surface the expected skill bridges"
fi

echo ""
echo "======================================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "======================================="
[ "${FAIL}" -eq 0 ] && exit 0 || exit 1

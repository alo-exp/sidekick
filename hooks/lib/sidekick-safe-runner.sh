#!/usr/bin/env bash
# =============================================================================
# Sidekick Plugin — Safe Sidekick Runner
# =============================================================================
# Runs a delegated sidekick command with a sanitized environment and captures
# raw output in a 0600 tempfile. Only a bounded, redacted view is written back
# to the host transcript.
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

sidekick="${1:-}"
shift || true

case "$sidekick" in
  forge) prefix="[FORGE]" ;;
  kay)   prefix="[KAY]" ;;
  *)
    printf '[SIDEKICK] invalid sidekick runner target\n' >&2
    exit 2
    ;;
esac

if [ "$#" -lt 1 ]; then
  printf '%s missing delegated command\n' "$prefix" >&2
  exit 2
fi

tmp="$(mktemp "${TMPDIR:-/tmp}/sidekick-${sidekick}.XXXXXX")"
chmod 600 "$tmp" 2>/dev/null || true
cleanup() { rm -f "$tmp"; }
trap cleanup EXIT

set +e
env -i \
  HOME="${HOME:-}" \
  PATH="${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}" \
  PWD="${PWD:-}" \
  USER="${USER:-}" \
  LOGNAME="${LOGNAME:-}" \
  SHELL="${SHELL:-/bin/sh}" \
  TERM="${TERM:-dumb}" \
  TMPDIR="${TMPDIR:-/tmp}" \
  LANG="${LANG:-C}" \
  LC_ALL="${LC_ALL:-}" \
  "$@" 2>&1 | python3 -c '
from pathlib import Path
import sys

limit = 2 * 1024 * 1024
path = Path(sys.argv[1])
buf = bytearray()
while True:
    chunk = sys.stdin.buffer.read(65536)
    if not chunk:
        break
    buf.extend(chunk)
    if len(buf) > limit:
        del buf[: len(buf) - limit]
path.write_bytes(bytes(buf))
' "$tmp"
pipe_status=("${PIPESTATUS[@]}")
cmd_rc="${pipe_status[0]:-1}"
collector_rc="${pipe_status[1]:-1}"
set -e
rc="$cmd_rc"
if [ "$collector_rc" -ne 0 ]; then
  rc="$collector_rc"
fi

python3 - "$tmp" "$prefix" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
prefix = sys.argv[2]

try:
    size = path.stat().st_size
    with path.open("rb") as fh:
        fh.seek(max(0, size - (2 * 1024 * 1024)))
        data = fh.read(2 * 1024 * 1024).decode("utf-8", "replace")
except Exception:
    data = ""

def strip_ansi(text: str) -> str:
    text = re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", text)
    text = re.sub(r"\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)", "", text)
    text = re.sub(r"\x1b[@-Z\\-_]", "", text)
    text = re.sub(r"[\x00-\x08\x0b-\x1f\x7f]", "", text)
    return text

def redact(text: str) -> str:
    sensitive = r"(?:[A-Za-z0-9_.-]+[_-])?(?:api[_-]?key|apikey|token|access_token|refresh_token|client_secret|password|secret)"
    text = re.sub(r'(?i)("authorization"\s*:\s*")((?:bearer\s+)?[^"]+)(")', r"\1[REDACTED]\3", text)
    text = re.sub(rf'(?i)("{sensitive}"\s*:\s*")([^"]+)(")', r"\1[REDACTED]\3", text)
    text = re.sub(r"(?i)(authorization\s*[:=]\s*)(?:bearer\s+)?[^\s,;]+.*", r"\1[REDACTED]", text)
    text = re.sub(rf"(?i)\b({sensitive})\b(\s*[:=]\s*)(\"[^\"]*\"|[^\s,;]+)", r"\1\2[REDACTED]", text)
    text = re.sub(r"sk-[A-Za-z0-9_\-./+]{10,}(?=\s|['\">},]|$)", "[REDACTED-SK-TOKEN]", text)
    text = re.sub(r"\bgh[pousra]_[A-Za-z0-9]{20,}\b", "[REDACTED-GH-TOKEN]", text)
    text = re.sub(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b", "[REDACTED-GH-TOKEN]", text)
    text = re.sub(r"\bxox[abprse]-[A-Za-z0-9-]{10,}\b", "[REDACTED-SLACK-TOKEN]", text)
    return text

clean = redact(strip_ansi(data))
if not clean.strip():
    raise SystemExit(0)

lines = clean.splitlines()
status = []
in_block = False
for line in lines:
    if not in_block and re.match(r"^\s*(?:\[(?:FORGE|KAY|CODEX)\]\s+)?STATUS:", line):
        in_block = True
    if in_block:
        status.append(line)
        if "PATTERNS_DISCOVERED:" in line or len(status) >= 20:
            break

selected = status if status else lines[-80:]
for line in selected:
    if line.startswith(prefix + " "):
        print(line)
    else:
        print(f"{prefix} {line}")
PY

exit "$rc"

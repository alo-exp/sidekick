#!/usr/bin/env bash
# Build export/import seed fixture from canonical test-notes-app (host-maintained golden).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${ROOT}/tests/test-notes-app"
DST="${ROOT}/tests/test-notes-app-seeds/export-import"
rm -rf "${DST}"
mkdir -p "${DST}"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --exclude='node_modules' --exclude='data' --exclude='.git' "${SRC}/" "${DST}/"
else
  cp -R "${SRC}/." "${DST}/"
fi
python3 - <<'PY' "${DST}/src/server.js"
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
text = re.sub(r"status:\s*'broken'", "status: 'ok'", text)
path.write_text(text)
PY
echo "Seed scaffold at ${DST} — run Kay task7-retry once and copy artifacts here, or apply export-import patch."

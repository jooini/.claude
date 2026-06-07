#!/usr/bin/env zsh
set -euo pipefail

STATE="$HOME/.claude/cache/moai-regression-check.json"
[ -f "$STATE" ] || exit 0

python3 - "$STATE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    record = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(0)

if record.get("status") != "fail":
    raise SystemExit(0)

print("MoAI regression check failed after the last sync.")
print(f"timestamp: {record.get('timestamp')}")
print("run: moai-regression-check --force")
tail = (record.get("output_tail") or "").strip()
if tail:
    print("last output:")
    print("\n".join(tail.splitlines()[-10:]))
PY

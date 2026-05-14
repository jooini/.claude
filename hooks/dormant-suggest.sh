#!/usr/bin/env bash
set -euo pipefail

SCRIPT="${DORMANT_CHUNKS_SCRIPT:-$HOME/.claude/scripts/dormant-chunks.py}"
THRESHOLD="${DORMANT_CHUNKS_THRESHOLD:-0.65}"
TOP_K="${DORMANT_CHUNKS_TOP_K:-20}"

if [[ "${1:-}" == "--settings-snippet" ]]; then
    cat <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/leonard/.claude/hooks/dormant-suggest.sh"
          }
        ]
      }
    ]
  }
}
JSON
    exit 0
fi

if [[ ! -f "$SCRIPT" ]]; then
    exit 0
fi

INPUT="$(cat 2>/dev/null || true)"
QUERY="${1:-}"
if [[ -z "$QUERY" && -n "$INPUT" ]]; then
    QUERY="$(python3 - "$INPUT" <<'PY'
import json
import sys

raw = sys.argv[1]
try:
    data = json.loads(raw)
except Exception:
    print(raw[:500])
    raise SystemExit(0)

for key in ("prompt", "user_prompt", "message", "query"):
    value = data.get(key) if isinstance(data, dict) else None
    if isinstance(value, str) and value.strip():
        print(value.strip()[:500])
        break
PY
)"
fi

if [[ -z "$QUERY" ]]; then
    exit 0
fi

OUTPUT="$(python3 "$SCRIPT" --query "$QUERY" --format json --top-k "$TOP_K" 2>/dev/null || true)"
if [[ -z "$OUTPUT" ]]; then
    exit 0
fi

python3 - "$OUTPUT" "$THRESHOLD" <<'PY'
import json
import sys

try:
    payload = json.loads(sys.argv[1])
    threshold = float(sys.argv[2])
except Exception:
    raise SystemExit(0)

chunks = payload.get("chunks") or []
if not chunks:
    raise SystemExit(0)

chunk = chunks[0]
score = float(chunk.get("dormant_score") or 0)
if score < threshold:
    raise SystemExit(0)

file_path = chunk.get("source") or chunk.get("file_path") or "(unknown)"
chunk_index = chunk.get("chunk_index")
summary = chunk.get("excerpt") or ""
print(f"💡 묻혀있던 청크 발견: {file_path}:chunk-{chunk_index} - {summary[:120]}", file=sys.stderr)
PY

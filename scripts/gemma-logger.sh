#!/bin/bash
# Gemma 호출 래퍼 — 기존 훅들이 쓸 수 있는 로깅 wrapper
# 사용법 (훅 내부에서):
#   RESULT=$(~/.claude/scripts/gemma-logger.sh <caller_name> <model> <prompt> [num_predict] [temperature])
#
# 기능:
# - Ollama 호출 + 응답 캡처
# - ~/.claude/cache/gemma-calls.jsonl 에 호출 메타 JSONL 기록
# - stdout에 응답만 출력 (기존 코드 호환)

: "${HOME:?}"
OLLAMA="${OLLAMA_HOST_LAN:-leonard.local:11434}"
LOG_FILE="$HOME/.claude/cache/gemma-calls.jsonl"
mkdir -p "$(dirname "$LOG_FILE")"

CALLER="${1:-unknown}"
MODEL="${2:-gemma4:e4b}"
PROMPT="${3:-}"
NUM_PREDICT="${4:-800}"
TEMPERATURE="${5:-0.3}"

if [ -z "$PROMPT" ]; then
    echo "Usage: gemma-logger.sh <caller> <model> <prompt> [num_predict] [temperature]" >&2
    exit 1
fi

TS_START=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
T_START=$(python3 -c "import time; print(time.time())")

# API 호출
export PROMPT MODEL NUM_PREDICT TEMPERATURE OLLAMA
RESPONSE=$(python3 <<'PYEOF'
import json, os, urllib.request, sys

try:
    body = json.dumps({
        "model": os.environ["MODEL"],
        "messages": [{"role": "user", "content": os.environ["PROMPT"]}],
        "stream": False,
        "keep_alive": "30m",
        "options": {
            "num_predict": int(os.environ["NUM_PREDICT"]),
            "temperature": float(os.environ["TEMPERATURE"])
        }
    }).encode()
    req = urllib.request.Request(
        f"http://{os.environ['OLLAMA']}/api/chat",
        data=body,
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        data = json.loads(r.read())
    result = data.get("message", {}).get("content", "")
    meta = {
        "content": result,
        "done_reason": data.get("done_reason"),
        "eval_count": data.get("eval_count"),
        "prompt_eval_count": data.get("prompt_eval_count"),
        "total_duration_ns": data.get("total_duration"),
    }
    # stderr로 메타, stdout은 실제 응답
    print(json.dumps(meta), file=sys.stderr)
    print(result)
except Exception as e:
    print(json.dumps({"error": str(e)}), file=sys.stderr)
    sys.exit(1)
PYEOF
2>/tmp/gemma-meta-$$.json)

EXIT_CODE=$?
T_END=$(python3 -c "import time; print(time.time())")
DURATION_MS=$(python3 -c "print(int((${T_END}-${T_START})*1000))")

# 메타 데이터 읽기
META=$(cat /tmp/gemma-meta-$$.json 2>/dev/null)
/bin/rm -f /tmp/gemma-meta-$$.json

STATUS="ok"
if [ $EXIT_CODE -ne 0 ]; then
    STATUS="error"
fi

# JSONL 로그 기록
python3 <<PYEOF
import json
meta_raw = '''${META}'''
try:
    meta = json.loads(meta_raw) if meta_raw else {}
except Exception:
    meta = {}

prompt = """${PROMPT}"""
response = meta.get("content", "")

record = {
    "timestamp": "${TS_START}",
    "caller": "${CALLER}",
    "model": "${MODEL}",
    "status": "${STATUS}",
    "duration_ms": ${DURATION_MS},
    "num_predict": ${NUM_PREDICT},
    "temperature": ${TEMPERATURE},
    "input_tokens": meta.get("prompt_eval_count"),
    "output_tokens": meta.get("eval_count"),
    "done_reason": meta.get("done_reason"),
    "prompt_preview": prompt[:500],
    "prompt_length": len(prompt),
    "response_preview": response[:500],
    "response_length": len(response),
}

with open("${LOG_FILE}", "a", encoding="utf-8") as f:
    f.write(json.dumps(record, ensure_ascii=False) + "\n")
PYEOF

echo "$RESPONSE"
exit $EXIT_CODE

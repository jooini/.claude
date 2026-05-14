#!/bin/bash
# Gemma 호출 래퍼 — ini CLI 우선 + urllib fallback
# 사용법 (훅/스크립트 내부에서):
#   RESULT=$(~/.claude/scripts/gemma-logger.sh <caller_name> <model> <prompt> [num_predict] [temperature])
#
# 기능:
# - ini CLI 호출 (`ini -p --model <model> --quiet`)
# - LAN 미접속 또는 ini 실패 시 urllib /api/chat 호출 fallback
# - ~/.claude/cache/gemma-calls.jsonl 에 호출 메타 JSONL 기록
# - stdout에 응답만 출력 (기존 코드 100% 호환)
#
# 마이그레이션: 2026-05-10. 백업: gemma-logger.sh.backup-2026-05-10

: "${HOME:?}"
OLLAMA="${OLLAMA_HOST_LAN:-leonard.local:11434}"
LOG_FILE="$HOME/.claude/cache/gemma-calls.jsonl"
INI_BIN="$HOME/.local/bin/ini"
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

# 1) ini 우선 시도 (단발 호출 모드)
USE_INI=0
RESPONSE=""
EXIT_CODE=1
TRANSPORT="urllib_fallback"

if [ -x "$INI_BIN" ]; then
    # ini는 OLLAMA_HOST_URL 환경변수 사용
    export OLLAMA_HOST_URL="http://${OLLAMA}"
    # ini는 num_ctx 오버라이드만 지원, num_predict는 모델 기본값
    # 응답만 stdout으로 (--quiet 자동 -p 모드에서 활성)
    RESPONSE=$(printf '%s' "$PROMPT" | timeout 90 "$INI_BIN" \
        --model "$MODEL" \
        --keep-alive "30m" \
        --no-rag \
        --no-cache \
        -p - 2>/tmp/gemma-ini-err-$$ )
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 0 ] && [ -n "$RESPONSE" ]; then
        USE_INI=1
        TRANSPORT="ini"
    fi
fi

# 2) ini 실패 또는 응답 없음 → urllib fallback
if [ $USE_INI -eq 0 ]; then
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
    print(json.dumps(meta), file=sys.stderr)
    print(result)
except Exception as e:
    print(json.dumps({"error": str(e)}), file=sys.stderr)
    sys.exit(1)
PYEOF
2>/tmp/gemma-meta-$$.json)
    EXIT_CODE=$?
fi

T_END=$(python3 -c "import time; print(time.time())")
DURATION_MS=$(python3 -c "print(int((${T_END}-${T_START})*1000))")

# 메타 데이터 읽기 (urllib fallback에서만 채워짐)
META=$(cat /tmp/gemma-meta-$$.json 2>/dev/null || echo "{}")
INI_ERR=$(cat /tmp/gemma-ini-err-$$ 2>/dev/null | head -c 500 || echo "")
/bin/rm -f /tmp/gemma-meta-$$.json /tmp/gemma-ini-err-$$

STATUS="ok"
if [ $EXIT_CODE -ne 0 ] || [ -z "$RESPONSE" ]; then
    STATUS="error"
fi

# JSONL 로그 기록
export META INI_ERR PROMPT TS_START CALLER MODEL STATUS DURATION_MS NUM_PREDICT TEMPERATURE TRANSPORT LOG_FILE
RESPONSE_FOR_LOG="$RESPONSE" python3 <<'PYEOF'
import json, os, sys

meta_raw = os.environ.get("META", "{}")
try:
    meta = json.loads(meta_raw) if meta_raw else {}
except Exception:
    meta = {}

prompt = os.environ.get("PROMPT", "")
response = os.environ.get("RESPONSE_FOR_LOG", "") or meta.get("content", "")

record = {
    "timestamp": os.environ.get("TS_START"),
    "caller": os.environ.get("CALLER"),
    "model": os.environ.get("MODEL"),
    "status": os.environ.get("STATUS"),
    "duration_ms": int(os.environ.get("DURATION_MS", "0")),
    "num_predict": int(os.environ.get("NUM_PREDICT", "0")),
    "temperature": float(os.environ.get("TEMPERATURE", "0")),
    "transport": os.environ.get("TRANSPORT", "unknown"),
    "input_tokens": meta.get("prompt_eval_count"),
    "output_tokens": meta.get("eval_count"),
    "done_reason": meta.get("done_reason"),
    "prompt_preview": prompt[:500],
    "prompt_length": len(prompt),
    "response_preview": response[:500],
    "response_length": len(response),
}
ini_err = os.environ.get("INI_ERR", "")
if ini_err:
    record["ini_stderr_preview"] = ini_err[:300]

with open(os.environ["LOG_FILE"], "a", encoding="utf-8") as f:
    f.write(json.dumps(record, ensure_ascii=False) + "\n")
PYEOF

echo "$RESPONSE"
exit $EXIT_CODE

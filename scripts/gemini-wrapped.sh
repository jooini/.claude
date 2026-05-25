#!/bin/zsh
# gemini-wrapped — Gemini/Antigravity(agy) CLI 호출 래퍼 + 사용량 로깅
#
# 2026-06-18 부로 무료/Pro/Ultra 사용자 대상 gemini CLI 요청 처리 종료 →
# Antigravity CLI(`agy`)로 전환. 본 래퍼는 GEMINI_CLI 환경변수로 CLI 선택.
#
# 환경변수:
#   GEMINI_CLI   "agy"(기본 권장) | "gemini" | 직접 경로. 미지정 시 agy 우선 탐지.
#   GEMINI_CALLER 호출자 식별자 (없으면 부모 프로세스명)
#
# 사용:
#   ~/.claude/scripts/gemini-wrapped.sh -p "질문"
#   echo "컨텍스트" | ~/.claude/scripts/gemini-wrapped.sh -p "요약"
#
# 로깅:
#   gemini  → ~/.claude/cache/gemini-calls.jsonl (stream-json stats 포함)
#   agy     → ~/.claude/cache/agy-calls.jsonl    (duration/exit_code만, stats 미지원)

: "${HOME:?}"

# --- nvm PATH 보강 (Claude Code Bash tool 등 nvm 미소싱 환경 대응) ------------
# gemini/node가 nvm 안에 있어 PATH 누락 시 'env: node: No such file' 발생
for v in v22.22.0 v22.4.1; do
    if [ -x "/Users/leonard/.nvm/versions/node/$v/bin/node" ]; then
        export PATH="/Users/leonard/.nvm/versions/node/$v/bin:$PATH"
        break
    fi
done

# --- CLI 결정 (gemini 우선 — 토큰 측정 가능, agy는 fallback) ------------------
# 2026-05-25 변경: agy는 stream-json 미지원으로 토큰 메타 0 → gemini를 default로
if [ -n "$GEMINI_CLI" ]; then
    CLI="$GEMINI_CLI"
elif command -v gemini >/dev/null 2>&1; then
    CLI="gemini"
elif command -v agy >/dev/null 2>&1; then
    CLI="agy"
else
    echo "gemini-wrapped: gemini/agy CLI 미설치" >&2
    exit 127
fi

# CLI 이름만 추출 (경로일 경우 basename)
CLI_NAME=$(basename "$CLI")

LOG_FILE="$HOME/.claude/cache/${CLI_NAME}-calls.jsonl"
mkdir -p "$(dirname "$LOG_FILE")"

CALLER="${GEMINI_CALLER:-$(ps -o comm= -p $PPID 2>/dev/null | tail -1 || echo 'unknown')}"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
START_MS=$(/usr/bin/python3 -c "import time;print(int(time.time()*1000))")

# --- agy 분기: stream-json 미지원 ---------------------------------------------
if [ "$CLI_NAME" = "agy" ]; then
    RAW=$(mktemp)
    trap 'rm -f "$RAW"' EXIT
    "$CLI" "$@" > "$RAW" 2>&1
    EXIT_CODE=$?
    END_MS=$(/usr/bin/python3 -c "import time;print(int(time.time()*1000))")
    cat "$RAW"
    DURATION=$((END_MS - START_MS))
    OUT_BYTES=$(/usr/bin/wc -c < "$RAW" | tr -d ' ')
    /usr/bin/python3 - <<PYEOF
import json
record = {
    'timestamp': "$TS",
    'caller': "$CALLER",
    'cli': "agy",
    'status': 'ok' if $EXIT_CODE == 0 else 'error',
    'exit_code': $EXIT_CODE,
    'duration_ms': $DURATION,
    'output_bytes': $OUT_BYTES,
}
with open("$LOG_FILE", 'a') as f:
    f.write(json.dumps(record, ensure_ascii=False) + '\n')
PYEOF
    exit $EXIT_CODE
fi

# --- gemini 분기: stream-json stats 추출 --------------------------------------
RAW=$(mktemp)
trap 'rm -f "$RAW"' EXIT

HAS_FORMAT=0
for arg in "$@"; do
    if [[ "$arg" == "--output-format" || "$arg" == "-o" ]]; then
        HAS_FORMAT=1
    fi
done

if [ $HAS_FORMAT -eq 1 ]; then
    exec "$CLI" "$@"
fi

"$CLI" --output-format stream-json "$@" > "$RAW" 2>&1
EXIT_CODE=$?

/usr/bin/python3 <<PYEOF
import json, sys
raw_path = "$RAW"
log_path = "$LOG_FILE"
caller = "$CALLER"
ts = "$TS"
exit_code = $EXIT_CODE

stats = None
content_parts = []
session_id = None
model = None

with open(raw_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except Exception:
            continue
        t = obj.get('type')
        if t == 'init':
            session_id = obj.get('session_id')
            model = obj.get('model')
        elif t == 'message' and obj.get('role') == 'assistant':
            c = obj.get('content', '')
            if c:
                content_parts.append(c)
        elif t == 'result':
            stats = obj.get('stats', {})

content = ''.join(content_parts)
sys.stdout.write(content)
if content and not content.endswith('\n'):
    sys.stdout.write('\n')

if stats:
    record = {
        'timestamp': ts,
        'caller': caller,
        'cli': 'gemini',
        'session_id': session_id,
        'model': model,
        'status': 'ok' if exit_code == 0 else 'error',
        'exit_code': exit_code,
        'total_tokens': stats.get('total_tokens', 0),
        'input_tokens': stats.get('input_tokens', 0),
        'output_tokens': stats.get('output_tokens', 0),
        'cached_tokens': stats.get('cached', 0),
        'duration_ms': stats.get('duration_ms', 0),
        'tool_calls': stats.get('tool_calls', 0),
        'models_breakdown': stats.get('models', {})
    }
    with open(log_path, 'a') as f:
        f.write(json.dumps(record, ensure_ascii=False) + '\n')

sys.exit(exit_code)
PYEOF

exit $?

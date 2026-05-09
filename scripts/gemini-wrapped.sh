#!/bin/zsh
# gemini-wrapped — Gemini CLI 호출을 감싸 stats(토큰) 정보를 jsonl에 기록
#
# 사용:
#   ~/.claude/scripts/gemini-wrapped.sh -p "질문"
#   echo "컨텍스트" | ~/.claude/scripts/gemini-wrapped.sh -p "요약"
#
# 동작:
#   1. gemini --output-format stream-json [원래 인자] 실행
#   2. stdin/stdout 모두 통과
#   3. 마지막 result 라인의 stats를 ~/.claude/cache/gemini-calls.jsonl에 append
#   4. 사용자에게는 평소처럼 텍스트만 보여줌 (assistant content만 추출)
#
# 호출자 식별: 환경변수 GEMINI_CALLER 있으면 사용, 없으면 부모 프로세스명

: "${HOME:?}"

LOG_FILE="$HOME/.claude/cache/gemini-calls.jsonl"
mkdir -p "$(dirname "$LOG_FILE")"

CALLER="${GEMINI_CALLER:-$(ps -o comm= -p $PPID 2>/dev/null | tail -1 || echo 'unknown')}"
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 임시 파일 — stream-json 출력 캡처
RAW=$(mktemp)
trap 'rm -f "$RAW"' EXIT

# stream-json 옵션이 사용자 인자에 이미 있으면 그대로, 없으면 추가
HAS_FORMAT=0
for arg in "$@"; do
    if [[ "$arg" == "--output-format" || "$arg" == "-o" ]]; then
        HAS_FORMAT=1
    fi
done

if [ $HAS_FORMAT -eq 1 ]; then
    # 사용자가 직접 format 지정 — 그대로 통과 (로깅 못함)
    exec gemini "$@"
fi

# stream-json으로 실행
gemini --output-format stream-json "$@" > "$RAW" 2>&1
EXIT_CODE=$?

# 결과 파싱
/usr/bin/python3 << PYEOF
import json, os, sys
from datetime import datetime

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
            # 비-JSON 라인 (Ripgrep 경고 등) 무시
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

# 응답 본문은 stdout으로 출력 (사용자에게 전달)
content = ''.join(content_parts)
sys.stdout.write(content)
if content and not content.endswith('\n'):
    sys.stdout.write('\n')

# stats 있으면 jsonl에 기록
if stats:
    record = {
        'timestamp': ts,
        'caller': caller,
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

#!/bin/zsh
# PostToolUse(Agent): 파이프라인 메트릭 기록
# 에이전트 실행 시간/성공여부/프로젝트별 분포 측정용
# 비동기 비차단 — 실패해도 파이프라인 영향 없음

: "${HOME:?}"

INPUT=$(cat)

# 디버그: duration_ms 누락 케이스 분석용 — 전체 페이로드 구조 캡처
# 30일 누적 후 fallback 로직 추가 결정. 캐시 디렉토리 30일+ 자동 정리됨.
DEBUG_DIR="$HOME/.claude/cache/pipeline-metrics-debug"
mkdir -p "$DEBUG_DIR"
DEBUG_FILE="$DEBUG_DIR/$(date +%Y-%m-%d).jsonl"
echo "$INPUT" | /usr/bin/python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    keys_top = sorted(d.keys())
    keys_resp = sorted(d.get('tool_response', {}).keys()) if isinstance(d.get('tool_response'), dict) else []
    keys_input = sorted(d.get('tool_input', {}).keys()) if isinstance(d.get('tool_input'), dict) else []
    out = {'ts': '$(date +%Y-%m-%dT%H:%M:%S)', 'top': keys_top, 'tool_response': keys_resp, 'tool_input': keys_input, 'has_duration_ms': 'duration_ms' in str(d)}
    print(json.dumps(out))
except Exception as e:
    print(json.dumps({'ts': '$(date +%Y-%m-%dT%H:%M:%S)', 'error': str(e)}))
" >> "$DEBUG_FILE" 2>/dev/null

AGENT_TYPE=$(echo "$INPUT" | /usr/bin/python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    # 1순위: tool_input.subagent_type (Task 도구 표준)
    t = d.get('tool_input', {}).get('subagent_type')
    if not t:
        # 2순위: top-level subagent_type
        t = d.get('subagent_type')
    if not t:
        # 3순위: tool_response 메타
        t = d.get('tool_response', {}).get('subagent_type') if isinstance(d.get('tool_response'), dict) else None
    print(t or 'unknown')
except Exception:
    print('parse-error')
" 2>/dev/null)
[ -z "$AGENT_TYPE" ] && AGENT_TYPE="unknown"

# duration_ms 페이로드 어디에 있을지 모르므로 여러 위치 시도
DURATION_MS=$(echo "$INPUT" | sed -n 's/.*"duration_ms"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
[ -z "$DURATION_MS" ] && DURATION_MS=$(echo "$INPUT" | sed -n 's/.*"totalDurationMs"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
[ -z "$DURATION_MS" ] && DURATION_MS=$(echo "$INPUT" | sed -n 's/.*"executionTimeMs"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
[ -z "$DURATION_MS" ] && DURATION_MS="0"

EXIT_CODE=$(echo "$INPUT" | sed -n 's/.*"exit_code"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
STATUS="ok"
[ -n "$EXIT_CODE" ] && [ "$EXIT_CODE" != "0" ] && STATUS="fail"

DESC=$(echo "$INPUT" | sed -n 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -c 80)

METRICS_DIR="$HOME/.claude/cache/metrics"
mkdir -p "$METRICS_DIR"

DATE=$(date +"%Y-%m-%d")
TIMESTAMP=$(date +"%Y-%m-%dT%H:%M:%S")
METRICS_FILE="$METRICS_DIR/${DATE}.tsv"

if [ ! -f "$METRICS_FILE" ]; then
    echo -e "timestamp\tagent\tproject\tstatus\tduration_ms\tdescription" > "$METRICS_FILE"
fi

CWD=$(pwd)
PROJECT=$(basename "${CWD}")

printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$TIMESTAMP" "$AGENT_TYPE" "$PROJECT" "$STATUS" "$DURATION_MS" "$DESC" \
    >> "$METRICS_FILE"

exit 0

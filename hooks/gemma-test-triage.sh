#!/bin/zsh
# PostToolUse(Bash): 테스트 실행 실패 감지 → Gemma가 {flaky/실제 버그/환경 문제} 분류
# 출력: hookSpecificOutput.additionalContext로 Claude에 주입
# 3회 연속 실패 시 Codex rescue 권고 플래그 추가 (기존 규칙과 통합)

: "${HOME:?}"

OLLAMA_HOST="${OLLAMA_HOST_LAN:-leonard.local:11434}"
CACHE_DIR="$HOME/.claude/cache/test-triage"
mkdir -p "$CACHE_DIR"

INPUT=$(cat)

# 테스트 명령 + exit code 추출
CMD=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('command', ''))
except Exception:
    pass
" 2>/dev/null)

if [ -z "$CMD" ]; then
    exit 0
fi

# 테스트 명령인지 확인 (휴리스틱)
case "$CMD" in
    *"npm test"*|*"npm run test"*|*"yarn test"*|*"pnpm test"*|*"pytest"*|*"py.test"*|*"gradle test"*|*"./gradlew test"*|*"mvn test"*|*"go test"*|*"cargo test"*|*"phpunit"*|*"vendor/bin/phpunit"*|*"jest"*|*"vitest"*|*"rspec"*)
        ;;
    *)
        exit 0
        ;;
esac

EXIT_CODE=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    resp = data.get('tool_response', {})
    for key in ('exit_code', 'exitCode', 'returncode'):
        if key in resp and resp[key] is not None:
            print(resp[key]); break
except Exception:
    pass
" 2>/dev/null)

if [ -z "$EXIT_CODE" ] || [ "$EXIT_CODE" = "0" ]; then
    # 성공 시 실패 카운터 리셋
    PROJECT_KEY=$(pwd | md5 -q 2>/dev/null || pwd | md5sum 2>/dev/null | awk '{print $1}')
    /bin/rm -f "$CACHE_DIR/${PROJECT_KEY}.count" 2>/dev/null
    exit 0
fi

# 출력 수집
OUTPUT=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    resp = data.get('tool_response', {})
    chunks = [resp.get('stderr', ''), resp.get('stdout', ''), resp.get('output', '')]
    combined = '\n'.join(c for c in chunks if c).strip()
    # 최근 200줄
    lines = combined.split('\n')[-200:]
    print('\n'.join(lines))
except Exception:
    pass
" 2>/dev/null)

if [ -z "$OUTPUT" ] || [ ${#OUTPUT} -lt 100 ]; then
    exit 0
fi

# 실패 카운터 업데이트
PROJECT_KEY=$(pwd | md5 -q 2>/dev/null || pwd | md5sum 2>/dev/null | awk '{print $1}')
COUNT_FILE="$CACHE_DIR/${PROJECT_KEY}.count"
COUNT=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNT_FILE"

# Ollama 확인
if ! curl -s --max-time 2 "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
    exit 0
fi

export OUTPUT CMD COUNT

PAYLOAD=$(python3 <<'PYEOF'
import json, os
out = os.environ["OUTPUT"]
cmd = os.environ["CMD"]
count = os.environ["COUNT"]
prompt = f"""테스트가 실패했다. 출력을 분석해서 한국어로 분류해줘.

출력 형식 (정확히):
**분류**: <flaky | 실제 버그 | 환경 문제 | 불명>
**증상**: <1줄 요약>
**원인 추정**: <1~2줄>
**다음 조치**: <1줄 권고>

분류 기준:
- flaky: 타이밍, race condition, 외부 의존성 가변성, 랜덤 실패
- 실제 버그: 코드 로직/타입/assertion 실제 오류
- 환경 문제: DB 연결 실패, 포트 충돌, 환경변수 누락, 의존성 미설치
- 불명: 출력으로 판단 불가

명령: {cmd}
실패 횟수: {count}회 연속

출력:
{out}
"""
print(json.dumps({
    "model": "gemma4:e4b",
    "messages": [
        {"role": "system", "content": "한국어로 4줄만. 설명/인사 금지."},
        {"role": "user", "content": prompt}
    ],
    "stream": False,
    "keep_alive": "30m",
    "options": {"num_predict": 300}
}))
PYEOF
)

if [ -z "$PAYLOAD" ]; then
    exit 0
fi

RESULT=$(curl -s --max-time 15 "http://${OLLAMA_HOST}/api/chat" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" 2>/dev/null | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('message', {}).get('content', ''))
except Exception:
    pass
" 2>/dev/null)

if [ -z "$RESULT" ]; then
    exit 0
fi

# 3회 이상 실패 시 Codex rescue 권고 추가
ESCALATION=""
if [ "$COUNT" -ge 3 ]; then
    ESCALATION="\n\n[에스컬레이션] 3회 연속 실패 — Codex rescue 호출 권장 (Skill: codex:rescue foreground)"
fi

export GEMMA_RESULT="$RESULT" ESCALATION
python3 -c "
import json, os
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'additionalContext': '[Gemma 테스트 triage]\n' + os.environ['GEMMA_RESULT'] + os.environ.get('ESCALATION', '')
    }
}))
"

exit 0

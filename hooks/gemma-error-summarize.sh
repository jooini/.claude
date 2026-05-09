#!/bin/zsh
# PostToolUse(Bash): Bash 명령 실패 시 stderr/stdout을 qwen-cli에 넘겨 한글 요약 생성
# 목적: Claude 컨텍스트 절약 — 긴 stack trace 대신 3줄 요약을 Claude에 주입
# 출력: hookSpecificOutput.additionalContext로 Claude 모델에 컨텍스트 주입

: "${HOME:?}"

QWEN="$HOME/.local/bin/qwen-cli"
[ -x "$QWEN" ] || exit 0

INPUT=$(cat)

# 빠른 사전 필터: tool_response에 실패 시그널이 전혀 없으면 파싱 스킵
# 정상 종료 케이스(95%)에서 python3 콜드스타트 회피
# 실패 시그널: exit_code 비-0, "error", "Error", "Traceback", "FAIL", stderr 본문 등
case "$INPUT" in
    *'"exit_code":0'*|*'"exit_code": 0'*|*'"success":true'*|*'"success": true'*)
        # 명백한 성공 — 추가 검사 없이 종료
        # 단 stderr가 비어있지 않거나 명시적 에러 키워드 있으면 통과 시키기 위해 한번 더 검사
        if ! echo "$INPUT" | grep -qiE '(traceback|error:|failed|fatal|exception)'; then
            exit 0
        fi
        ;;
esac

# 회사 LAN 외부에서 호출 시 즉시 skip (TCP 1초 캐시 5분)
source "$HOME/.claude/hooks/_lib/ollama-available.sh"
ollama_available || exit 0

# exit code 추출 (0이 아닐 때만 트리거)
EXIT_CODE=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    resp = data.get('tool_response', {})
    for key in ('exit_code', 'exitCode', 'returncode'):
        if key in resp and resp[key] is not None:
            print(resp[key]); break
    else:
        if resp.get('success') is True:
            print(0)
except Exception:
    pass
" 2>/dev/null)

if [ -z "$EXIT_CODE" ] || [ "$EXIT_CODE" = "0" ]; then
    exit 0
fi

# 커맨드 + 출력 수집 (최근 100줄)
PAYLOAD_RAW=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    cmd = data.get('tool_input', {}).get('command', '')
    resp = data.get('tool_response', {})
    chunks = [resp.get('stderr', ''), resp.get('stdout', ''), resp.get('output', '')]
    combined = '\n'.join(c for c in chunks if c).strip()
    if not combined:
        print('', end='')
    else:
        lines = combined.split('\n')[-100:]
        print(cmd + '\n===OUTPUT===\n' + '\n'.join(lines))
except Exception:
    pass
" 2>/dev/null)

if [ -z "$PAYLOAD_RAW" ]; then
    exit 0
fi

# 출력이 너무 짧으면 요약 불필요
if [ ${#PAYLOAD_RAW} -lt 100 ]; then
    exit 0
fi

# 조건 검사 목적의 exit code는 스킵
CMD_LINE=$(echo "$PAYLOAD_RAW" | head -1)
case "$CMD_LINE" in
    *"grep "*|*"test "*|*"[ "*|*"which "*|*"curl -f"*)
        exit 0 ;;
esac

# qwen-cli 호출 — debugger 페르소나 (qwen2.5-coder:14b 자동 적용)
PROMPT=$(printf '다음 Bash 명령이 실패했다. 출력을 분석해서 한국어로 간결하게 정리.\n\n형식 (정확히 3줄):\n**원인**: <1줄>\n**위치**: <파일:라인 또는 함수명, 없으면 "불명">\n**다음 조치**: <1줄 권고>\n\n원문 복사/장황한 설명 금지.\n\n명령 및 출력:\n%s' "$PAYLOAD_RAW")

RESULT=$(echo "$PROMPT" | "$QWEN" -p - --profile debugger --num-ctx 8192 2>/dev/null)
EXIT=$?

if [ "$EXIT" -ne 0 ] || [ -z "$RESULT" ]; then
    exit 0
fi

export GEMMA_RESULT="$RESULT"
python3 -c "
import json, os
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'additionalContext': '[qwen-cli 에러 요약]\n' + os.environ['GEMMA_RESULT']
    }
}))
"

exit 0

#!/bin/zsh
# PreToolUse(Agent): code-reviewer 실행 전 Gemma(로컬 Ollama) 프리스캔
# Gemini와 병렬로 동작. 민감 코드/로컬 세컨드 오피니언 담당
# exit 0 + stdout = 비차단 리마인더

: "${HOME:?}"

INPUT=$(cat)

AGENT_TYPE=$(echo "$INPUT" | sed -n 's/.*"subagent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

# code-reviewer 에이전트만 대상
if [ "$AGENT_TYPE" != "code-reviewer" ]; then
    exit 0
fi

# git repo 확인
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    exit 0
fi

# diff 존재 여부 확인
DIFF=$(git diff HEAD 2>/dev/null)
if [ -z "$DIFF" ]; then
    DIFF=$(git diff HEAD~1 2>/dev/null)
fi
if [ -z "$DIFF" ]; then
    exit 0
fi

PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
CACHE_DIR="$HOME/.claude/cache/gemma"
mkdir -p "$CACHE_DIR"
OUTPUT_FILE="$CACHE_DIR/${PROJECT_NAME}-review-prescan.md"

# 최근 5분 내 결과 있으면 재사용
if [ -f "$OUTPUT_FILE" ]; then
    FILE_AGE=$(( $(date +%s) - $(stat -f %m "$OUTPUT_FILE" 2>/dev/null || echo 0) ))
    if [ "$FILE_AGE" -lt 300 ]; then
        echo "[Gemma 프리스캔 캐시] code-reviewer에 아래 컨텍스트 포함할 것:"
        cat "$OUTPUT_FILE"
        exit 0
    fi
fi

# Ollama 서버 살아있는지 빠르게 확인 (3초 타임아웃)
if ! curl -s --max-time 3 http://leonard.local:11434/api/tags >/dev/null 2>&1; then
    echo "[Gemma 프리스캔 스킵] Ollama 서버(leonard.local:11434) 접근 불가 — code-reviewer 단독 진행"
    exit 0
fi

echo "[Gemma 리뷰 프리스캔 실행 중] 완료까지 최대 30초..."

# diff 500줄 컷
DIFF_TRUNCATED=$(echo "$DIFF" | head -500)

# JSON 페이로드 안전하게 만들기 위해 python 사용
PAYLOAD=$(python3 -c "
import json, sys
diff = sys.stdin.read()
prompt = f'''다음 코드 변경사항을 간결하게 리뷰해줘. 한국어로 답하고 핵심 문제만 지적:
1. 로직 오류 / 엣지 케이스 누락
2. 보안 취약점
3. 기존 코드와의 일관성 문제

변경사항:
{diff}'''
print(json.dumps({
    'model': 'gemma4:e4b',
    'messages': [
        {'role': 'system', 'content': '한국어로 간결하게 답변. 과장 없이 실제 문제만 지적.'},
        {'role': 'user', 'content': prompt}
    ],
    'stream': False,
    'keep_alive': '30m'
}))
" <<<"$DIFF_TRUNCATED" 2>/dev/null)

if [ -z "$PAYLOAD" ]; then
    echo "[Gemma 프리스캔 실패] 페이로드 생성 오류 — code-reviewer 단독 진행"
    exit 0
fi

RESULT=$(curl -s --max-time 30 http://leonard.local:11434/api/chat \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print(data.get('message', {}).get('content', ''))
except Exception:
    pass
" 2>/dev/null)

if [ -n "$RESULT" ]; then
    echo "$RESULT" > "$OUTPUT_FILE"
    echo "[Gemma 프리스캔 완료] code-reviewer 프롬프트에 아래 컨텍스트 포함할 것:"
    echo "---"
    echo "$RESULT"
else
    echo "[Gemma 프리스캔 실패/타임아웃] — code-reviewer 단독 진행"
fi

exit 0

#!/bin/zsh
# PreToolUse(Bash): git commit 감지 → staged diff를 Gemma에 넘겨 커밋 메시지 초안 생성
# exit 0 + stdout = 비차단 힌트 (사용자/Claude가 최종 결정)
# 실패/서버다운/타임아웃 시 즉시 스킵 (원본 커밋 흐름 블로킹 없음)

: "${HOME:?}"

OLLAMA_HOST="${OLLAMA_HOST_LAN:-leonard.local:11434}"
CACHE_DIR="$HOME/.claude/cache/gemma"
mkdir -p "$CACHE_DIR"

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p')

# git commit 명령인지 확인
if ! echo "$COMMAND" | grep -q 'git commit'; then
    exit 0
fi

# 이미 -m "메시지"가 있는 경우 = 실제 커밋 실행 단계 → 스킵 (검증 훅이 처리)
# Claude Code가 넘기는 JSON에서는 내부 따옴표가 \" 형태로 escape되어 있음
if echo "$COMMAND" | grep -qE '\-m[[:space:]]+(\\?["'"'"'])'; then
    exit 0
fi

# heredoc 커밋도 이미 메시지 있음 → 스킵
if echo "$COMMAND" | grep -q '<<.*EOF'; then
    exit 0
fi

# git repo 확인
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    exit 0
fi

# staged 변경 확인
STAGED=$(git diff --cached --name-only 2>/dev/null)
if [ -z "$STAGED" ]; then
    exit 0
fi

# 민감 파일 스테이징 감지 시 Gemma 호출 스킵 (유출 위험)
if echo "$STAGED" | grep -qE '(\.env$|\.env\.|credentials|\.pem$|\.key$|secrets?\.(json|yaml|yml))'; then
    echo "[커밋 초안 스킵] 민감 파일 스테이징 감지 — Gemma 호출 안 함"
    exit 0
fi

PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
OUTPUT_FILE="$CACHE_DIR/${PROJECT_NAME}-commit-draft.md"

# 1분 이내 캐시 재사용 (같은 diff 반복 방지)
DIFF_HASH=$(git diff --cached 2>/dev/null | md5 -q 2>/dev/null || git diff --cached 2>/dev/null | md5sum 2>/dev/null | awk '{print $1}')
CACHED_HASH_FILE="$CACHE_DIR/${PROJECT_NAME}-commit-draft.hash"

if [ -f "$OUTPUT_FILE" ] && [ -f "$CACHED_HASH_FILE" ]; then
    CACHED_HASH=$(cat "$CACHED_HASH_FILE" 2>/dev/null)
    FILE_AGE=$(( $(date +%s) - $(stat -f %m "$OUTPUT_FILE" 2>/dev/null || echo 0) ))
    if [ "$CACHED_HASH" = "$DIFF_HASH" ] && [ "$FILE_AGE" -lt 60 ]; then
        echo "[커밋 메시지 초안 (Gemma 캐시)]"
        echo "---"
        cat "$OUTPUT_FILE"
        echo "---"
        echo "위 초안 참고하되 최종 메시지는 직접 결정."
        exit 0
    fi
fi

# Ollama 서버 빠르게 확인 (3초 타임아웃)
if ! curl -s --max-time 3 "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
    exit 0
fi

# staged diff + 파일 목록 수집 (500줄 컷)
DIFF_TRUNCATED=$(git diff --cached 2>/dev/null | head -500)
STAT=$(git diff --cached --stat 2>/dev/null)

if [ -z "$DIFF_TRUNCATED" ]; then
    exit 0
fi

echo "[Gemma 커밋 초안 생성 중] 최대 15초..."

PAYLOAD=$(python3 -c "
import json, sys
data = sys.stdin.read()
stat, diff = data.split('---DIFF---', 1)
prompt = f'''다음 staged 변경사항을 분석해서 한국어 커밋 메시지 초안을 작성해줘.

형식:
<타입>: <한 줄 요약 (70자 이내)>

<본문 (선택, 왜 바꿨는지 3줄 이내)>

타입 후보: feat / fix / refactor / chore / docs / test / style / perf
Co-Authored-By 절대 포함하지 말 것.

변경 파일 통계:
{stat}

변경 내용:
{diff}
'''
print(json.dumps({
    'model': 'gemma4:e4b',
    'messages': [
        {'role': 'system', 'content': '한국어로 간결한 커밋 메시지만 출력. 설명/해설 금지. 바로 쓸 수 있는 형식으로.'},
        {'role': 'user', 'content': prompt}
    ],
    'stream': False,
    'keep_alive': '30m'
}))
" <<EOF 2>/dev/null
${STAT}
---DIFF---
${DIFF_TRUNCATED}
EOF
)

if [ -z "$PAYLOAD" ]; then
    exit 0
fi

RESULT=$(curl -s --max-time 15 "http://${OLLAMA_HOST}/api/chat" \
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
    echo "$DIFF_HASH" > "$CACHED_HASH_FILE"
    echo "[커밋 메시지 초안 (Gemma)]"
    echo "---"
    echo "$RESULT"
    echo "---"
    echo "위 초안 참고하되 최종 메시지는 직접 결정."
fi

exit 0

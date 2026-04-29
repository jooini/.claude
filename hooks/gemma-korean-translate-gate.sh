#!/bin/zsh
# PreToolUse(Bash): git commit / gh pr 명령에서 영어 메시지 감지 → 한글 번역 초안 제시
# 기존 commit-korean-check는 차단만, 이 훅은 번역 초안을 제공해 재작성 돕기
# exit 0 + stdout = 비차단 힌트 (commit-korean-check가 차단 결정)

: "${HOME:?}"

OLLAMA_HOST="${OLLAMA_HOST_LAN:-leonard.local:11434}"

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('tool_input', {}).get('command', ''))
except Exception:
    pass
" 2>/dev/null)

if [ -z "$COMMAND" ]; then
    exit 0
fi

# git commit / gh pr create / gh pr edit 명령만 대상
case "$COMMAND" in
    *"git commit"*-m*|*"gh pr create"*|*"gh pr edit"*)
        ;;
    *)
        exit 0
        ;;
esac

# 메시지 본문 추출 (-m "..." 또는 --title "..." / --body "...")
MSG=$(echo "$COMMAND" | python3 -c "
import sys, re
s = sys.stdin.read()
# -m '...' 또는 -m \"...\" 패턴 (escaped 따옴표 포함)
patterns = [
    r'-m\s+\\\\\"(.+?)\\\\\"',
    r'-m\s+\"(.+?)\"',
    r\"-m\s+'(.+?)'\",
    r'--title\s+\\\\\"(.+?)\\\\\"',
    r'--title\s+\"(.+?)\"',
    r'--body\s+\\\\\"(.+?)\\\\\"',
    r'--body\s+\"(.+?)\"',
]
for p in patterns:
    m = re.search(p, s)
    if m:
        print(m.group(1))
        break
" 2>/dev/null | head -1)

if [ -z "$MSG" ]; then
    exit 0
fi

# 한글 포함되어 있으면 번역 불필요
if echo "$MSG" | grep -q '[가-힣]'; then
    exit 0
fi

# 영어 단어 2개 이상 있는지 (단순 해시/ID 같은 것 필터)
WORD_COUNT=$(echo "$MSG" | grep -oE '[a-zA-Z]{3,}' | wc -l | tr -d ' ')
if [ "$WORD_COUNT" -lt 2 ]; then
    exit 0
fi

# Ollama 확인
if ! curl -s --max-time 2 "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
    exit 0
fi

export MSG

PAYLOAD=$(python3 <<'PYEOF'
import json, os
msg = os.environ["MSG"]
prompt = f"""다음 영문 커밋/PR 메시지를 한국어로 번역해줘.

규칙:
- Conventional Commits 타입 접두어(feat/fix/refactor 등)는 유지
- 70자 이내 간결하게
- 번역 결과만 출력. 설명/따옴표/인사 금지

영문 원본:
{msg}
"""
print(json.dumps({
    "model": "gemma4:e4b",
    "messages": [
        {"role": "system", "content": "번역 결과 한 줄만 출력."},
        {"role": "user", "content": prompt}
    ],
    "stream": False,
    "keep_alive": "30m",
    "options": {"num_predict": 100}
}))
PYEOF
)

if [ -z "$PAYLOAD" ]; then
    exit 0
fi

RESULT=$(curl -s --max-time 10 "http://${OLLAMA_HOST}/api/chat" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" 2>/dev/null | python3 -c "
import json, sys
try:
    print(json.load(sys.stdin).get('message', {}).get('content', ''))
except Exception:
    pass
" 2>/dev/null)

if [ -n "$RESULT" ]; then
    echo "[한글 번역 초안 (Gemma)] 원본: \"${MSG}\""
    echo "  → ${RESULT}"
    echo "팀 컨벤션은 한글. 위 초안 참고해서 재작성 권장."
fi

exit 0

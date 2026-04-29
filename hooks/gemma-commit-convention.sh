#!/bin/zsh
# PreToolUse(Bash): git commit -m 감지 → 메시지가 Conventional Commits 규약 따르는지 검사
# 위반 시 Gemma가 올바른 타입 제안, stdout으로 힌트 출력 (비차단)

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

# git commit -m 명령만
if ! echo "$COMMAND" | grep -qE 'git commit.*-m'; then
    exit 0
fi

# 메시지 추출
MSG=$(echo "$COMMAND" | python3 -c "
import sys, re
s = sys.stdin.read()
patterns = [
    r'-m\s+\\\\\"(.+?)\\\\\"',
    r'-m\s+\"(.+?)\"',
    r\"-m\s+'(.+?)'\",
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

# 첫 줄만 규약 검사
FIRST_LINE=$(echo "$MSG" | head -1)

# 이미 Conventional Commits 규약 따르는지 확인
# 패턴: type(scope): message 또는 type: message
if echo "$FIRST_LINE" | grep -qE '^(feat|fix|refactor|chore|docs|test|style|perf|build|ci|revert)(\([^)]+\))?!?:[[:space:]]'; then
    exit 0
fi

# Ollama 확인
if ! curl -s --max-time 2 "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
    exit 0
fi

# staged diff도 같이 보내서 정확한 타입 추정 도움
DIFF_STAT=""
if git rev-parse --is-inside-work-tree &>/dev/null; then
    DIFF_STAT=$(git diff --cached --stat 2>/dev/null | head -30)
fi

export MSG DIFF_STAT

PAYLOAD=$(python3 <<'PYEOF'
import json, os
msg = os.environ["MSG"]
stat = os.environ.get("DIFF_STAT", "")
prompt = f"""다음 커밋 메시지가 Conventional Commits 규약을 따르지 않는다.
규약 맞게 수정한 초안을 한 줄로 제시해줘.

규약 형식: `<type>(<scope>): <summary>` 또는 `<type>: <summary>`
type 후보: feat / fix / refactor / chore / docs / test / style / perf / build / ci / revert

원본 메시지:
{msg}

변경 파일 통계 (타입 추정 참고):
{stat}

출력 규칙:
- 초안 한 줄만. 설명/인사/따옴표 없이.
- 한글 유지 (원본이 한글이면).
- 70자 이내.
"""
print(json.dumps({
    "model": "gemma4:e4b",
    "messages": [
        {"role": "system", "content": "Conventional Commits 형식 한 줄만 출력."},
        {"role": "user", "content": prompt}
    ],
    "stream": False,
    "keep_alive": "30m",
    "options": {"num_predict": 80}
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
    echo "[Conventional Commits 위반 감지]"
    echo "  원본: ${FIRST_LINE}"
    echo "  제안: ${RESULT}"
    echo "규약 준수 재작성 권장."
fi

exit 0

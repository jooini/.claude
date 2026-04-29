#!/bin/zsh
# PostToolUse(Edit|Write): 의존성 파일 수정 감지 → Gemma가 추가/제거/업그레이드 패키지 한 줄 요약
# 기존 dependency-change-detect가 Gemini 호출하던 부분을 Gemma로 로컬화
# 출력: hookSpecificOutput.additionalContext로 Claude에 주입

: "${HOME:?}"

OLLAMA_HOST="${OLLAMA_HOST_LAN:-leonard.local:11434}"

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    resp = data.get('tool_response', {})
    fp = resp.get('filePath') or resp.get('file_path')
    if not fp:
        fp = data.get('tool_input', {}).get('file_path', '')
    print(fp)
except Exception:
    pass
" 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# 의존성 파일인지 확인
case "$(basename "$FILE_PATH")" in
    package.json|requirements.txt|requirements-*.txt|Pipfile|pyproject.toml|composer.json|build.gradle|build.gradle.kts|pom.xml|Cargo.toml|Gemfile|go.mod)
        ;;
    *)
        exit 0
        ;;
esac

# git diff로 변경사항 추출 (untracked는 스킵)
if ! git -C "$(dirname "$FILE_PATH")" rev-parse --is-inside-work-tree &>/dev/null; then
    exit 0
fi

DIFF=$(git -C "$(dirname "$FILE_PATH")" diff -- "$FILE_PATH" 2>/dev/null)
if [ -z "$DIFF" ]; then
    DIFF=$(git -C "$(dirname "$FILE_PATH")" diff --cached -- "$FILE_PATH" 2>/dev/null)
fi
if [ -z "$DIFF" ]; then
    exit 0
fi

# 너무 크면 컷
DIFF_TRUNCATED=$(echo "$DIFF" | head -150)

# Ollama 확인
if ! curl -s --max-time 2 "http://${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
    exit 0
fi

export DIFF_TRUNCATED
BASENAME=$(basename "$FILE_PATH")
export BASENAME

PAYLOAD=$(python3 <<'PYEOF'
import json, os
d = os.environ["DIFF_TRUNCATED"]
fname = os.environ["BASENAME"]
prompt = f"""의존성 파일 '{fname}'이 변경되었다. diff를 분석해서 한국어로 정리해줘.

출력 형식 (정확히):
**추가**: <패키지명@버전 나열, 없으면 "없음">
**제거**: <패키지명 나열, 없으면 "없음">
**업그레이드**: <패키지명: 구버전→신버전 나열, 없으면 "없음">
**주의**: <major version 점프/deprecated 패키지/보안 주의 사항, 없으면 "없음">

규칙:
- 장식/설명/인사 금지. 위 4줄만.
- 모르는 패키지는 추측하지 말고 이름만 기록.

diff:
{d}
"""
print(json.dumps({
    "model": "gemma4:e4b",
    "messages": [
        {"role": "system", "content": "한국어로 4줄만. 설명 금지."},
        {"role": "user", "content": prompt}
    ],
    "stream": False,
    "keep_alive": "30m",
    "options": {"num_predict": 3000}
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

export GEMMA_RESULT="$RESULT" BASENAME
python3 -c "
import json, os
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'additionalContext': '[Gemma 의존성 변경 요약 — ' + os.environ['BASENAME'] + ']\n' + os.environ['GEMMA_RESULT']
    }
}))
"

exit 0

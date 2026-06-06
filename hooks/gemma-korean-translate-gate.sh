#!/bin/zsh
# PreToolUse(Bash): git commit / gh pr 명령에서 영어 메시지 감지 → 한글 번역 초안 제시
# 기존 commit-korean-check는 차단만, 이 훅은 번역 초안을 제공해 재작성 돕기
# exit 0 + stdout = 비차단 힌트 (commit-korean-check가 차단 결정)

: "${HOME:?}"

[ -x "$HOME/.claude/scripts/llm-call.sh" ] || exit 0

# 회사 LAN 외부에서 호출 시 즉시 skip (TCP 1초 캐시 5분)
source "$HOME/.claude/hooks/_lib/ollama-available.sh"
ollama_available || exit 0

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

# ini — korean 페르소나가 자동 적용 (qwen3.5:9b)
PROMPT=$(printf '다음 영문 커밋/PR 메시지를 한국어로 번역.\n\n규칙:\n- Conventional Commits 타입 접두어(feat/fix/refactor 등)는 유지\n- 70자 이내 간결하게\n- 번역 결과만 출력. 설명/따옴표/인사 금지\n\n영문 원본:\n%s' "$MSG")

RESULT=$(echo "$PROMPT" | "$HOME/.claude/scripts/llm-call.sh" ini \
    --caller gemma-korean-translate-gate \
    --timeout 12 \
    --profile korean \
    --num-ctx 8192 \
    --prompt - \
    2>/dev/null)
EXIT=$?

if [ "$EXIT" -eq 0 ] && [ -n "$RESULT" ]; then
    echo "[한글 번역 초안 (ini)] 원본: \"${MSG}\""
    echo "  → ${RESULT}"
    echo "팀 컨벤션은 한글. 위 초안 참고해서 재작성 권장."
fi

exit 0

#!/bin/zsh
# PreToolUse(Agent): code-reviewer 실행 전 Gemini 리뷰 프리스캔
# Gemini가 넓고 얕게, code-reviewer가 좁고 깊게 분석
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
CACHE_DIR="$HOME/.claude/cache/gemini"
mkdir -p "$CACHE_DIR"
OUTPUT_FILE="$CACHE_DIR/${PROJECT_NAME}-review-prescan.md"

# 최근 5분 내 결과 있으면 재사용
if [ -f "$OUTPUT_FILE" ]; then
    FILE_AGE=$(( $(date +%s) - $(stat -f %m "$OUTPUT_FILE" 2>/dev/null || echo 0) ))
    if [ "$FILE_AGE" -lt 300 ]; then
        echo "[Gemini 프리스캔 캐시] code-reviewer에 아래 컨텍스트 포함할 것:"
        cat "$OUTPUT_FILE"
        exit 0
    fi
fi

echo "[Gemini 리뷰 프리스캔 실행 중] 완료까지 대기..."

# Gemini 동기 실행 (타임아웃 90초)
DIFF_TRUNCATED=$(echo "$DIFF" | head -500)
RESULT=$(timeout 90 gemini -p "다음 코드 변경사항을 리뷰해줘. 큰 문제점 위주로:
1. 로직 오류 / 엣지 케이스 누락
2. 성능 이슈
3. 보안 취약점
4. 기존 코드와의 일관성 문제

변경사항:
${DIFF_TRUNCATED}" 2>/dev/null)

if [ -n "$RESULT" ]; then
    echo "$RESULT" > "$OUTPUT_FILE"
    echo "[Gemini 프리스캔 완료] code-reviewer 프롬프트에 아래 컨텍스트를 포함할 것:"
    echo "---"
    echo "$RESULT"
else
    echo "[Gemini 프리스캔 실패/타임아웃] — code-reviewer 단독 진행"
fi

exit 0

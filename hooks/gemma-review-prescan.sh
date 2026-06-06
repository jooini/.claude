#!/bin/zsh
# PreToolUse(Agent): code-reviewer 실행 전 ini(로컬 Ollama) 프리스캔
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
        echo "[ini 프리스캔 캐시] code-reviewer에 아래 컨텍스트 포함할 것:"
        cat "$OUTPUT_FILE"
        exit 0
    fi
fi

# LLM 어댑터 확인
if [ ! -x "$HOME/.claude/scripts/llm-call.sh" ]; then
    echo "[ini 프리스캔 스킵] llm-call.sh 미설치 — code-reviewer 단독 진행"
    exit 0
fi

# 회사 LAN 외부에서 호출 시 즉시 skip (캐시 5분, 신선 시 0.03초)
source "$HOME/.claude/hooks/_lib/ollama-available.sh"
if ! ollama_available; then
    echo "[ini 프리스캔 스킵] Ollama 서버 접근 불가 — code-reviewer 단독 진행"
    exit 0
fi

echo "[ini 리뷰 프리스캔 실행 중] 완료까지 최대 30초..."

# diff 500줄 컷
DIFF_TRUNCATED=$(echo "$DIFF" | head -500)

# ini stdin 프롬프트 구성 (reviewer 페르소나가 시스템 프롬프트 담당)
PROMPT=$(cat <<EOF
다음 코드 변경사항을 간결하게 리뷰해줘. 한국어로 답하고 핵심 문제만 지적:
1. 로직 오류 / 엣지 케이스 누락
2. 보안 취약점
3. 기존 코드와의 일관성 문제

변경사항:
$DIFF_TRUNCATED
EOF
)

RESULT=$(printf '%s' "$PROMPT" | "$HOME/.claude/scripts/llm-call.sh" ini \
    --caller gemma-review-prescan \
    --timeout 30 \
    --profile reviewer \
    --num-ctx 8192 \
    --prompt - \
    2>/dev/null)

if [ -n "$RESULT" ]; then
    echo "$RESULT" > "$OUTPUT_FILE"
    echo "[ini 프리스캔 완료] code-reviewer 프롬프트에 아래 컨텍스트 포함할 것:"
    echo "---"
    echo "$RESULT"
else
    echo "[ini 프리스캔 실패/타임아웃] — code-reviewer 단독 진행"
fi

exit 0

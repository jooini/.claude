#!/bin/zsh
# PreToolUse(Agent): 에이전트 실행 전 관련 캐시 컨텍스트 자동 안내
# exit 0 + stdout = 비차단 리마인더

: "${HOME:?}"

INPUT=$(cat)

AGENT_TYPE=$(echo "$INPUT" | sed -n 's/.*"subagent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
[ -z "$AGENT_TYPE" ] && exit 0

# 현재 프로젝트 추출
CWD=$(pwd)
PROJECT_NAME=$(basename "$CWD")
if ! echo "$CWD" | grep -q '/Workspace/'; then
    exit 0
fi

CACHE_DIR="$HOME/.claude/cache"
CONTEXT_PARTS=""

# Gemini 스캔 결과
GEMINI_SCAN="$CACHE_DIR/gemini/${PROJECT_NAME}-scan.md"
if [ -f "$GEMINI_SCAN" ]; then
    FILE_AGE=$(( $(date +%s) - $(stat -f %m "$GEMINI_SCAN" 2>/dev/null || echo 0) ))
    if [ "$FILE_AGE" -lt 3600 ]; then
        CONTEXT_PARTS="${CONTEXT_PARTS}\n  - Gemini 스캔: cat ${GEMINI_SCAN}"
    fi
fi

# Gemini 리뷰 프리스캔 (code-reviewer만)
if [ "$AGENT_TYPE" = "code-reviewer" ]; then
    PRESCAN="$CACHE_DIR/gemini/${PROJECT_NAME}-review-prescan.md"
    if [ -f "$PRESCAN" ]; then
        FILE_AGE=$(( $(date +%s) - $(stat -f %m "$PRESCAN" 2>/dev/null || echo 0) ))
        if [ "$FILE_AGE" -lt 600 ]; then
            CONTEXT_PARTS="${CONTEXT_PARTS}\n  - Gemini 프리스캔: cat ${PRESCAN}"
        fi
    fi
fi

# Codex rescue 결과 (code-tester만)
if [ "$AGENT_TYPE" = "code-tester" ]; then
    RESCUE="$CACHE_DIR/codex/${PROJECT_NAME}-rescue.md"
    if [ -f "$RESCUE" ]; then
        FILE_AGE=$(( $(date +%s) - $(stat -f %m "$RESCUE" 2>/dev/null || echo 0) ))
        if [ "$FILE_AGE" -lt 1800 ]; then
            CONTEXT_PARTS="${CONTEXT_PARTS}\n  - Codex rescue: cat ${RESCUE}"
        fi
    fi
fi

# Gemini 의존성 분석 (backend-developer, code-tester만)
case "$AGENT_TYPE" in
    backend-developer|frontend-developer|code-tester)
        DEPS="$CACHE_DIR/gemini/${PROJECT_NAME}-deps.md"
        if [ -f "$DEPS" ]; then
            FILE_AGE=$(( $(date +%s) - $(stat -f %m "$DEPS" 2>/dev/null || echo 0) ))
            if [ "$FILE_AGE" -lt 3600 ]; then
                CONTEXT_PARTS="${CONTEXT_PARTS}\n  - Gemini 의존성 분석: cat ${DEPS}"
            fi
        fi
        ;;
esac

if [ -n "$CONTEXT_PARTS" ]; then
    echo "[캐시 컨텍스트] ${PROJECT_NAME} — 에이전트 프롬프트에 아래 결과를 포함할 것:${CONTEXT_PARTS}"
fi

exit 0

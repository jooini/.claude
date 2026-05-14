#!/bin/bash
# 학습 컨텍스트 1분 요약
# /morning, /start 루틴이 호출. 사람이 읽는 ~10줄 출력.
#
# 사용법:
#   ~/.claude/scripts/learning-morning-context.sh
#
# 의존:
#   - macOS date(BSD): date -v-1d
#   - learning-queue.md, learning-queue-blocked.log, Learning/YYYY-MM/

set -u

QUEUE_FILE="$HOME/Workspace/weaversbrain/weaversbrain/Learning/learning-queue.md"
BLOCKED_LOG="$HOME/.claude/cache/learning-queue-blocked.log"
LEARNING_DIR="$HOME/Workspace/weaversbrain/weaversbrain/Learning"

TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d)

# --- 측정 (조용히 실패 허용) ---

# grep -c 는 매치 0일 때 exit 1을 내며 "0"을 출력 — 안전 카운터로 통일
safe_count() {
    local pattern="$1"
    local file="$2"
    if [ ! -f "$file" ]; then
        echo 0
        return
    fi
    local n
    n=$(grep -c "$pattern" "$file" 2>/dev/null)
    [ -z "$n" ] && n=0
    echo "$n"
}

YESTERDAY_ADDED=$(safe_count "$YESTERDAY" "$QUEUE_FILE")
OPEN_COUNT=$(safe_count "^- \[ \]" "$QUEUE_FILE")
if [ -f "$QUEUE_FILE" ]; then
    OLDEST_OPEN=$(grep "^- \[ \]" "$QUEUE_FILE" 2>/dev/null | head -1)
else
    OLDEST_OPEN=""
fi

YESTERDAY_BLOCKED=$(safe_count "$YESTERDAY" "$BLOCKED_LOG")
TODAY_BLOCKED=$(safe_count "$TODAY" "$BLOCKED_LOG")

if [ -d "$LEARNING_DIR" ]; then
    NOTES_7D=$(find "$LEARNING_DIR" -type f -name "*.md" -mtime -7 -not -name "learning-queue*" 2>/dev/null | wc -l | tr -d ' ')
else
    NOTES_7D=0
fi

# --- 가장 오래된 미정리 경과일 계산 ---
OLDEST_DAYS=""
if [ -n "$OLDEST_OPEN" ]; then
    # 형식 예: "- [ ] **2026-05-09 14:22** ..."
    OLDEST_DATE=$(echo "$OLDEST_OPEN" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1)
    if [ -n "$OLDEST_DATE" ]; then
        OLDEST_EPOCH=$(date -j -f "%Y-%m-%d" "$OLDEST_DATE" "+%s" 2>/dev/null || echo "")
        TODAY_EPOCH=$(date "+%s")
        if [ -n "$OLDEST_EPOCH" ]; then
            OLDEST_DAYS=$(( (TODAY_EPOCH - OLDEST_EPOCH) / 86400 ))
        fi
    fi
fi

# --- 출력 ---
echo "📚 학습 컨텍스트 ($TODAY)"
echo "──────────────────────────────────────"
echo "  • 어제 큐 추가:    ${YESTERDAY_ADDED}건"
echo "  • 미정리 큐:       ${OPEN_COUNT}건"
if [ -n "$OLDEST_OPEN" ]; then
    OLDEST_PREVIEW=$(echo "$OLDEST_OPEN" | sed 's/^- \[ \] //' | cut -c1-60)
    if [ -n "$OLDEST_DAYS" ]; then
        echo "  • 가장 오래된:     ${OLDEST_DAYS}일 경과 — ${OLDEST_PREVIEW}..."
    else
        echo "  • 가장 오래된:     ${OLDEST_PREVIEW}..."
    fi
fi
echo "  • 어제 차단:       ${YESTERDAY_BLOCKED}건 (Hook 효과)"
echo "  • 오늘 차단:       ${TODAY_BLOCKED}건"
echo "  • 최근 7일 노트:   ${NOTES_7D}개"
echo ""

# --- 권고 ---
RECOMMENDATIONS=()
if [ "$OPEN_COUNT" -ge 5 ] 2>/dev/null; then
    RECOMMENDATIONS+=("미정리 ${OPEN_COUNT}건 — \`/deep-learn queue\` 권장")
fi
if [ -n "$OLDEST_DAYS" ] && [ "$OLDEST_DAYS" -gt 14 ] 2>/dev/null; then
    RECOMMENDATIONS+=("가장 오래된 항목 ${OLDEST_DAYS}일 경과 — 즉시 학습 또는 close")
fi

if [ ${#RECOMMENDATIONS[@]} -gt 0 ]; then
    echo "💡 권고"
    for rec in "${RECOMMENDATIONS[@]}"; do
        echo "  - $rec"
    done
fi

exit 0

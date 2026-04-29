#!/bin/zsh
# SessionStart hook: 일주일에 한 번 주간 회고 노트 생성
# 트리거: 매주 첫 세션 (월요일 또는 그 주 첫 세션 오픈)
# 출력: ~/.claude/cache/retro/YYYY-WW.md (ISO week)
# 데이터: qwen-cli stats --tail 7d + 최근 7일 세션 요약 cat
# 엔진: qwen-cli writer 페르소나 (qwen3.5:9b)
# 실패/서버다운/cli 미설치 시 즉시 스킵 (세션 시작 블로킹 없음)

: "${HOME:?}"

QWEN="$HOME/.local/bin/qwen-cli"
RETRO_DIR="$HOME/.claude/cache/retro"
SESSION_SUMMARY_DIR="$HOME/.claude/cache/session-summary"

# qwen-cli 미설치 시 즉시 스킵
[ -x "$QWEN" ] || exit 0

# 회사 LAN 외부에서 호출 시 즉시 skip (TCP 1초 캐시 5분)
source "$HOME/.claude/hooks/_lib/ollama-available.sh"
ollama_available || exit 0

mkdir -p "$RETRO_DIR"

# 1) 요일 체크 — 월요일(1)에만 자동 생성
#    추가로: 그 주 회고가 아직 없으면 그 주 첫 세션 오픈 시에도 생성 (사용자가 월요일에 안 쓸 수도)
DOW=$(date +%u)  # 1=Mon ... 7=Sun
YEAR_WEEK=$(date +%G-%V)  # ISO week (e.g., 2026-18)
OUTPUT_FILE="$RETRO_DIR/${YEAR_WEEK}.md"

# 2) 이번 주 회고 이미 있으면 스킵
if [ -f "$OUTPUT_FILE" ]; then
    exit 0
fi

# 월요일 아니면서 + 이번 주 회고도 없으면 → 그 주 첫 세션이라도 생성
# (즉, 둘 중 하나라도 만족하면 진행. 사실상 "그 주 회고 없으면 만든다"가 본질)
# DOW 별도 분기 필요 없음 — 위 체크가 이미 충분.
# 단 "월요일이 아니면 즉시 exit 0" 요구사항 반영을 위해
# 사용자 의도(둘 중 하나)에 맞춰: 월요일이거나 OR 그 주 첫 세션이면 진행
# 위 OUTPUT_FILE 부재 체크가 곧 "그 주 첫 세션" 판정이므로 이대로 진행

# 3) qwen-cli stats --tail 7d 실행 (실패해도 best-effort)
STATS_OUTPUT=$("$QWEN" stats --tail 7d 2>/dev/null)
STATS_EXIT=$?
if [ "$STATS_EXIT" -ne 0 ] || [ -z "$STATS_OUTPUT" ]; then
    STATS_OUTPUT="(qwen-cli stats 호출 실패 또는 출력 없음 — 세션 요약만으로 진행)"
fi

# 4) 최근 7일 mtime 세션 요약 파일 수집 (최대 30개)
SESSIONS_BODY=""
if [ -d "$SESSION_SUMMARY_DIR" ]; then
    # 최근 7일 내 mtime, 최신 정렬, 최대 30개
    SESSION_FILES=$(find "$SESSION_SUMMARY_DIR" -type f -name "*.md" -mtime -7 -print0 2>/dev/null \
        | xargs -0 ls -t 2>/dev/null \
        | head -30)

    if [ -n "$SESSION_FILES" ]; then
        # 본문 합치기. 각 파일 사이 구분선
        SESSIONS_BODY=$(echo "$SESSION_FILES" | while IFS= read -r f; do
            [ -f "$f" ] || continue
            echo "===== $(basename "$f") ====="
            cat "$f"
            echo ""
        done)
    fi
fi

# 5) 본문 너무 길면 (~50KB+) 가장 최근 10개만 다시 합치기
BODY_BYTES=$(printf '%s' "$SESSIONS_BODY" | wc -c | tr -d ' ')
if [ "${BODY_BYTES:-0}" -gt 50000 ] && [ -d "$SESSION_SUMMARY_DIR" ]; then
    SESSION_FILES=$(find "$SESSION_SUMMARY_DIR" -type f -name "*.md" -mtime -7 -print0 2>/dev/null \
        | xargs -0 ls -t 2>/dev/null \
        | head -10)
    SESSIONS_BODY=$(echo "$SESSION_FILES" | while IFS= read -r f; do
        [ -f "$f" ] || continue
        echo "===== $(basename "$f") ====="
        cat "$f"
        echo ""
    done)
fi

if [ -z "$SESSIONS_BODY" ]; then
    SESSIONS_BODY="(최근 7일 세션 요약 없음)"
fi

# 6) qwen-cli writer 페르소나로 회고 노트 생성
PROMPT=$(printf '다음은 지난 한 주간의 Claude Code 사용 통계와 세션 요약이다. 한국어로 주간 회고 노트를 작성해줘.\n\n출력 형식 (정확히 이 4개 섹션, 다른 섹션 추가 금지):\n\n## 이번 주 데이터\n<stats 출력에서 핵심 지표 3-5개 (호출 수, 토큰, 모델별 분포 등). 숫자 위주.>\n\n## 잘한 것\n- <근거 있는 성과 1>\n- <근거 있는 성과 2>\n- <근거 있는 성과 3>\n\n## 개선할 점\n- <반복된 비효율/실수 1>\n- <반복된 비효율/실수 2>\n\n## 다음 주 우선순위\n- <세션 요약에서 미완료/후속 조치로 언급된 것>\n- <상위 우선순위 작업>\n\n규칙:\n- 통계 + 세션 요약을 근거로만 작성. 추측 금지\n- 이모지/장식/인사말 금지\n- 위 4개 섹션 헤더 그대로 유지\n- 각 항목 짧게 (한 줄)\n\n[STATS]\n%s\n\n[SESSIONS]\n%s' "$STATS_OUTPUT" "$SESSIONS_BODY")

RESULT=$(echo "$PROMPT" | "$QWEN" -p - --profile writer --num-ctx 16384 2>/dev/null)
EXIT=$?

# qwen-cli 실패 시: 원재료라도 저장
if [ "$EXIT" -ne 0 ] || [ -z "$RESULT" ]; then
    {
        echo "# 주간 회고 원재료 (${YEAR_WEEK}) — qwen-cli 호출 실패"
        echo ""
        echo "생성: $(date +%Y-%m-%d\ %H:%M:%S)"
        echo ""
        echo "## stats"
        echo ""
        echo "$STATS_OUTPUT"
        echo ""
        echo "## sessions"
        echo ""
        echo "$SESSIONS_BODY"
    } > "$OUTPUT_FILE"
    echo "주간 회고 원재료 저장됨 (qwen-cli 실패): $OUTPUT_FILE"
    exit 0
fi

# 7) 결과 저장
{
    echo "# 주간 회고: ${YEAR_WEEK}"
    echo ""
    echo "생성: $(date +%Y-%m-%d\ %H:%M:%S)"
    echo "엔진: qwen-cli (writer / qwen3.5:9b)"
    echo ""
    echo "$RESULT"
    echo ""
    echo "---"
    echo ""
    echo "## 원재료 (stats)"
    echo ""
    echo '```'
    echo "$STATS_OUTPUT"
    echo '```'
} > "$OUTPUT_FILE"

# 8) SessionStart stdout — 한 줄 알림
echo "주간 회고 생성됨: $OUTPUT_FILE"

exit 0

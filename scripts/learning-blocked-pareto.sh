#!/bin/zsh
# 학습 큐 차단 로그 Pareto 리포트
# 사용: ~/.claude/scripts/learning-blocked-pareto.sh [N일]
#       기본 7일

DAYS="${1:-7}"
LOG="$HOME/.claude/cache/learning-queue-blocked.log"

if [ ! -f "$LOG" ]; then
    echo "차단 로그 없음: $LOG"
    exit 0
fi

CUTOFF=$(date -v-${DAYS}d +%Y-%m-%d 2>/dev/null || date -d "${DAYS} days ago" +%Y-%m-%d)

echo "=== 학습 큐 차단 로그 분석 (최근 ${DAYS}일) ==="
echo "기준일: ${CUTOFF} 이후"
echo ""

FILTERED=$(awk -v cutoff="$CUTOFF" '$1 >= cutoff' "$LOG")
TOTAL=$(echo "$FILTERED" | grep -c .)

if [ "$TOTAL" -eq 0 ]; then
    echo "차단 건수: 0"
    exit 0
fi

echo "총 차단 건수: $TOTAL"
echo ""

echo "── 사유별 분포 (Pareto) ──"
echo "$FILTERED" | grep -oE '\[[A-Z_]+\]' | sort | uniq -c | sort -rn | awk '{
    pct = ($1 / '"$TOTAL"') * 100
    bar = ""
    n = int(pct / 2)
    for (i = 0; i < n; i++) bar = bar "█"
    printf "  %-25s %4d  %5.1f%%  %s\n", $2, $1, pct, bar
}'

echo ""
echo "── 일별 추이 ──"
echo "$FILTERED" | awk '{print substr($1, 1, 10)}' | sort | uniq -c | awk '{
    bar = ""
    for (i = 0; i < $1; i++) bar = bar "▪"
    printf "  %s  %3d  %s\n", $2, $1, bar
}'

echo ""
echo "── 최근 5건 (샘플) ──"
echo "$FILTERED" | tail -5

echo ""
echo "── False Positive 후보 검출 ──"
echo "(영문 식별자 포함 + SHORT_FRAGMENT로 차단 = 정상 학습 질문일 가능성)"
FP=$(echo "$FILTERED" | grep "SHORT_FRAGMENT" | grep -E '[A-Za-z_]{4,}' | head -3)
if [ -z "$FP" ]; then
    echo "  검출 안 됨"
else
    echo "$FP" | sed 's/^/  /'
fi

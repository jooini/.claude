#!/bin/zsh
# 학습 큐 일일 스냅샷 — JSON으로 누적
# cron: 0 23 * * * ~/.claude/scripts/learning-queue-snapshot.sh
# 사용: ~/.claude/scripts/learning-queue-snapshot.sh [report]
#       (인자 없으면 스냅샷 추가, "report" 면 누적 리포트 출력)

QUEUE="$HOME/Workspace/weaversbrain/weaversbrain/Learning/learning-queue.md"
DATA="$HOME/.claude/cache/learning-queue-snapshots.jsonl"
mkdir -p "$(dirname "$DATA")"

if [ "$1" = "report" ]; then
    if [ ! -f "$DATA" ]; then
        echo "스냅샷 없음: $DATA"
        exit 0
    fi

    echo "=== 학습 큐 메트릭 추이 ==="
    echo ""
    echo "날짜         미정리  정리됨  노이즈율  처리량(전일대비)"
    echo "─────────────────────────────────────────────────────"

    awk -F',' 'BEGIN { prev_done = -1 }
    {
        gsub(/[{}"]/, "")
        date = ""; open = ""; done = ""; rate = ""
        for (i = 1; i <= NF; i++) {
            split($i, kv, ":")
            gsub(/^ +| +$/, "", kv[1])
            gsub(/^ +| +$/, "", kv[2])
            if (kv[1] == "date") date = kv[2]
            if (kv[1] == "open") open = kv[2]
            if (kv[1] == "done") done = kv[2]
            if (kv[1] == "noise_rate") rate = kv[2]
        }
        delta = (prev_done >= 0) ? (done - prev_done) : 0
        printf "  %s   %4s   %4s   %5s%%   %+d\n", date, open, done, rate, delta
        prev_done = done
    }' "$DATA"

    echo ""
    LAST=$(tail -1 "$DATA")
    echo "── 최신 스냅샷 ──"
    echo "$LAST"
    exit 0
fi

# 스냅샷 추가
if [ ! -f "$QUEUE" ]; then
    echo "큐 파일 없음: $QUEUE" >&2
    exit 1
fi

OPEN=$(grep -c "^- \[ \]" "$QUEUE" 2>/dev/null | tr -d ' ')
DONE=$(grep -c "^- \[x\]" "$QUEUE" 2>/dev/null | tr -d ' ')
TOTAL=$((OPEN + DONE))

if [ "$TOTAL" -eq 0 ]; then
    NOISE_RATE=0
else
    NOISE_RATE=$(echo "scale=1; $DONE * 100 / $TOTAL" | bc)
fi

# 가장 오래된 미정리 항목 날짜
OLDEST=$(grep "^- \[ \]" "$QUEUE" | grep -oE '\*\*[0-9]{4}-[0-9]{2}-[0-9]{2}' | sed 's/\*\*//' | sort | head -1)
[ -z "$OLDEST" ] && OLDEST="null"

DATE_NOW=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%Y-%m-%dT%H:%M:%S)

# 같은 날 스냅샷 있으면 갱신 (마지막 기록만 유지)
if [ -f "$DATA" ]; then
    grep -v "\"date\":\"${DATE_NOW}\"" "$DATA" > "$DATA.tmp" && mv "$DATA.tmp" "$DATA"
fi

if [ "$OLDEST" = "null" ]; then
    echo "{\"timestamp\":\"$TIMESTAMP\",\"date\":\"$DATE_NOW\",\"open\":$OPEN,\"done\":$DONE,\"total\":$TOTAL,\"noise_rate\":$NOISE_RATE,\"oldest_open\":null}" >> "$DATA"
else
    echo "{\"timestamp\":\"$TIMESTAMP\",\"date\":\"$DATE_NOW\",\"open\":$OPEN,\"done\":$DONE,\"total\":$TOTAL,\"noise_rate\":$NOISE_RATE,\"oldest_open\":\"$OLDEST\"}" >> "$DATA"
fi

echo "스냅샷 기록: open=$OPEN done=$DONE noise_rate=$NOISE_RATE%"

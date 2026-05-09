#!/bin/zsh
# Stop hook: 매 응답 종료 시 직전 턴에 발동된 훅의 요약 표시 (D안)
# 비용 목표: <100ms

: "${HOME:?}"

TIMING_DIR="$HOME/.claude/cache/hook-timing"
TODAY=$(date +%Y-%m-%d)
FILE="$TIMING_DIR/${TODAY}.tsv"
[ -f "$FILE" ] || exit 0

WINDOW_SEC="${TURN_SUMMARY_WINDOW:-30}"

# 1단계: 빠른 윈도우 컷 — 마지막 N분어치 라인만 추출
# date 한 번 호출로 윈도우 시작 시각의 ISO 문자열 생성
WINDOW_START_ISO=$(date -v-${WINDOW_SEC}S +"%Y-%m-%dT%H:%M:%S")

# tail로 가장 최근 라인부터 보면서 윈도우 시작 이전이면 끊기
# (전체 파일 스캔 회피)
tail -r "$FILE" 2>/dev/null | awk -F'\t' -v start="$WINDOW_START_ISO" -v win="$WINDOW_SEC" '
    BEGIN { count = 0; sum_ms = 0; max_ms = 0 }
    $1 == "timestamp" { next }
    {
        if ($1 < start) exit
        count++
        sum_ms += $3
        if ($3 + 0 > max_ms) { max_ms = $3 + 0; max_hook = $2 }
        seen[$2]++
    }
    END {
        if (count < 5) exit
        n = 0
        for (h in seen) { n++; arr_c[n] = seen[h]; arr_n[n] = h }
        max_show = 3
        if (n < max_show) max_show = n
        for (i = 1; i <= max_show; i++) {
            best = i
            for (j = i + 1; j <= n; j++) if (arr_c[j] > arr_c[best]) best = j
            if (best != i) {
                tc = arr_c[i]; arr_c[i] = arr_c[best]; arr_c[best] = tc
                tn = arr_n[i]; arr_n[i] = arr_n[best]; arr_n[best] = tn
            }
        }
        kinds = length(seen)
        printf "[turn-summary] 직전 %ds: 훅 %d회 / %d종류 / 총 %dms / 최대 %dms (%s)\n",
            win, count, kinds, sum_ms, max_ms, max_hook
        printf "  TOP:"
        for (i = 1; i <= max_show; i++) printf " %s(%d)", arr_n[i], arr_c[i]
        printf "\n"
    }
'

exit 0

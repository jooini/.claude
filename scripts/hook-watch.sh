#!/bin/zsh
# hook-watch — 훅 발동을 실시간 스트림으로 표시
#
# 사용법:
#   ~/.claude/scripts/hook-watch.sh           # 모든 훅 발동 라이브
#   ~/.claude/scripts/hook-watch.sh slow      # 평균 100ms+ 느린 것만
#   ~/.claude/scripts/hook-watch.sh blocked   # exit≠0만
#   ~/.claude/scripts/hook-watch.sh gemini    # 이름에 'gemini' 포함만
#
# 별도 터미널에서 띄워두면 Claude Code 사용 중 훅 발동이 실시간으로 흐름.

: "${HOME:?}"

TIMING_DIR="$HOME/.claude/cache/hook-timing"
TODAY=$(date +%Y-%m-%d)
FILE="$TIMING_DIR/${TODAY}.tsv"

MODE="${1:-all}"
FILTER=""

case "$MODE" in
    all)     FILTER='1' ;;
    slow)    FILTER='$3 >= 100' ;;
    blocked) FILTER='$4 != 0' ;;
    output)  FILTER='$7 == "output"' ;;
    *)       # 임의 패턴 — 훅 이름 부분 일치
             FILTER="\$2 ~ /$MODE/" ;;
esac

if [ ! -f "$FILE" ]; then
    echo "오늘자 데이터 없음: $FILE"
    echo "Claude Code에서 도구 호출이 한 번 이상 일어나야 데이터가 누적됩니다."
    exit 1
fi

# ANSI 색상
C_RESET='\033[0m'
C_DIM='\033[2m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_RED='\033[31m'
C_CYAN='\033[36m'
C_BOLD='\033[1m'

echo "${C_BOLD}=== hook-watch [${MODE}] $(date +%H:%M:%S) ===${C_RESET}"
echo "${C_DIM}파일: $FILE${C_RESET}"
echo "${C_DIM}컬럼: 시각  훅이름  소요(ms)  exit  사이드이펙트${C_RESET}"
echo "${C_DIM}Ctrl+C 종료. 자정 넘어가면 새 파일로 자동 전환됨 (재실행 필요).${C_RESET}"
echo ""

# tail -F: 파일 truncate/회전에도 버팀
tail -F -n 0 "$FILE" 2>/dev/null | awk -F'\t' -v filter="$FILTER" -v R="$C_RESET" -v D="$C_DIM" -v G="$C_GREEN" -v Y="$C_YELLOW" -v RD="$C_RED" -v CY="$C_CYAN" '
    BEGIN { OFS = "  " }
    NR == 1 && $1 == "timestamp" { next }  # 헤더 스킵
    {
        if (!('"$FILTER"')) next
        # 시각 (HH:MM:SS만)
        ts = substr($1, 12, 8)
        # 색상: duration_ms 기반
        col = G
        if ($3 + 0 >= 200) col = RD
        else if ($3 + 0 >= 100) col = Y
        # 사이드이펙트 색상
        side_col = D
        if ($7 == "output") side_col = CY
        if ($7 == "block_or_error") side_col = RD
        printf "%s%s%s  %s%-38s%s  %s%5dms%s  exit=%s  %s%s%s\n",
            D, ts, R,
            "", $2, R,
            col, $3+0, R,
            $4,
            side_col, $7, R
        fflush()
    }
'

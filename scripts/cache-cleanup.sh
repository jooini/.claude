#!/bin/zsh
# 오래된 캐시 파일 정리 — 디렉토리별 차등 TTL
# 회고/분석 데이터는 30일 보존, 일반 캐시는 7일
: "${HOME:?}"

CACHE_DIR="$HOME/.claude/cache"

if [ ! -d "$CACHE_DIR" ]; then
    exit 0
fi

# 30일 보존 (회고/라우팅 분석에 필요)
PRESERVE_30D=(
    "agent-routing-memo"
    "metrics"
    "pipeline-metrics-debug"
    "md-trace"
    "md-live/.suggestions"
)

for d in "${PRESERVE_30D[@]}"; do
    [ -d "$CACHE_DIR/$d" ] && find "$CACHE_DIR/$d" -type f -mtime +30 -delete 2>/dev/null
done

# 나머지: 7일 (PRESERVE_30D 디렉토리 제외)
# find -prune은 expression 그룹핑이 까다로워 zsh 호환성 이슈 → for 루프로 명시적 처리
TOP_DIRS=$(find "$CACHE_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
for top in $TOP_DIRS; do
    skip=false
    for d in "${PRESERVE_30D[@]}"; do
        case "$top" in
            "$CACHE_DIR/$d"|"$CACHE_DIR/${d%%/*}") skip=true; break ;;
        esac
    done
    [ "$skip" = true ] && continue
    find "$top" -type f -mtime +7 -delete 2>/dev/null
done
# CACHE_DIR 직속 파일은 7일 룰 적용
find "$CACHE_DIR" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null

# 빈 디렉토리 정리
find "$CACHE_DIR" -type d -empty -delete 2>/dev/null

echo "[캐시 정리] $(date +%Y-%m-%d) 완료 — 30일 보존: ${#PRESERVE_30D[@]}개 디렉토리"

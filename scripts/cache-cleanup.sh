#!/bin/zsh
# 오래된 캐시 파일 정리 (7일 이상)
: "${HOME:?}"

CACHE_DIR="$HOME/.claude/cache"

if [ ! -d "$CACHE_DIR" ]; then
    exit 0
fi

# 7일 이상된 파일 삭제
find "$CACHE_DIR" -type f -mtime +7 -delete 2>/dev/null

# 빈 디렉토리 정리
find "$CACHE_DIR" -type d -empty -delete 2>/dev/null

echo "[캐시 정리] $(date +%Y-%m-%d) 완료"

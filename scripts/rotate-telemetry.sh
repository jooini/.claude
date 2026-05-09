#!/bin/zsh
# Telemetry 로그 자동 로테이션
#
# - gemini-telemetry.jsonl 50MB 초과 시 자동 archive + gzip
# - 90일 이상 archive 자동 삭제
#
# 호출 권장:
#   - cron 또는 launchd 일일 1회 (매일 새벽)
#   - 또는 Stop hook 에 추가 (응답 끝 비동기)

: "${HOME:?}"

TELEMETRY="$HOME/.claude/cache/gemini-telemetry.jsonl"
ARCHIVE_DIR="$HOME/.claude/cache/telemetry-archive"
SIZE_THRESHOLD_MB="${TELEMETRY_ROTATE_MB:-50}"
RETENTION_DAYS="${TELEMETRY_RETENTION_DAYS:-90}"

mkdir -p "$ARCHIVE_DIR"

# 1) 크기 체크 후 로테이션
if [ -f "$TELEMETRY" ]; then
    SIZE_MB=$(/usr/bin/stat -f %z "$TELEMETRY" 2>/dev/null | awk '{print int($1/1048576)}')
    if [ "${SIZE_MB:-0}" -ge "$SIZE_THRESHOLD_MB" ]; then
        ARCHIVE_FILE="$ARCHIVE_DIR/gemini-telemetry-$(date +%Y%m%d-%H%M).jsonl"
        mv "$TELEMETRY" "$ARCHIVE_FILE"
        /usr/bin/gzip "$ARCHIVE_FILE"
        touch "$TELEMETRY"
        echo "[rotate-telemetry] ${SIZE_MB}MB → archived: ${ARCHIVE_FILE}.gz"
    fi
fi

# 2) 90일 이상 archive 삭제
/usr/bin/find "$ARCHIVE_DIR" -name "*.gz" -mtime +${RETENTION_DAYS} -delete 2>/dev/null

exit 0

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

# 3) md-live 일별 파일 90일 retention
#    - 일별/툴별/에이전트별 jsonl 90일 초과 시 archive 디렉토리로 gzip 이동
#    - turns.jsonl, agent-reads.jsonl 등 단일 누적 파일은 건드리지 않음
MD_LIVE_DIR="$HOME/.claude/cache/md-live"
MD_LIVE_ARCHIVE="$MD_LIVE_DIR/archive"
MD_LIVE_RETENTION_DAYS="${MD_LIVE_RETENTION_DAYS:-90}"

if [ -d "$MD_LIVE_DIR" ]; then
    mkdir -p "$MD_LIVE_ARCHIVE"
    # 일별 분할 패턴: YYYY-MM-DD.jsonl, tool-trace-YYYY-MM-DD.jsonl, agent-trace-YYYY-MM-DD.jsonl
    /usr/bin/find "$MD_LIVE_DIR" -maxdepth 1 -type f \
        \( -name "????-??-??.jsonl" -o -name "tool-trace-????-??-??.jsonl" -o -name "agent-trace-????-??-??.jsonl" \) \
        -mtime +${MD_LIVE_RETENTION_DAYS} -print 2>/dev/null | while read -r daily_file; do
        base=$(basename "$daily_file")
        /usr/bin/gzip -c "$daily_file" > "$MD_LIVE_ARCHIVE/${base}.gz" && rm -f "$daily_file"
        echo "[rotate-telemetry] md-live archived: $base.gz"
    done
    # archive 자체도 RETENTION_DAYS*4 (1년) 후 삭제
    /usr/bin/find "$MD_LIVE_ARCHIVE" -name "*.gz" -mtime +$((MD_LIVE_RETENTION_DAYS * 4)) -delete 2>/dev/null
fi

# 4) dashboard 로그 위생 (launchd append 모드 누적 대응)
#    - dashboard.err / dashboard.log 100KB 초과 시 archive 로 옮기고 in-place truncate
#    - launchd 가 append fd 를 잡고 있어 mv 하면 새 파일이 생성 안 됨 → cp + ': > file' 패턴
DASHBOARD_LOG_DIR="$HOME/.claude/cache"
DASHBOARD_ARCHIVE="$DASHBOARD_LOG_DIR/dashboard-archive"
DASHBOARD_THRESHOLD_KB="${DASHBOARD_LOG_KB:-100}"
DASHBOARD_RETENTION_DAYS="${DASHBOARD_LOG_RETENTION_DAYS:-30}"

mkdir -p "$DASHBOARD_ARCHIVE"
for log_name in dashboard.err dashboard.log; do
    log_path="$DASHBOARD_LOG_DIR/$log_name"
    [ -f "$log_path" ] || continue
    SIZE_KB=$(/usr/bin/stat -f %z "$log_path" 2>/dev/null | awk '{print int($1/1024)}')
    if [ "${SIZE_KB:-0}" -ge "$DASHBOARD_THRESHOLD_KB" ]; then
        ts=$(date +%Y%m%d-%H%M)
        archive_file="$DASHBOARD_ARCHIVE/${log_name}-${ts}"
        /bin/cp "$log_path" "$archive_file" && /usr/bin/gzip "$archive_file"
        : > "$log_path"
        echo "[rotate-telemetry] dashboard ${log_name} ${SIZE_KB}KB → archived: ${archive_file}.gz (truncated in place)"
    fi
done
/usr/bin/find "$DASHBOARD_ARCHIVE" -name "*.gz" -mtime +${DASHBOARD_RETENTION_DAYS} -delete 2>/dev/null

exit 0

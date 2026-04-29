#!/bin/zsh
# 매일 오전 9시 cron — 자동 헬스 리포트 + 주간 triage 갱신
# launchctl 또는 crontab으로 스케줄링
#
# 설치:
#   crontab -e
#   0 9 * * * /bin/zsh /Users/leonard/.claude/scripts/gemma-cron-daily.sh
#
# 또는 launchd plist 별도 제공 (gemma-cron.plist)

: "${HOME:?}"
LOG="$HOME/.claude/cache/gemma-cron.log"
mkdir -p "$(dirname "$LOG")"

log() {
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $1" >> "$LOG"
}

log "=== cron 일일 실행 시작 ==="

# 환경변수 로드 (cron은 minimal env)
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.nvm/versions/node/v22.22.0/bin"
export HOME="${HOME:-/Users/leonard}"

# Ollama 연결 확인
if ! curl -s --max-time 3 "http://${OLLAMA_HOST_LAN:-leonard.local:11434}/api/tags" >/dev/null 2>&1; then
    log "Ollama 접근 불가 — 스킵"
    exit 0
fi

# 1. 어제 헬스 리포트 생성 (어제 날짜로)
YESTERDAY=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d "1 day ago" +%Y-%m-%d)
log "1/3 어제(${YESTERDAY}) 헬스 리포트 생성..."
python3 "$HOME/.claude/scripts/gemma-health-report.py" "$YESTERDAY" >> "$LOG" 2>&1
log "   완료"

# 2. 월요일이면 triage 재생성 (주간 대청소용)
DOW=$(date +%u)
if [ "$DOW" = "1" ]; then
    log "2/3 월요일 — triage 재생성"
    TRIAGE_TOP=30 python3 "$HOME/.claude/scripts/gemma-triage-dirty.py" >> "$LOG" 2>&1
    log "   완료"
else
    log "2/3 triage 스킵 (월요일 아님)"
fi

# 3. Obsidian Projects/gemma/ 로 결과물 이관 (어제 날짜)
log "3/4 Obsidian 이관 (어제 ${YESTERDAY})..."
VAULT="$HOME/Workspace/weaversbrain/weaversbrain"
GEMMA_DIR="$VAULT/Projects/gemma/$YESTERDAY"
if [ -d "$VAULT" ]; then
    mkdir -p "$GEMMA_DIR"
    for src in \
        "$HOME/.claude/cache/health-report/${YESTERDAY}.md:health-report.md" \
        "$HOME/.claude/cache/daily-draft/${YESTERDAY}.md:daily-draft.md" \
        "$HOME/.claude/cache/morning-brief/${YESTERDAY}.md:morning-brief.md" \
        "$HOME/.claude/cache/triage-dirty/${YESTERDAY}.md:triage-dirty.md"; do
        SRC_PATH="${src%%:*}"
        DST_NAME="${src##*:}"
        if [ -f "$SRC_PATH" ]; then
            /bin/cp "$SRC_PATH" "$GEMMA_DIR/$DST_NAME"
            log "   ✅ $DST_NAME"
        fi
    done
else
    log "   ⚠️ Vault 없음 — 이관 스킵"
fi

# 4. 오래된 캐시 정리 (30일 이상)
log "4/4 오래된 캐시 정리..."
find "$HOME/.claude/cache/health-report" -name "*.md" -mtime +30 -delete 2>/dev/null
find "$HOME/.claude/cache/morning-brief" -name "*.md" -mtime +14 -delete 2>/dev/null
find "$HOME/.claude/cache/session-summary" -name "*.md" -mtime +30 -delete 2>/dev/null
log "   완료"

log "=== cron 종료 ==="

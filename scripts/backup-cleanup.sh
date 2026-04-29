#!/bin/zsh
# 백업 파일 자동 정리 (30일 이상)
#
# 대상:
#   1. ~/Workspace/*/.claude/agents/*.md.bak* (프로젝트 dev.md/docs.md 백업)
#   2. ~/.claude/CLAUDE.md.bak* (글로벌 CLAUDE.md 백업)
#   3. ~/.claude/settings.json.bak* (글로벌 settings.json 백업)
#   4. ~/.claude/backups/ (구 백업 디렉토리)
#   5. ~/.claude/file-history/ (30일+ 파일 히스토리)
#
# 실행: 매주 월요일 또는 cron 등록
#
# 안전:
#   - 30일 이상만 삭제
#   - 가장 최근 백업 1개는 보존 (각 카테고리별)
#   - dry-run 모드 지원 (--dry-run)

: "${HOME:?}"

DRY_RUN=0
[ "$1" = "--dry-run" ] && DRY_RUN=1

LOG="$HOME/.claude/cache/backup-cleanup.log"
mkdir -p "$(dirname "$LOG")"

log_msg() {
    echo "[$(date +%Y-%m-%d_%H:%M)] $*" | tee -a "$LOG"
}

run_cmd() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[DRY-RUN] $*"
    else
        eval "$*"
    fi
}

log_msg "=== backup-cleanup 시작 (DRY_RUN=$DRY_RUN) ==="

# 1. dev.md / docs.md 백업 정리 (30일+, 카테고리별 최신 1개 보존)
# .claude/agents/*.md.bak* 만 대상 (node_modules, vendor 등 제외)
log_msg "[1] 프로젝트 .claude/agents/*.md.bak 정리"
DEV_BAK_OLD=$(/usr/bin/find $HOME/Workspace -maxdepth 5 -path "*/.claude/agents/*.md.bak*" -mtime +30 2>/dev/null)
DEV_BAK_COUNT=$(echo "$DEV_BAK_OLD" | grep -c . 2>/dev/null || echo 0)
log_msg "  대상: ${DEV_BAK_COUNT}개"

if [ -n "$DEV_BAK_OLD" ] && [ "$DEV_BAK_COUNT" -gt 0 ]; then
    echo "$DEV_BAK_OLD" | while IFS= read -r f; do
        [ -z "$f" ] && continue
        run_cmd "/bin/rm '$f'"
    done
fi

# 2. ~/.claude/CLAUDE.md.bak* 정리 (30일+, 최신 3개 보존)
log_msg "[2] CLAUDE.md.bak 정리"
CLAUDE_BAKS=$(/bin/ls -t $HOME/.claude/CLAUDE.md.bak* 2>/dev/null | tail -n +4)
if [ -n "$CLAUDE_BAKS" ]; then
    echo "$CLAUDE_BAKS" | while IFS= read -r f; do
        [ -z "$f" ] && continue
        # 30일 이상된 것만
        if /usr/bin/find "$f" -mtime +30 2>/dev/null | grep -q .; then
            run_cmd "/bin/rm '$f'"
            log_msg "  삭제: $(basename "$f")"
        fi
    done
fi

# 3. ~/.claude/settings.json.bak* 정리 (30일+, 최신 3개 보존)
log_msg "[3] settings.json.bak 정리"
SETTINGS_BAKS=$(/bin/ls -t $HOME/.claude/settings.json.bak* 2>/dev/null | tail -n +4)
if [ -n "$SETTINGS_BAKS" ]; then
    echo "$SETTINGS_BAKS" | while IFS= read -r f; do
        [ -z "$f" ] && continue
        if /usr/bin/find "$f" -mtime +30 2>/dev/null | grep -q .; then
            run_cmd "/bin/rm '$f'"
            log_msg "  삭제: $(basename "$f")"
        fi
    done
fi

# 4. ~/.claude/backups/ 디렉토리 (30일+ 파일)
log_msg "[4] ~/.claude/backups/ 정리"
if [ -d "$HOME/.claude/backups" ]; then
    BACKUPS_OLD=$(/usr/bin/find $HOME/.claude/backups -type f -mtime +30 2>/dev/null | wc -l | tr -d ' ')
    log_msg "  대상: ${BACKUPS_OLD}개"
    run_cmd "/usr/bin/find $HOME/.claude/backups -type f -mtime +30 -delete 2>/dev/null"
    run_cmd "/usr/bin/find $HOME/.claude/backups -type d -empty -delete 2>/dev/null"
fi

# 5. ~/.claude/file-history (30일+)
log_msg "[5] ~/.claude/file-history 정리"
if [ -d "$HOME/.claude/file-history" ]; then
    FH_OLD=$(/usr/bin/find $HOME/.claude/file-history -type f -mtime +30 2>/dev/null | wc -l | tr -d ' ')
    log_msg "  대상: ${FH_OLD}개"
    run_cmd "/usr/bin/find $HOME/.claude/file-history -type f -mtime +30 -delete 2>/dev/null"
    run_cmd "/usr/bin/find $HOME/.claude/file-history -type d -empty -delete 2>/dev/null"
fi

# 6. 결과 요약
log_msg "=== 디스크 사용량 ==="
log_msg "  ~/.claude/cache:        $(/usr/bin/du -sh $HOME/.claude/cache 2>/dev/null | cut -f1)"
log_msg "  ~/.claude/backups:      $(/usr/bin/du -sh $HOME/.claude/backups 2>/dev/null | cut -f1)"
log_msg "  ~/.claude/file-history: $(/usr/bin/du -sh $HOME/.claude/file-history 2>/dev/null | cut -f1)"

log_msg "=== backup-cleanup 종료 ==="

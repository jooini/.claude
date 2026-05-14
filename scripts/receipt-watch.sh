#!/bin/zsh
# receipt-watch — ~/Documents/Receipts/inbox 폴더 감시
# 새 영수증 이미지 감지 시:
#   1. macOS 알림 표시
#   2. ~/.claude/cache/receipt-queue.jsonl 에 큐 추가
#   3. 사용자가 다음 Claude 세션에서 /receipt-report 호출하면 큐를 비우고 OCR
#
# launchd로 5분마다 실행 (또는 cron)

set -euo pipefail

INBOX="$HOME/Documents/Receipts/inbox"
QUEUE="$HOME/.claude/cache/receipt-queue.jsonl"
SEEN="$HOME/.claude/cache/receipt-seen.txt"

[ ! -d "$INBOX" ] && exit 0
mkdir -p "$(dirname "$QUEUE")"
touch "$SEEN" "$QUEUE"

new_count=0
for f in "$INBOX"/*.{jpg,jpeg,png,heic,JPG,JPEG,PNG,HEIC}(N); do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    if grep -qxF "$name" "$SEEN"; then
        continue
    fi
    echo "$name" >> "$SEEN"
    size=$(stat -f%z "$f" 2>/dev/null || echo 0)
    mtime=$(stat -f%m "$f" 2>/dev/null || echo 0)
    iso=$(date -r "$mtime" -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
    printf '{"file":"%s","path":"%s","size":%s,"detected":"%s","status":"queued"}\n' \
        "$name" "$f" "$size" "$iso" >> "$QUEUE"
    new_count=$((new_count + 1))
done

if [ "$new_count" -gt 0 ]; then
    osascript -e "display notification \"$new_count 개 영수증 큐 추가됨. /receipt-process 로 처리\" with title \"📸 Receipt Watch\"" 2>/dev/null || true
    echo "[$(date +%H:%M)] queued $new_count receipts" >> "$HOME/.claude/cache/receipt-watch.log"
fi

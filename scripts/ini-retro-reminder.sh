#!/bin/zsh
# 1주 후 (2026-05-07) ini 활용도 회고 알림
# 실행 후 자기 자신을 cron에서 제거 (1회성)

TARGET="2026-05-07"
TODAY=$(date +%Y-%m-%d)

if [ "$TODAY" != "$TARGET" ]; then
    exit 0
fi

# macOS 알림센터로 발송
osascript -e 'display notification "ini 활용도 측정 시점 — Claude Code에서 /retro 7 실행 권장" with title "📊 ini 회고" sound name "Glass"'

# 데일리 노트에 TODO 추가 (Obsidian Vault)
VAULT="$HOME/Workspace/weaversbrain/weaversbrain"
DAILY="$VAULT/Daily/$TODAY.md"
if [ -d "$VAULT/Daily" ]; then
    mkdir -p "$VAULT/Daily"
    echo "- [ ] 📊 ini 활용도 회고 — Claude Code에서 \`/retro 7\` 실행 (keep-alive 적용 후 1주 측정)" >> "$DAILY"
fi

# 자기 자신 cron 제거 (1회성)
crontab -l 2>/dev/null | grep -v "ini-retro-reminder.sh" | crontab -

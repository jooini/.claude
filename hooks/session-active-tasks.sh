#!/bin/bash
# 세션 시작 시 미완료 active + 백로그 현황 한 줄 표시 (v2 스키마 대응)
# v2: docs/backlog.md 표에서 status!=done 카운트
# v1 폴백: `- [ ]` 체크박스 카운트

BASE="$HOME/Workspace"
PROJECTS=(
  "identity-hub" "maxai-b2c-backend" "identity-keycloak"
  "speakingmax-backend" "identity-hub-frontend" "identity-hub-python-sdk"
  "keycloak-kakao-social-provider" "sso-fallback-monitor"
  "member-api" "wb-platform-backend" "ai-agentic-workflow"
  "maxai-docker" "identity-platform-docker"
)

ACTIVE_COUNT=0
BACKLOG_TOTAL=0

for proj in "${PROJECTS[@]}"; do
  ACTIVE_DIR="$BASE/$proj/docs/active"
  BACKLOG="$BASE/$proj/docs/backlog.md"

  if [ -d "$ACTIVE_DIR" ]; then
    AC=$(/usr/bin/find "$ACTIVE_DIR" -name "*.md" -not -name ".gitkeep" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')
    ACTIVE_COUNT=$((ACTIVE_COUNT + AC))
  fi

  if [ ! -f "$BACKLOG" ]; then
    continue
  fi

  if /usr/bin/grep -q "<!-- schema: v2 -->" "$BACKLOG"; then
    COUNT=$(/usr/bin/awk -F'|' '
      /^\| ID \|/ { header=1; next }
      header && /^\|/ && !/^\|-/ {
        s=$6; gsub(/^ +| +$/,"",s)
        if (s != "" && s != "done") n++
      }
      END { print n+0 }
    ' "$BACKLOG" 2>/dev/null)
  else
    COUNT=$(/usr/bin/grep -c '^- \[ \]' "$BACKLOG" 2>/dev/null || echo 0)
  fi
  COUNT=${COUNT:-0}
  BACKLOG_TOTAL=$((BACKLOG_TOTAL + COUNT))
done

if [ "$ACTIVE_COUNT" -gt 0 ] || [ "$BACKLOG_TOTAL" -gt 0 ]; then
  echo "[태스크 현황] 진행중: ${ACTIVE_COUNT}건 | 백로그: ${BACKLOG_TOTAL}건. /backlog 로 상세."
fi

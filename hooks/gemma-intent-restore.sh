#!/bin/zsh
# SessionStart hook: 현재 프로젝트의 가장 최근 의도 파일 출력
# gemma-morning-brief와 다름: 특정 프로젝트의 "이어서 할 일"에 집중

: "${HOME:?}"

INTENT_DIR="$HOME/.claude/intent"

# 현재 작업 디렉토리에서 프로젝트 추정
CWD=$(pwd 2>/dev/null)
PROJECT=""

# ~/Workspace/PROJECTNAME/ 패턴 매칭
if [[ "$CWD" == "$HOME/Workspace/"* ]]; then
    PROJECT=$(echo "$CWD" | /usr/bin/sed "s|$HOME/Workspace/||" | /usr/bin/cut -d/ -f1)
elif [[ "$CWD" == "$HOME" ]] || [[ "$CWD" == "$HOME/.claude" ]]; then
    PROJECT="general"
fi

if [ -z "$PROJECT" ]; then
    exit 0
fi

# 해당 프로젝트의 latest 의도
LATEST="$INTENT_DIR/$PROJECT/latest.md"

if [ ! -f "$LATEST" ]; then
    exit 0
fi

# 파일 나이 계산
AGE_SEC=$(( $(date +%s) - $(stat -f %m "$LATEST" 2>/dev/null || echo 0) ))
AGE_HOUR=$((AGE_SEC / 3600))
AGE_DAY=$((AGE_HOUR / 24))

# Stale 가드:
#   - general 버킷은 홈 디렉토리의 여러 주제가 섞이므로 6시간 이상이면 스킵
#   - 일반 프로젝트 버킷은 24시간 이상이면 스킵
AGE_HOUR_TOTAL=$((AGE_SEC / 3600))
if [ "$PROJECT" = "general" ]; then
    if [ "$AGE_HOUR_TOTAL" -ge 6 ]; then
        exit 0
    fi
else
    if [ "$AGE_HOUR_TOTAL" -ge 24 ]; then
        exit 0
    fi
fi

if [ "$AGE_DAY" -gt 0 ]; then
    AGE_STR="${AGE_DAY}일 전"
elif [ "$AGE_HOUR" -gt 0 ]; then
    AGE_STR="${AGE_HOUR}시간 전"
else
    AGE_MIN=$((AGE_SEC / 60))
    AGE_STR="${AGE_MIN}분 전"
fi

# 출력 — "마지막 목표 / 다음 작업 / 주의점" 3줄만 추출
INTENT_CONTENT=$(/usr/bin/awk '
    /^마지막 목표:/ { print }
    /^다음 작업:/ { print }
    /^주의점:/ { print }
' "$LATEST" 2>/dev/null)

if [ -z "$INTENT_CONTENT" ]; then
    exit 0
fi

echo "=== [이전 세션 의도 — $PROJECT / $AGE_STR] ==="
echo "$INTENT_CONTENT"
echo ""
echo "(전체: cat $LATEST)"
exit 0

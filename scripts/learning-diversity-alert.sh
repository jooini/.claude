#!/bin/zsh
# 학습 도메인 편식 알람 — 진단 결과를 오늘자 Daily 노트에 append
# 사용: ~/.claude/scripts/learning-diversity-alert.sh
# cron 예: 0 9 * * 1 ~/.claude/scripts/learning-diversity-alert.sh

set -e

DIAG_SCRIPT="$HOME/.claude/scripts/learning-diversity-check.sh"
VAULT="$HOME/Workspace/weaversbrain/weaversbrain"
TODAY=$(date +%Y-%m-%d)
MONTH=$(date +%Y-%m)
DAILY_DIR="$VAULT/Daily/$MONTH"
DAILY_FILE="$DAILY_DIR/$TODAY.md"
SECTION_HEADER="## 학습 편식 알람 (자동 생성)"

if [ ! -x "$DIAG_SCRIPT" ]; then
    echo "진단 스크립트 없음/실행 불가: $DIAG_SCRIPT" >&2
    exit 1
fi

# Daily 노트 폴더 보장
mkdir -p "$DAILY_DIR"

# Daily 노트 없으면 frontmatter 만 갖춘 빈 파일 생성
if [ ! -f "$DAILY_FILE" ]; then
    cat > "$DAILY_FILE" <<EOF
---
title: $TODAY 일일 보고서
date: $TODAY
type: daily
tags: [daily]
---

# $TODAY

EOF
fi

# 같은 날 알람 이미 추가됐으면 스킵 (중복 방지)
if grep -qF "$SECTION_HEADER" "$DAILY_FILE"; then
    echo "이미 알람 추가됨, 스킵: $DAILY_FILE"
    exit 0
fi

# 진단 실행 (table 모드 출력만 사용)
TABLE_OUT=$("$DIAG_SCRIPT" table)

# JSON 으로 zero/stale 도메인 추출 → 헤드라인
JSON_OUT=$("$DIAG_SCRIPT" json)
ZERO_LIST=$(echo "$JSON_OUT" | jq -r '.zero_domains | join(", ")')
ZERO_COUNT=$(echo "$JSON_OUT" | jq -r '.zero_domains | length')
STALE_COUNT=$(echo "$JSON_OUT" | jq -r '.stale_domains | length')
STALE_LINES=$(echo "$JSON_OUT" | jq -r '.stale_domains[] | "- \(.domain) — 마지막 \(.last_date) (\(.days_since)일 경과)"')

# 헤드라인 결정
if [ "$ZERO_COUNT" -eq 0 ] && [ "$STALE_COUNT" -eq 0 ]; then
    HEADLINE="✅ 학습 편식 없음 — 모든 도메인 30일 이내 학습"
else
    PARTS=()
    [ "$ZERO_COUNT" -gt 0 ] && PARTS+=("0개 도메인 ${ZERO_COUNT}개")
    [ "$STALE_COUNT" -gt 0 ] && PARTS+=("30일+ 미학습 ${STALE_COUNT}개")
    HEADLINE="⚠️ 학습 편식 감지 — $(IFS=", "; echo "${PARTS[*]}")"
fi

# Daily 노트에 append
{
    echo ""
    echo "$SECTION_HEADER"
    echo ""
    echo "$HEADLINE"
    echo ""
    if [ "$ZERO_COUNT" -gt 0 ]; then
        echo "**노트 0개 도메인**: $ZERO_LIST"
        echo ""
    fi
    if [ "$STALE_COUNT" -gt 0 ]; then
        echo "**30일 이상 미학습 도메인**:"
        echo "$STALE_LINES"
        echo ""
    fi
    echo "<details>"
    echo "<summary>전체 도메인 분포 (펼치기)</summary>"
    echo ""
    echo '```'
    echo "$TABLE_OUT"
    echo '```'
    echo ""
    echo "</details>"
    echo ""
    echo "_생성: $(date +%Y-%m-%dT%H:%M:%S) by learning-diversity-alert.sh_"
} >> "$DAILY_FILE"

echo "알람 추가 완료: $DAILY_FILE"
echo "$HEADLINE"

#!/bin/zsh
# asset-debt.sh — 자산 라이프사이클 부채 리포트 (주간 cron 권장)
#
# 측정:
#   - 30일+ 미사용/미수정 스킬/훅 → retire 후보
#   - 90일+ 미수정 knowledge 파일 → archive 후보 (자동 삭제 절대 금지)
#   - stale 문서 — Sessions/Plans/Projects 중 같은 토픽 중복 후보
#
# 출력: ~/.claude/cache/asset-debt-{YYYY-MM-DD}.md
# 자동 삭제 없음. 사용자가 검토 후 결정.

set -e

: "${HOME:?}"

TODAY=$(date +%Y-%m-%d)
REPORT="$HOME/.claude/cache/asset-debt-${TODAY}.md"
SKILL_DIR="$HOME/.claude/skills"
HOOK_DIR="$HOME/.claude/hooks"
KNOWLEDGE_DIR="$HOME/.claude/knowledge"
VAULT="$HOME/Workspace/weaversbrain/weaversbrain"

THRESHOLD_HOOK_DAYS=30
THRESHOLD_SKILL_DAYS=30
THRESHOLD_KNOWLEDGE_DAYS=90

mkdir -p "$(dirname "$REPORT")"

{
    echo "# 자산 부채 리포트 — $TODAY"
    echo ""
    echo "_자동 생성. 자동 삭제 없음. 사용자 검토 후 결정._"
    echo ""

    echo "## 1. 30일+ 미수정 훅 (retire 후보)"
    echo ""
    echo "| 파일 | 마지막 수정 | 경과일 |"
    echo "|---|---|---:|"
    if [ -d "$HOOK_DIR" ]; then
        find "$HOOK_DIR" -maxdepth 1 -type f -name "*.sh" -mtime "+${THRESHOLD_HOOK_DAYS}" 2>/dev/null \
        | while read -r f; do
            name=$(basename "$f")
            mtime=$(stat -f "%Sm" -t "%Y-%m-%d" "$f" 2>/dev/null || stat -c "%y" "$f" 2>/dev/null | cut -d' ' -f1)
            now_s=$(date +%s)
            file_s=$(stat -f "%m" "$f" 2>/dev/null || stat -c "%Y" "$f" 2>/dev/null)
            days=$(( (now_s - file_s) / 86400 ))
            echo "| \`$name\` | $mtime | ${days}d |"
        done
    fi
    echo ""

    echo "## 2. 30일+ 미수정 스킬 (retire 후보)"
    echo ""
    echo "| 스킬 | 마지막 수정 | 경과일 |"
    echo "|---|---|---:|"
    if [ -d "$SKILL_DIR" ]; then
        for skill in "$SKILL_DIR"/*/; do
            [ -d "$skill" ] || continue
            skill_md="${skill}SKILL.md"
            [ -f "$skill_md" ] || continue
            now_s=$(date +%s)
            file_s=$(stat -f "%m" "$skill_md" 2>/dev/null || stat -c "%Y" "$skill_md" 2>/dev/null)
            days=$(( (now_s - file_s) / 86400 ))
            if [ "$days" -gt "$THRESHOLD_SKILL_DAYS" ]; then
                mtime=$(stat -f "%Sm" -t "%Y-%m-%d" "$skill_md" 2>/dev/null || stat -c "%y" "$skill_md" | cut -d' ' -f1)
                name=$(basename "$skill")
                echo "| \`$name\` | $mtime | ${days}d |"
            fi
        done
    fi
    echo ""

    echo "## 3. 90일+ 미수정 knowledge (archive 후보 — 사용자 승인 필수)"
    echo ""
    if [ -d "$KNOWLEDGE_DIR" ]; then
        STALE_KB=$(find "$KNOWLEDGE_DIR" -type f -name "*.md" -mtime "+${THRESHOLD_KNOWLEDGE_DAYS}" 2>/dev/null | wc -l | tr -d ' ')
        echo "총 ${STALE_KB}개 파일이 ${THRESHOLD_KNOWLEDGE_DAYS}일+ 미수정."
        echo ""
        echo "(파일 목록은 길어서 생략. 필요 시: \`find $KNOWLEDGE_DIR -type f -name '*.md' -mtime +${THRESHOLD_KNOWLEDGE_DAYS}\`)"
    fi
    echo ""

    echo "## 4. 자산 흐름 요약 (지난 7일)"
    echo ""
    NEW_SKILLS=$(find "$SKILL_DIR" -maxdepth 2 -type d -mtime -7 2>/dev/null | grep -cv "^$SKILL_DIR$" || echo 0)
    NEW_HOOKS=$(find "$HOOK_DIR" -maxdepth 1 -type f -name "*.sh" -mtime -7 2>/dev/null | wc -l | tr -d ' ')
    RETIRED=0
    if [ -d "$HOOK_DIR/_disabled" ]; then
        RETIRED=$(find "$HOOK_DIR/_disabled" -maxdepth 1 -type f -mtime -7 2>/dev/null | wc -l | tr -d ' ')
    fi
    echo "| 항목 | 7일 전→현재 |"
    echo "|---|---:|"
    echo "| 신규 스킬 | $NEW_SKILLS |"
    echo "| 신규/수정 훅 | $NEW_HOOKS |"
    echo "| retire | $RETIRED |"
    BALANCE=$((NEW_SKILLS + NEW_HOOKS - RETIRED))
    echo "| 순증 | $BALANCE |"
    echo ""
    if [ "$BALANCE" -gt 5 ] && [ "$RETIRED" -eq 0 ]; then
        echo "⚠️ **불균형 경고** — 일주일간 ${BALANCE}건 신규, retire 0건. 라이프사이클 미작동."
    fi
    echo ""

    echo "## 5. 권장 액션"
    echo ""
    echo "1. 위 retire 후보 중 실제로 안 쓰는 것: \`mv ~/.claude/hooks/{이름}.sh ~/.claude/hooks/_disabled/\`"
    echo "2. knowledge archive 결정은 **반드시 사용자가 직접**. Claude 자동 처리 금지."
    echo "3. 다음 주 같은 시간에 다시 측정. 경향 추적."

} > "$REPORT"

echo "리포트: $REPORT"
echo ""
head -50 "$REPORT"

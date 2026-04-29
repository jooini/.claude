#!/bin/zsh
# PostToolUse(Edit|Write): 작업목록 .md 파일 수정 시 진행률 자동 표시
#
# 매칭 패턴:
#   - *작업목록*.md
#   - *todo*.md / *TODO*.md
#   - *tasks*.md
#   - docs/plans/*.md
#   - Projects/*/*.md (Obsidian)
#
# 동작: 체크리스트 카운트(- [x] / - [X] / - [ ]) → 진행률 + 막대그래프 stdout
# 100% 도달 시 축하 메시지 추가
# 외부 LLM(Ollama 등) 호출 없음. 빈 입력/잘못된 JSON은 조용히 종료

: "${HOME:?}"

INPUT=$(cat 2>/dev/null)

if [ -z "$INPUT" ]; then
    exit 0
fi

# file_path 추출 (다른 hook 들과 동일 컨벤션)
FILE_PATH=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# .md 파일 아니면 즉시 종료
case "$FILE_PATH" in
    *.md) ;;
    *) exit 0 ;;
esac

# 파일 실제 존재 여부 확인
if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

FILENAME=$(/usr/bin/basename "$FILE_PATH")
LOWER_PATH=$(echo "$FILE_PATH" | /usr/bin/tr '[:upper:]' '[:lower:]')
LOWER_NAME=$(echo "$FILENAME" | /usr/bin/tr '[:upper:]' '[:lower:]')

# 매칭 패턴 검사
MATCHED=0
case "$FILENAME" in
    *작업목록*.md) MATCHED=1 ;;
esac

if [ "$MATCHED" -eq 0 ]; then
    case "$LOWER_NAME" in
        *todo*.md|*tasks*.md) MATCHED=1 ;;
    esac
fi

if [ "$MATCHED" -eq 0 ]; then
    case "$LOWER_PATH" in
        */docs/plans/*.md) MATCHED=1 ;;
        */projects/*/*.md) MATCHED=1 ;;
    esac
fi

if [ "$MATCHED" -eq 0 ]; then
    exit 0
fi

# 체크박스 카운트
DONE=$(/usr/bin/grep -cE '^[[:space:]]*[-*][[:space:]]+\[[xX]\]' "$FILE_PATH" 2>/dev/null)
TODO=$(/usr/bin/grep -cE '^[[:space:]]*[-*][[:space:]]+\[ \]' "$FILE_PATH" 2>/dev/null)

DONE=${DONE:-0}
TODO=${TODO:-0}

TOTAL=$((DONE + TODO))

if [ "$TOTAL" -le 0 ]; then
    exit 0
fi

# 진행률 계산
PERCENT=$((DONE * 100 / TOTAL))
REMAIN=$((TOTAL - DONE))

# 막대그래프 (총 20칸)
BAR_WIDTH=20
FILLED=$((DONE * BAR_WIDTH / TOTAL))
EMPTY=$((BAR_WIDTH - FILLED))

BAR=""
i=0
while [ $i -lt $FILLED ]; do
    BAR="${BAR}█"
    i=$((i + 1))
done
i=0
while [ $i -lt $EMPTY ]; do
    BAR="${BAR}░"
    i=$((i + 1))
done

# stdout 출력 (Claude Code 에 컨텍스트 주입)
printf '📋 작업목록 진행률 — %s\n' "$FILENAME"
printf '  완료: %d / %d (%d%%)\n' "$DONE" "$TOTAL" "$PERCENT"
printf '  남은 항목: %d건\n' "$REMAIN"
printf '  [%s] %d%%\n' "$BAR" "$PERCENT"

if [ "$PERCENT" -ge 100 ]; then
    printf '🎉 모든 항목 완료!\n'
fi

exit 0
